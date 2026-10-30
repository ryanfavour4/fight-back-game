extends CanvasLayer

# SceneRouter Autoload - Fight Back
# Smooth screen transitions between scenes.

var _fade_rect: ColorRect
var _is_transitioning: bool = false

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade_rect)

func change_scene(scene_path: String, duration: float = 0.25) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP

	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, duration)
	await tween.finished

	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame

	var tween_in := create_tween()
	tween_in.tween_property(_fade_rect, "color:a", 0.0, duration)
	await tween_in.finished

	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_transitioning = false
