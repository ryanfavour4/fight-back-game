extends Resource
class_name CharacterData

# Data-driven character definition with runtime SpriteFrames builder.

@export var character_id: String = "karasu"
@export var display_name: String = "Karasu Tengu"
@export var avatar_path: String = "res://assets/fantasy-character-avatar-face-icons/PNG/Transperent/con20.png"

@export_group("Stats")
@export var max_health: float = 100.0
@export var walk_speed: float = 280.0
@export var jump_velocity: float = -650.0
@export var damage_multiplier: float = 1.0
@export var default_facing: float = 1.0 # 1.0 = sprite sheet faces right, -1.0 = faces left

@export_group("Sprite Sheets")
@export var idle_sheet_path: String = ""
@export var idle_frames: int = 6
@export var walk_sheet_path: String = ""
@export var walk_frames: int = 8
@export var jump_sheet_path: String = ""
@export var jump_frames: int = 15
@export var attack_light_sheet_path: String = ""
@export var attack_light_frames: int = 6
@export var attack_heavy_sheet_path: String = ""
@export var attack_heavy_frames: int = 4
@export var attack_special_sheet_path: String = ""
@export var attack_special_frames: int = 3
@export var hurt_sheet_path: String = ""
@export var hurt_frames: int = 3
@export var dead_sheet_path: String = ""
@export var dead_frames: int = 6

@export_group("Moves")
@export var light_move: MoveData
@export var heavy_move: MoveData
@export var special_move: MoveData

func build_sprite_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	# Remove default animation if present
	if sf.has_animation("default"):
		sf.remove_animation("default")

	_add_anim_from_sheet(sf, "idle", idle_sheet_path, idle_frames, 8.0, true)
	_add_anim_from_sheet(sf, "walk", walk_sheet_path, walk_frames, 10.0, true)
	_add_anim_from_sheet(sf, "jump", jump_sheet_path, jump_frames, 12.0, false)
	_add_anim_from_sheet(sf, "attack_light", attack_light_sheet_path, attack_light_frames, 12.0, false)
	_add_anim_from_sheet(sf, "attack_heavy", attack_heavy_sheet_path, attack_heavy_frames, 10.0, false)
	_add_anim_from_sheet(sf, "attack_special", attack_special_sheet_path, attack_special_frames, 10.0, false)
	_add_anim_from_sheet(sf, "hurt", hurt_sheet_path, hurt_frames, 8.0, false)
	_add_anim_from_sheet(sf, "dead", dead_sheet_path, dead_frames, 8.0, false)

	return sf

func _add_anim_from_sheet(sf: SpriteFrames, anim_name: String, sheet_path: String, frame_count: int, fps: float, loop: bool) -> void:
	if sheet_path.is_empty() or not ResourceLoader.exists(sheet_path):
		return

	var tex: Texture2D = load(sheet_path)
	if tex == null:
		return

	sf.add_animation(anim_name)
	sf.set_animation_speed(anim_name, fps)
	sf.set_animation_loop(anim_name, loop)

	var tex_w: float = tex.get_width()
	var tex_h: float = tex.get_height()
	var frame_w: float = tex_w / max(frame_count, 1)

	for i in range(frame_count):
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(i * frame_w, 0, frame_w, tex_h)
		atlas.filter_clip = true
		sf.add_frame(anim_name, atlas)
