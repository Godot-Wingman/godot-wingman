@tool
extends RefCounted
## Handlers of the "signals" toolset: listing, connecting and disconnecting signals, like
## the Node dock's Signals tab. Connections made here are saved with the scene.

const WingmanError := preload("../utils/wingman_error.gd")
const CoreHandlers := preload("core_handlers.gd")

var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("list_signals", _list_signals)
	dispatcher.register_method("connect_signal", _connect_signal)
	dispatcher.register_method("disconnect_signal", _disconnect_signal)


func _list_signals(params: Dictionary) -> Variant:
	var node: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", ".")))
	if node is WingmanError:
		return node
	var only_connected := bool(params.get("only_connected", false))
	var signals := []
	for signal_information in node.get_signal_list():
		var connections := []
		for connection in node.get_signal_connection_list(signal_information["name"]):
			# Only connections saved with the scene; the editor makes its own internal ones too.
			if int(connection["flags"]) & CONNECT_PERSIST == 0:
				continue
			var callable: Callable = connection["callable"]
			var target := callable.get_object()
			connections.append("%s() on %s" % [callable.get_method(), _context.describe_node_path(target) if target is Node else str(target)])
		if only_connected and connections.is_empty():
			continue
		var entry := {"signal": CoreHandlers.describe_method(signal_information, false)}
		if not connections.is_empty():
			entry["connected_to"] = connections
		signals.append(entry)
	return {"node": _context.describe_node_path(node), "signals": signals}


## Connects a signal to a method. With create_method, a missing method is added to the
## target's GDScript, like the editor's "Connect" dialog does.
func _connect_signal(params: Dictionary) -> Variant:
	var source: Variant = _context.find_node_in_edited_scene(String(params.get("from_node", "")))
	if source is WingmanError:
		return source
	var target: Variant = _context.find_node_in_edited_scene(String(params.get("to_node", "")))
	if target is WingmanError:
		return target
	var signal_name := String(params.get("signal", ""))
	if not source.has_signal(signal_name):
		return WingmanError.new("SIGNAL_NOT_FOUND", "%s has no signal '%s'." % [source.get_class(), signal_name], "Use list_signals to see the available signals.")
	var method_name := String(params.get("method", "_on_%s_%s" % [String(source.name).to_snake_case(), signal_name]))

	var created_method := false
	if not target.has_method(method_name):
		if not bool(params.get("create_method", true)):
			return WingmanError.new("METHOD_NOT_FOUND", "%s has no method '%s'." % [target.name, method_name], "Pass create_method: true to add it.")
		var creation_problem: Variant = _add_method_to_script(target, method_name, _find_signal_arguments(source, signal_name))
		if creation_problem is WingmanError:
			return creation_problem
		created_method = true

	var callable := Callable(target, method_name)
	var binds: Array = params.get("binds", []) if params.get("binds") is Array else []
	if not binds.is_empty():
		callable = callable.bindv(binds)
	if source.is_connected(signal_name, callable):
		return WingmanError.new("ALREADY_CONNECTED", "%s.%s is already connected to %s()." % [source.name, signal_name, method_name])

	var connection_flags := CONNECT_PERSIST
	if bool(params.get("deferred", false)):
		connection_flags |= CONNECT_DEFERRED
	if bool(params.get("one_shot", false)):
		connection_flags |= CONNECT_ONE_SHOT

	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action("Connect %s.%s" % [source.name, signal_name])
	undo_redo.add_do_method(source, "connect", signal_name, callable, connection_flags)
	undo_redo.add_undo_method(source, "disconnect", signal_name, callable)
	undo_redo.commit_action()
	return {
		"connected": "signal %s of %s -> %s() on %s" % [signal_name, _context.describe_node_path(source), method_name, _context.describe_node_path(target)],
		"method_created_in_script": created_method,
	}


func _disconnect_signal(params: Dictionary) -> Variant:
	var source: Variant = _context.find_node_in_edited_scene(String(params.get("from_node", "")))
	if source is WingmanError:
		return source
	var signal_name := String(params.get("signal", ""))
	var method_name := String(params.get("method", ""))
	for connection in source.get_signal_connection_list(signal_name):
		var callable: Callable = connection["callable"]
		if callable.get_method() != method_name:
			continue
		var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
		undo_redo.create_action("Disconnect %s.%s" % [source.name, signal_name])
		undo_redo.add_do_method(source, "disconnect", signal_name, callable)
		undo_redo.add_undo_method(source, "connect", signal_name, callable, int(connection["flags"]))
		undo_redo.commit_action()
		return {"disconnected": "%s.%s -> %s()" % [source.name, signal_name, method_name]}
	return WingmanError.new("NOT_CONNECTED", "%s.%s is not connected to a method named '%s'." % [source.name, signal_name, method_name])


func _find_signal_arguments(source: Node, signal_name: String) -> Array:
	for signal_information in source.get_signal_list():
		if signal_information["name"] == signal_name:
			return signal_information["args"]
	return []


## Appends `func method_name(arguments) -> void: pass` to the target's GDScript.
func _add_method_to_script(target: Node, method_name: String, signal_arguments: Array) -> Variant:
	var script: Script = target.get_script()
	if script == null or not script is GDScript or script.resource_path == "" or script.resource_path.contains("::"):
		return WingmanError.new("NO_SCRIPT", "%s has no GDScript file to add '%s' to." % [target.name, method_name], "Attach a script first (create_script with attach_to), or connect to an existing method.")
	var argument_declarations: Array[String] = []
	for argument in signal_arguments:
		argument_declarations.append("%s: %s" % [argument["name"], CoreHandlers.describe_property_type(argument)])
	var source_code := FileAccess.get_file_as_string(script.resource_path).rstrip("\n")
	source_code += "\n\n\nfunc %s(%s) -> void:\n\tpass # Replace with function body.\n" % [method_name, ", ".join(argument_declarations)]

	var file := FileAccess.open(script.resource_path, FileAccess.WRITE)
	if file == null:
		return WingmanError.new("WRITE_FAILED", "Could not write '%s'." % script.resource_path)
	file.store_string(source_code)
	file.close()
	script.source_code = source_code
	script.reload(true)
	return null
