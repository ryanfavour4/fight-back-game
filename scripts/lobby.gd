extends Control

# Lobby Controller - Fight Back
# Supports:
# 1. ONLINE (ROOM CODE): Create / Join with 4-letter room codes via Render relay server.
# 2. LOCAL LAN (DIRECT IP): Offline local tournament mode via ENet UDP.

@onready var username_input: LineEdit = $CenterContainer/Panel/MarginContainer/VBoxContainer/UsernameContainer/UsernameInput
@onready var online_tab_btn: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/ModeSelector/OnlineTabBtn
@onready var lan_tab_btn: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/ModeSelector/LanTabBtn

# Online Section
@onready var online_section: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBoxContainer/OnlineSection
@onready var create_room_btn: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/OnlineSection/HostSection/CreateRoomButton
@onready var room_code_display: PanelContainer = $CenterContainer/Panel/MarginContainer/VBoxContainer/OnlineSection/RoomCodeDisplay
@onready var code_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/OnlineSection/RoomCodeDisplay/HBox/CodeLabel
@onready var copy_code_btn: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/OnlineSection/RoomCodeDisplay/HBox/CopyCodeButton
@onready var room_code_input: LineEdit = $CenterContainer/Panel/MarginContainer/VBoxContainer/OnlineSection/JoinSection/RoomCodeInput
@onready var join_room_btn: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/OnlineSection/JoinSection/JoinRoomButton
@onready var server_ping_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/OnlineSection/ServerPingLabel

# LAN Section
@onready var lan_section: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBoxContainer/LanSection
@onready var ip_input: LineEdit = $CenterContainer/Panel/MarginContainer/VBoxContainer/LanSection/IPInput
@onready var lan_host_btn: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/LanSection/LanButtons/LanHostButton
@onready var lan_join_btn: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/LanSection/LanButtons/LanJoinButton
@onready var lan_info_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/LanSection/LanInfoLabel

# Shared
@onready var status_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/StatusLabel
@onready var players_panel: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBoxContainer/PlayersPanel
@onready var player1_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/PlayersPanel/Player1Label
@onready var player2_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/PlayersPanel/Player2Label
@onready var start_match_button: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/PlayersPanel/StartMatchButton
@onready var back_button: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/BackButton

# Wake-up Modal
@onready var wakeup_modal: PanelContainer = $WakeupModal
@onready var cancel_wakeup_btn: Button = $WakeupModal/Margin/VBox/CancelWakeupBtn

var _config_path: String = "user://settings.cfg"
var _is_online_mode: bool = true

func _ready() -> void:
	wakeup_modal.visible = false
	_load_saved_settings()

	# Mode buttons
	online_tab_btn.pressed.connect(func(): _set_mode(true))
	lan_tab_btn.pressed.connect(func(): _set_mode(false))

	# Online buttons
	create_room_btn.pressed.connect(_on_create_room_pressed)
	join_room_btn.pressed.connect(_on_join_room_pressed)
	copy_code_btn.pressed.connect(_on_copy_code_pressed)

	# LAN buttons
	lan_host_btn.pressed.connect(_on_lan_host_pressed)
	lan_join_btn.pressed.connect(_on_lan_join_pressed)

	# Shared buttons
	back_button.pressed.connect(_on_back_pressed)
	start_match_button.pressed.connect(_on_start_match_pressed)
	cancel_wakeup_btn.pressed.connect(_on_cancel_wakeup_pressed)

	# NetworkManager signals
	NetworkManager.connection_success.connect(_on_connection_success)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.peer_joined.connect(_on_peer_joined)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.players_synced.connect(_on_players_synced)
	NetworkManager.room_created.connect(_on_room_created)
	NetworkManager.room_join_failed.connect(_on_room_join_failed)
	NetworkManager.ping_updated.connect(_on_ping_updated)
	if NetworkManager.has_signal("connection_progress"):
		NetworkManager.connection_progress.connect(_on_connection_progress)

	# Set default tab
	_set_mode(true)

	# Pre-warm relay server on Render
	if NetworkManager.relay_client:
		NetworkManager.relay_client.prewarm_server(NetworkManager.relay_url)

	# If already connected via CLI flag
	if NetworkManager.current_room_code != "" or NetworkManager.peer != null:
		_update_connected_ui()

