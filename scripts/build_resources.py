import os

moves = {
    'karasu_light': ('Light Slash', 'attack_light', 1, 2, 3, 5, 8.0, 14, 220, -150, 65, 45, 50, -15, 'swing', False),
    'karasu_heavy': ('Heavy Cleave', 'attack_heavy', 1, 1, 2, 3, 16.0, 20, 360, -220, 85, 55, 60, -20, 'swing', False),
    'karasu_special': ('Wing Tempest', 'attack_special', 0, 1, 2, 2, 22.0, 24, 420, -260, 110, 70, 75, -25, 'special', False),

    'kitsune_light': ('Spirit Palm', 'attack_light', 2, 3, 5, 9, 7.0, 12, 180, -140, 60, 45, 45, -10, 'swing', False),
    'kitsune_heavy': ('Tails Whirl', 'attack_heavy', 3, 4, 6, 9, 14.0, 18, 320, -200, 80, 50, 55, -15, 'swing', False),
    'kitsune_special': ('Fox Fire Blast', 'attack_special', 1, 2, 3, 6, 18.0, 22, 280, -180, 50, 40, 60, -20, 'special', True),

    'yamabushi_light': ('Iron Hilt', 'attack_light', 0, 1, 1, 2, 11.0, 16, 260, -180, 70, 50, 50, -15, 'swing', False),
    'yamabushi_heavy': ('Mountain Splitter', 'attack_heavy', 1, 2, 3, 5, 20.0, 24, 450, -280, 95, 60, 65, -25, 'hit_heavy', False),
    'yamabushi_special': ('Earth Quake', 'attack_special', 1, 2, 3, 3, 26.0, 28, 520, -320, 120, 80, 80, -30, 'special', False),
}

os.makedirs('resources/moves', exist_ok=True)
os.makedirs('resources/characters', exist_ok=True)

for k, v in moves.items():
    content = f"""[gd_resource type="Resource" script_class="MoveData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/move_data.gd" id="1_move"]

[resource]
script = ExtResource("1_move")
move_name = "{v[0]}"
animation_name = "{v[1]}"
startup_frame = {v[2]}
active_frame_start = {v[3]}
active_frame_end = {v[4]}
recovery_frame = {v[5]}
damage = {v[6]}
hitstun_frames = {v[7]}
knockback = Vector2({v[8]}, {v[9]})
hitbox_size = Vector2({v[10]}, {v[11]})
hitbox_offset = Vector2({v[12]}, {v[13]})
sfx_name = "{v[14]}"
is_projectile = {str(v[15]).lower()}
projectile_speed = 550.0
"""
    with open(f'resources/moves/{k}.tres', 'w') as f:
        f.write(content)

