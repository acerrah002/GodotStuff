extends Control

# --- Reusable helpers ------------------------------------------------
func _label(text: String, font_size: int, color := Color.WHITE) -> Label:
	var l = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	if color != Color.WHITE: l.add_theme_color_override("font_color", color)
	return l

func _btn(text: String, font_size: int, min_w := 150, min_h := 50) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.add_theme_font_size_override("font_size", font_size)
	return b

func _hbox() -> HBoxContainer:
	var h = HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 10)
	return h

# ---------------------------------------------------------------------
var ip_label: Label
var copy_ip_btn: Button
var player_list: ItemList
var start_game_btn: Button
var leave_btn: Button
var status_label: Label
var chat_ui: ChatUI

var is_host: bool = false
var local_player_name: String
var player_ids: Array = []

func _ready() -> void:
	is_host = NetworkManager.is_host
	local_player_name = NetworkManager.local_player_name
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_update_ip_display()
	_refresh_player_list()

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_stopped.connect(_on_server_stopped)
	NetworkManager.game_start_countdown.connect(_on_countdown_update)
	NetworkManager.game_start_cancelled.connect(_on_countdown_cancel)

	for id in NetworkManager.players:
		_on_player_connected(id, NetworkManager.players[id].name)

func _build_ui() -> void:
	var main = HBoxContainer.new()
	main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main.size_flags_horizontal = SIZE_EXPAND_FILL
	main.size_flags_vertical   = SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 20)
	add_child(main)

	var left = VBoxContainer.new()
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	left.size_flags_vertical   = SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.35
	left.add_theme_constant_override("separation", 12)
	main.add_child(left)

	left.add_child(_label("Game Lobby", 32))

	# IP display (host only)
	if is_host:
		var row = _hbox()
		ip_label = _label("Your IP: " + Upnp.external_ip, 20)
		row.add_child(ip_label)
		copy_ip_btn = _btn("Copy IP", 16, 120, 40)
		copy_ip_btn.pressed.connect(_on_copy_ip)
		row.add_child(copy_ip_btn)
		left.add_child(row)

	# Player list
	player_list = ItemList.new()
	player_list.size_flags_horizontal = SIZE_EXPAND_FILL
	player_list.size_flags_vertical   = SIZE_EXPAND_FILL
	left.add_child(player_list)

	# Start & Leave buttons
	var btn_row = _hbox()
	btn_row.add_theme_constant_override("separation", 15)
	start_game_btn = _btn("Start Game", 22)
	start_game_btn.disabled = not is_host
	start_game_btn.pressed.connect(_on_start_game)
	btn_row.add_child(start_game_btn)

	leave_btn = _btn("Leave", 22)
	leave_btn.pressed.connect(_on_leave)
	btn_row.add_child(leave_btn)
	left.add_child(btn_row)

	# Status
	status_label = _label("Waiting for host...", 14, Color.YELLOW)
	left.add_child(status_label)

	# Chat panel
	chat_ui = ChatUI.new()
	chat_ui.size_flags_horizontal = SIZE_EXPAND_FILL
	chat_ui.size_flags_vertical   = SIZE_EXPAND_FILL
	chat_ui.size_flags_stretch_ratio = 0.65
	chat_ui.message_sent.connect(_on_chat_message_sent)
	main.add_child(chat_ui)

# ---------- Player list ----------
func _refresh_player_list() -> void:
	player_list.clear()
	player_ids.clear()
	for id in NetworkManager.players:
		var p = NetworkManager.players[id]
		var ping = NetworkManager.get_player_ping(id)
		var entry = "%s - %dms" % [p.name, ping]
		if id == 1:
			entry += " (Host)"
		player_list.add_item(entry)
		player_ids.append(id)

# ---------- Chat ----------
func _on_chat_message_sent(msg: String):
	chat_ui.add_message(local_player_name, msg)
	rpc("_receive_chat", local_player_name, msg)

@rpc("any_peer", "reliable")
func _receive_chat(sender: String, msg: String):
	chat_ui.add_message(sender, msg)

func _add_chat_message(sender: String, msg: String):
	chat_ui.add_message(sender, msg)

# ---------- Other callbacks ----------
func _on_player_connected(id: int, pname: String) -> void:
	_refresh_player_list()
	_add_chat_message("System", pname + " joined.")

func _on_player_disconnected(id: int, pname: String) -> void:
	_refresh_player_list()
	_add_chat_message("System", pname + " left.")

func _on_server_stopped() -> void:
	status_label.text = "Host ended session."
	start_game_btn.disabled = true

func _update_ip_display() -> void:
	if ip_label: ip_label.text = "Your IP: " + Upnp.external_ip

func _on_copy_ip() -> void:
	DisplayServer.clipboard_set(Upnp.external_ip)
	status_label.text = "IP copied!"

func _on_start_game() -> void:
	print("[Lobby] Start Game pressed. is_host:", is_host)
	if not is_host: return
	status_label.text = "Starting countdown..."
	NetworkManager.start_game_countdown()

func _on_countdown_update(seconds: int) -> void:
	print("[Lobby] Countdown tick: ", seconds)
	if seconds == 0:
		status_label.text = "Starting now!"
		start_game_btn.disabled = true
		get_tree().change_scene_to_file(NetworkManager.game_scene_path)
	else:
		status_label.text = "Game starting in %d..." % seconds
		start_game_btn.disabled = true

func _on_countdown_cancel() -> void:
	print("[Lobby] Countdown cancelled")
	status_label.text = "Countdown cancelled."
	start_game_btn.disabled = false

func _on_leave() -> void:
	NetworkManager._stop()
	get_tree().change_scene_to_file("res://UIScenes/MainMenu.tscn")
