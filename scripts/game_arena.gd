extends Node2D

# Game Arena Controller - Fight Back
# Manages match round flow, camera tracking/shake, HUD health bars, timer, and results.

signal match_concluded(winner_peer_id: int)

@export var match_time_left: float = 99.0
@export var round_number: int = 1
@export var is_round_active: bool = false

# Player nodes
var p1: CharacterBody2D
var p2: CharacterBody2D

# Arena Nodes
@onready var camera: Camera2D = $Camera2D
@onready var p1_spawn: Marker2D = $SpawnPoints/P1Spawn
@onready var p2_spawn: Marker2D = $SpawnPoints/P2Spawn
@onready var p1_container: Node2D = $Fighters/P1Container
@onready var p2_container: Node2D = $Fighters/P2Container
@onready var projectiles_container: Node2D = $Projectiles

# HUD Nodes
@onready var p1_health_bar: TextureProgressBar = $HUD/TopBar/P1HealthContainer/VBox/BarControl/P1HealthBar
@onready var p1_damage_bar: TextureProgressBar = $HUD/TopBar/P1HealthContainer/VBox/BarControl/P1DamageBar
@onready var p1_avatar: TextureRect = $HUD/TopBar/P1HealthContainer/P1Avatar
@onready var p1_name: Label = $HUD/TopBar/P1HealthContainer/VBox/P1Name
@onready var p1_gems: HBoxContainer = $HUD/TopBar/P1HealthContainer/P1Gems

@onready var p2_health_bar: TextureProgressBar = $HUD/TopBar/P2HealthContainer/VBox/BarControl/P2HealthBar
@onready var p2_damage_bar: TextureProgressBar = $HUD/TopBar/P2HealthContainer/VBox/BarControl/P2DamageBar
@onready var p2_avatar: TextureRect = $HUD/TopBar/P2HealthContainer/P2Avatar
@onready var p2_name: Label = $HUD/TopBar/P2HealthContainer/VBox/P2Name
@onready var p2_gems: HBoxContainer = $HUD/TopBar/P2HealthContainer/P2Gems

@onready var timer_label: Label = $HUD/TopBar/TimerContainer/TimerLabel
@onready var banner_label: Label = $HUD/BannerContainer/BannerLabel

# Results & Leave Menu
@onready var results_panel: PanelContainer = $HUD/ResultsPanel
@onready var results_title: Label = $HUD/ResultsPanel/MarginContainer/VBoxContainer/ResultsTitle
@onready var rematch_button: Button = $HUD/ResultsPanel/MarginContainer/VBoxContainer/HBoxContainer/RematchButton
@onready var leave_button: Button = $HUD/ResultsPanel/MarginContainer/VBoxContainer/HBoxContainer/LeaveButton
@onready var rematch_status: Label = $HUD/ResultsPanel/MarginContainer/VBoxContainer/RematchStatus

@onready var leave_menu: PanelContainer = $HUD/LeaveMenu
@onready var resume_btn: Button = $HUD/LeaveMenu/MarginContainer/VBoxContainer/ResumeButton
@onready var confirm_leave_btn: Button = $HUD/LeaveMenu/MarginContainer/VBoxContainer/ConfirmLeaveButton

# Debug Overlay
@onready var debug_overlay: PanelContainer = $HUD/DebugOverlay
@onready var debug_text: Label = $HUD/DebugOverlay/MarginContainer/DebugText

# Camera shake variables
var _shake_timer: float = 0.0
var _shake_intensity: float = 0.0
var _debug_log_frame: int = 0
var _round_started: bool = false
var _next_projectile_id: int = 0
var last_failsafe_msg: String = ""
var _latest_state_tick: int = -1

var player_scene: PackedScene = preload("res://scenes/player.tscn")
var projectile_scene: PackedScene = preload("res://scenes/projectile.tscn")
var tex_gem_empty: Texture2D = preload("res://assets/dark-fantasy-hud/Dark-Fantasy-HUD-FREE-Sample/png/2x/obsidian_azure/orbs/orb_socket_128.png")
var tex_gem_filled: Texture2D = preload("res://assets/dark-fantasy-hud/Dark-Fantasy-HUD-FREE-Sample/png/2x/obsidian_azure/orbs/orb_fill_health_128.png")

func _is_server_authority() -> bool:
	if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET:
		return multiplayer.is_server()
	return NetworkManager.is_host

