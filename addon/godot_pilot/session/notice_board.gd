@tool
extends RefCounted
## News for the AIs connected to this editor, delivered with their next answer.
##
## An MCP server cannot interrupt the AI, but every answer the editor sends goes back
## into a tool result. So news waits here, one queue per connection, and the bridge
## attaches it to the next response for that connection (the "notices" field). The MCP
## server adds it to the end of the tool result, where the AI reads it.
##
## News is:
## - what the person did: undo or redo with Ctrl+Z, changes by hand, going back to
##   before a step in the Godot Pilot panel, a message typed in the panel;
## - what other AIs said with tell_other_ais, and when they connect or leave.
##
## An AI that connects later gets the recent messages, so it knows what others are doing.

const KIND_MESSAGE := "message"
const KIND_UNDO := "undo"
const KIND_REDO := "redo"
const KIND_PERSON_EDIT := "person_edit"
const KIND_WENT_BACK := "went_back"
const KIND_AI_CONNECTED := "ai_connected"
const KIND_AI_LEFT := "ai_left"

## Connection id used for news from the person at the editor.
const PERSON := 0
const MAXIMUM_QUEUE_LENGTH := 50
const RECENT_MESSAGE_COUNT := 10
const RECENT_MESSAGE_SECONDS := 30 * 60
const MAXIMUM_ACTION_NAMES := 5

## connection id -> {"ai_client": String, "queue": Array[Dictionary]}
var _connections: Dictionary = {}
## Messages from AIs and the person, kept for AIs that connect later.
var _recent_messages: Array[Dictionary] = []


func add_connection(connection_id: int, ai_client: String) -> void:
	var queue: Array[Dictionary] = []
	for message in _recent_messages:
		var age_seconds := Time.get_unix_time_from_system() - float(message["unix_time"])
		if int(message["from_connection"]) != connection_id and age_seconds <= RECENT_MESSAGE_SECONDS:
			queue.append(message)
	var other_names := get_connected_ai_names(connection_id)
	if not other_names.is_empty():
		queue.push_front(_make_notice(KIND_AI_CONNECTED, PERSON, "",
			"Other AIs are working in this editor too: %s. Say what you are about to change with tell_other_ais, so you do not undo each other's work." % ", ".join(other_names)))
	_connections[connection_id] = {"ai_client": ai_client, "queue": queue}
	_add(_make_notice(KIND_AI_CONNECTED, connection_id, ai_client,
		"%s connected to this editor and may change the same project. Tell it what you are working on with tell_other_ais." % ai_client))


func remove_connection(connection_id: int) -> void:
	var connection: Dictionary = _connections.get(connection_id, {})
	_connections.erase(connection_id)
	if connection.is_empty():
		return
	# Only worth telling when the AI that left is a different application, not the same
	# MCP server reconnecting.
	var ai_client := String(connection["ai_client"])
	if not get_connected_ai_names(-1).has(ai_client):
		_add(_make_notice(KIND_AI_LEFT, connection_id, ai_client, "%s disconnected from this editor." % ai_client))


## Names of the connected AI applications, without the given connection.
func get_connected_ai_names(except_connection_id: int) -> PackedStringArray:
	var names := PackedStringArray()
	for connection_id: int in _connections:
		if connection_id != except_connection_id:
			names.append(String(_connections[connection_id]["ai_client"]))
	return names


## A message from an AI (tell_other_ais) or from the person (the panel). Returns the
## names of the AIs that will get it.
func post_message(from_connection_id: int, from_name: String, text: String) -> PackedStringArray:
	var sender := "the person at the editor" if from_connection_id == PERSON else from_name
	var notice := _make_notice(KIND_MESSAGE, from_connection_id, from_name, "Message from %s: \"%s\"" % [sender, text])
	_recent_messages.append(notice)
	while _recent_messages.size() > RECENT_MESSAGE_COUNT:
		_recent_messages.pop_front()
	_add(notice)
	return get_connected_ai_names(from_connection_id)


## The person undid or redid changes with Ctrl+Z / Ctrl+Y. made_by_connection_id is the
## AI that made the change, or -1 when the person made it.
func report_undo_or_redo(kind: String, action_names: PackedStringArray, place: String, made_by_connection_id: int, made_by_name: String) -> void:
	var notice := _make_notice(kind, PERSON, "", "")
	notice["action_names"] = action_names
	notice["place"] = place
	notice["made_by_connection"] = made_by_connection_id
	notice["made_by_name"] = made_by_name
	_add(notice)


