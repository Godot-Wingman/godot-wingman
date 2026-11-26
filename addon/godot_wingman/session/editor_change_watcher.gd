@tool
extends RefCounted
## Notices when the person undoes, redoes or changes something in the editor, so the
## AIs hear about it (notice_board.gd) instead of working on a state that is gone.
##
## The editor's undo history (EditorUndoRedoManager) has one history for project-wide
## changes and one per scene. Each has a version number: committing or redoing an
## action raises it, undoing lowers it. After every change of a watched history the
## new state is compared with the last one:
## - version went down: the person undid actions;
## - version went up, same number of actions, and the action is the one that was next:
##   the person redid it;
## - otherwise a new action was committed: by an AI when one of its tool calls is
##   running, else by the person.
##
## Both the manager's signals and each history's own version_changed are watched: an undo
## started from code (UndoRedo.undo()) only raises the latter.

const NoticeBoard := preload("notice_board.gd")

var _session: RefCounted
var _notices: NoticeBoard
## history id -> {"version", "action_count", "current_action", "next_action_name"}
var _last_states: Dictionary = {}
## history id -> {version: {"connection_id": int, "client": String}}
var _versions_made_by_ai: Dictionary = {}


func _init(session: RefCounted, notices: NoticeBoard) -> void:
	_session = session
	_notices = notices
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.history_changed.connect(check_for_changes)
	undo_redo.version_changed.connect(check_for_changes)
	remember_current_state()


func disconnect_from_editor() -> void:
	var undo_redo := EditorInterface.get_editor_undo_redo()
	if undo_redo.history_changed.is_connected(check_for_changes):
		undo_redo.history_changed.disconnect(check_for_changes)
	if undo_redo.version_changed.is_connected(check_for_changes):
		undo_redo.version_changed.disconnect(check_for_changes)


## Takes the current state as the starting point, without reporting anything. Called
## when another scene is opened and after going back to a checkpoint.
func remember_current_state() -> void:
	var undo_redo := EditorInterface.get_editor_undo_redo()
	for history_id in _watched_history_ids():
		var history := undo_redo.get_history_undo_redo(history_id)
		if history != null:
			_watch_history(history)
			_last_states[history_id] = _read_state(history)


func check_for_changes() -> void:
	var undo_redo := EditorInterface.get_editor_undo_redo()
	for history_id in _watched_history_ids():
		var history := undo_redo.get_history_undo_redo(history_id)
		if history == null:
			continue
		_watch_history(history)
		var state := _read_state(history)
		var last_state: Dictionary = _last_states.get(history_id, {})
		_last_states[history_id] = state
		if last_state.is_empty() or int(state["version"]) == int(last_state["version"]):
			continue
		if _session.is_going_back:
			continue
		_report_change(history_id, history, last_state, state)


func _report_change(history_id: int, history: UndoRedo, last_state: Dictionary, state: Dictionary) -> void:
	var place := _describe_history(history_id)
	var version := int(state["version"])
	var last_version := int(last_state["version"])
	var made_by_ai: Dictionary = _versions_made_by_ai.get_or_add(history_id, {})

	# While an AI tool call runs, the changes are the AI's own.
	var running_call: Dictionary = _session.get_running_ai_call()
	if not running_call.is_empty():
		if version > last_version:
			made_by_ai[version] = {"connection_id": int(running_call.get("connection_id", -1)), "client": String(running_call.get("client", "AI"))}
		return

	if version < last_version:
		var undone_names := PackedStringArray()
		for action_index in range(int(state["current_action"]) + 1, int(last_state["current_action"]) + 1):
			undone_names.append(history.get_action_name(action_index))
		var maker: Dictionary = made_by_ai.get(last_version, {})
		_notices.report_undo_or_redo(NoticeBoard.KIND_UNDO, undone_names, place, int(maker.get("connection_id", -1)), String(maker.get("client", "")))
		return

	var current_name := history.get_action_name(int(state["current_action"])) if int(state["current_action"]) >= 0 else ""
	var is_redo := int(state["action_count"]) == int(last_state["action_count"]) \
		and int(state["current_action"]) == int(last_state["current_action"]) + 1 \
		and current_name == String(last_state["next_action_name"])
	if is_redo:
		var maker: Dictionary = made_by_ai.get(version, {})
		_notices.report_undo_or_redo(NoticeBoard.KIND_REDO, PackedStringArray([current_name]), place, int(maker.get("connection_id", -1)), String(maker.get("client", "")))
		return

	made_by_ai.erase(version)
	_notices.report_person_edit(current_name, place)


func _watch_history(history: UndoRedo) -> void:
	if not history.version_changed.is_connected(check_for_changes):
		history.version_changed.connect(check_for_changes)


func _watched_history_ids() -> Array[int]:
	var history_ids: Array[int] = [EditorUndoRedoManager.GLOBAL_HISTORY]
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root != null:
		var scene_history_id := EditorInterface.get_editor_undo_redo().get_object_history_id(scene_root)
		if not history_ids.has(scene_history_id):
			history_ids.append(scene_history_id)
	return history_ids


func _describe_history(history_id: int) -> String:
	if history_id == EditorUndoRedoManager.GLOBAL_HISTORY:
		return "the project (not a scene)"
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root != null and not scene_root.scene_file_path.is_empty():
		return scene_root.scene_file_path
	return "the open scene"


static func _read_state(history: UndoRedo) -> Dictionary:
	var current_action := history.get_current_action()
	var action_count := history.get_history_count()
	return {
		"version": history.get_version(),
		"action_count": action_count,
		"current_action": current_action,
		"next_action_name": history.get_action_name(current_action + 1) if current_action + 1 < action_count else "",
	}
