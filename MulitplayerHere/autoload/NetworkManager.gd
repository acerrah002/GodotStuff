extends Node

signal player_connected(id: int, name: String)
signal player_disconnected(id: int, name: String)
signal connection_success()
signal connection_failed(reason: String)
signal server_stopped()
signal game_start_countdown(seconds: int)
signal game_start_cancelled()

var peer: ENetMultiplayerPeer = null
var players: Dictionary = {}   # id -> { "name": String }
var is_host: bool = false
var local_player_name: String = "Player"

# Generic cap so any future game can set its own limit before hosting.
# Enforced at the ENet layer below, so no manual kick logic is needed.
@export var max_players: int = 4

@export var game_scene_path: String = "res://UIScenes/Platformer.tscn"

var _countdown_timer: Timer = null
var _countdown_seconds: int = 10

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connected_to_server.connect(_on_client_connected)

# use_upnp defaults to false: the UPNP tab already opens the port itself
# before calling this, so LAN/direct-IP hosting no longer redundantly
# (and pointlessly, on Android) tries to talk to a UPnP gateway.
func host_game(port: int, player_name: String, use_upnp: bool = false) -> bool:
	if peer: return false
	if use_upnp:
		Upnp.open_port(port, "CTF Game")
	peer = ENetMultiplayerPeer.new()
	# max_players includes the host itself, so ENet only needs to accept
	# (max_players - 1) additional connections. ENet rejects anyone beyond
	# that automatically - no manual kick logic required.
	var err = peer.create_server(port, max(max_players - 1, 1))
	if err != OK:
		peer = null
		connection_failed.emit("Could not start server")
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	local_player_name = player_name
	_register_player(1, player_name)
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
	rpc_id(1, "_server_register_player", local_player_name)
	connection_success.emit()

@rpc("any_peer", "reliable")
func _server_register_player(pname: String) -> void:
	var id = multiplayer.get_remote_sender_id()
	_register_player(id, pname)

func _register_player(id: int, pname: String) -> void:
	players[id] = {"name": pname}
	player_connected.emit(id, pname)
	if is_host:
		for existing_id in players:
			if existing_id != id:
				rpc_id(id, "_sync_player", existing_id, players[existing_id].name)
		rpc("_sync_player", id, pname)

@rpc("authority", "reliable")
func _sync_player(id: int, pname: String) -> void:
	if players.has(id): return
	players[id] = {"name": pname}
	player_connected.emit(id, pname)

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
		rpc("_sync_countdown", 0)
	else:
		game_start_countdown.emit(_countdown_seconds)
		rpc("_sync_countdown", _countdown_seconds)

# ---------- Player ping ----------
func get_player_ping(id: int) -> int:
	if peer:
		if peer.has_method("get_peer_ping"):
			return peer.get_peer_ping(id)
	return 0

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
	LanManager.stop_lan()
	server_stopped.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_stop()
