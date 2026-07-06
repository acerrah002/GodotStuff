extends Node

signal player_connected(id: int, name: String)
signal player_disconnected(id: int, name: String)
signal connection_success()
signal connection_failed(reason: String)
signal server_stopped()
signal game_start_countdown(seconds: int)
signal game_start_cancelled()
signal player_team_changed(id: int, team: int)   # ← new signal

var peer: ENetMultiplayerPeer = null
var players: Dictionary = {}   # id -> { "name": String, "team": int }
var is_host: bool = false
var local_player_name: String = "Player"
var team_mode: int = 1          # 0 = selective, 1 = random

@export var game_scene_path: String = "res://Maps/roblox_houses.scn"

var _countdown_timer: Timer = null
var _countdown_seconds: int = 10

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connected_to_server.connect(_on_client_connected)

func host_game(port: int, player_name: String) -> bool:
	if peer: return false
	Upnp.open_port(port, "CTF Game")
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, 8)
	if err != OK:
		peer = null
		connection_failed.emit("Could not start server")
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	local_player_name = player_name
	# In selective mode, the host starts with no team (will choose in lobby)
	var initial_team = -1 if team_mode == 0 else 0
	_register_player(1, player_name, initial_team)
	connection_success.emit()
	return true

func join_game(ip: String, port: int, player_name: String) -> bool:
	if peer: return false
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, port)
	if err != OK:
		peer = null
		connection_failed.emit("Could not connect")
		return false
	multiplayer.multiplayer_peer = peer
	is_host = false
	local_player_name = player_name
	return true

func _on_client_connected() -> void:
	rpc_id(1, "_server_register_player", local_player_name, -1)
	connection_success.emit()

@rpc("any_peer", "reliable")
func _server_register_player(pname: String, team_wish: int) -> void:
	var id = multiplayer.get_remote_sender_id()
	var assigned_team = team_wish
	if team_mode == 1:   # random
		assigned_team = randi() % 2
	_register_player(id, pname, assigned_team)
	rpc_id(id, "_set_team", assigned_team)
	rpc_id(id, "_sync_team_mode", team_mode)

func _register_player(id: int, pname: String, team: int) -> void:
	players[id] = {"name": pname, "team": team}
	player_connected.emit(id, pname)
	if is_host:
		for existing_id in players:
			if existing_id != id:
				rpc_id(id, "_sync_player", existing_id, players[existing_id].name, players[existing_id].team)
		rpc("_sync_player", id, pname, team)

@rpc("authority", "reliable")
func _sync_player(id: int, pname: String, team: int) -> void:
	if players.has(id): return
	players[id] = {"name": pname, "team": team}
	player_connected.emit(id, pname)

@rpc("authority", "reliable")
func _set_team(team: int) -> void:
	var my_id = multiplayer.get_unique_id()
	if players.has(my_id):
		players[my_id].team = team

# ---------- Team request (modified) ----------
# In _request_team:
@rpc("any_peer", "reliable")
func _request_team(team: int) -> void:
	print("[NM] _request_team called. team_mode:", team_mode, " sender:", multiplayer.get_remote_sender_id())
	if team_mode != 0:
		print("[NM]   Ignored – team_mode is not selective")
		return
	var id = multiplayer.get_remote_sender_id()
	print("[NM]   Request from peer", id, "to switch to team", team)
	if players.has(id):
		players[id].team = team
		print("[NM]   Updated local player dict")
		player_team_changed.emit(id, team)
		print("[NM]   Emitted player_team_changed locally")
		rpc("_on_team_updated", id, team)
		print("[NM]   Sent _on_team_updated RPC")
	else:
		print("[NM]   ERROR: player", id, "not in players dict")

# In _on_team_updated:
@rpc("authority", "reliable")
func _on_team_updated(id: int, team: int) -> void:
	print("[NM] _on_team_updated received: id", id, "team", team)
	if players.has(id):
		players[id].team = team
		player_team_changed.emit(id, team)
		print("[NM]   Updated + emitted player_team_changed")
	else:
		print("[NM]   Player not in dict (ignored)")


# Team mode management
@rpc("any_peer", "reliable")
func _set_team_mode(mode: int) -> void:
	if not is_host: return
	team_mode = mode
	rpc("_sync_team_mode", mode)

@rpc("authority", "reliable")
func _sync_team_mode(mode: int) -> void:
	team_mode = mode

# ---------- Game start with countdown ----------
func start_game_countdown() -> void:
	if not is_host or game_scene_path.is_empty():
		return
	
	# Cancel any existing countdown
	if _countdown_timer:
		_countdown_timer.stop()
		_countdown_timer.queue_free()
		_countdown_timer = null
		game_start_cancelled.emit()
	
	_countdown_seconds = 10
	_countdown_timer = Timer.new()
	_countdown_timer.wait_time = 1.0
	_countdown_timer.timeout.connect(_on_countdown_tick)
	add_child(_countdown_timer)
	_countdown_timer.start()
	
	game_start_countdown.emit(_countdown_seconds)
	# RPC the countdown to all clients
	rpc("_sync_countdown", _countdown_seconds)

@rpc("authority", "reliable")
func _sync_countdown(seconds: int) -> void:
	game_start_countdown.emit(seconds)

func _on_countdown_tick() -> void:
	_countdown_seconds -= 1
	print("[NetworkManager] Countdown tick: ", _countdown_seconds)
	if _countdown_seconds <= 0:
		_countdown_timer.stop()
		_countdown_timer.queue_free()
		_countdown_timer = null
		game_start_countdown.emit(0)
		rpc("_sync_countdown", 0)        # <-- send the final "0" to all clients
	else:
		game_start_countdown.emit(_countdown_seconds)
		rpc("_sync_countdown", _countdown_seconds)

# Inside NetworkManager.gd

# --- New: force assign a player's team (host only) ---
# In _force_team (already fine, just add print):
@rpc("authority", "reliable")
func _force_team(target_id: int, team: int) -> void:
	print("[NM] _force_team: target", target_id, "team", team)
	if not is_host: return
	if players.has(target_id):
		players[target_id].team = team
		player_team_changed.emit(target_id, team)
		rpc("_on_team_updated", target_id, team)
		print("[NM]   Forced + broadcasted")

# --- New: shuffle all players into random teams (host only) ---
# In _shuffle_teams:
@rpc("authority", "reliable")
func _shuffle_teams() -> void:
	print("[NM] _shuffle_teams called")
	if not is_host: return
	for id in players.keys():
		var new_team = randi() % 2
		players[id].team = new_team
		player_team_changed.emit(id, new_team)
		rpc("_on_team_updated", id, new_team)
		print("[NM]   Shuffled", id, "->", new_team)

# ---------- Player ping ----------
func get_player_ping(id: int) -> int:
	if peer:
		if peer.has_method("get_peer_ping"):
			return peer.get_peer_ping(id)
	return 0

# Rest of the script unchanged...
func _on_peer_connected(id: int) -> void:
	print("[NetworkManager] Peer connected: ", id)

func _on_peer_disconnected(id: int) -> void:
	print("[NetworkManager] Peer disconnected: ", id)
	if players.has(id):
		var pname = players[id].name
		players.erase(id)
		player_disconnected.emit(id, pname)

func _on_connection_failed() -> void:
	peer = null
	connection_failed.emit("Connection failed")

func _on_server_disconnected() -> void:
	_stop()



func _stop() -> void:
	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	players.clear()
	is_host = false
	server_stopped.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_stop()
