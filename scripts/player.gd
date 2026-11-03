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
var _ring_buffer_idx: int = 0
var _arena_cached: Node = null

# Input caching
var local_input_mask: int = 0
var host_cached_input: int = 0
var current_tick: int = 0

# Client prediction & server reconciliation
var client_input_seq: int = 0
var input_history: Array[Dictionary] = []
var pred_correction_offset: Vector2 = Vector2.ZERO
var last_pred_error: float = 0.0
var last_correction_size: float = 0.0

# Host input queue & sequencing
var client_input_queue: Array[Dictionary] = []
var last_processed_client_seq: int = 0

# Sync properties for MultiplayerSynchronizer
@export var sync_position: Vector2 = Vector2.ZERO
@export var sync_velocity: Vector2 = Vector2.ZERO
@export var sync_state: int = 0
@export var sync_facing: float = 1.0
@export var sync_health: float = 100.0
@export var sync_anim: String = "idle"
@export var sync_frame: int = 0
@export var sync_hitbox_active: bool = false

# Input buffering & network hold constants
const INPUT_BUFFER_WINDOW_FRAMES: int = 10
const CLIENT_INPUT_HOLD_FRAMES: int = 8

var buffered_attack: int = 0
var attack_buffer_timer: int = 0
var buffered_jump: bool = false
var jump_buffer_timer: int = 0

var _hold_light_frames: int = 0
var _hold_heavy_frames: int = 0
var _hold_special_frames: int = 0
var _hold_jump_frames: int = 0

var _prev_received_mask: int = 0
var _prev_local_mask: int = 0

var attack_register_count: Dictionary = {
	"attack_light": 0,
	"attack_heavy": 0,
	"attack_special": 0
}

var _test_presses_sent: Dictionary = {
	"light": 0,
	"heavy": 0,
	"special": 0
}

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
	_arena_cached = get_tree().current_scene
	ring_buffer.resize(RING_BUFFER_SIZE)
	for i in range(RING_BUFFER_SIZE):
		ring_buffer[i] = {}

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

	_update_facing_visual()

func _update_facing_visual() -> void:
	var def_facing: float = character_data.default_facing if character_data else 1.0
	sprite.flip_h = (facing_direction * def_facing < 0.0)

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
func _get_arena() -> Node:
	if _arena_cached == null or not is_instance_valid(_arena_cached):
		_arena_cached = get_tree().current_scene
	return _arena_cached