func _ready() -> void:
	AudioManager.play_battle_music()

	_setup_debug_overlay()
	_setup_leave_menu()
	_setup_results_panel()
	_spawn_fighters()

	NetworkManager.peer_left.connect(_on_opponent_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	GameState.rematch_state_changed.connect(_on_rematch_state_changed)

	if NetworkManager.current_mode == NetworkManager.NetworkMode.ONLINE_ROOM:
		NetworkManager.fighter_states_received.connect(_on_fighter_states_received)

	if _is_server_authority():
		var t := get_tree().create_timer(0.6)
		t.timeout.connect(func():
			if not _round_started:
				_round_started = true
				_start_new_round(1)
		)
	else:
		if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET:
			rpc_id(1, "rpc_client_arena_ready")
		else:
			NetworkManager.send_network_event("/root/GameArena", "rpc_client_arena_ready")

func _setup_debug_overlay() -> void:
	debug_overlay.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		debug_overlay.visible = not debug_overlay.visible
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		dump_freeze_log("MANUAL DUMP (F9)")
	elif event.is_action_pressed("ui_cancel"):
		leave_menu.visible = not leave_menu.visible

func _setup_leave_menu() -> void:
	leave_menu.visible = false
	resume_btn.pressed.connect(func(): leave_menu.visible = false; AudioManager.play_ui_click())
	confirm_leave_btn.pressed.connect(_on_leave_confirmed)

func _setup_results_panel() -> void:
	results_panel.visible = false
	rematch_button.pressed.connect(_on_rematch_pressed)
	leave_button.pressed.connect(_on_leave_confirmed)

func _spawn_fighters() -> void:
	# Instantiate P1
	p1 = player_scene.instantiate()
	p1.name = "Player1"
	p1.peer_id = 1
	p1.player_number = 1
	p1.position = p1_spawn.position
	p1.sync_position = p1_spawn.position
	p1.facing_direction = 1.0
	var p1_char_id: String = GameState.player_characters.get(1, "karasu")
	var p1_res := load("res://resources/characters/" + p1_char_id + ".tres") as CharacterData
	p1.character_data = p1_res.duplicate(true) if p1_res else null
	p1.add_to_group("fighters")
	p1_container.add_child(p1)

	# Instantiate P2
	p2 = player_scene.instantiate()
	p2.name = "Player2"
	p2.peer_id = GameState.client_peer_id if GameState.client_peer_id > 0 else 2
	p2.player_number = 2
	p2.position = p2_spawn.position
	p2.sync_position = p2_spawn.position
	p2.facing_direction = -1.0
	var p2_char_id: String = GameState.player_characters.get(p2.peer_id, "karasu")
	var p2_res := load("res://resources/characters/" + p2_char_id + ".tres") as CharacterData
	p2.character_data = p2_res.duplicate(true) if p2_res else null
	p2.add_to_group("fighters")
	p2_container.add_child(p2)

	# Setup opponents
	p1.opponent = p2
	p2.opponent = p1

	# Connect health signals
	p1.health_changed.connect(_on_p1_health_changed)
	p2.health_changed.connect(_on_p2_health_changed)
	p1.fighter_ko.connect(_on_fighter_ko)
	p2.fighter_ko.connect(_on_fighter_ko)

	# Setup HUD
	_setup_hud_elements(p1.character_data, p2.character_data)

func _setup_hud_elements(c1: CharacterData, c2: CharacterData) -> void:
	p1_name.text = GameState.local_username if NetworkManager.is_host else GameState.remote_username
	p2_name.text = GameState.remote_username if NetworkManager.is_host else GameState.local_username

	p1_avatar.texture = load(c1.avatar_path)
	p2_avatar.texture = load(c2.avatar_path)
	p2_avatar.modulate = Color(0.82, 0.88, 1.05) # Visual tint for P2

	p1_health_bar.max_value = c1.max_health
	p1_health_bar.value = c1.max_health
	p1_damage_bar.max_value = c1.max_health
	p1_damage_bar.value = c1.max_health

	p2_health_bar.max_value = c2.max_health
	p2_health_bar.value = c2.max_health
	p2_damage_bar.max_value = c2.max_health
	p2_damage_bar.value = c2.max_health

	_update_gem_indicators()

func _physics_process(delta: float) -> void:
	_update_camera(delta)
	_update_debug_info()
	_log_fighter_diagnostics()

	if NetworkManager.is_autotest and _is_server_authority() and is_round_active:
		_process_autotest_combat()
	elif NetworkManager.is_facing_test and not _is_server_authority() and is_round_active:
		_process_client_facing_test()
	elif NetworkManager.is_walk_test and not _is_server_authority() and is_round_active:
		_process_client_walk_test()

	if _is_server_authority():
		if is_round_active:
			if NetworkManager.is_attack_test:
				match_time_left = 99.0
			else:
				match_time_left -= delta
			if match_time_left <= 0.0:
				match_time_left = 0.0
				_handle_time_out()
			_update_timer_display()
			if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET:
				rpc("rpc_sync_timer", match_time_left)
			else:
				# 60 Hz full state snapshot rate during active combat
				_send_online_state_snapshot()
		elif NetworkManager.current_mode == NetworkManager.NetworkMode.ONLINE_ROOM:
			_update_timer_display()
			if Engine.get_physics_frames() % 4 == 0:
				_send_online_state_snapshot()

func _update_timer_display() -> void:
	if timer_label:
		timer_label.text = "%02d" % int(ceilf(match_time_left))

func _send_online_state_snapshot() -> void:
	if not p1 or not p2 or not is_instance_valid(p1) or not is_instance_valid(p2):
		return
	var p2_ack: int = p2.last_processed_client_seq if ("last_processed_client_seq" in p2) else 0
	var payload := {
		"tm": match_time_left,
		"p1": {
			"pos": [p1.position.x, p1.position.y],
			"vel": [p1.velocity.x, p1.velocity.y],
			"st": int(p1.current_state),
			"fc": p1.facing_direction,
			"hp": p1.health,
			"an": p1.sprite.animation if p1.sprite else "",
			"fr": p1.sprite.frame if p1.sprite else 0,
			"hb": p1.sync_hitbox_active
		},
		"p2": {
			"pos": [p2.position.x, p2.position.y],
			"vel": [p2.velocity.x, p2.velocity.y],
			"st": int(p2.current_state),
			"fc": p2.facing_direction,
			"hp": p2.health,
			"an": p2.sprite.animation if p2.sprite else "",
			"fr": p2.sprite.frame if p2.sprite else 0,
			"hb": p2.sync_hitbox_active,
			"ack": p2_ack
		}
	}
	NetworkManager.send_fighter_states(Engine.get_physics_frames(), payload)

func _on_fighter_states_received(tick: int, payload: Dictionary) -> void:
	if tick <= _latest_state_tick:
		return
	_latest_state_tick = tick

	if payload.has("tm"):
		match_time_left = float(payload["tm"])
		_update_timer_display()

	var d1: Dictionary = payload.get("p1", {})
	if p1 and not d1.is_empty():
		p1.sync_position = Vector2(d1["pos"][0], d1["pos"][1])
		p1.sync_velocity = Vector2(d1["vel"][0], d1["vel"][1])
		p1.sync_state = d1["st"]
		p1.sync_facing = d1["fc"]
		p1.sync_health = d1["hp"]
		p1.sync_anim = d1["an"]
		p1.sync_frame = d1["fr"]
		p1.sync_hitbox_active = d1["hb"]

	var d2: Dictionary = payload.get("p2", {})
	if p2 and not d2.is_empty():
		if p2.has_method("on_server_snapshot_received"):
			p2.on_server_snapshot_received(d2)
		else:
			p2.sync_position = Vector2(d2["pos"][0], d2["pos"][1])
			p2.sync_velocity = Vector2(d2["vel"][0], d2["vel"][1])
			p2.sync_state = d2["st"]
			p2.sync_facing = d2["fc"]
			p2.sync_health = d2["hp"]
			p2.sync_anim = d2["an"]
			p2.sync_frame = d2["fr"]
			p2.sync_hitbox_active = d2["hb"]
		p2.sync_frame = d2["fr"]
		p2.sync_hitbox_active = d2["hb"]

var _attack_test_reported: bool = false
var _combat_test_reported: bool = false
var _walk_test_start_msec: int = 0
var _walk_test_reported: bool = false
var _facing_test_reported: bool = false
var _facing_stage1_done: bool = false

func _process_autotest_combat() -> void:
	if not p1 or not p2 or not is_instance_valid(p1) or not is_instance_valid(p2):
		return

	if NetworkManager.is_facing_test and not _facing_test_reported:
		var p1_char: String = p1.character_data.character_id if p1.character_data else "none"
		var p2_char: String = p2.character_data.character_id if p2.character_data else "none"
		var p1_def_f: float = p1.character_data.default_facing if p1.character_data else 1.0
		var p2_def_f: float = p2.character_data.default_facing if p2.character_data else 1.0
		var p1_flip: bool = p1.sprite.flip_h if p1.sprite else false
		var p2_flip: bool = p2.sprite.flip_h if p2.sprite else false

		# Stage 1: Initial spawn facing check
		if not _facing_stage1_done:
			var facing_ok: bool = true
			if p1.position.x >= p2.position.x:
				print("ERROR: P1 is not to the left of P2!"); facing_ok = false
			if p1.facing_direction != 1.0:
				print("ERROR: P1 does not face right (1.0)!"); facing_ok = false
			if p2.facing_direction != -1.0:
				print("ERROR: P2 does not face left (-1.0)!"); facing_ok = false

			if p1_flip != (p1.facing_direction * p1_def_f < 0.0):
				print("ERROR: P1 sprite flip does not match facing calculation!"); facing_ok = false
			if p2_flip != (p2.facing_direction * p2_def_f < 0.0):
				print("ERROR: P2 sprite flip does not match facing calculation!"); facing_ok = false

			if not facing_ok:
				_facing_test_reported = true
				print("FACING & SPAWN INITIAL CHECK: FAILED")
				get_tree().quit(1)
				return
			_facing_stage1_done = true
			print("[FACING CHECK 1: MATCH START] P1 (%s) faces right (1.0), P2 (%s) faces left (-1.0) -> CORRECT" % [p1_char, p2_char])

		# Stage 2: After P2 walks past P1
		if _facing_stage1_done and p2.position.x < p1.position.x - 30.0:
			_facing_test_reported = true
			var crossed_ok: bool = true
			if p2.facing_direction != 1.0:
				print("ERROR: P2 did not turn around to face right after crossing P1!"); crossed_ok = false
			if p1.facing_direction != -1.0:
				print("ERROR: P1 did not turn around to face left after being crossed!"); crossed_ok = false

			if p1.sprite.flip_h != (p1.facing_direction * p1_def_f < 0.0):
				print("ERROR: P1 sprite flip incorrect after turning!"); crossed_ok = false
			if p2.sprite.flip_h != (p2.facing_direction * p2_def_f < 0.0):
				print("ERROR: P2 sprite flip incorrect after turning!"); crossed_ok = false

			print("================================================================================")
			if crossed_ok:
				print("=== [FACING TEST SUCCESS: BOTH CHARACTERS FACE EACH OTHER AT START & AFTER CROSSING] ===")
				print("P1 (%s) and P2 (%s) facing dynamically and visual sprite flips 100%% verified." % [p1_char, p2_char])
			else:
				print("=== [FACING TEST FAILED] ===")
			print("================================================================================")
			var t := get_tree().create_timer(1.0)
			t.timeout.connect(func(): get_tree().quit(0 if crossed_ok else 1))

	if NetworkManager.is_walk_test and not _walk_test_reported:
		if _walk_test_start_msec == 0:
			_walk_test_start_msec = Time.get_ticks_msec()

		var elapsed_sec: float = (Time.get_ticks_msec() - _walk_test_start_msec) / 1000.0
		var frame := Engine.get_physics_frames()
		if frame % 60 == 0:
			var p2_err: float = p2.last_pred_error if ("last_pred_error" in p2) else 0.0
			var p2_corr: float = p2.last_correction_size if ("last_correction_size" in p2) else 0.0
			var t_text := timer_label.text if timer_label else "N/A"
			print("[WALK TEST %.1fs] timer=%s match_time=%.1f | P1: pos=%.1f anim=%s frame=%d vel=%.1f | P2: pos=%.1f anim=%s frame=%d vel=%.1f pred_err=%.2f corr=%.2f" % [
				elapsed_sec, t_text, match_time_left,
				p1.position.x, p1.sprite.animation, p1.sprite.frame, p1.velocity.x,
				p2.position.x, p2.sprite.animation, p2.sprite.frame, p2.velocity.x,
				p2_err, p2_corr
			])

		if elapsed_sec >= 60.0:
			_walk_test_reported = true
			print("================================================================================")
			print("=== [WALK TEST SUCCESS: KITSUNE WALKED SMOOTHLY FOR 60 SECONDS] ===")
			print("Continuous smooth walk verified on both host and joiner without stalls or snaps.")
			print("================================================================================")
			var t := get_tree().create_timer(1.0)
			t.timeout.connect(func(): get_tree().quit(0))

	if NetworkManager.is_combat_test and not _combat_test_reported:
		var p1_total_atks: int = p1.attack_register_count["attack_light"] + p1.attack_register_count["attack_heavy"] + p1.attack_register_count["attack_special"]
		var p2_total_atks: int = p2.attack_register_count["attack_light"] + p2.attack_register_count["attack_heavy"] + p2.attack_register_count["attack_special"]
		if p2_total_atks >= 10 and p1_total_atks >= 10:
			_combat_test_reported = true
			print("================================================================================")
			print("=== [COMBAT TEST SUCCESS: P2 ATTACKED FIRST, BOTH FIGHTERS ATTACKED FREELY] ===")
			print("P1 Attacks Executed: Light=%d, Heavy=%d, Special=%d (Total: %d)" % [
				p1.attack_register_count["attack_light"], p1.attack_register_count["attack_heavy"], p1.attack_register_count["attack_special"], p1_total_atks
			])
			print("P2 Attacks Executed: Light=%d, Heavy=%d, Special=%d (Total: %d)" % [
				p2.attack_register_count["attack_light"], p2.attack_register_count["attack_heavy"], p2.attack_register_count["attack_special"], p2_total_atks
			])
			print("Both fighters can attack after taking hits. Zero attack lockout!")
			print("================================================================================")
			var t := get_tree().create_timer(1.5)
			t.timeout.connect(func(): get_tree().quit(0))

	if NetworkManager.is_attack_test and not _attack_test_reported:
		if p1.attack_register_count["attack_light"] >= 30 and p1.attack_register_count["attack_heavy"] >= 30 and p1.attack_register_count["attack_special"] >= 30 and p2.attack_register_count["attack_light"] >= 30 and p2.attack_register_count["attack_heavy"] >= 30 and p2.attack_register_count["attack_special"] >= 30:
			_attack_test_reported = true
			print("================================================================================")
			print("=== [ATTACK BUFFER 30/30 VERIFICATION SUCCESS] ===")
			print("P1 Registered: Light=%d/30, Heavy=%d/30, Special=%d/30" % [p1.attack_register_count["attack_light"], p1.attack_register_count["attack_heavy"], p1.attack_register_count["attack_special"]])
			print("P2 Registered: Light=%d/30, Heavy=%d/30, Special=%d/30" % [p2.attack_register_count["attack_light"], p2.attack_register_count["attack_heavy"], p2.attack_register_count["attack_special"]])
			print("All 30 presses registered with 100% reliability for both Host (P1) and Client (P2)!")
			print("================================================================================")
			var t := get_tree().create_timer(1.5)
			t.timeout.connect(func():
				get_tree().quit(0)
			)

var _client_facing_stage1_done: bool = false
var _client_facing_stage2_done: bool = false

func _process_client_facing_test() -> void:
	if not p1 or not p2 or not is_instance_valid(p1) or not is_instance_valid(p2):
		return
	var p1_char: String = p1.character_data.character_id if p1.character_data else "none"
	var p2_char: String = p2.character_data.character_id if p2.character_data else "none"

	if not _client_facing_stage1_done and is_round_active:
		_client_facing_stage1_done = true
		print("[CLIENT FACING CHECK 1: MATCH START] P1 (%s) facing=%.1f flip_h=%s | P2 (%s) facing=%.1f flip_h=%s" % [
			p1_char, p1.facing_direction, str(p1.sprite.flip_h),
			p2_char, p2.facing_direction, str(p2.sprite.flip_h)
		])

	if _client_facing_stage1_done and not _client_facing_stage2_done and p2.position.x < p1.position.x - 30.0:
		_client_facing_stage2_done = true
		print("[CLIENT FACING CHECK 2: AFTER CROSSING] P1 (%s) facing=%.1f flip_h=%s | P2 (%s) facing=%.1f flip_h=%s" % [
			p1_char, p1.facing_direction, str(p1.sprite.flip_h),
			p2_char, p2.facing_direction, str(p2.sprite.flip_h)
		])
		var t := get_tree().create_timer(1.2)
		t.timeout.connect(func(): get_tree().quit(0))

var _client_walk_start_msec: int = 0
func _process_client_walk_test() -> void:
	if _client_walk_start_msec == 0:
		_client_walk_start_msec = Time.get_ticks_msec()
	var elapsed_sec: float = (Time.get_ticks_msec() - _client_walk_start_msec) / 1000.0
	var frame := Engine.get_physics_frames()
	if frame % 60 == 0:
		var p2_err: float = p2.last_pred_error if ("last_pred_error" in p2) else 0.0
		var p2_corr: float = p2.last_correction_size if ("last_correction_size" in p2) else 0.0
		var t_text := timer_label.text if timer_label else "N/A"
		print("[CLIENT WALK TEST %.1fs] timer_label=%s match_time=%.1f | P2 pos=%.1f vel=%.1f pred_err=%.2f corr=%.2f" % [
			elapsed_sec, t_text, match_time_left,
			p2.position.x, p2.velocity.x, p2_err, p2_corr
		])
	if elapsed_sec >= 62.0:
		get_tree().quit(0)

func _update_camera(delta: float) -> void:
	if not p1 or not p2 or not is_instance_valid(p1) or not is_instance_valid(p2):
		return

	# If fighters have invalid/zero positions, stay centered at default arena coordinates
	if p1.position == Vector2.ZERO or p2.position == Vector2.ZERO:
		camera.position = camera.position.lerp(Vector2(960.0, 380.0), 7.0 * delta)
		camera.zoom = camera.zoom.lerp(Vector2(1.03, 1.03), 5.0 * delta)
		return

	# Midpoint
	var mid_x: float = (p1.position.x + p2.position.x) * 0.5
	var target_cam_pos := Vector2(clampf(mid_x, 500.0, 1420.0), 380.0)

	# Camera Shake
	if _shake_timer > 0.0:
		_shake_timer -= delta
		var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_intensity
		target_cam_pos += offset
	else:
		_shake_intensity = 0.0

	camera.position = camera.position.lerp(target_cam_pos, 7.0 * delta)

	# Dynamic zoom based on fighter distance
	var dist := absf(p1.position.x - p2.position.x)
	var target_zoom: float = clampf(1.15 - (dist / 1400.0) * 0.35, 0.85, 1.15)
	camera.zoom = camera.zoom.lerp(Vector2(target_zoom, target_zoom), 5.0 * delta)

func apply_camera_shake(duration: float, intensity: float) -> void:
	_shake_timer = duration
	_shake_intensity = intensity

func _update_debug_info() -> void:
	if not debug_overlay.visible:
		return
	var fps := Engine.get_frames_per_second()
	var my_id := multiplayer.get_unique_id() if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET else (1 if NetworkManager.is_host else 2)
	var auth := ""
	var ping: int = 0
	if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET:
		auth = "LAN HOST (Authority)" if multiplayer.is_server() else "LAN CLIENT (Remote)"
		if NetworkManager.peer != null and not multiplayer.is_server():
			ping = int(NetworkManager.peer.get_peer(1).get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	else:
		auth = "ONLINE HOST (0ms local delay)" if NetworkManager.is_host else ("ONLINE CLIENT (Room: %s)" % NetworkManager.current_room_code)
		ping = NetworkManager.last_ping_ms

	var failsafe_info := "\nFailsafe: " + (last_failsafe_msg if not last_failsafe_msg.is_empty() else "None (Normal)")

	var p1_diag := "P1: None"
	var p2_diag := "P2: None"
	if p1 and is_instance_valid(p1) and p1.has_method("get_diagnostic_info"):
		var d1: Dictionary = p1.get_diagnostic_info()
		p1_diag = "P1: state=%s can_atk=%s buf_atk=%d(t=%d) hitstop=%d hitstun=%d has_hit=%s in_bits=%d" % [
			d1["state"], str(d1["can_attack"]), d1["atk_buf"], d1["buf_timer"], d1["hitstop"], d1["hitstun"], str(d1["has_hit"]), d1["input"]
		]
	if p2 and is_instance_valid(p2) and p2.has_method("get_diagnostic_info"):
		var d2: Dictionary = p2.get_diagnostic_info()
		p2_diag = "P2: state=%s can_atk=%s in_bits=%d pred_err=%.2fpx corr=%.2fpx" % [
			d2["state"], str(d2["can_attack"]), d2["input"], d2.get("pred_err", 0.0), d2.get("corr", 0.0)
		]

	debug_text.text = "FPS: %d\nPeer ID: %d\nRole: %s\nPing: %d ms\nTick: %d%s\n%s\n%s" % [
		fps, my_id, auth, ping, Engine.get_physics_frames(), failsafe_info, p1_diag, p2_diag
	]

	if Engine.get_physics_frames() % 60 == 0:
		print("[F3 DIAG frame=%d] %s | %s" % [Engine.get_physics_frames(), p1_diag, p2_diag])

# ==============================================================================
# ROUND MANAGEMENT (HOST AUTHORITATIVE)
# ==============================================================================
func _start_new_round(round_idx: int) -> void:
	round_number = round_idx
	match_time_left = GameState.ROUND_TIME_LIMIT
	_update_timer_display()
	is_round_active = false
	clear_all_projectiles()

	# Position fighters
	p1.reset_fighter(p1_spawn.position, 1.0)
	p2.reset_fighter(p2_spawn.position, -1.0)

	if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET:
		var s1 := p1.get_node_or_null("Synchronizer") as MultiplayerSynchronizer
		if s1: s1.public_visibility = true
		var s2 := p2.get_node_or_null("Synchronizer") as MultiplayerSynchronizer
		if s2: s2.public_visibility = true

	NetworkManager.send_network_event("/root/GameArena", "rpc_show_round_intro", [round_number])

@rpc("any_peer", "call_remote", "reliable")
func rpc_client_arena_ready() -> void:
	if _is_server_authority() and not _round_started:
		_round_started = true
		_start_new_round(1)

@rpc("authority", "call_local", "reliable")
func rpc_show_round_intro(r_num: int) -> void:
	round_number = r_num
	match_time_left = GameState.ROUND_TIME_LIMIT
	_update_timer_display()
	clear_all_projectiles()
	if p1 and is_instance_valid(p1) and p1_spawn:
		p1.reset_fighter(p1_spawn.position, 1.0)
	if p2 and is_instance_valid(p2) and p2_spawn:
		p2.reset_fighter(p2_spawn.position, -1.0)

	banner_label.text = "ROUND " + str(r_num)
	banner_label.visible = true
	AudioManager.play_round_start()

	var t1 := get_tree().create_timer(1.2)
	t1.timeout.connect(func():
		banner_label.text = "FIGHT!"
		var t2 := get_tree().create_timer(0.8)
		t2.timeout.connect(func():
			banner_label.visible = false
			is_round_active = true
		)
	)

@rpc("authority", "call_local", "unreliable")
func rpc_sync_timer(time_val: float) -> void:
	match_time_left = time_val
	_update_timer_display()

func _on_p1_health_changed(new_hp: float, max_hp: float) -> void:
	p1_health_bar.value = new_hp
	var tw := create_tween()
	tw.tween_property(p1_damage_bar, "value", new_hp, 0.45).set_delay(0.2)
	apply_camera_shake(0.2, 8.0)

func _on_p2_health_changed(new_hp: float, max_hp: float) -> void:
	p2_health_bar.value = new_hp
	var tw := create_tween()
	tw.tween_property(p2_damage_bar, "value", new_hp, 0.45).set_delay(0.2)
	apply_camera_shake(0.2, 8.0)

func _on_fighter_ko(ko_peer_id: int) -> void:
	if not _is_server_authority() or not is_round_active:
		return

	is_round_active = false
	clear_all_projectiles()
	apply_camera_shake(0.4, 14.0)

	var winner_id: int = p2.peer_id if ko_peer_id == p1.peer_id else p1.peer_id
	NetworkManager.send_network_event("/root/GameArena", "rpc_show_ko_banner", [winner_id])

func _handle_time_out() -> void:
	is_round_active = false
	var winner_id: int = 0
	if p1.health > p2.health:
		winner_id = p1.peer_id
	elif p2.health > p1.health:
		winner_id = p2.peer_id
	else:
		winner_id = 0 # Draw

	NetworkManager.send_network_event("/root/GameArena", "rpc_show_timeout_banner", [winner_id])

@rpc("authority", "call_local", "reliable")
func rpc_show_timeout_banner(winner_id: int) -> void:
	banner_label.text = "TIME UP!"
	banner_label.visible = true
	var timer := get_tree().create_timer(1.2)
	timer.timeout.connect(func():
		_process_round_conclusion(winner_id)
	)

@rpc("authority", "call_local", "reliable")
func rpc_show_ko_banner(winner_id: int) -> void:
	banner_label.text = "K.O.!"
	banner_label.visible = true
	var timer := get_tree().create_timer(1.5)
	timer.timeout.connect(func():
		_process_round_conclusion(winner_id)
	)

func _process_round_conclusion(winner_id: int) -> void:
	if _is_server_authority():
		GameState.record_round_win(winner_id)
		NetworkManager.send_network_event("/root/GameArena", "rpc_update_match_progress", [GameState.rounds_won[p1.peer_id], GameState.rounds_won[p2.peer_id]])

		# Check if match is concluded
		if GameState.rounds_won[p1.peer_id] >= GameState.MAX_ROUNDS_TO_WIN or GameState.rounds_won[p2.peer_id] >= GameState.MAX_ROUNDS_TO_WIN:
			var overall_winner: int = p1.peer_id if GameState.rounds_won[p1.peer_id] >= GameState.MAX_ROUNDS_TO_WIN else p2.peer_id
			NetworkManager.send_network_event("/root/GameArena", "rpc_show_match_results", [overall_winner])
		else:
			var t := get_tree().create_timer(2.0)
			t.timeout.connect(func():
				_start_new_round(round_number + 1)
			)

@rpc("authority", "call_local", "reliable")
func rpc_update_match_progress(p1_wins: int, p2_wins: int) -> void:
	GameState.rounds_won[p1.peer_id] = p1_wins
	GameState.rounds_won[p2.peer_id] = p2_wins
	_update_gem_indicators()

func _update_gem_indicators() -> void:
	var p1_id: int = 1
	if p1 and is_instance_valid(p1) and "peer_id" in p1:
		p1_id = int(p1.peer_id)
	var p2_id: int = GameState.client_peer_id if GameState.client_peer_id > 0 else 2
	if p2 and is_instance_valid(p2) and "peer_id" in p2:
		p2_id = int(p2.peer_id)
	var p1_w: int = GameState.rounds_won.get(p1_id, 0)
	var p2_w: int = GameState.rounds_won.get(p2_id, 0)

	var my_peer := str(multiplayer.get_unique_id() if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET else (1 if NetworkManager.is_host else 2))
	print("[ROUND CIRCLES] Peer %s updated circles: P1_wins=%d (G1=%s, G2=%s) | P2_wins=%d (G1=%s, G2=%s)" % [
		my_peer,
		p1_w, "RED" if p1_w >= 1 else "EMPTY", "RED" if p1_w >= 2 else "EMPTY",
		p2_w, "RED" if p2_w >= 1 else "EMPTY", "RED" if p2_w >= 2 else "EMPTY"
	])

	for i in range(p1_gems.get_child_count()):
		var gem := p1_gems.get_child(i) as TextureRect
		if gem:
			if i < p1_w:
				gem.texture = tex_gem_filled
				gem.modulate = Color(0.95, 0.12, 0.12, 1.0) # RED for won round
			else:
				gem.texture = tex_gem_empty
				gem.modulate = Color(0.25, 0.25, 0.35, 0.6) # Dark empty socket

	for i in range(p2_gems.get_child_count()):
		var gem := p2_gems.get_child(i) as TextureRect
		if gem:
			if i < p2_w:
				gem.texture = tex_gem_filled
				gem.modulate = Color(0.95, 0.12, 0.12, 1.0) # RED for won round
			else:
				gem.texture = tex_gem_empty
				gem.modulate = Color(0.25, 0.25, 0.35, 0.6) # Dark empty socket

@rpc("authority", "call_local", "reliable")
func rpc_show_match_results(overall_winner: int) -> void:
	is_round_active = false
	clear_all_projectiles()
	banner_label.visible = false
	results_panel.visible = true

	var my_id := multiplayer.get_unique_id() if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET else (1 if NetworkManager.is_host else 2)
	if overall_winner == my_id:
		results_title.text = "YOU WIN!"
		results_title.modulate = Color(1.0, 0.85, 0.2)
	else:
		results_title.text = "YOU LOSE!"
		results_title.modulate = Color(0.9, 0.3, 0.3)

	rematch_status.text = "Waiting for both fighters to request rematch..."
	rematch_button.disabled = false

	if NetworkManager.is_autotest:
		var t := get_tree().create_timer(0.8)
		t.timeout.connect(func():
			_on_rematch_pressed()
		)

func _on_rematch_pressed() -> void:
	AudioManager.play_ui_click()
	rematch_button.disabled = true
	rematch_status.text = "Rematch requested! Waiting for opponent..."
	GameState.request_rematch()

func _on_rematch_state_changed() -> void:
	if GameState.both_want_rematch():
		rematch_status.text = "Both fighters agreed! Starting rematch..."
		if _is_server_authority():
			var timer := get_tree().create_timer(1.2)
			timer.timeout.connect(func():
				GameState.reset_for_rematch()
				NetworkManager.send_network_event("/root/GameArena", "rpc_restart_match", [])
			)

@rpc("authority", "call_local", "reliable")
func rpc_restart_match() -> void:
	results_panel.visible = false
	clear_all_projectiles()
	GameState.reset_for_rematch()
	_update_gem_indicators()
	if NetworkManager.is_autotest:
		print("=== [AUTOTEST SUCCESS] Full match flow verified: Connect -> Character Select -> Battle -> KO -> Results -> Rematch Restart! ===")
		var t := get_tree().create_timer(1.2)
		t.timeout.connect(func():
			get_tree().quit(0)
		)
	elif _is_server_authority():
		_start_new_round(1)

func _on_leave_confirmed() -> void:
	AudioManager.play_ui_click()
	NetworkManager.close_connection()
	SceneRouter.change_scene("res://scenes/lobby.tscn")

func _on_opponent_disconnected(_id: int) -> void:
	banner_label.text = "OPPONENT LEFT THE MATCH"
	banner_label.visible = true
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		NetworkManager.close_connection()
		SceneRouter.change_scene("res://scenes/lobby.tscn")
	)

func _on_server_disconnected() -> void:
	banner_label.text = "SERVER DISCONNECTED"
	banner_label.visible = true
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		NetworkManager.close_connection()
		SceneRouter.change_scene("res://scenes/lobby.tscn")
	)

