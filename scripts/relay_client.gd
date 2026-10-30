extends Node

# Relay Client - Fight Back
# Manages the outbound WebSocket connection to the Render relay server for Room-Code online play.
# Handles HTTP wake-up ping, room creation, room joining, ping/pong RTT measurement,
# and high-speed bidirectional routing of STATE (loss-tolerant) and EVENT (guaranteed) packets.

signal connected_to_relay()
signal connection_failed(error_message: String)
signal connection_closed(reason: String)

signal room_created(room_code: String)
signal room_join_success(room_code: String, host_name: String, assigned_name: String)
signal room_join_failed(error_code: String, error_msg: String)

signal peer_joined(role: String, username: String)
signal peer_left(reason: String)

signal state_received(tick: int, payload: Dictionary)
signal event_received(event_name: String, args: Array)

signal ping_updated(ping_ms: int)
signal server_awake_status(is_awake: bool)
signal connection_progress(elapsed_sec: float, message: String)

const GAME_VERSION: String = "1.0.0"
const KEEPALIVE_INTERVAL_SEC: float = 25.0
const PING_INTERVAL_SEC: float = 1.0
const TOTAL_CONNECT_TIMEOUT_SEC: float = 90.0
const RETRY_INTERVAL_SEC: float = 2.5

var ws: WebSocketPeer = null
var relay_url: String = ""
var relay_url_source: String = "default"
var current_room_code: String = ""
var is_host: bool = false
var local_username: String = ""
var last_ping_ms: int = 0

var _last_keepalive_time: float = 0.0
var _last_ping_time: float = 0.0
var _is_connecting: bool = false
var _total_connect_elapsed: float = 0.0
var _second_log_timer: float = 0.0
var _retry_cooldown: float = 0.0
var _last_close_code: int = -1
var _last_close_reason: String = ""

# HTTP pre-warm request node
var http_request: HTTPRequest = null
var is_server_awake: bool = false
var is_waking_server: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	http_request = HTTPRequest.new()
	http_request.timeout = 45.0 # Allow time for Render cold start
	http_request.request_completed.connect(_on_http_request_completed)
	add_child(http_request)

func _state_to_name(st: int) -> String:
	match st:
		WebSocketPeer.STATE_CONNECTING: return "STATE_CONNECTING (0)"
		WebSocketPeer.STATE_OPEN: return "STATE_OPEN (1)"
		WebSocketPeer.STATE_CLOSING: return "STATE_CLOSING (2)"
		WebSocketPeer.STATE_CLOSED: return "STATE_CLOSED (3)"
		_: return "STATE_UNKNOWN (" + str(st) + ")"

