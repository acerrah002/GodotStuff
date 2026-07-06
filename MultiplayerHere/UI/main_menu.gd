extends Control

@export var lobby_scene: String = "res://Scenes/UIScenes/lobby.tscn"
@export var default_port: int = 8080

# UI elements
var name_input: LineEdit
var upnp_host_btn: Button
var upnp_join_btn: Button
var upnp_status: Label
var lan_host_btn: Button
var lan_join_btn: Button
var lan_status: Label
var bt_host_btn: Button
var bt_join_btn: Button
var bt_status: Label

func _ready() -> void:
	_build_ui()
	_connect_signals()

func _build_ui() -> void:
	var tab_container = TabContainer.new()
	tab_container.name = "TabContainer"
	tab_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(tab_container)

	# ---- Settings tab (only player name) ----
	var settings_vbox = _create_tab("Settings")
	settings_vbox.add_theme_constant_override("separation", 10)
	var name_label = Label.new()
	name_label.text = "Your Name:"
	name_label.add_theme_font_size_override("font_size", 20)
	settings_vbox.add_child(name_label)
	name_input = LineEdit.new()
	name_input.placeholder_text = "Enter your name"
	name_input.custom_minimum_size = Vector2(250, 40)
	name_input.add_theme_font_size_override("font_size", 18)
	settings_vbox.add_child(name_input)
	tab_container.add_child(settings_vbox)

	# ----- UPNP Tab -----
	var upnp_tab = _create_tab("UPNP")
	var upnp_vbox = upnp_tab
	upnp_host_btn = _add_button(upnp_vbox, "Host Game (UPNP)")
	var upnp_join_hbox = HBoxContainer.new()
	upnp_join_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	upnp_join_hbox.add_theme_constant_override("separation", 10)
	upnp_vbox.add_child(upnp_join_hbox)
	var upnp_ip = LineEdit.new()
	upnp_ip.placeholder_text = "Enter host IP"
	upnp_ip.custom_minimum_size = Vector2(200, 40)
	upnp_ip.add_theme_font_size_override("font_size", 18)
	upnp_join_hbox.add_child(upnp_ip)
	upnp_join_btn = Button.new()
	upnp_join_btn.text = "Join Game (UPNP)"
	upnp_join_btn.custom_minimum_size = Vector2(200, 40)
	upnp_join_btn.add_theme_font_size_override("font_size", 18)
	upnp_join_hbox.add_child(upnp_join_btn)
	upnp_status = _add_status_label(upnp_vbox)
	tab_container.add_child(upnp_tab)

	# ----- Wi‑Fi (LAN) Tab -----
	var lan_tab = _create_tab("Wi‑Fi (LAN)")
	var lan_vbox = lan_tab
	lan_host_btn = _add_button(lan_vbox, "Host Game (LAN)")
	lan_join_btn = _add_button(lan_vbox, "Join Game (LAN)")
	lan_status   = _add_status_label(lan_vbox)
	tab_container.add_child(lan_tab)

	# ----- Bluetooth Tab -----
	var bt_tab = _create_tab("Bluetooth")
	var bt_vbox = bt_tab
	bt_host_btn = _add_button(bt_vbox, "Host Game (Bluetooth)")
	bt_join_btn = _add_button(bt_vbox, "Join Game (Bluetooth)")
	bt_status   = _add_status_label(bt_vbox)
	tab_container.add_child(bt_tab)

func _create_tab(title: String) -> VBoxContainer:
	var vbox = VBoxContainer.new()
	vbox.name = title
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 20)
	var title_label = Label.new()
	title_label.text = title + " Connection"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title_label)
	return vbox

func _add_button(parent: VBoxContainer, text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(250, 60)
	btn.add_theme_font_size_override("font_size", 20)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(btn)
	return btn

func _add_status_label(parent: VBoxContainer) -> Label:
	var lbl = Label.new()
	lbl.text = "Status: Idle"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color.GRAY)
	parent.add_child(lbl)
	return lbl