func _sample_local_input() -> int:
	if NetworkManager.is_combat_test:
		var mask: int = 0
		var frame := Engine.get_physics_frames()
		var arena = _get_arena()
		if arena and "is_round_active" in arena and arena.is_round_active:
			if opponent and is_instance_valid(opponent):
				var dist: float = absf(global_position.x - opponent.global_position.x)
				if player_number == 2:
					# P2 attacks FIRST: approaches immediately and attacks
					if dist > 70.0:
						mask |= (INPUT_LEFT if position.x > opponent.position.x else INPUT_RIGHT)
					else:
						if frame % 25 == 0:
							mask |= INPUT_LIGHT
							_hold_light_frames = CLIENT_INPUT_HOLD_FRAMES
						elif frame % 25 == 8:
							mask |= INPUT_HEAVY
							_hold_heavy_frames = CLIENT_INPUT_HOLD_FRAMES
						elif frame % 25 == 16:
							mask |= INPUT_SPECIAL
							_hold_special_frames = CLIENT_INPUT_HOLD_FRAMES
				else:
					# P1 waits for P2's first attack to land (takes the hit first), then counter-attacks aggressively
					if frame >= 140:
						if dist > 70.0:
							mask |= (INPUT_RIGHT if position.x < opponent.position.x else INPUT_LEFT)
						else:
							if frame % 25 == 4:
								mask |= INPUT_LIGHT
								_hold_light_frames = CLIENT_INPUT_HOLD_FRAMES
							elif frame % 25 == 12:
								mask |= INPUT_HEAVY
								_hold_heavy_frames = CLIENT_INPUT_HOLD_FRAMES
							elif frame % 25 == 20:
								mask |= INPUT_SPECIAL
								_hold_special_frames = CLIENT_INPUT_HOLD_FRAMES

		if _hold_jump_frames > 0:
			mask |= INPUT_JUMP
			_hold_jump_frames -= 1
		if _hold_light_frames > 0:
			mask |= INPUT_LIGHT
			_hold_light_frames -= 1
		if _hold_heavy_frames > 0:
			mask |= INPUT_HEAVY
			_hold_heavy_frames -= 1
		if _hold_special_frames > 0:
			mask |= INPUT_SPECIAL
			_hold_special_frames -= 1
		return mask

	if NetworkManager.is_facing_test:
		var mask: int = 0
		var arena = _get_arena()
		if arena and "is_round_active" in arena and arena.is_round_active:
			if player_number == 2:
				# Walk left past P1
				if opponent and is_instance_valid(opponent):
					if position.x > opponent.position.x - 120.0:
						mask |= INPUT_LEFT
		return mask

	if NetworkManager.is_walk_test:
		var mask: int = 0
		var frame := Engine.get_physics_frames()
		var arena = _get_arena()
		if arena and "is_round_active" in arena and arena.is_round_active:
			# Walk right for 120 frames, then left for 120 frames
			var cycle := (frame / 120) % 2
			if cycle == 0:
				mask |= INPUT_RIGHT
			else:
				mask |= INPUT_LEFT
		return mask

	if NetworkManager.is_attack_test:
		var mask: int = 0
		var frame := Engine.get_physics_frames()
		var arena = _get_arena()
		if arena and "is_round_active" in arena and arena.is_round_active:
			# Press once every 35 frames (~0.58s), alternating between Light (1-30), Heavy (31-60), Special (61-90)
			# Offset P1 and P2 slightly so their attack animations don't collide (P1 on %35==0, P2 on %35==18)
			var offset: int = 0 if player_number == 1 else 18
			if (frame + offset) % 35 == 0:
				if _test_presses_sent["light"] < 30:
					_test_presses_sent["light"] += 1
					_hold_light_frames = CLIENT_INPUT_HOLD_FRAMES
					print("[TEST INPUT] P%d sent LIGHT press #%d at frame %d" % [player_number, _test_presses_sent["light"], frame])
				elif _test_presses_sent["heavy"] < 30:
					_test_presses_sent["heavy"] += 1
					_hold_heavy_frames = CLIENT_INPUT_HOLD_FRAMES
					print("[TEST INPUT] P%d sent HEAVY press #%d at frame %d" % [player_number, _test_presses_sent["heavy"], frame])
				elif _test_presses_sent["special"] < 30:
					_test_presses_sent["special"] += 1
					_hold_special_frames = CLIENT_INPUT_HOLD_FRAMES
					print("[TEST INPUT] P%d sent SPECIAL press #%d at frame %d" % [player_number, _test_presses_sent["special"], frame])

		if _hold_jump_frames > 0:
			mask |= INPUT_JUMP
			_hold_jump_frames -= 1
		if _hold_light_frames > 0:
			mask |= INPUT_LIGHT
			_hold_light_frames -= 1
		if _hold_heavy_frames > 0:
			mask |= INPUT_HEAVY
			_hold_heavy_frames -= 1
		if _hold_special_frames > 0:
			mask |= INPUT_SPECIAL
			_hold_special_frames -= 1
		return mask

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

	# Detect rising edge button presses and initiate hold window
	if Input.is_action_just_pressed("p_jump"):
		_hold_jump_frames = CLIENT_INPUT_HOLD_FRAMES
	if Input.is_action_just_pressed("p_light"):
		_hold_light_frames = CLIENT_INPUT_HOLD_FRAMES
	if Input.is_action_just_pressed("p_heavy"):
		_hold_heavy_frames = CLIENT_INPUT_HOLD_FRAMES
	if Input.is_action_just_pressed("p_special"):
		_hold_special_frames = CLIENT_INPUT_HOLD_FRAMES

	# Hold active attack and jump buttons in outgoing mask so single dropped packets are not lost
	if _hold_jump_frames > 0:
		mask |= INPUT_JUMP
		_hold_jump_frames -= 1
	if _hold_light_frames > 0:
		mask |= INPUT_LIGHT
		_hold_light_frames -= 1
	if _hold_heavy_frames > 0:
		mask |= INPUT_HEAVY
		_hold_heavy_frames -= 1
	if _hold_special_frames > 0:
		mask |= INPUT_SPECIAL
		_hold_special_frames -= 1

	return mask

