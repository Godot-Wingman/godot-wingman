@tool
extends Node
## A small WebSocket server that runs inside the Godot editor.
##
## The MCP server connects to it to send requests ("add this node", "take a
## screenshot") and receive the answers. Safety rules:
## - It only listens on 127.0.0.1, so other computers can never reach it.
## - The first message of every connection must contain the secret token from the
##   registry file. Connections without the right token are closed.
##
## Message format (JSON text frames):
##   client -> editor: {"type": "hello", "token": "...", "client": {...}}
##   editor -> client: {"type": "hello_ok", "editor": {...}}
##   client -> editor: {"type": "request", "id": 7, "method": "ping", "params": {}}
##   editor -> client: {"type": "response", "id": 7, "ok": true, "result": ...}

signal client_count_changed(authenticated_client_count: int)

const FIRST_PORT := 6550
const LAST_PORT := 6599
## Screenshots and big scene dumps can be several megabytes.
const SOCKET_BUFFER_SIZE_BYTES := 64 * 1024 * 1024
const MAX_QUEUED_PACKETS := 4096
const HANDSHAKE_TIMEOUT_MILLISECONDS := 10000
const UNAUTHORIZED_CLOSE_CODE := 4001


## One connected MCP server.
class ClientConnection:
	var socket := WebSocketPeer.new()
	var is_authenticated := false
	var connected_at_milliseconds := 0
	var client_name := "unknown"
	## What the MCP server told us in its hello: AI client name, version, permission mode.
	var description := {}


var port: int = 0

var _tcp_server := TCPServer.new()
var _clients: Array[ClientConnection] = []
var _dispatcher: RefCounted
var _token: String
var _editor_information: Dictionary


func _init(dispatcher: RefCounted, token: String, editor_information: Dictionary) -> void:
	name = "GodotPilotBridgeServer"
	_dispatcher = dispatcher
	_token = token
	_editor_information = editor_information


## Tries ports from FIRST_PORT to LAST_PORT and keeps the first free one.
func start_listening() -> Error:
	for candidate_port in range(FIRST_PORT, LAST_PORT + 1):
		if _tcp_server.listen(candidate_port, "127.0.0.1") == OK:
			port = candidate_port
			return OK
	return ERR_CANT_CREATE


## One entry per connected MCP server: {ai_client, server_version, permission_mode}.
func get_client_descriptions() -> Array:
	var descriptions := []
	for client in _clients:
		if client.is_authenticated:
			descriptions.append(client.description)
	return descriptions


func get_authenticated_client_count() -> int:
	return _clients.filter(func(client: ClientConnection) -> bool: return client.is_authenticated).size()


func _process(_delta: float) -> void:
	_accept_new_clients()
	# Iterate over a copy because _poll_client can remove clients from the list.
	for client in _clients.duplicate():
		_poll_client(client)


func _exit_tree() -> void:
	for client in _clients:
		client.socket.close(1001, "Godot editor is closing")
	_clients.clear()
	_tcp_server.stop()


func _accept_new_clients() -> void:
	while _tcp_server.is_connection_available():
		var client := ClientConnection.new()
		client.socket.inbound_buffer_size = SOCKET_BUFFER_SIZE_BYTES
		client.socket.outbound_buffer_size = SOCKET_BUFFER_SIZE_BYTES
		client.socket.max_queued_packets = MAX_QUEUED_PACKETS
		client.socket.accept_stream(_tcp_server.take_connection())
		client.connected_at_milliseconds = Time.get_ticks_msec()
		_clients.append(client)


func _poll_client(client: ClientConnection) -> void:
	client.socket.poll()
	var state := client.socket.get_ready_state()

	if state == WebSocketPeer.STATE_CLOSED:
		var was_authenticated := client.is_authenticated
		_clients.erase(client)
		if was_authenticated:
			client_count_changed.emit(get_authenticated_client_count())
		return

	var waited_milliseconds := Time.get_ticks_msec() - client.connected_at_milliseconds
	if not client.is_authenticated and waited_milliseconds > HANDSHAKE_TIMEOUT_MILLISECONDS:
		client.socket.close(UNAUTHORIZED_CLOSE_CODE, "No hello message received in time")
		return

	if state != WebSocketPeer.STATE_OPEN:
		return

	while client.socket.get_available_packet_count() > 0:
		var message_text := client.socket.get_packet().get_string_from_utf8()
		_handle_message(client, message_text)


func _handle_message(client: ClientConnection, message_text: String) -> void:
	var message: Variant = JSON.parse_string(message_text)
	if not message is Dictionary:
		_send(client, {"type": "protocol_error", "message": "Every message must be a JSON object."})
		return

	if not client.is_authenticated:
		_handle_hello(client, message)
		return

	if message.get("type") == "request":
		_run_request(client, message)


func _handle_hello(client: ClientConnection, message: Dictionary) -> void:
	if message.get("type") != "hello" or String(message.get("token", "")) != _token:
		_send(client, {"type": "hello_rejected", "reason": "Missing or wrong token."})
		client.socket.close(UNAUTHORIZED_CLOSE_CODE, "Unauthorized")
		return

	client.is_authenticated = true
	var client_information: Variant = message.get("client", {})
	if client_information is Dictionary:
		client.client_name = String(client_information.get("name", "unknown"))
		client.description = {
			"ai_client": String(client_information.get("ai_client", client.client_name)),
			"server_version": String(client_information.get("version", "")),
			"permission_mode": String(client_information.get("permission_mode", "")),
		}
	_send(client, {"type": "hello_ok", "editor": _editor_information})
	client_count_changed.emit(get_authenticated_client_count())


## Runs one request. Called without `await` so that a slow request (for example one
## that waits for a frame to render) does not block other requests.
func _run_request(client: ClientConnection, message: Dictionary) -> void:
	var request_id: Variant = message.get("id")
	var method_name := String(message.get("method", ""))
	var response: Dictionary = await _dispatcher.dispatch(method_name, message.get("params", {}))
	response["type"] = "response"
	response["id"] = request_id
	if client.socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send(client, response)


func _send(client: ClientConnection, payload: Dictionary) -> void:
	client.socket.send_text(escape_control_characters(JSON.stringify(payload)))


## Godot's JSON.stringify leaves some control characters (like the ESC of terminal
## colors) unescaped, which makes the JSON invalid for other parsers.
## Compact JSON has no raw control characters outside strings, so replacing every one
## of them with its \u escape is always safe. Code 0 is skipped: Godot strings cannot
## contain it, and String.chr(0) itself logs a Unicode error.
static func escape_control_characters(json_text: String) -> String:
	for character_code in range(1, 32):
		var control_character := String.chr(character_code)
		if json_text.contains(control_character):
			json_text = json_text.replace(control_character, "\\u%04x" % character_code)
	return json_text
