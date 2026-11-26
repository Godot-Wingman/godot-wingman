@tool
extends RefCounted
## Handlers of the "audio" toolset (audio buses and sound files) and of the import
## options of any asset (filesystem toolset): pixel-art texture filtering, sound looping,
## 3D model scale...
##
## Bus changes are saved to the project's bus layout file right away (the Audio panel
## at the bottom of the editor shows them), but they are not part of the undo history.

const PilotError := preload("../utils/pilot_error.gd")
const ValueCodec := preload("../utils/value_codec.gd")
const PropertyEditing := preload("../utils/property_editing.gd")

const DEFAULT_BUS_LAYOUT_PATH := "res://default_bus_layout.tres"

var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("get_audio_buses", _get_audio_buses)
	dispatcher.register_method("edit_audio_buses", _edit_audio_buses)
	dispatcher.register_method("get_audio_file_info", _get_audio_file_info)
	dispatcher.register_method("get_import_options", _get_import_options)
	dispatcher.register_method("set_import_options", _set_import_options)


func _get_audio_buses(_params: Dictionary) -> Variant:
	var buses: Array[Dictionary] = []
	for bus_index in AudioServer.bus_count:
		var effects: Array[String] = []
		for effect_index in AudioServer.get_bus_effect_count(bus_index):
			var effect := AudioServer.get_bus_effect(bus_index, effect_index)
			effects.append("%d: %s%s" % [effect_index, effect.get_class(), "" if AudioServer.is_bus_effect_enabled(bus_index, effect_index) else " (disabled)"])
		var bus := {
			"index": bus_index,
			"name": AudioServer.get_bus_name(bus_index),
			"volume_db": snappedf(AudioServer.get_bus_volume_db(bus_index), 0.01),
			"send": String(AudioServer.get_bus_send(bus_index)) if bus_index > 0 else null,
			"effects": effects,
		}
		if AudioServer.is_bus_mute(bus_index):
			bus["mute"] = true
		if AudioServer.is_bus_solo(bus_index):
			bus["solo"] = true
		if AudioServer.is_bus_bypassing_effects(bus_index):
			bus["bypass_effects"] = true
		buses.append(bus)
	return {"layout_file": _bus_layout_path(), "buses": buses}


## Runs a list of bus operations in order, then saves the layout file.
func _edit_audio_buses(params: Dictionary) -> Variant:
	var operations: Array = params.get("operations", []) if params.get("operations") is Array else []
	if operations.is_empty():
		return PilotError.new("NOTHING_TO_DO", "Pass operations, for example [{\"action\": \"add\", \"bus\": \"Music\", \"volume_db\": -6}].")
	var done: Array[String] = []
	for operation_index in operations.size():
		var operation: Variant = operations[operation_index]
		if not operation is Dictionary:
			return _partial_failure(done, PilotError.new("INVALID_OPERATION", "Operation %d is not an object." % operation_index))
		var outcome: Variant = _run_bus_operation(operation)
		if outcome is PilotError:
			outcome.message = "Operation %d (%s): %s" % [operation_index, operation.get("action", "?"), outcome.message]
			return _partial_failure(done, outcome)
		done.append(outcome)
	var save_error := _save_bus_layout()
	if save_error != OK:
		return PilotError.new("SAVE_FAILED", "The changes were made but the layout could not be saved: %s." % error_string(save_error))
	var result: Dictionary = _get_audio_buses({})
	result["done"] = done
	return result