func _set_mode(online: bool) -> void:
	AudioManager.play_ui_click()
	_is_online_mode = online
	online_section.visible = online
	lan_section.visible = not online

	if online:
		online_tab_btn.modulate = Color(1, 0.85, 0.3)
		lan_tab_btn.modulate = Color(0.7, 0.7, 0.7)
		status_label.text = "Create a room or enter a friend's room code to battle."
	else:
		online_tab_btn.modulate = Color(0.7, 0.7, 0.7)
		lan_tab_btn.modulate = Color(0.4, 0.8, 1)
		status_label.text = "Host or join a match directly on your local network (LAN)."

func _load_saved_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_config_path) == OK:
		username_input.text = cfg.get_value("player", "name", "Fighter_" + str(randi_range(100, 999)))
		ip_input.text = cfg.get_value("network", "last_ip", "127.0.0.1")
		if cfg.has_section_key("network", "relay_url"):
			var saved_relay: String = cfg.get_value("network", "relay_url", "").strip_edges()
			if not saved_relay.is_empty() and NetworkManager.relay_url_source != "--relay argument":
				NetworkManager.relay_url = saved_relay
				NetworkManager.relay_url_source = "saved settings"
				print("[LOBBY] Loaded relay_url from saved settings: '%s'" % saved_relay)
	else:
		username_input.text = "Fighter_" + str(randi_range(100, 999))
		ip_input.text = "127.0.0.1"

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", username_input.text.strip_edges())
	cfg.set_value("network", "last_ip", ip_input.text.strip_edges())
	cfg.set_value("network", "relay_url", NetworkManager.relay_url)
	cfg.save(_config_path)

func _on_connection_progress(elapsed_sec: float, msg: String) -> void:
	status_label.text = msg
	status_label.modulate = Color(1.0, 0.85, 0.3)
	if wakeup_modal:
		wakeup_modal.visible = true
		var desc_lbl = wakeup_modal.get_node_or_null("Margin/VBox/Desc") as Label
		if desc_lbl:
			desc_lbl.text = "Waking up the server...\nThis can take up to a minute on the free tier.\nElapsed: %d s / 90 s" % int(elapsed_sec)

# ==============================================================================
# ONLINE ACTIONS
# ==============================================================================
func _on_create_room_pressed() -> void:
	AudioManager.play_ui_click()
	_save_settings()

	var u_name := username_input.text.strip_edges()
	if u_name.is_empty():
		status_label.text = "Please enter a valid fighter name."
		return

	_set_inputs_locked(true)
	status_label.text = "Connecting to relay server..."
	status_label.modulate = Color(1.0, 0.85, 0.3)

	# Show wakeup modal if server takes > 1.5s to respond
	var wakeup_timer := get_tree().create_timer(1.5)
	wakeup_timer.timeout.connect(func():
		if NetworkManager.current_room_code == "" and NetworkManager.is_host:
			wakeup_modal.visible = true
	)

	NetworkManager.create_online_room(u_name)

func _on_room_created(code: String) -> void:
	wakeup_modal.visible = false
	room_code_display.visible = true
	code_label.text = "YOUR ROOM CODE: " + code
	status_label.text = "Room %s created! Share this code with your friend." % code
	status_label.modulate = Color(0.3, 1.0, 0.4)

func _on_copy_code_pressed() -> void:
	AudioManager.play_ui_click()
	if NetworkManager.current_room_code != "":
		DisplayServer.clipboard_set(NetworkManager.current_room_code)
		copy_code_btn.text = "COPIED!"
		var t := get_tree().create_timer(1.5)
		t.timeout.connect(func(): copy_code_btn.text = "COPY")

func _on_join_room_pressed() -> void:
	AudioManager.play_ui_click()
	_save_settings()

	var u_name := username_input.text.strip_edges()
	var code := room_code_input.text.strip_edges().to_upper()

	if u_name.is_empty():
		status_label.text = "Please enter a valid fighter name."
		return
	if code.length() < 4:
		status_label.text = "Please enter a 4-letter room code (e.g. K7QM)."
		return

	_set_inputs_locked(true)
	status_label.text = "Joining room %s..." % code
	status_label.modulate = Color(1.0, 0.85, 0.3)

	var wakeup_timer := get_tree().create_timer(1.5)
	wakeup_timer.timeout.connect(func():
		if GameState.client_peer_id == 0 and not NetworkManager.is_host and _is_online_mode:
			wakeup_modal.visible = true
	)

	NetworkManager.join_online_room(code, u_name)

func _on_room_join_failed(err_code: String, err_msg: String) -> void:
	wakeup_modal.visible = false
	_set_inputs_locked(false)
	status_label.text = "Join failed: " + err_msg
	status_label.modulate = Color(1.0, 0.3, 0.3)

