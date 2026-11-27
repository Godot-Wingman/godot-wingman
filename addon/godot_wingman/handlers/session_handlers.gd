@tool
extends RefCounted
## Requests about permissions, the activity list, checkpoints and messages between AIs
## (session/wingman_session.gd).
##
## The MCP server calls authorize_tool_call before every tool that changes something
## and finish_tool_call after it. tell_other_ais uses post_message_to_other_ais,
## reply_to_person and wait_for_person_message are the AI's side of the panel's chat.
## The other methods exist for tests and for the server's own use.

const WingmanError := preload("../utils/wingman_error.gd")
const WingmanSession := preload("../session/wingman_session.gd")

var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("authorize_tool_call", _authorize_tool_call)
	dispatcher.register_method("finish_tool_call", _finish_tool_call)
	dispatcher.register_method("get_session_state", _get_session_state)
	dispatcher.register_method("set_editor_permission_mode", _set_editor_permission_mode)
	dispatcher.register_method("go_back_to_before_step", _go_back_to_before_step)
	dispatcher.register_method("post_message_to_other_ais", _post_message_to_other_ais)
	dispatcher.register_method("rename_ai", _rename_ai)
	dispatcher.register_method("reply_to_person", _reply_to_person)
	dispatcher.register_method("wait_for_person_message", _wait_for_person_message)
	dispatcher.register_method("send_chat_message_as_person", _send_chat_message_as_person)


func _authorize_tool_call(params: Dictionary) -> Dictionary:
	return await _context.session.authorize(params)


func _finish_tool_call(params: Dictionary) -> Dictionary:
	_context.session.finish(int(params.get("activity_id", -1)), bool(params.get("succeeded", false)), String(params.get("result", "")))
	return {"recorded": true}


func _get_session_state(_params: Dictionary) -> Dictionary:
	return {
		"editor_mode": _context.session.default_mode,
		"connections": _describe_connections(),
		"activity": _context.session.activity,
		"messages": _context.session.messages,
	}


func _describe_connections() -> Array:
	var descriptions := []
	for connection_id: int in _context.session.connections:
		var connection: Dictionary = _context.session.connections[connection_id]
		descriptions.append({
			"connection_id": connection_id,
			"name": connection["name"],
			"ai_client": connection["ai_client"],
			"mode": connection["mode"],
			"server_mode": connection["server_mode"],
			"tools_allowed_for_session": connection["tools_allowed"].keys(),
		})
	return descriptions


## Without connection_id the mode applies to every AI and becomes the default.
func _set_editor_permission_mode(params: Dictionary) -> Variant:
	var mode := String(params.get("mode", ""))
	if not WingmanSession.MODES.has(mode):
		return WingmanError.new("INVALID_MODE", "Unknown permission mode '%s'." % mode, "Use full, confirm or read-only.")
	if params.has("connection_id"):
		var connection_id := int(params["connection_id"])
		if not _context.session.connections.has(connection_id):
			return WingmanError.new("UNKNOWN_CONNECTION", "No AI with connection id %d is connected." % connection_id, "get_session_state lists the connected AIs.")
		_context.session.set_connection_mode(connection_id, mode)
	else:
		_context.session.set_mode_for_everyone(mode)
	return {"editor_mode": mode}


## What the person does by clicking an AI's name in the panel.
func _rename_ai(params: Dictionary) -> Variant:
	var connection_id := int(params.get("connection_id", -1))
	var new_name := String(params.get("name", "")).strip_edges()
	if not _context.session.connections.has(connection_id) or new_name.is_empty():
		return WingmanError.new("INVALID_RENAME", "Give the connection_id of a connected AI and a name.", "get_session_state lists the connected AIs.")
	_context.session.rename_connection(connection_id, new_name)
	return {"name": _context.session.connections[connection_id]["name"]}


func _go_back_to_before_step(params: Dictionary) -> Variant:
	var outcome: Dictionary = await _context.session.go_back_to_before(int(params.get("activity_id", -1)))
	if outcome.is_empty():
		return WingmanError.new("NO_CHECKPOINT", "That step has no checkpoint.", "Only changes made in this editor session can be undone this way.")
	return outcome


func _post_message_to_other_ais(params: Dictionary) -> Variant:
	var message := String(params.get("message", "")).strip_edges()
	if message.is_empty():
		return WingmanError.new("EMPTY_MESSAGE", "The message is empty.", "Write what you are about to change, for example: \"I am rewriting res://player.gd\".")
	var caller: Dictionary = params.get("_caller", {}) if params.get("_caller") is Dictionary else {}
	var connection_id := int(caller.get("connection_id", -1))
	var sender: String = _context.session.get_connection_name(connection_id, String(caller.get("ai_client", "AI")))
	var receivers: PackedStringArray = _context.session.post_message(connection_id, sender, message)
	return {"delivered_to": Array(receivers)}


func _reply_to_person(params: Dictionary) -> Variant:
	var message := String(params.get("message", "")).strip_edges()
	if message.is_empty():
		return WingmanError.new("EMPTY_MESSAGE", "The message is empty.", "Write your answer to the person.")
	var caller := _get_caller(params)
	var connection_id := int(caller.get("connection_id", -1))
	var sender: String = _context.session.get_connection_name(connection_id, String(caller.get("ai_client", "AI")))
	var files: Array = params.get("files", []) if params.get("files") is Array else []
	_context.session.post_reply(connection_id, sender, message, files)
	return {"shown": true}


## Waits until the person writes to the calling AI in the chat. The message comes back
## as news ("notices") with this answer.
func _wait_for_person_message(params: Dictionary) -> Variant:
	var connection_id := int(_get_caller(params).get("connection_id", -1))
	var timeout_seconds := float(params.get("timeout_seconds", 240.0))
	var has_message: bool = await _context.session.wait_for_person_message(connection_id, timeout_seconds)
	return {"message_arrived": has_message}


## What the person does in the chat, for tests: to = a connection id, or -1 for every AI.
func _send_chat_message_as_person(params: Dictionary) -> Variant:
	var text := String(params.get("text", "")).strip_edges()
	if text.is_empty():
		return WingmanError.new("EMPTY_MESSAGE", "The message is empty.", "Give a text.")
	var attachments: Array = params.get("attachments", []) if params.get("attachments") is Array else []
	_context.session.send_from_person(int(params.get("to", WingmanSession.EVERYONE)), text, attachments)
	return {"sent": true}


func _get_caller(params: Dictionary) -> Dictionary:
	return params.get("_caller", {}) if params.get("_caller") is Dictionary else {}
