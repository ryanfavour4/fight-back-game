extends Resource
class_name MoveData

# Data-driven move definition for fighting game attacks.

@export var move_name: String = "Light Attack"
@export var animation_name: String = "attack_light"
@export var startup_frame: int = 1
@export var active_frame_start: int = 2
@export var active_frame_end: int = 3
@export var recovery_frame: int = 5
@export var damage: float = 10.0
@export var hitstun_frames: int = 15
@export var knockback: Vector2 = Vector2(250.0, -180.0)
@export var hitbox_size: Vector2 = Vector2(70.0, 60.0)
@export var hitbox_offset: Vector2 = Vector2(50.0, -20.0)
@export var sfx_name: String = "swing"
@export var is_projectile: bool = false
@export var projectile_speed: float = 550.0