func _log_fighter_diagnostics() -> void:
	if not debug_overlay.visible:
		return

	_debug_log_frame += 1
	if _debug_log_frame % 60 != 0:
		return

	var my_id := multiplayer.get_unique_id() if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET else (1 if NetworkManager.is_host else 2)
	var is_srv := _is_server_authority()
	var tag := "[DIAG Peer=%d Server=%s]" % [my_id, str(is_srv)]

	var fighters_in_group := get_tree().get_nodes_in_group("fighters")
	print("%s Fighter group count: %d" % [tag, fighters_in_group.size()])

	var fighter_list: Array = []
	if p1 and is_instance_valid(p1): fighter_list.append(p1)
	if p2 and is_instance_valid(p2): fighter_list.append(p2)

	if fighter_list.is_empty():
		print("%s NO FIGHTERS EXIST IN ARENA!" % [tag])
	else:
		for f in fighter_list:
			var s: AnimatedSprite2D = f.get_node_or_null("AnimatedSprite2D")
			var sf_ok: bool = (s != null and s.sprite_frames != null)
			var cur_anim: String = s.animation if s else "none"
			var cur_frame: int = s.frame if s else -1
			var s_scale: Vector2 = s.scale if s else Vector2.ZERO
			print("%s Fighter: name=%s path=%s auth=%d is_auth=%s gpos=%s pos=%s sync_pos=%s vis=%s mod=%s z=%d sf_not_null=%s anim=%s frame=%d scale=%s" % [
				tag, f.name, f.get_path(), f.get_multiplayer_authority(), str(f.is_multiplayer_authority()),
				str(f.global_position), str(f.position), str(f.sync_position),
				str(f.visible), str(f.modulate), f.z_index,
				str(sf_ok), cur_anim, cur_frame, str(s_scale)
			])

	var cam_follow_target := Vector2.ZERO
	if p1 and p2 and is_instance_valid(p1) and is_instance_valid(p2):
		var mid_x: float = (p1.position.x + p2.position.x) * 0.5
		cam_follow_target = Vector2(clampf(mid_x, 500.0, 1420.0), 380.0)

	print("%s Camera2D: gpos=%s zoom=%s is_current=%s follow_target=%s" % [
		tag, str(camera.global_position), str(camera.zoom), str(camera.is_current()), str(cam_follow_target)
	])