## The person changed something by hand. Consecutive changes are merged into one notice.
func report_person_edit(action_name: String, place: String) -> void:
	for connection: Dictionary in _connections.values():
		var queue: Array = connection["queue"]
		var last_notice: Dictionary = queue.back() if not queue.is_empty() else {}
		if last_notice.get("kind") == KIND_PERSON_EDIT:
			var counts: Dictionary = last_notice["action_counts"]
			counts[action_name] = int(counts.get(action_name, 0)) + 1
			if not Array(last_notice["places"]).has(place):
				last_notice["places"].append(place)
			continue
		var notice := _make_notice(KIND_PERSON_EDIT, PERSON, "", "")
		notice["action_counts"] = {action_name: 1}
		notice["places"] = [place]
		_append_to_queue(queue, notice)


func report_went_back(step_description: String, outcome: Dictionary) -> void:
	var parts := PackedStringArray()
	if not Array(outcome.get("changed", [])).is_empty():
		parts.append("restored: " + ", ".join(PackedStringArray(outcome["changed"])))
	if not Array(outcome.get("removed", [])).is_empty():
		parts.append("deleted (created after that step): " + ", ".join(PackedStringArray(outcome["removed"])))
	var changes := "; ".join(parts) if not parts.is_empty() else "no files changed"
	_add(_make_notice(KIND_WENT_BACK, PERSON, "",
		"The person went back to before %s in the Godot Pilot panel (%s). Read these files again before you change them; work done after that step is gone." % [step_description, changes]))


## The news for one connection, as text lines, and empties its queue.
func take_pending(connection_id: int) -> Array:
	var connection: Dictionary = _connections.get(connection_id, {})
	if connection.is_empty() or Array(connection["queue"]).is_empty():
		return []
	var texts := []
	for notice: Dictionary in connection["queue"]:
		texts.append({"time": notice["time"], "kind": notice["kind"], "text": _describe_for(notice, connection_id)})
	connection["queue"] = [] as Array[Dictionary]
	return texts


func _describe_for(notice: Dictionary, receiver_connection_id: int) -> String:
	match String(notice["kind"]):
		KIND_UNDO, KIND_REDO:
			var verb := "undid" if notice["kind"] == KIND_UNDO else "redid"
			var maker := ""
			var made_by := int(notice["made_by_connection"])
			if made_by == receiver_connection_id:
				maker = " It was your change."
			elif made_by > 0:
				maker = " It was a change by %s." % notice["made_by_name"]
			var names := "\", \"".join(notice["action_names"])
			return "The person %s \"%s\" in %s (Ctrl+Z / Ctrl+Y).%s Check the current state before you continue." % [verb, names, notice["place"], maker]
		KIND_PERSON_EDIT:
			var descriptions := PackedStringArray()
			var counts: Dictionary = notice["action_counts"]
			for action_name: String in counts:
				if descriptions.size() == MAXIMUM_ACTION_NAMES:
					descriptions.append("...")
					break
				var count := int(counts[action_name])
				descriptions.append("\"%s\"" % action_name if count == 1 else "\"%s\" x%d" % [action_name, count])
			return "The person changed things by hand in %s: %s. Check the current state before you change the same things." % [", ".join(PackedStringArray(notice["places"])), ", ".join(descriptions)]
	return String(notice["text"])


func _add(notice: Dictionary) -> void:
	var from_connection := int(notice["from_connection"])
	for connection_id: int in _connections:
		if connection_id != from_connection or from_connection == PERSON:
			_append_to_queue(_connections[connection_id]["queue"], notice)


func _append_to_queue(queue: Array, notice: Dictionary) -> void:
	queue.append(notice)
	while queue.size() > MAXIMUM_QUEUE_LENGTH:
		queue.pop_front()


func _make_notice(kind: String, from_connection_id: int, from_name: String, text: String) -> Dictionary:
	return {
		"kind": kind,
		"from_connection": from_connection_id,
		"from_name": from_name,
		"text": text,
		"time": Time.get_time_string_from_system(),
		"unix_time": Time.get_unix_time_from_system(),
	}
