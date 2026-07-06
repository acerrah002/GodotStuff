extends Node2D

# =====================================================================
# GSwitch-style ship runner. Host is authoritative for physics, obstacle
# spawning, and elimination. Clients predict their own ship's Y locally
# for responsive controls, and get corrected/relayed everything else by
# the host. This file is fully self-contained - the lobby/main menu
# know nothing about it, so they stay reusable for future game modes.
# =====================================================================

# ---------- Tunables ----------
const SCROLL_SPEED := 220.0
const GRAVITY := 900.0
const THRUST := -1500.0
const MAX_FALL_SPEED := 480.0
const MAX_RISE_SPEED := -480.0
const SHIP_SPAWN_X := 220.0
const SHIP_HALF := 16.0
const GAP_HEIGHT := 190.0
const SPAWN_INTERVAL_MIN := 1.1
const SPAWN_INTERVAL_MAX := 1.9
const ELIM_LEFT_BOUND := -60.0
const ELIM_MARGIN := 60.0
const RECONCILE_THRESHOLD := 40.0
const MAX_PLAYERS := 4

@export var lobby_return_scene: String = "res://UIScenes/lobby.tscn"

var SHIP_COLORS := [
	Color(0.95, 0.25, 0.25),
	Color(0.25, 0.55, 0.95),
	Color(0.30, 0.90, 0.40),
	Color(0.95, 0.85, 0.20),
]

var is_host: bool = false
var local_player_id: int = -1
var view_w: float
var view_h: float

var ship_nodes: Dictionary = {}         # id -> Node2D                (everyone)
var ship_alive_visual: Dictionary = {}  # id -> bool                  (everyone)
var ship_states: Dictionary = {}        # id -> {x,y,vel_y,holding,alive}  (host only)
var active_obstacles: Array = []        # host only - used for collision checks
var all_obstacle_visuals: Array = []    # everyone - used to move/cleanup visuals

var local_vel_y: float = 0.0
var local_holding: bool = false
var _game_ended: bool = false
var _spawn_timer: float = 1.2
var elapsed_time: float = 0.0
var rng := RandomNumberGenerator.new()

var obstacles_layer: Node2D
var ships_layer: Node2D
var alive_label: Label
var distance_label: Label
var eliminated_banner: Label
var game_over_overlay: Control
var game_over_label: Label

func _ready() -> void:
	rng.randomize()
	is_host = NetworkManager.is_host
	local_player_id = multiplayer.get_unique_id()
	var vp := get_viewport_rect().size
	view_w = vp.x
	view_h = vp.y

	obstacles_layer = Node2D.new()
	add_child(obstacles_layer)
	ships_layer = Node2D.new()
	add_child(ships_layer)

	_build_background()
	_build_ui()
	_spawn_all_ships()

	if is_host:
		NetworkManager.player_disconnected.connect(_on_player_left_mid_game)
		_spawn_timer = rng.randf_range(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX)

# ---------- Setup ----------
func _build_background() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.16)
	bg.size = Vector2(view_w, view_h)
	bg.z_index = -10
	add_child(bg)

func _build_ui() -> void:
	var ui = CanvasLayer.new()
	add_child(ui)

	alive_label = Label.new()
	alive_label.add_theme_font_size_override("font_size", 20)
	alive_label.position = Vector2(16, 12)
	ui.add_child(alive_label)

	distance_label = Label.new()
	distance_label.add_theme_font_size_override("font_size", 18)
	distance_label.position = Vector2(view_w - 190, 12)
	ui.add_child(distance_label)

	eliminated_banner = Label.new()
	eliminated_banner.text = "You were eliminated - spectating"
	eliminated_banner.add_theme_font_size_override("font_size", 20)
	eliminated_banner.add_theme_color_override("font_color", Color(1, 0.4, 0.3))
	eliminated_banner.visible = false
	eliminated_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eliminated_banner.custom_minimum_size = Vector2(440, 30)
	eliminated_banner.position = Vector2(view_w / 2.0 - 220, 16)
	ui.add_child(eliminated_banner)

	var leave_btn = Button.new()
	leave_btn.text = "Leave Match"
	leave_btn.custom_minimum_size = Vector2(130, 40)
	leave_btn.position = Vector2(view_w - 150, view_h - 56)
	leave_btn.pressed.connect(_on_leave_match_pressed)
	ui.add_child(leave_btn)

	game_over_overlay = _build_game_over_overlay()
	game_over_overlay.visible = false
	ui.add_child(game_over_overlay)