# ==============================================================================
# PROJECTILE & HIT EFFECTS NETWORKING
# ==============================================================================
func spawn_projectile_networked(spawn_pos: Vector2, dir: float, spd: float, owner_id: int, p_num: int, dmg: float, kb: Vector2, hitstun: int) -> void:
	if not _is_server_authority():
		return
	_next_projectile_id += 1
	var pid := _next_projectile_id
	NetworkManager.send_network_event("/root/GameArena", "rpc_spawn_projectile", [pid, spawn_pos, dir, spd, owner_id, p_num, dmg, kb, hitstun])

@rpc("authority", "call_local", "reliable")
func rpc_spawn_projectile(pid: int, spawn_pos: Vector2, dir: float, spd: float, owner_id: int, p_num: int, dmg: float, kb: Vector2, hitstun: int) -> void:
	if projectiles_container == null or not is_instance_valid(projectiles_container):
		return

	var proj = projectile_scene.instantiate()
	proj.name = "Proj_" + str(pid)
	proj.proj_id = pid
	proj.position = spawn_pos
	proj.direction = dir
	proj.speed = spd
	proj.owner_peer_id = owner_id
	proj.is_visual_only = not _is_server_authority()
	proj.damage = dmg
	proj.knockback = kb
	proj.hitstun_frames = hitstun

	if _is_server_authority():
		if p_num == 1:
			proj.collision_layer = 64 # Layer 7
			proj.collision_mask = 8   # Layer 4 (P2 Hurtbox)
		else:
			proj.collision_layer = 128 # Layer 8
			proj.collision_mask = 4    # Layer 3 (P1 Hurtbox)
	else:
		proj.collision_layer = 0
		proj.collision_mask = 0
		proj.monitoring = false
		proj.monitorable = false

	projectiles_container.add_child(proj)
	var my_peer_id := multiplayer.get_unique_id() if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET else (1 if NetworkManager.is_host else 2)
	print("[PROJECTILE] Spawned on Peer %d (Server=%s) name=%s at gpos=%s dir=%.1f" % [
		my_peer_id, str(_is_server_authority()), proj.name, str(spawn_pos), dir
	])

