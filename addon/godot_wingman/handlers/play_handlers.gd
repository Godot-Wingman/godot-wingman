@tool
extends RefCounted
## Handlers that start and stop the game, and pass requests on to the running game
## (looking at it, playing it, inspecting it). See runtime/game_bridge.gd for the
## game side.

const WingmanError := preload("../utils/wingman_error.gd")

const DEFAULT_GAME_REQUEST_TIMEOUT_SECONDS := 30.0
const GAME_START_TIMEOUT_SECONDS := 30.0

var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("run_game", _run_game)
	dispatcher.register_method("stop_game", _stop_game)
	dispatcher.register_method("game_request", _game_request)


func _run_game(params: Dictionary) -> Variant:
	if EditorInterface.is_playing_scene():
		if not bool(params.get("restart", false)):
			return WingmanError.new("ALREADY_RUNNING", "The game is already running.", "Use it as it is, or pass restart: true.")
		EditorInterface.stop_playing_scene()
		await _context.get_scene_tree().create_timer(0.5).timeout

	var scene := String(params.get("scene", "main"))
	match scene:
		"main":
			if String(ProjectSettings.get_setting("application/run/main_scene", "")) == "":
				return WingmanError.new("NO_MAIN_SCENE", "The project has no main scene.", "Set application/run/main_scene with set_project_settings, or pass scene: \"current\" or a scene path.")
			EditorInterface.play_main_scene()
		"current":
			if _context.get_edited_scene_root() == null:
				return WingmanError.new("NO_OPEN_SCENE", "No scene is open to run.")
			EditorInterface.play_current_scene()
		_:
			if not ResourceLoader.exists(scene):
				return WingmanError.new("SCENE_NOT_FOUND", "No scene at '%s'." % scene)
			EditorInterface.play_custom_scene(scene)

	var is_connected: bool = await _context.game_bridge.wait_until_ready(float(params.get("wait_seconds", GAME_START_TIMEOUT_SECONDS)))
	if not is_connected:
		return WingmanError.new(
			"GAME_DID_NOT_CONNECT",
			"The game started but did not connect within the time limit.",
			"It may have crashed at startup: read get_logs (the editor shows game errors there too), or take_editor_screenshot to look at the Debugger panel."
		)
	var state: Dictionary = await _context.game_bridge.request("get_state", {}, DEFAULT_GAME_REQUEST_TIMEOUT_SECONDS)
	return {"running": true, "scene": scene, "state": state.get("result")}


func _stop_game(_params: Dictionary) -> Dictionary:
	var was_running := EditorInterface.is_playing_scene()
	EditorInterface.stop_playing_scene()
	return {"stopped": was_running}


## Forwards {"method", "params"} to the running game and returns its answer.
## Encoded images come back as bytes and are turned into base64 text here.
func _game_request(params: Dictionary) -> Variant:
	var timeout_seconds := float(params.get("timeout_seconds", DEFAULT_GAME_REQUEST_TIMEOUT_SECONDS))
	var answer: Dictionary = await _context.game_bridge.request(String(params.get("method", "")), params.get("params", {}), timeout_seconds)
	if not answer["ok"]:
		var error: Dictionary = answer["error"]
		return WingmanError.new(String(error.get("code", "GAME_ERROR")), String(error.get("message", "")), String(error.get("hint", "")), error.get("details"))
	return _encode_image_bytes(answer["result"])


func _encode_image_bytes(value: Variant) -> Variant:
	if value is Dictionary:
		var converted := {}
		for key in value:
			if key == "bytes" and value[key] is PackedByteArray:
				converted["data_base64"] = Marshalls.raw_to_base64(value[key])
			else:
				converted[key] = _encode_image_bytes(value[key])
		return converted
	if value is Array:
		return value.map(func(item: Variant) -> Variant: return _encode_image_bytes(item))
	return value