func _build_game_over_overlay() -> Control:
	var overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	game_over_label = Label.new()
	game_over_label.add_theme_font_size_override("font_size", 34)
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_over_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(game_over_label)
	return overlay

func _make_ship_visual(color: Color) -> Node2D:
	var node = Node2D.new()
	var poly = Polygon2D.new()
	poly.color = color
	poly.polygon = PackedVector2Array([
		Vector2(-16, 0), Vector2(-4, -12), Vector2(16, 0), Vector2(-4, 12)
	])
	node.add_child(poly)
	var outline = Line2D.new()
	outline.points = PackedVector2Array([
		Vector2(-16, 0), Vector2(-4, -12), Vector2(16, 0), Vector2(-4, 12), Vector2(-16, 0)
	])
	outline.width = 2.0
	outline.default_color = Color(0, 0, 0, 0.6)
	node.add_child(outline)
	return node

func _spawn_all_ships() -> void:
	var ids = NetworkManager.players.keys()
	ids.sort()
	ids = ids.slice(0, MAX_PLAYERS)
	for i in ids.size():
		var id = ids[i]
		var color = SHIP_COLORS[i % SHIP_COLORS.size()]
		var spawn_y = view_h / 2.0 + (i - (ids.size() - 1) / 2.0) * 55.0
		var ship = _make_ship_visual(color)
		ship.position = Vector2(SHIP_SPAWN_X, spawn_y)
		ships_layer.add_child(ship)
		ship_nodes[id] = ship
		ship_alive_visual[id] = true
		if is_host:
			ship_states[id] = {"x": SHIP_SPAWN_X, "y": spawn_y, "vel_y": 0.0, "holding": false, "alive": true}
	_refresh_alive_count_label()

# ---------- Input ----------
func _unhandled_input(event: InputEvent) -> void:
	if local_player_id == -1 or _game_ended:
		return
	if not ship_alive_visual.get(local_player_id, false):
		return
	var pressed_state = null
	if event is InputEventScreenTouch:
		pressed_state = event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pressed_state = event.pressed
	elif event is InputEventKey and event.keycode == KEY_SPACE and not event.echo:
		pressed_state = event.pressed
	if pressed_state == null:
		return
	_set_local_holding(pressed_state)

func _set_local_holding(pressed: bool) -> void:
	local_holding = pressed
	if is_host:
		if ship_states.has(local_player_id):
			ship_states[local_player_id].holding = pressed
	else:
		rpc_id(1, "_client_set_holding", pressed)

@rpc("any_peer", "reliable")
func _client_set_holding(pressed: bool) -> void:
	var id = multiplayer.get_remote_sender_id()
	if ship_states.has(id):
		ship_states[id].holding = pressed

# ---------- Per-frame movement ----------
func _process(delta: float) -> void:
	for obs in all_obstacle_visuals.duplicate():
		if not is_instance_valid(obs):
			all_obstacle_visuals.erase(obs)
			continue
		obs.position.x -= SCROLL_SPEED * delta
		if obs.position.x < -300.0:
			all_obstacle_visuals.erase(obs)
			active_obstacles.erase(obs)
			obs.queue_free()
	if not _game_ended:
		elapsed_time += delta
	distance_label.text = "Distance: %d m" % int(elapsed_time * (SCROLL_SPEED / 10.0))

func _physics_process(delta: float) -> void:
	if _game_ended:
		return
	if is_host:
		_host_simulate(delta)
	else:
		_predict_local_ship(delta)

func _predict_local_ship(delta: float) -> void:
	if local_player_id == -1 or not ship_alive_visual.get(local_player_id, false):
		return
	var ship = ship_nodes.get(local_player_id)
	if not ship or not is_instance_valid(ship):
		return
	var accel = THRUST if local_holding else GRAVITY
	local_vel_y = clamp(local_vel_y + accel * delta, MAX_RISE_SPEED, MAX_FALL_SPEED)
	ship.position.y = clamp(ship.position.y + local_vel_y * delta, 0.0, view_h)