@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_send_client_input(mask: int, seq: int) -> void:
	receive_client_input(mask, seq)

func receive_client_input(mask: int, seq: int) -> void:
	if not _is_host_sim():
		return

	var entry: Dictionary = { "seq": seq, "mask": mask }
	if client_input_queue.is_empty() or seq > client_input_queue[-1]["seq"]:
		client_input_queue.append(entry)
	else:
		var inserted: bool = false
		for i in range(client_input_queue.size()):
			if client_input_queue[i]["seq"] == seq:
				inserted = true
				break
			elif client_input_queue[i]["seq"] > seq:
				client_input_queue.insert(i, entry)
				inserted = true
				break
		if not inserted:
			client_input_queue.append(entry)

	if client_input_queue.size() > 60:
		client_input_queue.pop_front()

# ==============================================================================
# HOST SIMULATION (60 Hz FIXED)
# ==============================================================================
func _can_attack() -> bool:
	if hitstop_frames_left > 0 or hitstun_frames_left > 0:
		return false
	if current_state in [State.IDLE, State.WALK, State.JUMP]:
		return true
	return false

func _execute_attack_from_mask(atk_mask: int) -> void:
	if atk_mask & INPUT_LIGHT:
		attack_register_count["attack_light"] += 1
		print("[BUFFER] P%d executed attack_light (Count: %d, frame: %d)" % [player_number, attack_register_count["attack_light"], Engine.get_physics_frames()])
		_start_attack(character_data.light_move, "attack_light")
	elif atk_mask & INPUT_HEAVY:
		attack_register_count["attack_heavy"] += 1
		print("[BUFFER] P%d executed attack_heavy (Count: %d, frame: %d)" % [player_number, attack_register_count["attack_heavy"], Engine.get_physics_frames()])
		_start_attack(character_data.heavy_move, "attack_heavy")
	elif atk_mask & INPUT_SPECIAL:
		attack_register_count["attack_special"] += 1
		print("[BUFFER] P%d executed attack_special (Count: %d, frame: %d)" % [player_number, attack_register_count["attack_special"], Engine.get_physics_frames()])
		_start_attack(character_data.special_move, "attack_special")

