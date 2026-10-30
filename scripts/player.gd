extends CharacterBody2D

# Player Fighter Controller - Fight Back
# Host-authoritative 60Hz physics simulation with runtime SpriteFrames and strict FSM.

signal health_changed(new_health: float, max_hp: float)
signal fighter_ko(peer_id: int)

enum State { IDLE, WALK, JUMP, ATTACK, HURT, DEAD }

const INPUT_LEFT: int = 1 << 0
const INPUT_RIGHT: int = 1 << 1
const INPUT_JUMP: int = 1 << 2
const INPUT_LIGHT: int = 1 << 3
const INPUT_HEAVY: int = 1 << 4
const INPUT_SPECIAL: int = 1 << 5

@export var peer_id: int = 1
@export var player_number: int = 1
@export var character_data: CharacterData

# Gameplay State
var current_state: State = State.IDLE
var facing_direction: float = 1.0 # 1.0 = right, -1.0 = left
var health: float = 100.0
var max_hp: float = 100.0
var opponent: CharacterBody2D = null

# Attack execution
var current_move: MoveData = null
var current_attack_anim: String = ""
var has_hit_target: bool = false
var has_spawned_projectile: bool = false
var hitstun_frames_left: int = 0
var hitstop_frames_left: int = 0
var state_ticks: int = 0

# Ring buffer for freeze diagnostics (~120 ticks)
const RING_BUFFER_SIZE: int = 120
var ring_buffer: Array[Dictionary] = []

# Input caching
var local_input_mask: int = 0
var host_cached_input: int = 0
var current_tick: int = 0

# Sync properties for MultiplayerSynchronizer
@export var sync_position: Vector2 = Vector2.ZERO
@export var sync_velocity: Vector2 = Vector2.ZERO
@export var sync_state: int = 0
@export var sync_facing: float = 1.0
@export var sync_health: float = 100.0
@export var sync_anim: String = "idle"
@export var sync_frame: int = 0
@export var sync_hitbox_active: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $BodyCollision
@onready var hurtbox: Area2D = $Hurtbox
@onready var hurtbox_shape: CollisionShape2D = $Hurtbox/CollisionShape2D
@onready var hitbox: Area2D = $Hitbox
@onready var hitbox_shape: CollisionShape2D = $Hitbox/CollisionShape2D
@onready var synchronizer: MultiplayerSynchronizer = $Synchronizer
@onready var pill_label: Label = $PillMarker/Label
@onready var landing_dust: CPUParticles2D = $LandingDust
@onready var hit_spark: CPUParticles2D = $HitSpark
@onready var shadow: Polygon2D = $Shadow

var projectile_scene: PackedScene = preload("res://scenes/projectile.tscn")

func _ready() -> void:
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)

	_setup_replication()
	_apply_character_data()
	_setup_collision_layers()
	_setup_visual_marker()

func _setup_visual_marker() -> void:
	if player_number == 1:
		pill_label.text = "P1"
		pill_label.modulate = Color(1.0, 0.85, 0.2) # Gold
		sprite.modulate = Color.WHITE
		facing_direction = 1.0
	else:
		pill_label.text = "P2"
		pill_label.modulate = Color(0.3, 0.8, 1.0) # Cyan
		sprite.modulate = Color(0.82, 0.88, 1.05) # Subtle cool tint per Override #3
		facing_direction = -1.0

	sprite.flip_h = (facing_direction < 0)

func _setup_collision_layers() -> void:
	# Layer 1 = World/Floor, Layer 2 = Players
	collision_layer = 2
	collision_mask = 1 # Collide with floor and stage walls

	if player_number == 1:
		# P1 Hurtbox: Layer 3 (val 4), mask = 0 (receives hits)
		hurtbox.collision_layer = 4
		hurtbox.collision_mask = 0

		# P1 Hitbox: Layer 5 (val 16), mask = Layer 4 (P2 Hurtbox, val 8)
		hitbox.collision_layer = 16
		hitbox.collision_mask = 8
	else:
		# P2 Hurtbox: Layer 4 (val 8), mask = 0
		hurtbox.collision_layer = 8
		hurtbox.collision_mask = 0

		# P2 Hitbox: Layer 6 (val 32), mask = Layer 3 (P1 Hurtbox, val 4)
		hitbox.collision_layer = 32
		hitbox.collision_mask = 4

	hitbox_shape.set_deferred("disabled", true)

