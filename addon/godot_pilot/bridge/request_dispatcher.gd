@tool
extends RefCounted
## Routes each incoming request to the handler function registered for its method name.
##
## Handlers are plain functions that receive the request parameters as a Dictionary
## and return either a JSON-friendly value or a PilotError. Handlers may use `await`.

const PilotError := preload("../utils/pilot_error.gd")

## Method name -> Callable that handles it.
var _handlers_by_method: Dictionary = {}


func register_method(method_name: String, handler: Callable) -> void:
	_handlers_by_method[method_name] = handler


func get_method_names() -> PackedStringArray:
	var method_names := PackedStringArray(_handlers_by_method.keys())
	method_names.sort()
	return method_names


## Runs the handler for `method_name` and wraps its outcome in a response Dictionary:
## {"ok": true, "result": ...} or {"ok": false, "error": {...}}.
func dispatch(method_name: String, params: Variant) -> Dictionary:
	if not _handlers_by_method.has(method_name):
		var unknown_method_error := PilotError.new(
			"UNKNOWN_METHOD",
			"The Godot addon does not know the method '%s'." % method_name,
			"The MCP server and the addon may be different versions. Reinstall the addon with the install_addon tool."
		)
		return {"ok": false, "error": unknown_method_error.to_dictionary()}

	var request_params: Dictionary = params if params is Dictionary else {}
	var handler: Callable = _handlers_by_method[method_name]
	var result: Variant = await handler.call(request_params)

	if result is PilotError:
		return {"ok": false, "error": result.to_dictionary()}
	return {"ok": true, "result": result}