func _run_bus_operation(operation: Dictionary) -> Variant:
	var action := String(operation.get("action", ""))
	var bus_name := String(operation.get("bus", ""))
	if action == "add":
		if bus_name == "" or AudioServer.get_bus_index(bus_name) != -1:
			return PilotError.new("INVALID_BUS", "A new bus needs a name that is not used yet.")
		AudioServer.add_bus()
		var new_index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(new_index, bus_name)
		var settings_outcome: Variant = _apply_bus_settings(new_index, operation)
		if settings_outcome is PilotError:
			return settings_outcome
		return "added bus %s" % bus_name

	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		return PilotError.new("BUS_NOT_FOUND", "There is no bus '%s'." % bus_name, "Use get_audio_buses to see the buses.")
	match action:
		"remove":
			if bus_index == 0:
				return PilotError.new("MASTER_BUS", "The Master bus cannot be removed.")
			AudioServer.remove_bus(bus_index)
			return "removed bus %s" % bus_name
		"set":
			var settings_outcome: Variant = _apply_bus_settings(bus_index, operation)
			if settings_outcome is PilotError:
				return settings_outcome
			return "changed bus %s" % bus_name
		"add_effect":
			var effect_type := String(operation.get("effect", ""))
			if not ClassDB.class_exists(effect_type) or not ClassDB.is_parent_class(effect_type, "AudioEffect") or not ClassDB.can_instantiate(effect_type):
				return PilotError.new("INVALID_EFFECT", "'%s' is not an audio effect class." % effect_type, "Examples: AudioEffectReverb, AudioEffectDelay, AudioEffectLowPassFilter, AudioEffectCompressor, AudioEffectLimiter, AudioEffectChorus, AudioEffectDistortion.")
			var effect: AudioEffect = ClassDB.instantiate(effect_type)
			var effect_properties: Dictionary = operation.get("properties", {}) if operation.get("properties") is Dictionary else {}
			for property_name in effect_properties:
				var conversion := PropertyEditing.convert_for_property(effect, String(property_name), effect_properties[property_name], null)
				if not conversion["ok"]:
					return PilotError.new("INVALID_PROPERTY", String(conversion["error"]))
				effect.set(String(property_name), conversion["value"])
			AudioServer.add_bus_effect(bus_index, effect)
			return "added %s to %s" % [effect_type, bus_name]
		"remove_effect":
			var effect_index := int(operation.get("effect_index", -1))
			if effect_index < 0 or effect_index >= AudioServer.get_bus_effect_count(bus_index):
				return PilotError.new("INVALID_EFFECT_INDEX", "Bus %s has no effect %d." % [bus_name, effect_index])
			AudioServer.remove_bus_effect(bus_index, effect_index)
			return "removed effect %d from %s" % [effect_index, bus_name]
	return PilotError.new("INVALID_ACTION", "Unknown action '%s'." % action, "Use add, remove, set, add_effect or remove_effect.")


func _apply_bus_settings(bus_index: int, operation: Dictionary) -> Variant:
	if operation.has("rename"):
		AudioServer.set_bus_name(bus_index, String(operation["rename"]))
	if operation.has("volume_db"):
		AudioServer.set_bus_volume_db(bus_index, float(operation["volume_db"]))
	if operation.has("mute"):
		AudioServer.set_bus_mute(bus_index, bool(operation["mute"]))
	if operation.has("solo"):
		AudioServer.set_bus_solo(bus_index, bool(operation["solo"]))
	if operation.has("bypass_effects"):
		AudioServer.set_bus_bypass_effects(bus_index, bool(operation["bypass_effects"]))
	if operation.has("send"):
		var send_bus := String(operation["send"])
		if AudioServer.get_bus_index(send_bus) == -1:
			return PilotError.new("BUS_NOT_FOUND", "There is no bus '%s' to send to." % send_bus)
		AudioServer.set_bus_send(bus_index, send_bus)
	return null


func _partial_failure(done: Array[String], error: PilotError) -> PilotError:
	if not done.is_empty():
		_save_bus_layout()
		error.hint = "These earlier operations were already made and saved: %s." % "; ".join(done)
	return error


func _save_bus_layout() -> Error:
	var layout_path := _bus_layout_path()
	var save_error := ResourceSaver.save(AudioServer.generate_bus_layout(), layout_path)
	if save_error == OK:
		EditorInterface.get_resource_filesystem().update_file(layout_path)
	return save_error


func _bus_layout_path() -> String:
	var configured_path := String(ProjectSettings.get_setting("audio/buses/default_bus_layout", DEFAULT_BUS_LAYOUT_PATH))
	return configured_path if configured_path != "" else DEFAULT_BUS_LAYOUT_PATH


