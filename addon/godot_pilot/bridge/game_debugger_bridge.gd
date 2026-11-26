@tool
extends EditorDebuggerPlugin
## The editor's end of the connection to the running game.
##
## When a game is started from the editor, Godot connects it to the editor's debugger.
## The game bridge (runtime/game_bridge.gd) uses that connection to receive requests
## and send answers, with messages named "godot_pilot:...". This class sends the
## requests and waits for the matching answers.

signal game_stopped
## The game bridge inside the game answered: the game is running and reachable.
signal game_ready

const CAPTURE_NAME := "godot_pilot"

var _scene_tree: SceneTree
var _active_session_id := -1
var _is_game_ready := false
var _next_request_id := 1
## Request id -> [succeeded: bool, payload]
var _answers_by_request_id: Dictionary = {}


func _init(scene_tree: SceneTree) -> void:
	_scene_tree = scene_tree


func is_game_ready() -> bool:
	return _is_game_ready


func _has_capture(capture: String) -> bool:
	return capture == CAPTURE_NAME


func _capture(message: String, data: Array, session_id: int) -> bool:
	match message:
		"%s:ready" % CAPTURE_NAME:
			_active_session_id = session_id
			_is_game_ready = true
			game_ready.emit()
			return true
		"%s:response" % CAPTURE_NAME:
			_answers_by_request_id[int(data[0])] = [bool(data[1]), data[2]]
			return true
	return false


func _setup_session(session_id: int) -> void:
	var session := get_session(session_id)
	session.stopped.connect(_on_session_stopped.bind(session_id))


func _on_session_stopped(session_id: int) -> void:
	if session_id != _active_session_id:
		return
	_is_game_ready = false
	_active_session_id = -1
	_answers_by_request_id.clear()
	game_stopped.emit()


## Waits until the game bridge said it is ready, or the time is up.
func wait_until_ready(timeout_seconds: float) -> bool:
	var deadline_milliseconds := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while not _is_game_ready and Time.get_ticks_msec() < deadline_milliseconds:
		await _scene_tree.process_frame
	return _is_game_ready


## Sends a request to the game and waits for the answer.
## Returns {"ok": true, "result": ...} or {"ok": false, "error": {...}}.
func request(method_name: String, params: Dictionary, timeout_seconds: float) -> Dictionary:
	if not _is_game_ready:
		return _failure("GAME_NOT_RUNNING", "The game is not running (or was not started from this editor).", "Start it with run_game.")
	var request_id := _next_request_id
	_next_request_id += 1
	get_session(_active_session_id).send_message("%s:request" % CAPTURE_NAME, [request_id, method_name, params])

	var deadline_milliseconds := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while not _answers_by_request_id.has(request_id):
		if not _is_game_ready:
			return _failure("GAME_STOPPED", "The game stopped before answering.", "It may have crashed or quit: read the game logs, or run it again.")
		if Time.get_ticks_msec() > deadline_milliseconds:
			return _failure("GAME_TIMEOUT", "The game did not answer '%s' within %d seconds." % [method_name, int(timeout_seconds)], "The game may be frozen in a loop, or a breakpoint stopped it.")
		await _scene_tree.process_frame

	var answer: Array = _answers_by_request_id[request_id]
	_answers_by_request_id.erase(request_id)
	if answer[0]:
		return {"ok": true, "result": answer[1]}
	return {"ok": false, "error": answer[1]}


func _failure(code: String, message: String, hint: String) -> Dictionary:
	return {"ok": false, "error": {"code": code, "message": message, "hint": hint}}