func _on_ping_updated(ping_ms: int) -> void:
	server_ping_label.text = "Relay Server: Online (Ping: %d ms)" % ping_ms

func _on_cancel_wakeup_pressed() -> void:
	AudioManager.play_ui_click()
	wakeup_modal.visible = false
	NetworkManager.close_connection()
	_set_inputs_locked(false)
	status_label.text = "Connection canceled."
	status_label.modulate = Color(0.85, 0.85, 0.85)

# ==============================================================================
# LAN ACTIONS
# ==============================================================================
func _on_lan_host_pressed() -> void:
	AudioManager.play_ui_click()
	_save_settings()

	var u_name := username_input.text.strip_edges()
	if u_name.is_empty():
		status_label.text = "Please enter a valid fighter name."
		return

	var err := NetworkManager.host_game(u_name)
	if err == OK:
		_set_inputs_locked(true)
		lan_info_label.text = "Host LAN IP: " + NetworkManager.get_lan_ip() + " : 7777"
		lan_info_label.visible = true
		status_label.text = "LAN Server running. Waiting for opponent on local network..."
		status_label.modulate = Color(0.4, 0.9, 1.0)

func _on_lan_join_pressed() -> void:
	AudioManager.play_ui_click()
	_save_settings()

	var u_name := username_input.text.strip_edges()
	var target_ip := ip_input.text.strip_edges()

	if u_name.is_empty():
		status_label.text = "Please enter a valid fighter name."
		return
	if target_ip.is_empty():
		target_ip = "127.0.0.1"

	var err := NetworkManager.join_game(target_ip, u_name)
	if err == OK:
		_set_inputs_locked(true)
		status_label.text = "Connecting to LAN host at " + target_ip + "..."
		status_label.modulate = Color(1.0, 0.85, 0.3)

# ==============================================================================
# CONNECTION EVENTS & READY STATE
# ==============================================================================
func _on_connection_success() -> void:
	wakeup_modal.visible = false
	if not NetworkManager.is_host:
		status_label.text = "Connected! Syncing fighter information..."
		status_label.modulate = Color(0.3, 1.0, 0.4)

func _on_connection_failed(msg: String) -> void:
	wakeup_modal.visible = false
	_set_inputs_locked(false)
	status_label.text = "Error: " + msg
	status_label.modulate = Color(1.0, 0.3, 0.3)
	players_panel.visible = false

func _on_peer_joined(_id: int) -> void:
	status_label.text = "Opponent joined! Ready to fight!"
	status_label.modulate = Color(0.3, 1.0, 0.4)

func _on_players_synced() -> void:
	_update_connected_ui()

func _update_connected_ui() -> void:
	players_panel.visible = true
	status_label.text = "Both fighters ready!"
	status_label.modulate = Color(0.3, 1.0, 0.4)

	if NetworkManager.is_host:
		player1_label.text = "P1 (Host): " + GameState.local_username
		player2_label.text = "P2: " + GameState.remote_username
		start_match_button.visible = true
		start_match_button.text = "PROCEED TO CHARACTER SELECT"
	else:
		player1_label.text = "P1 (Host): " + GameState.remote_username
		player2_label.text = "P2 (You): " + GameState.local_username
		start_match_button.visible = false

func _on_start_match_pressed() -> void:
	if NetworkManager.is_host:
		AudioManager.play_ui_click()
		if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET:
			rpc("rpc_go_to_character_select")
		else:
			NetworkManager.send_network_event("/root/Lobby", "rpc_go_to_character_select")

@rpc("authority", "call_local", "reliable")
func rpc_go_to_character_select() -> void:
	SceneRouter.change_scene("res://scenes/character_select.tscn")

func _on_peer_left(_id: int) -> void:
	status_label.text = "Opponent left the match."
	status_label.modulate = Color(1.0, 0.3, 0.3)
	players_panel.visible = false
	_set_inputs_locked(false)

func _on_server_disconnected() -> void:
	status_label.text = "Host left the match."
	status_label.modulate = Color(1.0, 0.3, 0.3)
	players_panel.visible = false
	_set_inputs_locked(false)

func _set_inputs_locked(locked: bool) -> void:
	create_room_btn.disabled = locked
	join_room_btn.disabled = locked
	lan_host_btn.disabled = locked
	lan_join_btn.disabled = locked
	username_input.editable = not locked
	room_code_input.editable = not locked
	ip_input.editable = not locked

func _on_back_pressed() -> void:
	AudioManager.play_ui_click()
	NetworkManager.close_connection()
	SceneRouter.change_scene("res://scenes/main_menu.tscn")
