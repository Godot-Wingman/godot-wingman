@tool
extends RefCounted
## Requests about permissions, the activity list, checkpoints and messages between AIs
## (session/wingman_session.gd).
##
## The MCP server calls authorize_tool_call before every tool that changes something
## and finish_tool_call after it. tell_other_ais uses post_message_to_other_ais. The
## other methods exist for tests and for the server's own use.

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


func _authorize_tool_call(params: Dictionary) -> Dictionary:
	return await _context.session.authorize(params)


func _finish_tool_call(params: Dictionary) -> Dictionary:
	_context.session.finish(int(params.get("activity_id", -1)), bool(params.get("succeeded", false)), String(params.get("result", "")))
	return {"recorded": true}


func _get_session_state(_params: Dictionary) -> Dictionary:
	return {
		"editor_mode": _context.session.editor_mode,
		"tools_allowed_for_session": Array(_context.session.get_tools_allowed_for_session()),
		"activity": _context.session.activity,
	}


func _set_editor_permission_mode(params: Dictionary) -> Variant:
	var mode := String(params.get("mode", ""))
	if not WingmanSession.MODES.has(mode):
		return WingmanError.new("INVALID_MODE", "Unknown permission mode '%s'." % mode, "Use full, confirm or read-only.")
	_context.session.set_editor_mode(mode)
	return {"editor_mode": mode}


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
	var sender := String(caller.get("ai_client", "AI"))
	var receivers: PackedStringArray = _context.session.post_message(connection_id, sender, message)
	return {"delivered_to": Array(receivers)}
