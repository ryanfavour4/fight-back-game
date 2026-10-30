extends Control

# Main Menu Controller - Fight Back

@onready var logo_texture: TextureRect = $CenterContainer/VBoxContainer/LogoContainer/Logo
@onready var versus_button: Button = $CenterContainer/VBoxContainer/ButtonsContainer/VersusButton
@onready var controls_button: Button = $CenterContainer/VBoxContainer/ButtonsContainer/ControlsButton
@onready var settings_button: Button = $CenterContainer/VBoxContainer/ButtonsContainer/SettingsButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/ButtonsContainer/QuitButton

@onready var controls_dialog: PanelContainer = $ControlsDialog
@onready var close_controls_button: Button = $ControlsDialog/MarginContainer/VBoxContainer/CloseControlsButton

@onready var settings_dialog: PanelContainer = $SettingsDialog
@onready var master_slider: HSlider = $SettingsDialog/MarginContainer/VBoxContainer/MasterSlider
@onready var music_slider: HSlider = $SettingsDialog/MarginContainer/VBoxContainer/MusicSlider
@onready var sfx_slider: HSlider = $SettingsDialog/MarginContainer/VBoxContainer/SFXSlider
@onready var close_settings_button: Button = $SettingsDialog/MarginContainer/VBoxContainer/CloseSettingsButton

var _time_passed: float = 0.0
var _logo_base_y: float = 0.0

func _ready() -> void:
	AudioManager.play_menu_music()

	versus_button.pressed.connect(_on_versus_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	close_controls_button.pressed.connect(func(): controls_dialog.visible = false; AudioManager.play_ui_click())
	close_settings_button.pressed.connect(func(): settings_dialog.visible = false; AudioManager.play_ui_click())

	master_slider.value = AudioManager.get_bus_volume(AudioManager.BUS_MASTER)
	music_slider.value = AudioManager.get_bus_volume(AudioManager.BUS_MUSIC)
	sfx_slider.value = AudioManager.get_bus_volume(AudioManager.BUS_SFX)

	master_slider.value_changed.connect(func(v): AudioManager.set_bus_volume(AudioManager.BUS_MASTER, v))
	music_slider.value_changed.connect(func(v): AudioManager.set_bus_volume(AudioManager.BUS_MUSIC, v))
	sfx_slider.value_changed.connect(func(v): AudioManager.set_bus_volume(AudioManager.BUS_SFX, v))

	if DisplayServer.is_touchscreen_available():
		quit_button.visible = false

	# Setup gentle fade-in and float animation for logo (Override #2)
	_logo_base_y = logo_texture.position.y
	logo_texture.modulate.a = 0.0
	var fade_tween := create_tween()
	fade_tween.tween_property(logo_texture, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE)

func _process(delta: float) -> void:
	_time_passed += delta
	# Floating bobbing animation
	logo_texture.position.y = _logo_base_y + sin(_time_passed * 2.2) * 8.0

func _on_versus_pressed() -> void:
	AudioManager.play_ui_click()
	SceneRouter.change_scene("res://scenes/lobby.tscn")

func _on_controls_pressed() -> void:
	AudioManager.play_ui_click()
	controls_dialog.visible = true

func _on_settings_pressed() -> void:
	AudioManager.play_ui_click()
	settings_dialog.visible = true

func _on_quit_pressed() -> void:
	AudioManager.play_ui_click()
	get_tree().quit()
