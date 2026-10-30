extends Control

# Character Select Controller - Fight Back
# Simple, robust character selection supporting identical picks with live preview & stats.

@onready var p1_name_label: Label = $VBoxContainer/TopBar/P1Slot/HBox/Info/P1NameLabel
@onready var p1_char_label: Label = $VBoxContainer/TopBar/P1Slot/HBox/Info/P1CharLabel
@onready var p1_avatar: TextureRect = $VBoxContainer/TopBar/P1Slot/HBox/P1Avatar
@onready var p1_lock_badge: Label = $VBoxContainer/TopBar/P1Slot/P1LockBadge

@onready var p2_name_label: Label = $VBoxContainer/TopBar/P2Slot/HBox/Info/P2NameLabel
@onready var p2_char_label: Label = $VBoxContainer/TopBar/P2Slot/HBox/Info/P2CharLabel
@onready var p2_avatar: TextureRect = $VBoxContainer/TopBar/P2Slot/HBox/P2Avatar
@onready var p2_lock_badge: Label = $VBoxContainer/TopBar/P2Slot/P2LockBadge

@onready var preview_sprite: AnimatedSprite2D = $VBoxContainer/MainSection/PreviewArea/PreviewSprite
@onready var char_name_display: Label = $VBoxContainer/MainSection/StatsPanel/VBoxContainer/CharName
@onready var stat_hp: ProgressBar = $VBoxContainer/MainSection/StatsPanel/VBoxContainer/StatHP
@onready var stat_speed: ProgressBar = $VBoxContainer/MainSection/StatsPanel/VBoxContainer/StatSpeed
@onready var stat_power: ProgressBar = $VBoxContainer/MainSection/StatsPanel/VBoxContainer/StatPower
@onready var special_desc: Label = $VBoxContainer/MainSection/StatsPanel/VBoxContainer/SpecialDesc

@onready var btn_karasu: Button = $VBoxContainer/RosterSection/GridContainer/BtnKarasu
@onready var btn_kitsune: Button = $VBoxContainer/RosterSection/GridContainer/BtnKitsune
@onready var btn_yamabushi: Button = $VBoxContainer/RosterSection/GridContainer/BtnYamabushi
@onready var lock_in_button: Button = $VBoxContainer/BottomBar/LockInButton
@onready var status_banner: Label = $VBoxContainer/BottomBar/StatusBanner

var characters: Dictionary = {}
var local_selection: String = "karasu"
var is_local_locked: bool = false

func _ready() -> void:
	characters["karasu"] = preload("res://resources/characters/karasu.tres")
	characters["kitsune"] = preload("res://resources/characters/kitsune.tres")
	characters["yamabushi"] = preload("res://resources/characters/yamabushi.tres")

	btn_karasu.pressed.connect(func(): _select_char("karasu"))
	btn_kitsune.pressed.connect(func(): _select_char("kitsune"))
	btn_yamabushi.pressed.connect(func(): _select_char("yamabushi"))

	btn_karasu.mouse_entered.connect(func(): _preview_char("karasu"))
	btn_kitsune.mouse_entered.connect(func(): _preview_char("kitsune"))
	btn_yamabushi.mouse_entered.connect(func(): _preview_char("yamabushi"))

	btn_karasu.focus_entered.connect(func(): _preview_char("karasu"))
	btn_kitsune.focus_entered.connect(func(): _preview_char("kitsune"))
	btn_yamabushi.focus_entered.connect(func(): _preview_char("yamabushi"))

	lock_in_button.pressed.connect(_on_lock_in_pressed)

	GameState.player_character_updated.connect(_on_player_char_updated)
	GameState.player_lock_updated.connect(_on_player_lock_updated)
	GameState.both_players_locked.connect(_on_both_players_locked)

	_setup_player_names()
	var default_char := "karasu"
	var all_args := OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())
	for arg in all_args:
		if arg.begins_with("--char="):
			default_char = arg.substr(7).strip_edges().to_lower()
	_select_char(default_char)
	btn_karasu.grab_focus()

	if NetworkManager.is_autotest:
		var t := get_tree().create_timer(0.6)
		t.timeout.connect(func():
			_on_lock_in_pressed()
		)