func _server_physics_step(delta: float) -> void:
	# Hitstop freeze frames
	if hitstop_frames_left > 0:
		hitstop_frames_left -= 1
		_check_failsafe_stuck()
		_update_sync_state()
		return

	# Determine active input mask and buffer new presses
	var input_mask: int = 0
	if player_number == 1:
		var raw_input := _sample_local_input()
		var new_presses := raw_input & ~_prev_local_mask
		_prev_local_mask = raw_input

		if new_presses & INPUT_LIGHT:
			buffered_attack = INPUT_LIGHT
			attack_buffer_timer = INPUT_BUFFER_WINDOW_FRAMES
		elif new_presses & INPUT_HEAVY:
			buffered_attack = INPUT_HEAVY
			attack_buffer_timer = INPUT_BUFFER_WINDOW_FRAMES
		elif new_presses & INPUT_SPECIAL:
			buffered_attack = INPUT_SPECIAL
			attack_buffer_timer = INPUT_BUFFER_WINDOW_FRAMES

		if new_presses & INPUT_JUMP:
			buffered_jump = true
			jump_buffer_timer = INPUT_BUFFER_WINDOW_FRAMES

		input_mask = raw_input
	else:
		if not client_input_queue.is_empty():
			while client_input_queue.size() > 4:
				var skipped: Dictionary = client_input_queue.pop_front()
				last_processed_client_seq = skipped["seq"]
				var s_mask: int = skipped["mask"]
				var s_presses: int = s_mask & ~_prev_received_mask
				_prev_received_mask = s_mask
				if s_presses & INPUT_LIGHT:
					buffered_attack = INPUT_LIGHT
					attack_buffer_timer = INPUT_BUFFER_WINDOW_FRAMES
				elif s_presses & INPUT_HEAVY:
					buffered_attack = INPUT_HEAVY
					attack_buffer_timer = INPUT_BUFFER_WINDOW_FRAMES
				elif s_presses & INPUT_SPECIAL:
					buffered_attack = INPUT_SPECIAL
					attack_buffer_timer = INPUT_BUFFER_WINDOW_FRAMES
				if s_presses & INPUT_JUMP:
					buffered_jump = true
					jump_buffer_timer = INPUT_BUFFER_WINDOW_FRAMES

			var cur_entry: Dictionary = client_input_queue.pop_front()
			last_processed_client_seq = cur_entry["seq"]
			host_cached_input = cur_entry["mask"]

			var new_client_presses: int = host_cached_input & ~_prev_received_mask
			_prev_received_mask = host_cached_input

			if new_client_presses & INPUT_LIGHT:
				buffered_attack = INPUT_LIGHT
				attack_buffer_timer = INPUT_BUFFER_WINDOW_FRAMES
			elif new_client_presses & INPUT_HEAVY:
				buffered_attack = INPUT_HEAVY
				attack_buffer_timer = INPUT_BUFFER_WINDOW_FRAMES
			elif new_client_presses & INPUT_SPECIAL:
				buffered_attack = INPUT_SPECIAL
				attack_buffer_timer = INPUT_BUFFER_WINDOW_FRAMES

			if new_client_presses & INPUT_JUMP:
				buffered_jump = true
				jump_buffer_timer = INPUT_BUFFER_WINDOW_FRAMES

		input_mask = host_cached_input

	local_input_mask = input_mask

	# Failsafe stuck check
	state_ticks += 1
	_check_failsafe_stuck()

	# Process buffered attack if fighter can act
	if attack_buffer_timer > 0:
		if _can_attack():
			var atk := buffered_attack
			buffered_attack = 0
			attack_buffer_timer = 0
			_execute_attack_from_mask(atk)
		else:
			attack_buffer_timer -= 1
			if attack_buffer_timer <= 0:
				buffered_attack = 0

	# Process buffered jump if fighter can act
	if jump_buffer_timer > 0:
		if is_on_floor() and (current_state in [State.IDLE, State.WALK]):
			buffered_jump = false
			jump_buffer_timer = 0
			velocity.y = character_data.jump_velocity
			AudioManager.play_jump()
			_transition_to(State.JUMP)
		else:
			jump_buffer_timer -= 1
			if jump_buffer_timer <= 0:
				buffered_jump = false

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
				_update_facing_visual()

func _state_idle_step(delta: float, input: int) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 1500.0 * delta)
	_apply_gravity(delta)

	if not is_on_floor():
		_transition_to(State.JUMP)
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
		return

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

	var arena = _get_arena()
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
	if current_state != State.HURT:
		hitstun_frames_left = 0
		hitstop_frames_left = 0
	if current_state != State.ATTACK:
		_set_hitbox_active(false)
		current_move = null
		has_hit_target = false
		has_spawned_projectile = false

func _play_anim(anim_name: String) -> void:
	if sprite.animation != anim_name:
		sprite.play(anim_name)

func _on_animation_finished() -> void:
	if not _is_host_sim():
		return

	if current_state == State.ATTACK:
		_set_hitbox_active(false)
		_transition_to(State.IDLE if is_on_floor() else State.JUMP)
		if attack_buffer_timer > 0 and _can_attack():
			var atk := buffered_attack
			buffered_attack = 0
			attack_buffer_timer = 0
			_execute_attack_from_mask(atk)
	elif current_state == State.HURT and health > 0.0:
		if hitstun_frames_left <= 0:
			_transition_to(State.IDLE if is_on_floor() else State.JUMP)
			if attack_buffer_timer > 0 and _can_attack():
				var atk := buffered_attack
				buffered_attack = 0
				attack_buffer_timer = 0
				_execute_attack_from_mask(atk)
		else:
			# Stay paused on the last hurt frame until hitstun_frames_left expires
			sprite.pause()

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
		var arena = _get_arena()
		if arena and arena.has_method("rpc_trigger_melee_hit_effects"):
			NetworkManager.send_network_event("/root/GameArena", "rpc_trigger_melee_hit_effects", [hitbox.global_position, current_move.sfx_name, dmg >= 15.0])

