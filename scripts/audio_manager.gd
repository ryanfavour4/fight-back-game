extends Node

# Audio Manager Autoload - Fight Back
# Handles background music and sound effects across Master, Music, and SFX buses.

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"

const PATH_MENU_MUSIC: String = "res://assets/futuristic-sounds-and-music-pack/Music/MP3/Game_menu_theme_loopable.mp3"
const PATH_BATTLE_MUSIC: String = "res://assets/futuristic-sounds-and-music-pack/Music/MP3/Battle_theme_loopable.mp3"

const PATH_SFX_HIT_LIGHT: String = "res://assets/futuristic-sounds-and-music-pack/Sounds/Can_drop.wav"
const PATH_SFX_HIT_HEAVY: String = "res://assets/futuristic-sounds-and-music-pack/Sounds/Crate_open_1.wav"
const PATH_SFX_SWING: String = "res://assets/futuristic-sounds-and-music-pack/Sounds/Laser_shot.wav"
const PATH_SFX_SPECIAL: String = "res://assets/futuristic-sounds-and-music-pack/Sounds/Truck_gun_shot.wav"
const PATH_SFX_JUMP: String = "res://assets/futuristic-sounds-and-music-pack/Sounds/Neon_1.wav"
const PATH_SFX_KO: String = "res://assets/futuristic-sounds-and-music-pack/Sounds/Tech_death_1.wav"
const PATH_SFX_UI_CLICK: String = "res://assets/futuristic-sounds-and-music-pack/Sounds/Insert_coin.wav"
const PATH_SFX_ROUND_START: String = "res://assets/futuristic-sounds-and-music-pack/Sounds/Police_signal.wav"

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_pool_size: int = 12
var _current_sfx_index: int = 0

var _streams: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio_players()
	_preload_audio()
	_load_volume_settings()

func _exit_tree() -> void:
	stop_music()
	if _music_player:
		_music_player.stream = null
	for p in _sfx_players:
		p.stream = null
	_streams.clear()

func _setup_audio_players() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = BUS_MUSIC
	add_child(_music_player)

	for i in range(_sfx_pool_size):
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer_" + str(i)
		player.bus = BUS_SFX
		add_child(player)
		_sfx_players.append(player)

func _preload_audio() -> void:
	_streams["menu_music"] = _load_stream(PATH_MENU_MUSIC)
	_streams["battle_music"] = _load_stream(PATH_BATTLE_MUSIC)
	_streams["hit_light"] = _load_stream(PATH_SFX_HIT_LIGHT)
	_streams["hit_heavy"] = _load_stream(PATH_SFX_HIT_HEAVY)
	_streams["swing"] = _load_stream(PATH_SFX_SWING)
	_streams["special"] = _load_stream(PATH_SFX_SPECIAL)
	_streams["jump"] = _load_stream(PATH_SFX_JUMP)
	_streams["ko"] = _load_stream(PATH_SFX_KO)
	_streams["ui_click"] = _load_stream(PATH_SFX_UI_CLICK)
	_streams["round_start"] = _load_stream(PATH_SFX_ROUND_START)

func _load_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var stream: AudioStream = load(path)
		return stream
	return null

func play_menu_music() -> void:
	play_music(_streams.get("menu_music"))

func play_battle_music() -> void:
	play_music(_streams.get("battle_music"))

func play_music(stream: AudioStream) -> void:
	if stream == null:
		return
	if _music_player.stream == stream and _music_player.playing:
		return
	_music_player.stream = stream
	_music_player.play()

func stop_music() -> void:
	_music_player.stop()

func play_sfx(stream: AudioStream, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	if stream == null or _sfx_players.is_empty():
		return
	var player: AudioStreamPlayer = _sfx_players[_current_sfx_index]
	_current_sfx_index = (_current_sfx_index + 1) % _sfx_players.size()
	player.stream = stream
	player.pitch_scale = pitch_scale
	player.volume_db = volume_db
	player.play()

func play_hit_light() -> void:
	play_sfx(_streams.get("hit_light"), randf_range(0.95, 1.05))

func play_hit_heavy() -> void:
	play_sfx(_streams.get("hit_heavy"), randf_range(0.9, 1.0))

func play_swing() -> void:
	play_sfx(_streams.get("swing"), randf_range(0.95, 1.1))

func play_special() -> void:
	play_sfx(_streams.get("special"), 1.0)

func play_jump() -> void:
	play_sfx(_streams.get("jump"), randf_range(0.95, 1.05))

func play_ko() -> void:
	play_sfx(_streams.get("ko"), 1.0)

func play_ui_click() -> void:
	play_sfx(_streams.get("ui_click"), 1.0)

func play_round_start() -> void:
	play_sfx(_streams.get("round_start"), 1.0)

func set_bus_volume(bus_name: StringName, linear_val: float) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		var clamped_val: float = clampf(linear_val, 0.0, 1.0)
		var db_val: float = linear_to_db(clamped_val) if clamped_val > 0.0001 else -80.0
		AudioServer.set_bus_volume_db(bus_idx, db_val)
		_save_volume_settings()

func get_bus_volume(bus_name: StringName) -> float:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		var db_val := AudioServer.get_bus_volume_db(bus_idx)
		return db_to_linear(db_val)
	return 1.0

func _save_volume_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", get_bus_volume(BUS_MASTER))
	cfg.set_value("audio", "music", get_bus_volume(BUS_MUSIC))
	cfg.set_value("audio", "sfx", get_bus_volume(BUS_SFX))
	cfg.save("user://audio_settings.cfg")

func _load_volume_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://audio_settings.cfg") == OK:
		set_bus_volume(BUS_MASTER, cfg.get_value("audio", "master", 1.0))
		set_bus_volume(BUS_MUSIC, cfg.get_value("audio", "music", 0.8))
		set_bus_volume(BUS_SFX, cfg.get_value("audio", "sfx", 1.0))
	else:
		set_bus_volume(BUS_MASTER, 1.0)
		set_bus_volume(BUS_MUSIC, 0.8)
		set_bus_volume(BUS_SFX, 1.0)