chars = {
    'karasu': {
        'id': 'karasu',
        'name': 'Karasu Tengu',
        'avatar': 'res://assets/fantasy-character-avatar-face-icons/PNG/Transperent/con20.png',
        'health': 100.0,
        'speed': 280.0,
        'jump': -650.0,
        'dmg_mult': 1.0,
        'idle_p': 'res://assets/characters/PNG/Karasu_tengu/Idle.png', 'idle_f': 6,
        'walk_p': 'res://assets/characters/PNG/Karasu_tengu/Walk.png', 'walk_f': 8,
        'jump_p': 'res://assets/characters/PNG/Karasu_tengu/Jump.png', 'jump_f': 15,
        'at1_p': 'res://assets/characters/PNG/Karasu_tengu/Attack_1.png', 'at1_f': 6,
        'at2_p': 'res://assets/characters/PNG/Karasu_tengu/Attack_2.png', 'at2_f': 4,
        'at3_p': 'res://assets/characters/PNG/Karasu_tengu/Attack_3.png', 'at3_f': 3,
        'hurt_p': 'res://assets/characters/PNG/Karasu_tengu/Hurt.png', 'hurt_f': 3,
        'dead_p': 'res://assets/characters/PNG/Karasu_tengu/Dead.png', 'dead_f': 6,
        'm_l': 'res://resources/moves/karasu_light.tres',
        'm_h': 'res://resources/moves/karasu_heavy.tres',
        'm_s': 'res://resources/moves/karasu_special.tres',
    },
    'kitsune': {
        'id': 'kitsune',
        'name': 'Kitsune',
        'avatar': 'res://assets/fantasy-character-avatar-face-icons/PNG/Transperent/con8.png',
        'health': 90.0,
        'speed': 250.0,
        'jump': -630.0,
        'dmg_mult': 1.1,
        'idle_p': 'res://assets/characters/PNG/Kitsune/Idle.png', 'idle_f': 8,
        'walk_p': 'res://assets/characters/PNG/Kitsune/Walk.png', 'walk_f': 8,
        'jump_p': 'res://assets/characters/PNG/Kitsune/Jump.png', 'jump_f': 10,
        'at1_p': 'res://assets/characters/PNG/Kitsune/Attack_1.png', 'at1_f': 10,
        'at2_p': 'res://assets/characters/PNG/Kitsune/Attack_2.png', 'at2_f': 10,
        'at3_p': 'res://assets/characters/PNG/Kitsune/Attack_3.png', 'at3_f': 7,
        'hurt_p': 'res://assets/characters/PNG/Kitsune/Hurt.png', 'hurt_f': 2,
        'dead_p': 'res://assets/characters/PNG/Kitsune/Dead.png', 'dead_f': 10,
        'm_l': 'res://resources/moves/kitsune_light.tres',
        'm_h': 'res://resources/moves/kitsune_heavy.tres',
        'm_s': 'res://resources/moves/kitsune_special.tres',
    },
    'yamabushi': {
        'id': 'yamabushi',
        'name': 'Yamabushi Tengu',
        'avatar': 'res://assets/fantasy-character-avatar-face-icons/PNG/Transperent/con26.png',
        'health': 120.0,
        'speed': 210.0,
        'jump': -680.0,
        'dmg_mult': 1.25,
        'idle_p': 'res://assets/characters/PNG/Yamabushi_tengu/Idle.png', 'idle_f': 6,
        'walk_p': 'res://assets/characters/PNG/Yamabushi_tengu/Walk.png', 'walk_f': 8,
        'jump_p': 'res://assets/characters/PNG/Yamabushi_tengu/Jump.png', 'jump_f': 15,
        'at1_p': 'res://assets/characters/PNG/Yamabushi_tengu/Attack_1.png', 'at1_f': 3,
        'at2_p': 'res://assets/characters/PNG/Yamabushi_tengu/Attack_2.png', 'at2_f': 6,
        'at3_p': 'res://assets/characters/PNG/Yamabushi_tengu/Attack_3.png', 'at3_f': 4,
        'hurt_p': 'res://assets/characters/PNG/Yamabushi_tengu/Hurt.png', 'hurt_f': 3,
        'dead_p': 'res://assets/characters/PNG/Yamabushi_tengu/Dead.png', 'dead_f': 6,
        'm_l': 'res://resources/moves/yamabushi_light.tres',
        'm_h': 'res://resources/moves/yamabushi_heavy.tres',
        'm_s': 'res://resources/moves/yamabushi_special.tres',
    }
}

for k, c in chars.items():
    content = f"""[gd_resource type="Resource" script_class="CharacterData" load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/character_data.gd" id="1_char"]
[ext_resource type="Resource" path="{c['m_l']}" id="2_ml"]
[ext_resource type="Resource" path="{c['m_h']}" id="3_mh"]
[ext_resource type="Resource" path="{c['m_s']}" id="4_ms"]

[resource]
script = ExtResource("1_char")
character_id = "{c['id']}"
display_name = "{c['name']}"
avatar_path = "{c['avatar']}"
max_health = {c['health']}
walk_speed = {c['speed']}
jump_velocity = {c['jump']}
damage_multiplier = {c['dmg_mult']}
idle_sheet_path = "{c['idle_p']}"
idle_frames = {c['idle_f']}
walk_sheet_path = "{c['walk_p']}"
walk_frames = {c['walk_f']}
jump_sheet_path = "{c['jump_p']}"
jump_frames = {c['jump_f']}
attack_light_sheet_path = "{c['at1_p']}"
attack_light_frames = {c['at1_f']}
attack_heavy_sheet_path = "{c['at2_p']}"
attack_heavy_frames = {c['at2_f']}
attack_special_sheet_path = "{c['at3_p']}"
attack_special_frames = {c['at3_f']}
hurt_sheet_path = "{c['hurt_p']}"
hurt_frames = {c['hurt_f']}
dead_sheet_path = "{c['dead_p']}"
dead_frames = {c['dead_f']}
light_move = ExtResource("2_ml")
heavy_move = ExtResource("3_mh")
special_move = ExtResource("4_ms")
"""
    with open(f'resources/characters/{k}.tres', 'w') as f:
        f.write(content)

print('All move and character resources written successfully.')