func take_hit(damage_amount: float, knockback: Vector2, hitstun_frames: int, hit_sfx: String) -> void:
	if not _is_host_sim() or current_state == State.DEAD:
		return

	if NetworkManager.is_attack_test:
		health = max_hp
	else:
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
	_update_facing_visual()
	health = max_hp
	current_state = State.IDLE
	current_move = null
	has_hit_target = false
	has_spawned_projectile = false
	hitstun_frames_left = 0
	hitstop_frames_left = 0
	state_ticks = 0
	_ring_buffer_idx = 0
	for d in ring_buffer:
		d.clear()
	input_history.clear()
	client_input_queue.clear()
	client_input_seq = 0
	last_processed_client_seq = 0
	pred_correction_offset = Vector2.ZERO
	last_pred_error = 0.0
	last_correction_size = 0.0
	if sprite:
		sprite.position = Vector2.ZERO
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
	elif current_state in [State.IDLE, State.WALK, State.JUMP] and state_ticks > 60 and not _can_attack():
		stuck_reason = "IDLE_ATTACK_LOCK (state=%s ticks=%d hitstun=%d hitstop=%d)" % [
			State.keys()[current_state], state_ticks, hitstun_frames_left, hitstop_frames_left
		]

	if stuck_reason != "":
		print("[FAILSAFE] P%d triggered failsafe: %s. Clearing locks!" % [player_number, stuck_reason])
		_set_hitbox_active(false)
		current_move = null
		has_hit_target = false
		has_spawned_projectile = false
		hitstop_frames_left = 0
		hitstun_frames_left = 0
		if current_state in [State.ATTACK, State.HURT]:
			_transition_to(State.IDLE if is_on_floor() else State.JUMP)
			_play_anim("idle" if is_on_floor() else "jump")
		var arena = _get_arena()
		if arena and arena.has_method("on_failsafe_triggered"):
			arena.on_failsafe_triggered(player_number, stuck_reason)

func _record_tick_state(input_mask: int) -> void:
	if not OS.is_debug_build():
		return
	if ring_buffer.size() < RING_BUFFER_SIZE:
		ring_buffer.resize(RING_BUFFER_SIZE)
		for i in range(RING_BUFFER_SIZE):
			if ring_buffer[i] == null:
				ring_buffer[i] = {}

	var entry: Dictionary = ring_buffer[_ring_buffer_idx]
	entry["tick"] = current_tick
	entry["time_ms"] = Time.get_ticks_msec()
	entry["state"] = State.keys()[current_state] if current_state < State.size() else str(current_state)
	entry["state_ticks"] = state_ticks
	entry["anim"] = sprite.animation if sprite else ""
	entry["frame"] = sprite.frame if sprite else -1
	entry["is_playing"] = sprite.is_playing() if sprite else false
	entry["gpos"] = global_position
	entry["vel"] = velocity
	entry["hitstop"] = hitstop_frames_left
	entry["hitstun"] = hitstun_frames_left
	entry["input"] = input_mask
	entry["has_proj"] = has_spawned_projectile
	entry["hitbox_act"] = sync_hitbox_active
	entry["on_floor"] = is_on_floor()

	_ring_buffer_idx = (_ring_buffer_idx + 1) % RING_BUFFER_SIZE

func get_ordered_ring_buffer() -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	for i in range(RING_BUFFER_SIZE):
		var idx := (_ring_buffer_idx + i) % RING_BUFFER_SIZE
		if not ring_buffer[idx].is_empty():
			ordered.append(ring_buffer[idx])
	return ordered

# ==============================================================================
# CLIENT PREDICTION, INTERPOLATION & RENDERING
# ==============================================================================
func _client_interpolation_step(delta: float) -> void:
	if player_number == 2:
		_client_predicted_step(delta)
	else:
		_client_remote_interpolation_step(delta)