func _apply_character_data() -> void:
	if character_data == null:
		character_data = preload("res://resources/characters/karasu.tres")

	max_hp = character_data.max_health
	health = max_hp
	sprite.sprite_frames = character_data.build_sprite_frames()
	sprite.scale = Vector2(1.5, 1.5)
	sprite.offset = Vector2(0, -64)
	_play_anim("idle")

func _is_host_sim() -> bool:
	if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET:
		return multiplayer.is_server()
	return NetworkManager.is_host

func _setup_replication() -> void:
	synchronizer.set_multiplayer_authority(1) # Host authoritative
	if _is_host_sim():
		synchronizer.public_visibility = false
	if synchronizer.replication_config == null:
		var cfg := SceneReplicationConfig.new()
		cfg.add_property(NodePath(".:sync_position"))
		cfg.property_set_replication_mode(NodePath(".:sync_position"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		cfg.add_property(NodePath(".:sync_velocity"))
		cfg.property_set_replication_mode(NodePath(".:sync_velocity"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		cfg.add_property(NodePath(".:sync_state"))
		cfg.property_set_replication_mode(NodePath(".:sync_state"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		cfg.add_property(NodePath(".:sync_facing"))
		cfg.property_set_replication_mode(NodePath(".:sync_facing"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		cfg.add_property(NodePath(".:sync_health"))
		cfg.property_set_replication_mode(NodePath(".:sync_health"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		cfg.add_property(NodePath(".:sync_anim"))
		cfg.property_set_replication_mode(NodePath(".:sync_anim"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		cfg.add_property(NodePath(".:sync_frame"))
		cfg.property_set_replication_mode(NodePath(".:sync_frame"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		cfg.add_property(NodePath(".:sync_hitbox_active"))
		cfg.property_set_replication_mode(NodePath(".:sync_hitbox_active"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		synchronizer.replication_config = cfg

func _physics_process(delta: float) -> void:
	current_tick += 1

	if _is_host_sim():
		_server_physics_step(delta)
	else:
		_client_interpolation_step(delta)

	_record_tick_state(local_input_mask)

# ==============================================================================
# INPUT GATHERING & NETWORKING
# ==============================================================================
func _sample_local_input() -> int:
	if NetworkManager.is_autotest:
		var mask: int = 0
		var frame := Engine.get_physics_frames()
		var dist: float = 300.0
		if opponent and is_instance_valid(opponent):
			dist = absf(global_position.x - opponent.global_position.x)

		if dist > 220.0:
			if character_data and character_data.character_id == "kitsune" and frame % 45 == 0:
				mask |= INPUT_SPECIAL
			else:
				mask |= (INPUT_RIGHT if facing_direction > 0 else INPUT_LEFT)
		elif dist > 80.0:
			if character_data and character_data.character_id == "kitsune" and frame % 40 == 0:
				mask |= INPUT_SPECIAL
			elif frame % 20 < 10:
				mask |= (INPUT_RIGHT if facing_direction > 0 else INPUT_LEFT)
		else:
			if frame % 24 == 0:
				mask |= INPUT_HEAVY
			elif frame % 12 == 0:
				mask |= INPUT_LIGHT
		return mask

	var mask: int = 0
	if Input.is_action_pressed("p_left"):
		mask |= INPUT_LEFT
	if Input.is_action_pressed("p_right"):
		mask |= INPUT_RIGHT
	if Input.is_action_just_pressed("p_jump"):
		mask |= INPUT_JUMP
	if Input.is_action_just_pressed("p_light"):
		mask |= INPUT_LIGHT
	if Input.is_action_just_pressed("p_heavy"):
		mask |= INPUT_HEAVY
	if Input.is_action_just_pressed("p_special"):
		mask |= INPUT_SPECIAL
	return mask

@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_send_client_input(mask: int, tick: int) -> void:
	if _is_host_sim():
		host_cached_input = mask

# ==============================================================================
# HOST SIMULATION (60 Hz FIXED)
# ==============================================================================
func _server_physics_step(delta: float) -> void:
	# Hitstop freeze frames
	if hitstop_frames_left > 0:
		hitstop_frames_left -= 1
		_check_failsafe_stuck()
		_update_sync_state()
		return

	# Determine active input mask for this player
	var input_mask: int = 0
	if player_number == 1:
		input_mask = _sample_local_input()
	else:
		input_mask = host_cached_input
		# Consume one-shot attack & jump actions so late or duplicate packets do not repeat
		host_cached_input &= ~(INPUT_JUMP | INPUT_LIGHT | INPUT_HEAVY | INPUT_SPECIAL)

	local_input_mask = input_mask

	# Failsafe stuck check
	state_ticks += 1
	_check_failsafe_stuck()

	# Auto-face opponent when in neutral states
	_update_auto_facing()

	# State Machine execution
	match current_state:
		State.IDLE:
			_state_idle_step(delta, input_mask)
		State.WALK:
			_state_walk_step(delta, input_mask)
		State.JUMP:
			_state_jump_step(delta, input_mask)
		State.ATTACK:
			_state_attack_step(delta)
		State.HURT:
			_state_hurt_step(delta)
		State.DEAD:
			_state_dead_step(delta)

	move_and_slide()
	_update_sync_state()

func _update_auto_facing() -> void:
	if opponent and is_instance_valid(opponent):
		if current_state in [State.IDLE, State.WALK, State.JUMP]:
			var dir := signf(opponent.position.x - position.x)
			if dir != 0.0:
				facing_direction = dir
				sprite.flip_h = (facing_direction < 0)

func _state_idle_step(delta: float, input: int) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 1500.0 * delta)
	_apply_gravity(delta)

	if not is_on_floor():
		_transition_to(State.JUMP)
		return

	if _check_attack_inputs(input):
		return

	if input & INPUT_JUMP:
		velocity.y = character_data.jump_velocity
		AudioManager.play_jump()
		_transition_to(State.JUMP)
		return

	if (input & INPUT_LEFT) or (input & INPUT_RIGHT):
		_transition_to(State.WALK)
		return

	_play_anim("idle")

func _state_walk_step(delta: float, input: int) -> void:
	_apply_gravity(delta)

	if not is_on_floor():
		_transition_to(State.JUMP)
		return

	if _check_attack_inputs(input):
		return

	if input & INPUT_JUMP:
		velocity.y = character_data.jump_velocity
		AudioManager.play_jump()
		_transition_to(State.JUMP)
		return

	var move_dir: float = 0.0
	if input & INPUT_LEFT:
		move_dir -= 1.0
	if input & INPUT_RIGHT:
		move_dir += 1.0

	if move_dir == 0.0:
		_transition_to(State.IDLE)
		return

	velocity.x = move_dir * character_data.walk_speed
	_play_anim("walk")

func _state_jump_step(delta: float, input: int) -> void:
	_apply_gravity(delta)

	# Air drift
	var move_dir: float = 0.0
	if input & INPUT_LEFT:
		move_dir -= 1.0
	if input & INPUT_RIGHT:
		move_dir += 1.0
	velocity.x = move_dir * (character_data.walk_speed * 0.75)

	_play_anim("jump")

	if is_on_floor() and velocity.y >= 0.0:
		landing_dust.restart()
		landing_dust.emitting = true
		_transition_to(State.IDLE)

func _state_attack_step(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
	_apply_gravity(delta)

	# Active hitbox check based on frame
	if current_move:
		var cur_frame := sprite.frame
		var is_active := (cur_frame >= current_move.active_frame_start and cur_frame <= current_move.active_frame_end)

		# Spawn projectile on active frame for ranged moves (Kitsune Special)
		if current_move.is_projectile:
			_set_hitbox_active(false)
			if is_active and not has_spawned_projectile:
				has_spawned_projectile = true
				_spawn_projectile()
		else:
			_set_hitbox_active(is_active)

	# Guard against animation completion without signal
	if not sprite.is_playing() and state_ticks > 5:
		_set_hitbox_active(false)
		_transition_to(State.IDLE if is_on_floor() else State.JUMP)

func _state_hurt_step(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	_apply_gravity(delta)

	if hitstun_frames_left > 0:
		hitstun_frames_left -= 1
	else:
		if health <= 0.0:
			_transition_to(State.DEAD)
		elif is_on_floor():
			_transition_to(State.IDLE)
		else:
			_transition_to(State.JUMP)

func _state_dead_step(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
	_apply_gravity(delta)
	_set_hitbox_active(false)
	_play_anim("dead")

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += 1800.0 * delta

func _check_attack_inputs(input: int) -> bool:
	if input & INPUT_LIGHT:
		_start_attack(character_data.light_move, "attack_light")
		return true
	if input & INPUT_HEAVY:
		_start_attack(character_data.heavy_move, "attack_heavy")
		return true
	if input & INPUT_SPECIAL:
		_start_attack(character_data.special_move, "attack_special")
		return true
	return false

func _start_attack(move: MoveData, anim_name: String) -> void:
	if move == null:
		return
	current_move = move
	current_attack_anim = anim_name
	has_hit_target = false
	has_spawned_projectile = false
	velocity.x = 0.0
	_transition_to(State.ATTACK)
	_play_anim(anim_name)

	# Play swing sound
	if move.sfx_name == "special":
		AudioManager.play_special()
	else:
		AudioManager.play_swing()

func _set_hitbox_active(active: bool) -> void:
	if not active or has_hit_target or current_move == null:
		hitbox_shape.set_deferred("disabled", true)
		sync_hitbox_active = false
		return

	hitbox_shape.set_deferred("disabled", false)
	sync_hitbox_active = true

	# Position hitbox with facing direction mirroring
	var rect_shape := hitbox_shape.shape as RectangleShape2D
	if rect_shape:
		rect_shape.size = current_move.hitbox_size
	hitbox.position = Vector2(current_move.hitbox_offset.x * facing_direction, current_move.hitbox_offset.y)

func _spawn_projectile() -> void:
	if current_move == null or not current_move.is_projectile:
		return

	var arena = get_tree().current_scene
	if arena and arena.has_method("spawn_projectile_networked"):
		var spawn_pos := position + Vector2(facing_direction * 45.0, -45.0)
		var dmg := current_move.damage * character_data.damage_multiplier
		arena.spawn_projectile_networked(
			spawn_pos,
			facing_direction,
			current_move.projectile_speed,
			peer_id,
			player_number,
			dmg,
			current_move.knockback,
			current_move.hitstun_frames
		)

func _transition_to(new_state: State) -> void:
	if current_state == State.DEAD:
		return
	current_state = new_state
	state_ticks = 0
	if current_state != State.ATTACK:
		_set_hitbox_active(false)
		current_move = null

func _play_anim(anim_name: String) -> void:
	if sprite.animation != anim_name:
		sprite.play(anim_name)

func _on_animation_finished() -> void:
	if not _is_host_sim():
		return

	if current_state == State.ATTACK:
		_set_hitbox_active(false)
		_transition_to(State.IDLE if is_on_floor() else State.JUMP)
	elif current_state == State.HURT and health > 0.0:
		_transition_to(State.IDLE if is_on_floor() else State.JUMP)

func _on_frame_changed() -> void:
	if not _is_host_sim():
		return
	if current_state == State.ATTACK and current_move:
		var cur_frame := sprite.frame
		var is_active := (cur_frame >= current_move.active_frame_start and cur_frame <= current_move.active_frame_end)
		if current_move.is_projectile:
			_set_hitbox_active(false)
			if is_active and not has_spawned_projectile:
				has_spawned_projectile = true
				_spawn_projectile()
		else:
			_set_hitbox_active(is_active)

func _on_hitbox_area_entered(area: Area2D) -> void:
	if not _is_host_sim():
		return
	if has_hit_target or current_move == null:
		return

	var target = area.get_parent()
	if target and target != self and target.has_method("take_hit"):
		has_hit_target = true
		hitbox_shape.set_deferred("disabled", true)

		var kb := Vector2(current_move.knockback.x * facing_direction, current_move.knockback.y)
		var dmg := current_move.damage * character_data.damage_multiplier
		target.take_hit(dmg, kb, current_move.hitstun_frames, current_move.sfx_name)

		# Hitstop freeze on both players
		hitstop_frames_left = 3
		target.hitstop_frames_left = 3

		# Notify arena to trigger melee hit effects (sparks, SFX, screen shake) across network
		var arena = get_tree().current_scene
		if arena and arena.has_method("rpc_trigger_melee_hit_effects"):
			NetworkManager.send_network_event("/root/GameArena", "rpc_trigger_melee_hit_effects", [hitbox.global_position, current_move.sfx_name, dmg >= 15.0])

func take_hit(damage_amount: float, knockback: Vector2, hitstun_frames: int, hit_sfx: String) -> void:
	if not _is_host_sim() or current_state == State.DEAD:
		return

	health = maxf(0.0, health - damage_amount)
	velocity = knockback
	hitstun_frames_left = hitstun_frames
	_transition_to(State.HURT)
	_play_anim("hurt")

	# Audio & Polish
	if hit_sfx == "hit_heavy" or damage_amount >= 15.0:
		AudioManager.play_hit_heavy()
	else:
		AudioManager.play_hit_light()

	health_changed.emit(health, max_hp)

	if health <= 0.0:
		AudioManager.play_ko()
		_transition_to(State.DEAD)
		fighter_ko.emit(peer_id)

func reset_fighter(spawn_pos: Vector2, facing: float) -> void:
	position = spawn_pos
	velocity = Vector2.ZERO
	facing_direction = facing
	sprite.flip_h = (facing_direction < 0)
	health = max_hp
	current_state = State.IDLE
	current_move = null
	has_hit_target = false
	has_spawned_projectile = false
	hitstun_frames_left = 0
	hitstop_frames_left = 0
	state_ticks = 0
	ring_buffer.clear()
	_set_hitbox_active(false)
	_play_anim("idle")
	health_changed.emit(health, max_hp)
	_update_sync_state()

func _update_sync_state() -> void:
	sync_position = position
	sync_velocity = velocity
	sync_state = int(current_state)
	sync_facing = facing_direction
	sync_health = health
	sync_anim = sprite.animation
	sync_frame = sprite.frame

# ==============================================================================
# FAILSAFE STUCK DETECTION & RING BUFFER LOGGING
# ==============================================================================
func _check_failsafe_stuck() -> void:
	if not _is_host_sim():
		return

	var stuck_reason := ""
	if hitstop_frames_left > 15:
		stuck_reason = "HITSTOP_OVERFLOW (%d frames)" % hitstop_frames_left
	elif current_state == State.ATTACK and state_ticks > 80:
		stuck_reason = "ATTACK_TIMEOUT (anim=%s frame=%d ticks=%d)" % [sprite.animation, sprite.frame, state_ticks]
	elif current_state == State.HURT and state_ticks > 75:
		stuck_reason = "HURT_TIMEOUT (anim=%s frame=%d ticks=%d)" % [sprite.animation, sprite.frame, state_ticks]

	if stuck_reason != "":
		_set_hitbox_active(false)
		current_move = null
		hitstop_frames_left = 0
		hitstun_frames_left = 0
		_transition_to(State.IDLE if is_on_floor() else State.JUMP)
		_play_anim("idle" if is_on_floor() else "jump")
		var arena = get_tree().current_scene
		if arena and arena.has_method("on_failsafe_triggered"):
			arena.on_failsafe_triggered(player_number, stuck_reason)

func _record_tick_state(input_mask: int) -> void:
	var entry: Dictionary = {
		"tick": current_tick,
		"time_ms": Time.get_ticks_msec(),
		"state": State.keys()[current_state] if current_state < State.size() else str(current_state),
		"state_ticks": state_ticks,
		"anim": sprite.animation if sprite else "",
		"frame": sprite.frame if sprite else -1,
		"is_playing": sprite.is_playing() if sprite else false,
		"gpos": global_position,
		"vel": velocity,
		"hitstop": hitstop_frames_left,
		"hitstun": hitstun_frames_left,
		"input": input_mask,
		"has_proj": has_spawned_projectile,
		"hitbox_act": sync_hitbox_active,
		"on_floor": is_on_floor()
	}
	ring_buffer.append(entry)
	if ring_buffer.size() > RING_BUFFER_SIZE:
		ring_buffer.pop_front()

func get_ordered_ring_buffer() -> Array[Dictionary]:
	return ring_buffer.duplicate()

# ==============================================================================
# CLIENT INTERPOLATION & RENDERING
# ==============================================================================
func _client_interpolation_step(delta: float) -> void:
	# Send local client input to host each tick
	if player_number == 2:
		var mask := _sample_local_input()
		NetworkManager.send_client_input(mask, current_tick)

	# Smoothly interpolate position towards authoritative host position
	var dist := position.distance_to(sync_position)
	if dist > 60.0:
		position = sync_position # Snap if too far
	else:
		position = position.lerp(sync_position, 18.0 * delta)

	velocity = sync_velocity
	facing_direction = sync_facing
	sprite.flip_h = (facing_direction < 0)

	if health != sync_health:
		health = sync_health
		health_changed.emit(health, max_hp)

	var old_anim := sprite.animation
	if sprite.animation != sync_anim:
		sprite.play(sync_anim)
		# Audio & visual cues on animation change for client
		if sync_anim == "attack_special":
			AudioManager.play_special()
		elif sync_anim in ["attack_light", "attack_heavy"]:
			AudioManager.play_swing()
		elif sync_anim == "jump" and old_anim != "jump":
			AudioManager.play_jump()
		elif sync_anim == "dead" and old_anim != "dead":
			AudioManager.play_ko()

		if old_anim == "jump" and sync_anim in ["idle", "walk"]:
			landing_dust.restart()
			landing_dust.emitting = true

	sprite.frame = sync_frame
	current_state = sync_state as State