func _process(delta: float) -> void:
	if _is_connecting:
		_total_connect_elapsed += delta
		_second_log_timer += delta

		var cur_state: int = WebSocketPeer.STATE_CLOSED
		if ws != null:
			ws.poll()
			cur_state = ws.get_ready_state()

		# Log state each second while connecting
		if _second_log_timer >= 1.0:
			_second_log_timer -= 1.0
			var msg := "Waking up the server... (%d s)" % int(_total_connect_elapsed)
			print("[RELAY] Connecting to '%s' (Source: %s) | Elapsed: %0.1fs / %0.1fs | WebSocketPeer state: %s" % [
				relay_url, relay_url_source, _total_connect_elapsed, TOTAL_CONNECT_TIMEOUT_SEC, _state_to_name(cur_state)
			])
			connection_progress.emit(_total_connect_elapsed, msg)

		if cur_state == WebSocketPeer.STATE_OPEN:
			_is_connecting = false
			_total_connect_elapsed = 0.0
			is_server_awake = true
			print("[RELAY] SUCCESS: Connected to relay server '%s'!" % relay_url)
			connected_to_relay.emit()
			_send_pending_handshake()

		elif cur_state == WebSocketPeer.STATE_CLOSED or ws == null:
			if ws != null:
				_last_close_code = ws.get_close_code()
				_last_close_reason = ws.get_close_reason()

			# Check if 90s budget expired
			if _total_connect_elapsed >= TOTAL_CONNECT_TIMEOUT_SEC:
				_is_connecting = false
				ws = null
				var msg := "Failed to connect to relay server after %d seconds." % int(TOTAL_CONNECT_TIMEOUT_SEC)
				if not _last_close_reason.is_empty():
					msg += " (" + _last_close_reason + ")"
				elif _last_close_code > 0:
					msg += " (Close Code " + str(_last_close_code) + ")"
				print("[RELAY] TIMEOUT: Connection attempt failed permanently after %0.1fs! Last close code: %d, reason: '%s'" % [
					_total_connect_elapsed, _last_close_code, _last_close_reason
				])
				connection_failed.emit(msg)
				return
			else:
				# Server may be waking up - retry connection
				_retry_cooldown -= delta
				if _retry_cooldown <= 0.0:
					_retry_cooldown = RETRY_INTERVAL_SEC
					print("[RELAY] Server sleeping or connection refused (Close code=%d, reason='%s'). Retrying in %0.1fs... (Elapsed: %0.1fs / %0.1fs)" % [
						_last_close_code, _last_close_reason, RETRY_INTERVAL_SEC, _total_connect_elapsed, TOTAL_CONNECT_TIMEOUT_SEC
					])
					prewarm_server(relay_url)
					_open_websocket_socket()

		return

	if ws == null:
		return

	ws.poll()
	var state := ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		# Process incoming packets
		while ws.get_available_packet_count() > 0:
			var packet := ws.get_packet()
			var json_str := packet.get_string_from_utf8()
			_handle_incoming_json(json_str)

		# Keepalive & Ping management
		var now_sec := Time.get_ticks_msec() / 1000.0
		if now_sec - _last_ping_time >= PING_INTERVAL_SEC:
			_last_ping_time = now_sec
			_send_ping()

	elif state == WebSocketPeer.STATE_CLOSED:
		var code := ws.get_close_code()
		var reason := ws.get_close_reason()
		ws = null
		print("[RELAY] Connection closed! Code: %d, reason: '%s'" % [code, reason])
		connection_closed.emit(reason if not reason.is_empty() else "Connection closed by server (code " + str(code) + ")")

# ==============================================================================
# HTTP SERVER WAKE-UP PRE-WARM (RENDER COLD START)
# ==============================================================================
func prewarm_server(target_url: String) -> void:
	if is_server_awake or is_waking_server:
		return
	var http_url := target_url.replace("wss://", "https://").replace("ws://", "http://")
	if not http_url.begins_with("http"):
		http_url = "http://" + http_url
	if not http_url.ends_with("/health"):
		http_url = http_url.rstrip("/") + "/health"

	is_waking_server = true
	var err := http_request.request(http_url)
	if err != OK:
		is_waking_server = false

func _on_http_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	is_waking_server = false
	if response_code == 200:
		is_server_awake = true
		server_awake_status.emit(true)
	else:
		server_awake_status.emit(false)

# ==============================================================================
# CONNECTION & HANDSHAKE
# ==============================================================================
var _pending_action: String = "" # "create" | "join"
var _pending_code: String = ""

func connect_and_create_room(url: String, username: String, url_source: String = "default") -> void:
	relay_url = url
	relay_url_source = url_source
	local_username = username
	is_host = true
	_pending_action = "create"
	print("[RELAY] Initiating room creation. Target URL: '%s' (Source: %s)" % [relay_url, relay_url_source])
	_start_websocket_connection()

func connect_and_join_room(url: String, code: String, username: String, url_source: String = "default") -> void:
	relay_url = url
	relay_url_source = url_source
	local_username = username
	is_host = false
	_pending_action = "join"
	_pending_code = code.strip_edges().to_upper()
	print("[RELAY] Initiating room join for code '%s'. Target URL: '%s' (Source: %s)" % [_pending_code, relay_url, relay_url_source])
	_start_websocket_connection()

func _start_websocket_connection() -> void:
	disconnect_relay()
	_is_connecting = true
	_total_connect_elapsed = 0.0
	_second_log_timer = 0.0
	_retry_cooldown = 0.0
	_last_close_code = -1
	_last_close_reason = ""
	prewarm_server(relay_url)
	_open_websocket_socket()