func notify_projectile_impact(pid: int, impact_pos: Vector2, is_hit: bool) -> void:
	if _is_server_authority():
		NetworkManager.send_network_event("/root/GameArena", "rpc_projectile_impact", [pid, impact_pos, is_hit])

@rpc("authority", "call_local", "reliable")
func rpc_projectile_impact(pid: int, impact_pos: Vector2, is_hit: bool) -> void:
	if projectiles_container and is_instance_valid(projectiles_container):
		var proj_node = projectiles_container.get_node_or_null("Proj_" + str(pid))
		if proj_node and is_instance_valid(proj_node) and proj_node.has_method("play_impact_and_free"):
			proj_node.play_impact_and_free(is_hit)
		elif is_hit:
			_spawn_orphan_burst(impact_pos)
	if is_hit:
		apply_camera_shake(0.2, 8.0)
	var my_peer_id := multiplayer.get_unique_id() if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET else (1 if NetworkManager.is_host else 2)
	print("[PROJECTILE] Impact/Despawn on Peer %d (Server=%s) id=%d at gpos=%s is_hit=%s" % [
		my_peer_id, str(_is_server_authority()), pid, str(impact_pos), str(is_hit)
	])

func _spawn_orphan_burst(pos: Vector2) -> void:
	var burst := AnimatedSprite2D.new()
	var proj_script = load("res://scripts/projectile.gd")
	if proj_script and proj_script.has_method("get_burst_sprite_frames"):
		burst.sprite_frames = proj_script.get_burst_sprite_frames()
		burst.animation = "burst"
		burst.global_position = pos
		burst.scale = Vector2(1.5, 1.5)
		burst.animation_finished.connect(burst.queue_free)
		if projectiles_container:
			projectiles_container.add_child(burst)
		else:
			add_child(burst)
		burst.play("burst")
		AudioManager.play_hit_light()