func _get_audio_file_info(params: Dictionary) -> Variant:
	var audio_path := String(params.get("path", ""))
	if not ResourceLoader.exists(audio_path):
		return PilotError.new("FILE_NOT_FOUND", "No file at '%s'." % audio_path, "Use list_files with filter \"*.ogg\" (or *.wav, *.mp3) to find sounds.")
	var stream := load(audio_path) as AudioStream
	if stream == null:
		return PilotError.new("NOT_AUDIO", "'%s' is not a sound." % audio_path)
	var result := {"path": audio_path, "class": stream.get_class(), "length_seconds": snappedf(stream.get_length(), 0.001)}
	if "loop" in stream:
		result["loop"] = stream.get("loop")
	if stream is AudioStreamWAV:
		result["loop_mode"] = ["disabled", "forward", "ping_pong", "backward"][(stream as AudioStreamWAV).loop_mode]
		result["stereo"] = (stream as AudioStreamWAV).stereo
		result["mix_rate"] = (stream as AudioStreamWAV).mix_rate
	var import_options: Variant = _read_import_file(audio_path)
	if import_options is Dictionary:
		result["import_options"] = import_options["options"]
	result["tip"] = "Looping is an import option (\"loop\" for ogg/mp3, \"edit/loop_mode\" for wav): change it with set_import_options."
	return result


func _get_import_options(params: Dictionary) -> Variant:
	var asset_path := String(params.get("path", ""))
	var import_file: Variant = _read_import_file(asset_path)
	if import_file is PilotError:
		return import_file
	return {"path": asset_path, "importer": import_file["importer"], "options": import_file["options"]}


## Changes options in the asset's .import file and reimports it, like the Import dock.
func _set_import_options(params: Dictionary) -> Variant:
	var asset_path := String(params.get("path", ""))
	var import_file: Variant = _read_import_file(asset_path)
	if import_file is PilotError:
		return import_file
	var config: ConfigFile = import_file["config"]
	var new_options: Dictionary = params.get("options", {}) if params.get("options") is Dictionary else {}
	if new_options.is_empty():
		return PilotError.new("NOTHING_TO_DO", "Pass options, for example {\"loop\": true}.", "Current options: %s." % ", ".join(import_file["options"].keys()))
	for option_name in new_options:
		if not config.has_section_key("params", option_name):
			return PilotError.new("UNKNOWN_OPTION", "The %s importer has no option '%s'." % [import_file["importer"], option_name], "Options: %s." % ", ".join(import_file["options"].keys()))
		var current_value: Variant = config.get_value("params", option_name)
		var conversion := ValueCodec.from_json_value(new_options[option_name], typeof(current_value))
		if not conversion["ok"]:
			return PilotError.new("INVALID_VALUE", "%s: %s" % [option_name, conversion["error"]])
		config.set_value("params", option_name, conversion["value"])
	var save_error := config.save(asset_path + ".import")
	if save_error != OK:
		return PilotError.new("SAVE_FAILED", "Could not write '%s.import': %s." % [asset_path, error_string(save_error)])
	EditorInterface.get_resource_filesystem().reimport_files(PackedStringArray([asset_path]))
	var changed := {}
	for option_name in new_options:
		changed[option_name] = ValueCodec.to_json_value(config.get_value("params", option_name))
	return {"path": asset_path, "changed": changed, "reimported": true}


func _read_import_file(asset_path: String) -> Variant:
	if not FileAccess.file_exists(asset_path):
		return PilotError.new("FILE_NOT_FOUND", "No file at '%s'." % asset_path)
	var config := ConfigFile.new()
	if config.load(asset_path + ".import") != OK:
		return PilotError.new("NOT_IMPORTED", "'%s' has no import settings (only imported assets like images, sounds and 3D models have them)." % asset_path)
	var options := {}
	if config.has_section("params"):
		for option_name in config.get_section_keys("params"):
			options[option_name] = ValueCodec.to_json_value(config.get_value("params", option_name))
	return {"config": config, "importer": String(config.get_value("remap", "importer", "unknown")), "options": options}
