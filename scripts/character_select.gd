extends Control

# Character Select Controller - Fight Back V2
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

@onready var btn_detola: Button = $VBoxContainer/RosterSection/GridContainer/BtnDetola
@onready var btn_egun: Button = $VBoxContainer/RosterSection/GridContainer/BtnEgun
@onready var lock_in_button: Button = $VBoxContainer/BottomBar/LockInButton
@onready var status_banner: Label = $VBoxContainer/BottomBar/StatusBanner

var characters: Dictionary = {}
var local_selection: String = "detola"
var is_local_locked: bool = false

func _ready() -> void:
	characters["detola"] = preload("res://resources/characters/detola.tres")
	characters["egun"] = preload("res://resources/characters/egun.tres")
	# Legacy aliases for backward compatibility in automated tests
	characters["karasu"] = characters["detola"]
	characters["kitsune"] = characters["detola"]
	characters["yamabushi"] = characters["egun"]
	characters["lava_wizard"] = characters["egun"]

	btn_detola.pressed.connect(func(): _select_char("detola"))
	btn_egun.pressed.connect(func(): _select_char("egun"))

	btn_detola.mouse_entered.connect(func(): _preview_char("detola"))
	btn_egun.mouse_entered.connect(func(): _preview_char("egun"))

	btn_detola.focus_entered.connect(func(): _preview_char("detola"))
	btn_egun.focus_entered.connect(func(): _preview_char("egun"))

	lock_in_button.pressed.connect(_on_lock_in_pressed)

	GameState.player_character_updated.connect(_on_player_char_updated)
	GameState.player_lock_updated.connect(_on_player_lock_updated)
	GameState.both_players_locked.connect(_on_both_players_locked)

	_setup_player_names()
	var default_char := "detola"
	var all_args := OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())
	for arg in all_args:
		if arg.begins_with("--char="):
			default_char = arg.substr(7).strip_edges().to_lower()
	_select_char(default_char)
	btn_detola.grab_focus()

	if NetworkManager.is_autotest:
		var t := get_tree().create_timer(0.6)
		t.timeout.connect(func():
			_on_lock_in_pressed()
		)

	if "--screenshot-charselect" in OS.get_cmdline_user_args() or "--screenshot-charselect" in OS.get_cmdline_args():
		var t := get_tree().create_timer(0.4)
		t.timeout.connect(func():
			var vp := get_viewport()
			if vp:
				var img := vp.get_texture().get_image()
				if img:
					img.save_png("dev-tools/v2_character_select.png")
					print("[SCREENSHOT] Saved dev-tools/v2_character_select.png")
			get_tree().quit(0)
		)

func _setup_player_names() -> void:
	if NetworkManager.is_host:
		p1_name_label.text = GameState.local_username + " (You)"
		p2_name_label.text = GameState.remote_username
	else:
		p1_name_label.text = GameState.remote_username
		p2_name_label.text = GameState.local_username + " (You)"

	_update_slot_display(1, "detola", false)
	_update_slot_display(GameState.client_peer_id, "egun", false)

func _preview_char(char_id: String) -> void:
	if not characters.has(char_id):
		return
	var c: CharacterData = characters[char_id]
	char_name_display.text = c.display_name.to_upper()
	stat_hp.value = (c.max_health / 130.0) * 100.0
	stat_speed.value = (c.walk_speed / 300.0) * 100.0
	stat_power.value = (c.damage_multiplier / 1.3) * 100.0

	if char_id == "detola":
		special_desc.text = "Special: Thunder Crescent - Explosive advancing Dambe kinetic blast."
	elif char_id == "egun":
		special_desc.text = "Special: Cowrie Blast - Unleashes ancestral spirit orb and shockwave."
	else:
		special_desc.text = "Special: Strike ability."

	# Animated preview
	preview_sprite.sprite_frames = c.build_sprite_frames()
	preview_sprite.scale = c.sprite_scale if "sprite_scale" in c else Vector2(1.0, 1.0)
	preview_sprite.offset = c.sprite_offset if "sprite_offset" in c else Vector2(0, -170)
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
	var char_id: String = GameState.player_characters.get(peer_id, "detola")
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
		p2_avatar.modulate = Color(0.95, 0.95, 1.05)
		p2_lock_badge.text = "READY" if is_locked else "SELECTING..."
		p2_lock_badge.modulate = Color(0.3, 1.0, 0.4) if is_locked else Color(0.7, 0.7, 0.7)

func _on_both_players_locked() -> void:
	status_banner.text = "MATCH STARTING! PREPARE TO FIGHT!"
	status_banner.modulate = Color(0.94, 0.78, 0.43, 1.0)
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