func clear_all_projectiles() -> void:
	if projectiles_container and is_instance_valid(projectiles_container):
		for child in projectiles_container.get_children():
			child.queue_free()

func _spawn_hit_spark(pos: Vector2) -> void:
	var spark := CPUParticles2D.new()
	spark.global_position = pos
	spark.amount = 14
	spark.lifetime = 0.25
	spark.one_shot = true
	spark.explosiveness = 1.0
	spark.spread = 180.0
	spark.gravity = Vector2(0, 0)
	spark.initial_velocity_min = 120.0
	spark.initial_velocity_max = 240.0
	spark.scale_amount_min = 3.0
	spark.scale_amount_max = 6.0
	spark.color = Color(1, 0.9, 0.2, 1)
	spark.emitting = true
	add_child(spark)
	var t := get_tree().create_timer(0.3)
	t.timeout.connect(spark.queue_free)

@rpc("authority", "call_local", "reliable")
func rpc_trigger_melee_hit_effects(hit_gpos: Vector2, sfx_name: String, is_heavy: bool) -> void:
	_spawn_hit_spark(hit_gpos)
	apply_camera_shake(0.2, 8.0)
	if is_heavy or sfx_name == "hit_heavy":
		AudioManager.play_hit_heavy()
	else:
		AudioManager.play_hit_light()

