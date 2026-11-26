@tool
extends RefCounted
## Requests about permissions, the activity list and checkpoints (session/pilot_session.gd).
##
## The MCP server calls authorize_tool_call before every tool that changes something
## and finish_tool_call after it. No AI tool exposes the other methods; they exist for
## tests and for the server's own use.

const PilotError := preload("../utils/pilot_error.gd")
const PilotSession := preload("../session/pilot_session.gd")

var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("authorize_tool_call", _authorize_tool_call)
	dispatcher.register_method("finish_tool_call", _finish_tool_call)
	dispatcher.register_method("get_session_state", _get_session_state)
	dispatcher.register_method("set_editor_permission_mode", _set_editor_permission_mode)
	dispatcher.register_method("go_back_to_before_step", _go_back_to_before_step)


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
	if not PilotSession.MODES.has(mode):
		return PilotError.new("INVALID_MODE", "Unknown permission mode '%s'." % mode, "Use full, confirm or read-only.")
	_context.session.set_editor_mode(mode)
	return {"editor_mode": mode}


func _go_back_to_before_step(params: Dictionary) -> Variant:
	var outcome: Dictionary = await _context.session.go_back_to_before(int(params.get("activity_id", -1)))
	if outcome.is_empty():
		return PilotError.new("NO_CHECKPOINT", "That step has no checkpoint.", "Only changes made in this editor session can be undone this way.")
	return outcome