func _client_predicted_step(delta: float) -> void:
	client_input_seq += 1
	var mask := _sample_local_input()
	NetworkManager.send_client_input(mask, client_input_seq)

	# If host reports HURT or DEAD, prioritize authoritative state
	if sync_state in [int(State.HURT), int(State.DEAD)]:
		position = sync_position
		velocity = sync_velocity
		current_state = sync_state as State
		pred_correction_offset = Vector2.ZERO
		input_history.clear()
		_update_auto_facing()
		_sync_client_animation(true)
		return

	# Record entry before simulation
	var hist_entry: Dictionary = {
		"seq": client_input_seq,
		"mask": mask,
		"delta": delta,
		"pos": position,
		"vel": velocity,
		"state": current_state
	}
	input_history.append(hist_entry)
	if input_history.size() > 120:
		input_history.pop_front()

	# Simulate local physics step using identical logic to server
	_simulate_predicted_step(mask, delta, false)

	# Update post-simulation result
	hist_entry["pos"] = position
	hist_entry["vel"] = velocity

	# Decay visual offset smoothly
	pred_correction_offset = pred_correction_offset.lerp(Vector2.ZERO, 1.0 - exp(-15.0 * delta))
	if pred_correction_offset.length_squared() < 0.01:
		pred_correction_offset = Vector2.ZERO
	sprite.position = pred_correction_offset

	_update_auto_facing()

	if health != sync_health:
		health = sync_health
		health_changed.emit(health, max_hp)

	_sync_client_animation(true)

func _simulate_predicted_step(input_mask: int, delta: float, is_replaying: bool = false) -> void:
	match current_state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, 1500.0 * delta)
			_apply_gravity(delta)
			if not is_on_floor():
				current_state = State.JUMP
			elif input_mask & INPUT_JUMP:
				velocity.y = character_data.jump_velocity
				if not is_replaying:
					AudioManager.play_jump()
				current_state = State.JUMP
			elif (input_mask & INPUT_LEFT) or (input_mask & INPUT_RIGHT):
				current_state = State.WALK
			else:
				if not is_replaying:
					_play_anim("idle")
		State.WALK:
			_apply_gravity(delta)
			if not is_on_floor():
				current_state = State.JUMP
			elif input_mask & INPUT_JUMP:
				velocity.y = character_data.jump_velocity
				if not is_replaying:
					AudioManager.play_jump()
				current_state = State.JUMP
			else:
				var move_dir: float = 0.0
				if input_mask & INPUT_LEFT:
					move_dir -= 1.0
				if input_mask & INPUT_RIGHT:
					move_dir += 1.0
				if move_dir == 0.0:
					current_state = State.IDLE
				else:
					velocity.x = move_dir * character_data.walk_speed
					if not is_replaying:
						_play_anim("walk")
		State.JUMP:
			_apply_gravity(delta)
			var move_dir: float = 0.0
			if input_mask & INPUT_LEFT:
				move_dir -= 1.0
			if input_mask & INPUT_RIGHT:
				move_dir += 1.0
			velocity.x = move_dir * (character_data.walk_speed * 0.75)
			if not is_replaying:
				_play_anim("jump")
			if is_on_floor() and velocity.y >= 0.0:
				if not is_replaying:
					landing_dust.restart()
					landing_dust.emitting = true
				current_state = State.IDLE
		State.ATTACK:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_apply_gravity(delta)
		State.HURT:
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			_apply_gravity(delta)
		State.DEAD:
			velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
			_apply_gravity(delta)

	move_and_slide()

