extends Node

# Network Manager Autoload - Fight Back
# Supports both:
# 1. ONLINE_ROOM (Default): Outbound WebSocket connection to Render relay server with room codes.
# 2. LAN_ENET: Direct UDP socket on port 7777 for offline LAN tournaments & development.

signal connection_success()
signal connection_failed(error_message: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal server_disconnected()
signal players_synced()

signal room_created(room_code: String)
signal room_join_failed(error_code: String, error_msg: String)
signal ping_updated(ping_ms: int)
signal fighter_states_received(tick: int, payload: Dictionary)

enum NetworkMode { LAN_ENET, ONLINE_ROOM }

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 2
const CONNECTION_TIMEOUT_SEC: float = 6.0
const DEFAULT_RELAY_URL: String = "ws://127.0.0.1:10000"

var current_mode: NetworkMode = NetworkMode.ONLINE_ROOM
var peer: ENetMultiplayerPeer = null
var relay_client: Node = null
var is_host: bool = false
var connection_timer: Timer

var relay_url: String = DEFAULT_RELAY_URL
var current_room_code: String = ""
var last_ping_ms: int = 0

var auto_cli_mode: bool = false
var is_autotest: bool = false
var custom_cli_name: String = ""

var _upnp_thread: Thread

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input_map()

	connection_timer = Timer.new()
	connection_timer.one_shot = true
	connection_timer.timeout.connect(_on_connection_timeout)
	add_child(connection_timer)

	_setup_relay_client()

	multiplayer.peer_connected.connect(_on_enet_peer_connected)
	multiplayer.peer_disconnected.connect(_on_enet_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_enet_connected_to_server)
	multiplayer.connection_failed.connect(_on_enet_connection_failed)
	multiplayer.server_disconnected.connect(_on_enet_server_disconnected)
	players_synced.connect(_on_players_synced_check_cli)

	call_deferred("_check_cli_args")

func _setup_relay_client() -> void:
	var script := load("res://scripts/relay_client.gd") as Script
	relay_client = script.new()
	relay_client.name = "RelayClient"
	add_child(relay_client)

	relay_client.room_created.connect(_on_relay_room_created)
	relay_client.room_join_success.connect(_on_relay_room_join_success)
	relay_client.room_join_failed.connect(_on_relay_room_join_failed)
	relay_client.peer_joined.connect(_on_relay_peer_joined)
	relay_client.peer_left.connect(_on_relay_peer_left)
	relay_client.state_received.connect(_on_relay_state_received)
	relay_client.event_received.connect(_on_relay_event_received)
	relay_client.ping_updated.connect(_on_relay_ping_updated)
	relay_client.connection_failed.connect(_on_relay_connection_failed)
	relay_client.connection_closed.connect(_on_relay_connection_closed)

# ==============================================================================
# ONLINE ROOM MODE
# ==============================================================================
func create_online_room(username: String) -> void:
	close_connection()
	current_mode = NetworkMode.ONLINE_ROOM
	is_host = true
	GameState.local_username = username.strip_edges() if not username.strip_edges().is_empty() else "Host"
	relay_client.connect_and_create_room(relay_url, GameState.local_username)

func join_online_room(code: String, username: String) -> void:
	close_connection()
	current_mode = NetworkMode.ONLINE_ROOM
	is_host = false
	GameState.local_username = username.strip_edges() if not username.strip_edges().is_empty() else "Client"
	relay_client.connect_and_join_room(relay_url, code, GameState.local_username)

func _on_relay_room_created(code: String) -> void:
	current_room_code = code
	print("[ONLINE] Room created successfully! Code: " + code)
	room_created.emit(code)
	GameState.register_players(1, 2)

func _on_relay_room_join_success(code: String, host_name: String, assigned_name: String) -> void:
	current_room_code = code
	print("[ONLINE] Joined room %s successfully as %s vs host %s" % [code, assigned_name, host_name])
	GameState.local_username = assigned_name
	GameState.remote_username = host_name
	GameState.register_players(1, 2)
	connection_success.emit()
	players_synced.emit()

func _on_relay_room_join_failed(err_code: String, err_msg: String) -> void:
	print("[ONLINE] Room join failed! Code: %s, Message: %s" % [err_code, err_msg])
	room_join_failed.emit(err_code, err_msg)
	connection_failed.emit(err_msg)

func _on_relay_peer_joined(role: String, remote_name: String) -> void:
	print("[ONLINE] Peer joined: role=%s, name=%s" % [role, remote_name])
	if is_host and role == "client":
		GameState.remote_username = remote_name
		peer_joined.emit(2)
		players_synced.emit()

func _on_relay_peer_left(reason: String) -> void:
	if is_host:
		peer_left.emit(2)
	else:
		server_disconnected.emit()

func _on_relay_ping_updated(ping_ms: int) -> void:
	last_ping_ms = ping_ms
	ping_updated.emit(ping_ms)

func _on_relay_connection_failed(msg: String) -> void:
	connection_failed.emit(msg)

func _on_relay_connection_closed(reason: String) -> void:
	if is_host:
		peer_left.emit(2)
	else:
		server_disconnected.emit()

func _on_relay_state_received(tick: int, payload: Dictionary) -> void:
	fighter_states_received.emit(tick, payload)

func _on_relay_event_received(event_name: String, args: Array) -> void:
	if event_name == "dispatch":
		if args.size() >= 3:
			var target_path: String = args[0]
			var method_name: String = args[1]
			var method_args: Array = args[2]
			var node := get_tree().root.get_node_or_null(target_path)
			if node and node.has_method(method_name):
				node.callv(method_name, method_args)
	elif event_name == "client_input":
		if is_host and args.size() >= 2:
			var arena = get_tree().current_scene
			if arena and "p2" in arena and arena.p2 and arena.p2.has_method("rpc_send_client_input"):
				arena.p2.rpc_send_client_input(args[0], args[1])

# ==============================================================================
# UNIFIED EVENT & STATE DISPATCHER
# ==============================================================================
func send_network_event(target_path: String, method_name: String, args: Array = []) -> void:
	if current_mode == NetworkMode.LAN_ENET:
		var node := get_tree().root.get_node_or_null(target_path)
		if node and node.has_method(method_name):
			node.rpc.callv([method_name] + args)
	else:
		# In Online mode: execute locally (call_local equivalent)
		var node := get_tree().root.get_node_or_null(target_path)
		if node and node.has_method(method_name):
			node.callv(method_name, args)
		# Forward reliable EVENT to opponent via relay
		if relay_client:
			relay_client.send_event("dispatch", [target_path, method_name, args])

func send_fighter_states(tick: int, payload: Dictionary) -> void:
	if current_mode == NetworkMode.ONLINE_ROOM and is_host:
		if relay_client:
			relay_client.send_state(tick, payload)

func send_client_input(mask: int, tick: int) -> void:
	if current_mode == NetworkMode.LAN_ENET:
		var arena = get_tree().current_scene
		if arena and "p2" in arena and arena.p2:
			arena.p2.rpc_id(1, "rpc_send_client_input", mask, tick)
	else:
		if relay_client:
			relay_client.send_event("client_input", [mask, tick])

# ==============================================================================
# LAN ENET MODE (PRESERVED UNCHANGED)
# ==============================================================================
func host_game(username: String, port: int = DEFAULT_PORT) -> Error:
	close_connection()
	current_mode = NetworkMode.LAN_ENET
	is_host = true
	GameState.local_username = username.strip_edges() if not username.strip_edges().is_empty() else "Host"

	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		is_host = false
		peer = null
		connection_failed.emit("Failed to create server on port " + str(port) + " (Error " + str(err) + ")")
		return err

	multiplayer.multiplayer_peer = peer
	_setup_upnp_async(port)
	connection_success.emit()
	return OK

func join_game(ip_address: String, username: String, port: int = DEFAULT_PORT) -> Error:
	close_connection()
	current_mode = NetworkMode.LAN_ENET
	is_host = false
	var target_ip := ip_address.strip_edges()
	if target_ip.is_empty():
		target_ip = "127.0.0.1"

	GameState.local_username = username.strip_edges() if not username.strip_edges().is_empty() else "Client"

	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(target_ip, port)
	if err != OK:
		peer = null
		connection_failed.emit("Failed to connect to " + target_ip + " (Error " + str(err) + ")")
		return err

	multiplayer.multiplayer_peer = peer
	connection_timer.start(CONNECTION_TIMEOUT_SEC)
	return OK

func close_connection() -> void:
	if connection_timer and not connection_timer.is_stopped():
		connection_timer.stop()

	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	peer = null
	if relay_client:
		relay_client.disconnect_relay()

	is_host = false
	current_room_code = ""
	GameState.reset_full_match()

func _on_enet_peer_connected(id: int) -> void:
	peer_joined.emit(id)
	if is_host:
		GameState.register_players(1, id)
		rpc_id(id, "rpc_receive_host_info", GameState.local_username)

@rpc("authority", "call_remote", "reliable")
func rpc_receive_host_info(host_name: String) -> void:
	GameState.remote_username = host_name
	GameState.register_players(1, multiplayer.get_unique_id())
	rpc_id(1, "rpc_receive_client_info", GameState.local_username)
	players_synced.emit()

@rpc("any_peer", "call_remote", "reliable")
func rpc_receive_client_info(client_name: String) -> void:
	GameState.remote_username = client_name
	players_synced.emit()

func _on_enet_peer_disconnected(id: int) -> void:
	peer_left.emit(id)
	close_connection()

func _on_enet_connected_to_server() -> void:
	connection_timer.stop()
	connection_success.emit()

func _on_enet_connection_failed() -> void:
	connection_timer.stop()
	close_connection()
	connection_failed.emit("Connection refused or server unreachable.")

func _on_connection_timeout() -> void:
	close_connection()
	connection_failed.emit("Connection timed out.")

func _on_enet_server_disconnected() -> void:
	close_connection()
	server_disconnected.emit()

func get_lan_ip() -> String:
	var addresses := IP.get_local_addresses()
	for addr in addresses:
		if not addr.contains(":") and addr != "127.0.0.1":
			if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
				return addr
	return "127.0.0.1"

func _exit_tree() -> void:
	if _upnp_thread and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()
	close_connection()

func _setup_upnp_async(port: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _upnp_thread and _upnp_thread.is_started():
		return
	_upnp_thread = Thread.new()
	_upnp_thread.start(_run_upnp_task.bind(port))

func _run_upnp_task(port: int) -> void:
	var upnp := UPNP.new()
	var res: int = upnp.discover(1500, 2, "InternetGatewayDevice")
	if res == UPNP.UPNP_RESULT_SUCCESS and upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
		upnp.add_port_mapping(port, port, "FightBack_UDP", "UDP")
		upnp.add_port_mapping(port, port, "FightBack_TCP", "TCP")

func _on_players_synced_check_cli() -> void:
	if auto_cli_mode and is_host:
		var timer := get_tree().create_timer(0.4)
		timer.timeout.connect(func():
			if current_mode == NetworkMode.LAN_ENET:
				rpc("rpc_cli_go_to_char_select")
			else:
				send_network_event("/root/NetworkManager", "rpc_cli_go_to_char_select")
		)

@rpc("authority", "call_local", "reliable")
func rpc_cli_go_to_char_select() -> void:
	SceneRouter.change_scene("res://scenes/character_select.tscn")

func _setup_input_map() -> void:
	var mappings: Dictionary = {
		"p_left": [
			_make_key(KEY_A),
			_make_key(KEY_LEFT),
			_make_joy_button(JOY_BUTTON_DPAD_LEFT),
			_make_joy_axis(JOY_AXIS_LEFT_X, -1.0)
		],
		"p_right": [
			_make_key(KEY_D),
			_make_key(KEY_RIGHT),
			_make_joy_button(JOY_BUTTON_DPAD_RIGHT),
			_make_joy_axis(JOY_AXIS_LEFT_X, 1.0)
		],
		"p_jump": [
			_make_key(KEY_W),
			_make_key(KEY_UP),
			_make_key(KEY_SPACE),
			_make_joy_button(JOY_BUTTON_DPAD_UP),
			_make_joy_button(JOY_BUTTON_A)
		],
		"p_light": [
			_make_key(KEY_J),
			_make_key(KEY_Z),
			_make_joy_button(JOY_BUTTON_X)
		],
		"p_heavy": [
			_make_key(KEY_K),
			_make_key(KEY_X),
			_make_joy_button(JOY_BUTTON_Y)
		],
		"p_special": [
			_make_key(KEY_L),
			_make_key(KEY_C),
			_make_joy_button(JOY_BUTTON_B)
		],
		"toggle_debug": [
			_make_key(KEY_F3)
		]
	}
	for action_name in mappings:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		for ev in mappings[action_name]:
			InputMap.action_add_event(action_name, ev)

func _make_key(key: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	return ev

func _make_joy_button(btn: JoyButton) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = btn
	return ev

func _make_joy_axis(axis: JoyAxis, val: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = val
	return ev

func _check_cli_args() -> void:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())

	var auto_host := false
	var auto_join_ip := ""
	var custom_name := ""
	var online_create := false
	var online_join_code := ""

	for arg in args:
		if arg == "--host":
			auto_host = true
		elif arg.begins_with("--join="):
			auto_join_ip = arg.substr(7).strip_edges()
		elif arg == "--join":
			auto_join_ip = "127.0.0.1"
		elif arg == "--autotest":
			is_autotest = true
		elif arg.begins_with("--name="):
			custom_name = arg.substr(7).strip_edges()
			custom_cli_name = custom_name
		elif arg.begins_with("--relay="):
			relay_url = arg.substr(8).strip_edges()
		elif arg == "--create-room":
			online_create = true
		elif arg.begins_with("--join-room="):
			online_join_code = arg.substr(12).strip_edges().to_upper()

	if auto_host:
		auto_cli_mode = true
		var h_name: String = custom_name if not custom_name.is_empty() else "HostPlayer"
		host_game(h_name)
		var tree := get_tree()
		if tree:
			tree.change_scene_to_file("res://scenes/lobby.tscn")
	elif not auto_join_ip.is_empty():
		auto_cli_mode = true
		var j_name: String = custom_name if not custom_name.is_empty() else "ClientPlayer"
		join_game(auto_join_ip, j_name)
		var tree := get_tree()
		if tree:
			tree.change_scene_to_file("res://scenes/lobby.tscn")
	elif online_create:
		auto_cli_mode = true
		var h_name: String = custom_name if not custom_name.is_empty() else "OnlineHost"
		create_online_room(h_name)
		var tree := get_tree()
		if tree:
			tree.change_scene_to_file("res://scenes/lobby.tscn")
	elif not online_join_code.is_empty():
		auto_cli_mode = true
		var j_name: String = custom_name if not custom_name.is_empty() else "OnlineClient"
		join_online_room(online_join_code, j_name)
		var tree := get_tree()
		if tree:
			tree.change_scene_to_file("res://scenes/lobby.tscn")