func _connect_signals() -> void:
	upnp_host_btn.pressed.connect(_on_upnp_host)
	upnp_join_btn.pressed.connect(_on_upnp_join)
	lan_host_btn.pressed.connect(_on_lan_host)
	lan_join_btn.pressed.connect(_on_lan_join)
	bt_host_btn.pressed.connect(_on_bt_host)
	bt_join_btn.pressed.connect(_on_bt_join)
	NetworkManager.connection_success.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connection_fail)
	LanManager.lan_host_ready.connect(_on_lan_host_ready)
	LanManager.lan_join_ready.connect(_on_lan_join_ready)
	BtManager.bt_host_ready.connect(_on_bt_host_ready)
	BtManager.bt_join_ready.connect(_on_bt_join_ready)

# ---------- Helper ----------
func _get_player_name() -> String:
	var n = name_input.text.strip_edges()
	return n if not n.is_empty() else "Player"

# ---------- UPNP ----------
func _on_upnp_host() -> void:
	upnp_status.text = "Status: Discovering UPNP..."
	NetworkManager.local_player_name = _get_player_name()
	Upnp.discovery_completed.connect(_on_upnp_discovered, CONNECT_ONE_SHOT)
	Upnp.discover()

func _on_upnp_discovered(success: bool) -> void:
	if not success:
		upnp_status.text = "Status: UPNP discovery failed."
		return
	upnp_status.text = "Status: Opening port %d..." % default_port
	var ok = Upnp.open_port(default_port, "CTF Game")
	if ok:
		NetworkManager.host_game(default_port, NetworkManager.local_player_name)
	else:
		upnp_status.text = "Status: Could not open port."

func _on_upnp_join() -> void:
	var ip = _get_upnp_ip_input()
	if ip.is_empty():
		upnp_status.text = "Status: Enter an IP address."
		return
	NetworkManager.local_player_name = _get_player_name()
	upnp_status.text = "Status: Connecting to %s:%d..." % [ip, default_port]
	NetworkManager.join_game(ip, default_port, NetworkManager.local_player_name)

# ---------- LAN ----------
func _on_lan_host() -> void:
	lan_status.text = "Status: Starting LAN host..."
	NetworkManager.local_player_name = _get_player_name()
	LanManager.host_lan(default_port)

func _on_lan_host_ready(ip: String, port: int) -> void:
	lan_status.text = "Status: Host ready at %s:%d" % [ip, port]
	NetworkManager.host_game(port, NetworkManager.local_player_name)

func _on_lan_join() -> void:
	lan_status.text = "Status: Searching for LAN games..."
	NetworkManager.local_player_name = _get_player_name()
	LanManager.join_lan(default_port)

func _on_lan_join_ready(ip: String, port: int) -> void:
	lan_status.text = "Status: Joining %s:%d..." % [ip, port]
	NetworkManager.join_game(ip, port, NetworkManager.local_player_name)

# ---------- Bluetooth ----------
func _on_bt_host() -> void:
	bt_status.text = "Status: Starting Bluetooth host..."
	NetworkManager.local_player_name = _get_player_name()
	BtManager.host_bt(default_port)

func _on_bt_host_ready(port: int) -> void:
	bt_status.text = "Status: Bluetooth host on port %d" % port
	NetworkManager.host_game(port, NetworkManager.local_player_name)

func _on_bt_join() -> void:
	bt_status.text = "Status: Searching for Bluetooth devices..."
	NetworkManager.local_player_name = _get_player_name()
	BtManager.join_bt("", default_port)

func _on_bt_join_ready(address: String, port: int) -> void:
	bt_status.text = "Status: Connecting to %s:%d..." % [address, port]
	NetworkManager.join_game(address, port, NetworkManager.local_player_name)

# ---------- Shared ----------
func _on_connected() -> void:
	if lobby_scene.is_empty(): return
	call_deferred("_change_to_lobby")

func _change_to_lobby() -> void:
	get_tree().change_scene_to_file(lobby_scene)

func _on_connection_fail(reason: String) -> void:
	upnp_status.text = "Status: " + reason
	lan_status.text = "Status: " + reason
	bt_status.text = "Status: " + reason

func _get_upnp_ip_input() -> String:
	for child in get_children():
		if child is TabContainer:
			var upnp_tab = child.get_child(1)   # second tab is UPNP after Settings
			if upnp_tab:
				for c in upnp_tab.get_children():
					if c is HBoxContainer:
						for cc in c.get_children():
							if cc is LineEdit:
								return cc.text.strip_edges()
	return ""