func on_server_snapshot_received(d: Dictionary) -> void:
	sync_position = Vector2(d["pos"][0], d["pos"][1])
	sync_velocity = Vector2(d["vel"][0], d["vel"][1])
	sync_state = d["st"]
	sync_facing = d["fc"]
	sync_health = d["hp"]
	sync_anim = d["an"]
	sync_frame = d["fr"]
	sync_hitbox_active = d["hb"]

	var ack_seq: int = d.get("ack", 0)
	if ack_seq <= 0:
		return

	if sync_state in [int(State.HURT), int(State.DEAD)]:
		position = sync_position
		velocity = sync_velocity
		current_state = sync_state as State
		pred_correction_offset = Vector2.ZERO
		input_history.clear()
		return

	var ack_idx: int = -1
	for i in range(input_history.size()):
		if input_history[i]["seq"] == ack_seq:
			ack_idx = i
			break

	if ack_idx < 0:
		while not input_history.is_empty() and input_history[0]["seq"] < ack_seq:
			input_history.pop_front()
		return

	var hist_entry: Dictionary = input_history[ack_idx]
	var predicted_at_ack: Vector2 = hist_entry["pos"]
	var error_vec: Vector2 = sync_position - predicted_at_ack
	var error_dist: float = error_vec.length()
	last_pred_error = error_dist

	var unacked: Array[Dictionary] = []
	for i in range(ack_idx + 1, input_history.size()):
		unacked.append(input_history[i])
	input_history = unacked

	if error_dist > 80.0:
		position = sync_position
		velocity = sync_velocity
		current_state = sync_state as State
		pred_correction_offset = Vector2.ZERO
		input_history.clear()
		return

	if error_dist > 0.5:
		var old_pos := position
		position = sync_position
		velocity = sync_velocity
		current_state = sync_state as State

		for entry in input_history:
			_simulate_predicted_step(entry["mask"], entry["delta"], true)
			entry["pos"] = position
			entry["vel"] = velocity
			entry["state"] = current_state

		var correction := old_pos - position
		pred_correction_offset = (pred_correction_offset + correction).limit_length(25.0)
		last_correction_size = pred_correction_offset.length()

func _client_remote_interpolation_step(delta: float) -> void:
	var dist := position.distance_to(sync_position)
	if dist > 150.0:
		position = sync_position # Snap if discrepancy is large
	else:
		# Time-based smooth exponential interpolation
		var blend: float = 1.0 - exp(-22.0 * delta)
		position = position.lerp(sync_position, blend)

	velocity = sync_velocity
	facing_direction = sync_facing
	_update_facing_visual()

	if health != sync_health:
		health = sync_health
		health_changed.emit(health, max_hp)

	_sync_client_animation(false)
	current_state = sync_state as State

func _sync_client_animation(is_local_predicted: bool) -> void:
	var old_anim := sprite.animation
	if is_local_predicted:
		if sync_state in [int(State.ATTACK), int(State.HURT), int(State.DEAD)]:
			if sprite.animation != sync_anim:
				sprite.play(sync_anim)
				if sync_anim == "attack_special":
					AudioManager.play_special()
				elif sync_anim in ["attack_light", "attack_heavy"]:
					AudioManager.play_swing()
				elif sync_anim == "dead":
					AudioManager.play_ko()
			sprite.frame = sync_frame
			current_state = sync_state as State
		else:
			var target_anim: String = "idle"
			if not is_on_floor():
				target_anim = "jump"
			elif current_state == State.WALK or absf(velocity.x) > 10.0:
				target_anim = "walk"
			if sprite.animation != target_anim:
				sprite.play(target_anim)
				if target_anim == "jump" and old_anim != "jump":
					AudioManager.play_jump()
			if old_anim == "jump" and target_anim in ["idle", "walk"]:
				landing_dust.restart()
				landing_dust.emitting = true
	else:
		if sprite.animation != sync_anim:
			sprite.play(sync_anim)
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

		if sync_anim in ["attack_light", "attack_heavy", "attack_special", "hurt", "dead"]:
			sprite.frame = sync_frame

func get_diagnostic_info() -> Dictionary:
	return {
		"p": player_number,
		"state": State.keys()[current_state],
		"can_attack": _can_attack(),
		"atk_buf": buffered_attack,
		"buf_timer": attack_buffer_timer,
		"hitstop": hitstop_frames_left,
		"hitstun": hitstun_frames_left,
		"has_hit": has_hit_target,
		"input": local_input_mask,
		"ticks": state_ticks,
		"facing": facing_direction,
		"pos": position,
		"pred_err": last_pred_error,
		"corr": last_correction_size
	}
