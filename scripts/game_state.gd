extends Node

# Game State Autoload - Fight Back
# Holds match state, selections, scores, and synchronized match settings.

signal player_character_updated(peer_id: int, character_id: String)
signal player_lock_updated(peer_id: int, is_locked: bool)
signal both_players_locked()
signal round_ended(winner_peer_id: int)
signal match_ended(winner_peer_id: int)
signal rematch_state_changed()

const CHAR_KARASU: String = "karasu"
const CHAR_KITSUNE: String = "kitsune"
const CHAR_YAMABUSHI: String = "yamabushi"

const MAX_ROUNDS_TO_WIN: int = 2
const ROUND_TIME_LIMIT: float = 99.0

var local_username: String = "Player"
var remote_username: String = "Opponent"

var host_peer_id: int = 1
var client_peer_id: int = 0

# Mapping: peer_id -> character_id
var player_characters: Dictionary = {}
# Mapping: peer_id -> is_locked
var player_locked: Dictionary = {}
# Mapping: peer_id -> rounds won
var rounds_won: Dictionary = {}
# Mapping: peer_id -> wants rematch
var rematch_requests: Dictionary = {}

var current_round: int = 1
var is_match_active: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset_full_match()

func reset_full_match() -> void:
	player_characters.clear()
	player_locked.clear()
	rounds_won.clear()
	rematch_requests.clear()
	current_round = 1
	is_match_active = false

func register_players(p_host_id: int, p_client_id: int) -> void:
	host_peer_id = p_host_id
	client_peer_id = p_client_id
	player_characters[host_peer_id] = CHAR_KARASU
	player_characters[client_peer_id] = CHAR_KARASU
	player_locked[host_peer_id] = false
	player_locked[client_peer_id] = false
	rounds_won[host_peer_id] = 0
	rounds_won[client_peer_id] = 0
	rematch_requests[host_peer_id] = false
	rematch_requests[client_peer_id] = false
	current_round = 1
	is_match_active = false

func select_character(character_id: String) -> void:
	var my_id := 1 if NetworkManager.is_host else 2
	if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET:
		my_id = multiplayer.get_unique_id()
		rpc("rpc_set_character", my_id, character_id)
	else:
		NetworkManager.send_network_event("/root/GameState", "rpc_set_character", [my_id, character_id])

@rpc("any_peer", "call_local", "reliable")
func rpc_set_character(peer_id: int, character_id: String) -> void:
	player_characters[peer_id] = character_id
	player_locked[peer_id] = false
	player_character_updated.emit(peer_id, character_id)
	player_lock_updated.emit(peer_id, false)

func lock_character() -> void:
	var my_id := 1 if NetworkManager.is_host else 2
	if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET:
		my_id = multiplayer.get_unique_id()
		rpc("rpc_lock_character", my_id)
	else:
		NetworkManager.send_network_event("/root/GameState", "rpc_lock_character", [my_id])

@rpc("any_peer", "call_local", "reliable")
func rpc_lock_character(peer_id: int) -> void:
	player_locked[peer_id] = true
	player_lock_updated.emit(peer_id, true)
	_check_both_locked()

func _check_both_locked() -> void:
	if player_characters.size() >= 2:
		var all_locked := true
		for pid in player_locked.keys():
			if not player_locked[pid]:
				all_locked = false
				break
		if all_locked:
			both_players_locked.emit()

func request_rematch() -> void:
	var my_id := 1 if NetworkManager.is_host else 2
	if NetworkManager.current_mode == NetworkManager.NetworkMode.LAN_ENET:
		my_id = multiplayer.get_unique_id()
		rpc("rpc_request_rematch", my_id)
	else:
		NetworkManager.send_network_event("/root/GameState", "rpc_request_rematch", [my_id])

@rpc("any_peer", "call_local", "reliable")
func rpc_request_rematch(peer_id: int) -> void:
	rematch_requests[peer_id] = true
	rematch_state_changed.emit()

func both_want_rematch() -> bool:
	if rematch_requests.size() < 2:
		return false
	for pid in rematch_requests.keys():
		if not rematch_requests[pid]:
			return false
	return true

func reset_for_rematch() -> void:
	rounds_won[host_peer_id] = 0
	rounds_won[client_peer_id] = 0
	rematch_requests[host_peer_id] = false
	rematch_requests[client_peer_id] = false
	current_round = 1
	is_match_active = true

func record_round_win(winner_peer_id: int) -> void:
	if winner_peer_id > 0:
		rounds_won[winner_peer_id] = rounds_won.get(winner_peer_id, 0) + 1
	round_ended.emit(winner_peer_id)
	
	if winner_peer_id > 0 and rounds_won[winner_peer_id] >= MAX_ROUNDS_TO_WIN:
		is_match_active = false
		match_ended.emit(winner_peer_id)
	else:
		current_round += 1
