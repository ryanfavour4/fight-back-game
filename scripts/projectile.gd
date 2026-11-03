extends Area2D

# Projectile for ranged special attacks (e.g. Kitsune Fox-Fire)
# Host simulates authoritative damage and collision.
# Client runs visual copy with synchronized spawn, movement, and impact events.

@export var speed: float = 550.0
@export var damage: float = 18.0
@export var knockback: Vector2 = Vector2(280.0, -180.0)
@export var hitstun_frames: int = 22

var direction: float = 1.0
var owner_peer_id: int = 1
var has_hit: bool = false
var lifetime: float = 2.0
var is_visual_only: bool = false
var proj_id: int = 0
var _arena_cached: Node = null

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var col_shape: CollisionShape2D = $CollisionShape2D

static var _cached_fly_frames: SpriteFrames = null
static var _cached_burst_frames: SpriteFrames = null

func _get_arena() -> Node:
	if _arena_cached == null or not is_instance_valid(_arena_cached):
		_arena_cached = get_tree().current_scene
	return _arena_cached

func _ready() -> void:
	_arena_cached = get_tree().current_scene
	if not is_visual_only:
		area_entered.connect(_on_area_entered)
	else:
		monitoring = false
		monitorable = false
		collision_layer = 0
		collision_mask = 0

	_setup_sprite_frames()

static func get_fly_sprite_frames() -> SpriteFrames:
	if _cached_fly_frames != null:
		return _cached_fly_frames

	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")

	var path := "res://assets/characters/PNG/Kitsune/Fire_1.png"
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		sf.add_animation("fly")
		sf.set_animation_speed("fly", 16.0)
		sf.set_animation_loop("fly", true)
		for i in range(14):
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(i * 64, 0, 64, 64)
			atlas.filter_clip = true
			sf.add_frame("fly", atlas)

	_cached_fly_frames = sf
	return _cached_fly_frames

static func get_burst_sprite_frames() -> SpriteFrames:
	if _cached_burst_frames != null:
		return _cached_burst_frames

	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")

	var path := "res://assets/characters/PNG/Kitsune/Fire_2.png"
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		sf.add_animation("burst")
		sf.set_animation_speed("burst", 20.0)
		sf.set_animation_loop("burst", false)
		for i in range(11):
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(i * 64, 0, 64, 64)
			atlas.filter_clip = true
			sf.add_frame("burst", atlas)

	_cached_burst_frames = sf
	return _cached_burst_frames

func _setup_sprite_frames() -> void:
	if sprite == null:
		return
	sprite.sprite_frames = get_fly_sprite_frames()
	sprite.scale = Vector2(1.5, 1.5)
	sprite.flip_h = (direction < 0)
	sprite.play("fly")

func _is_host_sim() -> bool:
	if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET:
		return multiplayer.is_server()
	return NetworkManager.is_host

func _physics_process(delta: float) -> void:
	position.x += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		play_impact_and_free(false)
		return

	if position.x < 30.0 or position.x > 1890.0:
		if _is_host_sim():
			var arena = _get_arena()
			if arena and arena.has_method("notify_projectile_impact"):
				arena.notify_projectile_impact(proj_id, global_position, false)
		play_impact_and_free(false)
		return

func _on_area_entered(area: Area2D) -> void:
	if has_hit or is_visual_only:
		return

	# Only host simulates hit consequences
	if _is_host_sim():
		var target = area.get_parent()
		if target and target.has_method("take_hit") and target.peer_id != owner_peer_id:
			has_hit = true
			var actual_kb := Vector2(knockback.x * direction, knockback.y)
			target.take_hit(damage, actual_kb, hitstun_frames, "special")

			# Hitstop freeze on target and camera shake
			target.hitstop_frames_left = 3
			var arena = _get_arena()
			if arena and arena.has_method("notify_projectile_impact"):
				arena.notify_projectile_impact(proj_id, global_position, true)
			else:
				play_impact_and_free(true)

func play_impact_and_free(spawn_burst: bool) -> void:
	if is_queued_for_deletion():
		return
	has_hit = true

	if spawn_burst:
		_spawn_burst_effect(global_position)
		AudioManager.play_hit_light()

	queue_free()

func _spawn_burst_effect(pos: Vector2) -> void:
	var burst := AnimatedSprite2D.new()
	burst.sprite_frames = get_burst_sprite_frames()
	burst.animation = "burst"
	burst.global_position = pos
	burst.scale = Vector2(1.5, 1.5)
	burst.flip_h = (direction < 0)
	burst.animation_finished.connect(burst.queue_free)

	var p_parent = get_parent()
	if p_parent and is_instance_valid(p_parent):
		p_parent.add_child(burst)
	else:
		get_tree().root.add_child(burst)

	burst.play("burst")