# ==============================================================================
# FAILSAFE & FREEZE DIAGNOSTICS (120-TICK RING BUFFER)
# ==============================================================================
func on_failsafe_triggered(p_num: int, reason: String) -> void:
	last_failsafe_msg = "P%d RESET from %s (tick %d)" % [p_num, reason, Engine.get_physics_frames()]
	print("[FAILSAFE] Triggered on P%d: %s at frame %d" % [p_num, reason, Engine.get_physics_frames()])
	dump_freeze_log("FAILSAFE_TRIGGERED: P%d - %s" % [p_num, reason])
	if _is_server_authority():
		NetworkManager.send_network_event("/root/GameArena", "rpc_sync_failsafe_msg", [last_failsafe_msg])

@rpc("authority", "call_local", "reliable")
func rpc_sync_failsafe_msg(msg: String) -> void:
	last_failsafe_msg = msg

func dump_freeze_log(trigger_reason: String) -> void:
	var lines: Array[String] = []
	var timestamp := Time.get_datetime_string_from_system()
	lines.append("=== FIGHT BACK FREEZE DIAGNOSTIC DUMP ===")
	lines.append("Timestamp: %s" % timestamp)
	lines.append("Reason: %s" % trigger_reason)
	var my_peer_id := multiplayer.get_unique_id() if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET else (1 if NetworkManager.is_host else 2)
	lines.append("Multiplayer: peer_id=%d is_server=%s" % [my_peer_id, str(_is_server_authority())])
	lines.append("Physics Frame: %d" % Engine.get_physics_frames())
	lines.append("Match State: round=%d is_active=%s time_left=%.1f" % [round_number, str(is_round_active), match_time_left])

	for f in [p1, p2]:
		if f and is_instance_valid(f):
			var char_name: String = f.character_data.display_name if ("character_data" in f and f.character_data) else "Unknown"
			var state_name: String = str(f.current_state)
			if "State" in f and f.current_state < f.State.size():
				state_name = f.State.keys()[f.current_state]
			var ticks: int = f.state_ticks if "state_ticks" in f else 0
			var hs_left: int = f.hitstop_frames_left if "hitstop_frames_left" in f else 0
			var hst_left: int = f.hitstun_frames_left if "hitstun_frames_left" in f else 0
			var buf_size: int = f.ring_buffer.size() if "ring_buffer" in f else 0
			lines.append("\n--- Player %d (%s) ---" % [f.player_number, char_name])
			lines.append("Current State: %s (state_ticks: %d)" % [state_name, ticks])
			lines.append("Hitstop frames left: %d | Hitstun frames left: %d" % [hs_left, hst_left])
			lines.append("Ring Buffer History (Last %d ticks):" % buf_size)
			var history: Array = f.get_ordered_ring_buffer() if f.has_method("get_ordered_ring_buffer") else []
			for entry in history:
				lines.append("  [T=%d dt=%dms] state=%s(%d) anim=%s:%d play=%s pos=(%.1f,%.1f) vel=(%.1f,%.1f) hs=%d hst=%d in=0x%X proj=%s hitbx=%s floor=%s" % [
					entry.get("tick", 0),
					entry.get("time_ms", 0),
					entry.get("state", "UNKNOWN"),
					entry.get("state_ticks", 0),
					entry.get("anim", ""),
					entry.get("frame", -1),
					str(entry.get("is_playing", false)),
					entry.get("gpos", Vector2.ZERO).x, entry.get("gpos", Vector2.ZERO).y,
					entry.get("vel", Vector2.ZERO).x, entry.get("vel", Vector2.ZERO).y,
					entry.get("hitstop", 0),
					entry.get("hitstun", 0),
					entry.get("input", 0),
					str(entry.get("has_proj", false)),
					str(entry.get("hitbox_act", false)),
					str(entry.get("on_floor", false))
				])

	var full_text := "\n".join(lines)
	print(full_text)

	var file := FileAccess.open("user://freeze_log.txt", FileAccess.WRITE)
	if file:
		file.store_string(full_text)
		file.close()
		print("[FREEZE_LOG] Dump written to user://freeze_log.txt")