func _open_websocket_socket() -> void:
	if ws != null:
		ws = null
	ws = WebSocketPeer.new()
	var err := ws.connect_to_url(relay_url)
	if err != OK:
		print("[RELAY] ws.connect_to_url('%s') returned immediate error code: %d" % [relay_url, err])
		ws = null
		_retry_cooldown = RETRY_INTERVAL_SEC

func _send_pending_handshake() -> void:
	if _pending_action == "create":
		_send_json({
			"type": "create_room",
			"username": local_username,
			"version": GAME_VERSION
		})
	elif _pending_action == "join":
		_send_json({
			"type": "join_room",
			"room_code": _pending_code,
			"username": local_username,
			"version": GAME_VERSION
		})
	_pending_action = ""

func disconnect_relay() -> void:
	if ws != null:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.close(1000, "Client leaving")
		ws = null
	_is_connecting = false
	_total_connect_elapsed = 0.0
	_second_log_timer = 0.0
	_retry_cooldown = 0.0
	current_room_code = ""

# ==============================================================================
# TRANSMISSION (STATE vs EVENT)
# ==============================================================================
func send_state(tick: int, payload: Dictionary) -> void:
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_send_json({
		"type": "game_data",
		"sub_type": "state",
		"tick": tick,
		"payload_str": var_to_str(payload)
	})

func send_event(event_name: String, args: Array) -> void:
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_send_json({
		"type": "game_data",
		"sub_type": "event",
		"event": event_name,
		"args_str": var_to_str(args)
	})

func _send_ping() -> void:
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_send_json({
		"type": "ping",
		"t": Time.get_ticks_msec()
	})

func _send_json(data: Dictionary) -> void:
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var text := JSON.stringify(data)
	ws.send_text(text)

# ==============================================================================
# INCOMING PACKET ROUTING
# ==============================================================================
func _handle_incoming_json(json_str: String) -> void:
	var parsed: Variant = JSON.parse_string(json_str)
	if not (parsed is Dictionary):
		return

	var msg := parsed as Dictionary
	var type: String = msg.get("type", "")

	match type:
		"pong":
			var sent_t: int = msg.get("t", 0)
			if sent_t > 0:
				last_ping_ms = max(0, Time.get_ticks_msec() - sent_t)
				ping_updated.emit(last_ping_ms)

		"room_created":
			current_room_code = msg.get("room_code", "")
			local_username = msg.get("assigned_username", local_username)
			room_created.emit(current_room_code)

		"join_result":
			var success: bool = msg.get("success", false)
			if success:
				current_room_code = msg.get("room_code", "")
				var host_name: String = msg.get("host_username", "Host")
				var assigned_name: String = msg.get("assigned_username", local_username)
				local_username = assigned_name
				room_join_success.emit(current_room_code, host_name, assigned_name)
			else:
				var err_code: String = msg.get("error", "UNKNOWN")
				var err_msg: String = msg.get("message", "Failed to join room")
				room_join_failed.emit(err_code, err_msg)

		"peer_joined":
			var role: String = msg.get("role", "")
			var username: String = msg.get("username", "")
			peer_joined.emit(role, username)

		"peer_left":
			var reason: String = msg.get("reason", "Opponent left the match")
			peer_left.emit(reason)

		"game_data":
			var sub_type: String = msg.get("sub_type", "")
			if sub_type == "state":
				var tick: int = msg.get("tick", 0)
				var payload: Dictionary = {}
				if msg.has("payload_str"):
					var parsed_p = str_to_var(msg["payload_str"])
					if parsed_p is Dictionary:
						payload = parsed_p
				elif msg.has("payload"):
					payload = msg.get("payload", {})
				state_received.emit(tick, payload)
			elif sub_type == "event":
				var event_name: String = msg.get("event", "")
				var args: Array = []
				if msg.has("args_str"):
					var parsed_a = str_to_var(msg["args_str"])
					if parsed_a is Array:
						args = parsed_a
					else:
						args = [parsed_a]
				elif msg.has("args"):
					args = msg.get("args", [])
				event_received.emit(event_name, args)