func _setup_player_names() -> void:
	if NetworkManager.is_host:
		p1_name_label.text = GameState.local_username + " (You)"
		p2_name_label.text = GameState.remote_username
	else:
		p1_name_label.text = GameState.remote_username
		p2_name_label.text = GameState.local_username + " (You)"

	_update_slot_display(1, "karasu", false)
	_update_slot_display(GameState.client_peer_id, "karasu", false)

func _preview_char(char_id: String) -> void:
	if not characters.has(char_id):
		return
	var c: CharacterData = characters[char_id]
	char_name_display.text = c.display_name.to_upper()
	stat_hp.value = (c.max_health / 130.0) * 100.0
	stat_speed.value = (c.walk_speed / 300.0) * 100.0
	stat_power.value = (c.damage_multiplier / 1.3) * 100.0

	if char_id == "karasu":
		special_desc.text = "Special: Wing Tempest - Rapid mid-range sonic slash."
	elif char_id == "kitsune":
		special_desc.text = "Special: Fox-Fire - Ranged spiritual flame projectile."
	elif char_id == "yamabushi":
		special_desc.text = "Special: Earth Quake - Heavy seismic shockwave."

	# Animated preview
	preview_sprite.sprite_frames = c.build_sprite_frames()
	preview_sprite.play("idle")

func _select_char(char_id: String) -> void:
	if is_local_locked:
		return
	local_selection = char_id
	_preview_char(char_id)
	AudioManager.play_ui_click()
	GameState.select_character(char_id)

func _on_lock_in_pressed() -> void:
	if is_local_locked:
		return
	is_local_locked = true
	lock_in_button.disabled = true
	lock_in_button.text = "LOCKED IN"
	AudioManager.play_ui_click()
	GameState.lock_character()

func _on_player_char_updated(peer_id: int, char_id: String) -> void:
	_update_slot_display(peer_id, char_id, false)

func _on_player_lock_updated(peer_id: int, is_locked: bool) -> void:
	var char_id: String = GameState.player_characters.get(peer_id, "karasu")
	_update_slot_display(peer_id, char_id, is_locked)

func _update_slot_display(peer_id: int, char_id: String, is_locked: bool) -> void:
	if not characters.has(char_id):
		return
	var c: CharacterData = characters[char_id]
	var avatar_tex: Texture2D = load(c.avatar_path)

	if peer_id == 1:
		p1_char_label.text = c.display_name
		p1_avatar.texture = avatar_tex
		p1_lock_badge.text = "READY" if is_locked else "SELECTING..."
		p1_lock_badge.modulate = Color(0.3, 1.0, 0.4) if is_locked else Color(0.7, 0.7, 0.7)
	else:
		p2_char_label.text = c.display_name
		p2_avatar.texture = avatar_tex
		# Apply subtle cool modulate to P2 avatar for visual differentiation (Override #3)
		p2_avatar.modulate = Color(0.82, 0.88, 1.05)
		p2_lock_badge.text = "READY" if is_locked else "SELECTING..."
		p2_lock_badge.modulate = Color(0.3, 1.0, 0.4) if is_locked else Color(0.7, 0.7, 0.7)

func _on_both_players_locked() -> void:
	status_banner.text = "MATCH STARTING! PREPARE TO FIGHT!"
	status_banner.modulate = Color(1.0, 0.85, 0.2)
	status_banner.visible = true

	if NetworkManager.is_host:
		var timer := get_tree().create_timer(1.2)
		timer.timeout.connect(func():
			if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET:
				rpc("rpc_start_arena")
			else:
				NetworkManager.send_network_event("/root/CharacterSelect", "rpc_start_arena")
		)

@rpc("authority", "call_local", "reliable")
func rpc_start_arena() -> void:
	SceneRouter.change_scene("res://scenes/game_arena.tscn")
