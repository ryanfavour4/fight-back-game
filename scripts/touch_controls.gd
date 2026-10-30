extends CanvasLayer

# Touch Controls overlay for Mobile & touch screens.
# Dispatches directly to project Input Map actions.

@onready var toggle_btn: Button = $ToggleTouchBtn
@onready var controls_root: Control = $ControlsRoot

func _ready() -> void:
	if DisplayServer.is_touchscreen_available():
		controls_root.visible = true
	else:
		controls_root.visible = false

	toggle_btn.pressed.connect(_on_toggle_pressed)

func _on_toggle_pressed() -> void:
	controls_root.visible = not controls_root.visible
	toggle_btn.text = "Hide Touch" if controls_root.visible else "Touch Controls"

func set_touch_visible(val: bool) -> void:
	controls_root.visible = val
	toggle_btn.text = "Hide Touch" if val else "Touch Controls"