# ---------- Host authoritative simulation ----------
func _host_simulate(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = rng.randf_range(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX)
		_host_spawn_obstacle()

	for id in ship_states.keys():
		var st = ship_states[id]
		if not st.alive:
			continue
		var accel = THRUST if st.holding else GRAVITY
		st.vel_y = clamp(st.vel_y + accel * delta, MAX_RISE_SPEED, MAX_FALL_SPEED)
		st.y += st.vel_y * delta

		var ship_rect = Rect2(st.x - SHIP_HALF, st.y - SHIP_HALF, SHIP_HALF * 2.0, SHIP_HALF * 2.0)
		var blocked := false
		for obs in active_obstacles.duplicate():
			if not is_instance_valid(obs):
				active_obstacles.erase(obs)
				continue
			var size: Vector2 = obs.get_meta("size")
			var obs_rect = Rect2(obs.position.x - size.x / 2.0, obs.position.y - size.y / 2.0, size.x, size.y)
			if ship_rect.intersects(obs_rect):
				var kind: String = obs.get_meta("kind")
				if kind == "hazard":
					_eliminate(id)
					blocked = false
					break
				else:
					blocked = true

		if st.alive and blocked:
			st.x -= SCROLL_SPEED * delta

		if st.alive and (st.x < ELIM_LEFT_BOUND or st.y < -ELIM_MARGIN or st.y > view_h + ELIM_MARGIN):
			_eliminate(id)

	_broadcast_ship_states()
	_check_game_over()

func _eliminate(id: int) -> void:
	if not ship_states.has(id) or not ship_states[id].alive:
		return
	ship_states[id].alive = false

func _host_spawn_obstacle() -> void:
	var spawn_x = view_w + 120.0
	if rng.randf() < 0.6:
		# Blocking wall with a gap - passable if you thread the needle,
		# otherwise it drags you toward the left edge of the screen.
		var gap_y = rng.randf_range(140.0, view_h - 140.0)
		var top_h = gap_y - GAP_HEIGHT / 2.0
		var bottom_h = view_h - (gap_y + GAP_HEIGHT / 2.0)
		var color = Color(0.85, 0.3, 0.3)
		var top = _make_obstacle_visual("block", Vector2(60, top_h), color, Vector2(spawn_x, top_h / 2.0))
		var bottom = _make_obstacle_visual("block", Vector2(60, bottom_h), color, Vector2(spawn_x, view_h - bottom_h / 2.0))
		active_obstacles.append(top)
		active_obstacles.append(bottom)
		rpc("_spawn_obstacle_remote", "wall", gap_y)
	else:
		# Hazard - instant elimination on contact.
		var hazard_y = rng.randf_range(60.0, view_h - 60.0)
		var hz = _make_obstacle_visual("hazard", Vector2(46, 46), Color(1, 0.85, 0.1), Vector2(spawn_x, hazard_y))
		active_obstacles.append(hz)
		rpc("_spawn_obstacle_remote", "hazard", hazard_y)

@rpc("authority", "reliable")
func _spawn_obstacle_remote(kind: String, y_value: float) -> void:
	if is_host:
		return  # host already built its own visuals locally
	var spawn_x = view_w + 120.0
	if kind == "wall":
		var gap_y = y_value
		var top_h = gap_y - GAP_HEIGHT / 2.0
		var bottom_h = view_h - (gap_y + GAP_HEIGHT / 2.0)
		var color = Color(0.85, 0.3, 0.3)
		_make_obstacle_visual("block", Vector2(60, top_h), color, Vector2(spawn_x, top_h / 2.0))
		_make_obstacle_visual("block", Vector2(60, bottom_h), color, Vector2(spawn_x, view_h - bottom_h / 2.0))
	else:
		_make_obstacle_visual("hazard", Vector2(46, 46), Color(1, 0.85, 0.1), Vector2(spawn_x, y_value))

func _make_obstacle_visual(kind: String, size: Vector2, color: Color, spawn_pos: Vector2) -> Node2D:
	var node = Node2D.new()
	node.position = spawn_pos
	node.set_meta("kind", kind)
	node.set_meta("size", size)
	var rect = ColorRect.new()
	rect.color = color
	rect.size = size
	rect.position = -size / 2.0
	node.add_child(rect)
	obstacles_layer.add_child(node)
	all_obstacle_visuals.append(node)
	return node

# ---------- State sync ----------
func _broadcast_ship_states() -> void:
	var flat: Array = []
	for id in ship_states.keys():
		var st = ship_states[id]
		flat.append(id)
		flat.append(st.x)
		flat.append(st.y)
		flat.append(1 if st.alive else 0)
	rpc("_sync_all_ships", flat)
	_sync_all_ships(flat)  # rpc() doesn't call the host itself, so apply locally too

@rpc("authority", "unreliable_ordered")
func _sync_all_ships(flat: Array) -> void:
	var i = 0
	while i < flat.size():
		var id = flat[i]
		var x = flat[i + 1]
		var y = flat[i + 2]
		var alive = flat[i + 3] == 1
		i += 4
		_apply_ship_sync(id, x, y, alive)

func _apply_ship_sync(id: int, x: float, y: float, alive: bool) -> void:
	var ship = ship_nodes.get(id)
	if not ship or not is_instance_valid(ship):
		return
	if id == local_player_id and not is_host:
		# Trust local prediction for Y unless it's drifted noticeably;
		# always trust the host for X (that's where block-drag lives).
		ship.position.x = x
		if abs(ship.position.y - y) > RECONCILE_THRESHOLD:
			ship.position.y = y
			local_vel_y = 0.0
	else:
		ship.position = Vector2(x, y)
	_set_ship_alive_visual(id, alive)

func _set_ship_alive_visual(id: int, alive: bool) -> void:
	var was_alive = ship_alive_visual.get(id, true)
	ship_alive_visual[id] = alive
	var ship = ship_nodes.get(id)
	if ship and is_instance_valid(ship):
		ship.visible = alive
	if was_alive and not alive:
		if id == local_player_id:
			eliminated_banner.visible = true
		_refresh_alive_count_label()

func _refresh_alive_count_label() -> void:
	var alive_count = 0
	for v in ship_alive_visual.values():
		if v:
			alive_count += 1
	alive_label.text = "Alive: %d/%d" % [alive_count, ship_alive_visual.size()]

# ---------- Game over / lobby return ----------
func _check_game_over() -> void:
	if _game_ended:
		return
	var alive_ids: Array = []
	for id in ship_states.keys():
		if ship_states[id].alive:
			alive_ids.append(id)
	var total = ship_states.size()
	if total > 1 and alive_ids.size() <= 1:
		_game_ended = true
		var winner_id = alive_ids[0] if alive_ids.size() == 1 else -1
		rpc("_game_over", winner_id)
		_game_over(winner_id)
	elif total == 1 and alive_ids.size() == 0:
		_game_ended = true
		rpc("_game_over", -1)
		_game_over(-1)

@rpc("authority", "reliable")
func _game_over(winner_id: int) -> void:
	_game_ended = true
	_show_game_over_overlay(winner_id)
	if is_host:
		await get_tree().create_timer(4.0).timeout
		_return_all_to_lobby()

func _show_game_over_overlay(winner_id: int) -> void:
	var text := ""
	if winner_id == -1:
		text = "Game Over!"
	elif NetworkManager.players.has(winner_id):
		text = "%s Wins!" % NetworkManager.players[winner_id].name
	else:
		text = "Player %d Wins!" % winner_id
	game_over_label.text = text + "\nReturning to lobby..."
	game_over_overlay.visible = true

func _return_all_to_lobby() -> void:
	rpc("_return_to_lobby")
	_return_to_lobby()

@rpc("authority", "reliable")
func _return_to_lobby() -> void:
	get_tree().change_scene_to_file(lobby_return_scene)

func _on_player_left_mid_game(id: int, _pname: String) -> void:
	if not is_host:
		return
	if ship_states.has(id) and ship_states[id].alive:
		_eliminate(id)
		_broadcast_ship_states()
		_check_game_over()

func _on_leave_match_pressed() -> void:
	NetworkManager._stop()
	get_tree().change_scene_to_file("res://UIScenes/MainMenu.tscn")
