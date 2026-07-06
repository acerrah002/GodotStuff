extends CanvasLayer

# ---------- Exported layout tweaks ----------
@export var prop_bar_offset := Vector2(30, 100)    # pixels from bottom‑left
@export var player_bar_offset := Vector2(30, 160)  # pixels from bottom‑left
@export var bar_width := 250.0
@export var bar_height := 25.0

# ---------- Existing UI ----------
var held_label: Label
var hover_label: Label
var flag_label: Label
var flag_bg: ColorRect

# ---------- Prop health bar ----------
var prop_health_bg: ColorRect
var prop_health_fill: ColorRect
var prop_health_label: Label

# ---------- Player health bar ----------
var player_health_bg: ColorRect
var player_health_fill: ColorRect
var player_health_label: Label
var player_max_health := 100.0
var player_health := 100.0

var player: Node = null

func _ready() -> void:
	if get_parent() != null and get_parent().is_multiplayer_authority():
		show()
	else:
		hide()
	player = get_parent()
	print("[PlayerUI] Parent: ", player.name if player else "null")

	# Weld indicators
	held_label = _make_label("WeldIndicator")
	hover_label = _make_label("HoverIndicator")
	hover_label.text = "🔗"
	hover_label.add_theme_color_override("font_color", Color.GREEN)

	# Flag (bottom‑center)
	flag_bg = _make_rect("FlagBackground", Color(0, 0, 0, 0.6), Control.PRESET_CENTER_BOTTOM)
	var style = StyleBoxFlat.new()
	style.border_color = Color.RED
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	flag_bg.add_theme_stylebox_override("panel", style)

	flag_label = _make_label_anchored("FlagIndicator", "FLAG", Color.WHITE, Control.PRESET_CENTER_BOTTOM)

	# Prop health bar
	prop_health_bg   = _make_rect("PropHealthBG", Color(0, 0, 0, 0.7), Control.PRESET_BOTTOM_LEFT)
	prop_health_fill = _make_rect("PropHealthFill", Color.GREEN, Control.PRESET_BOTTOM_LEFT)
	prop_health_label = _make_label_anchored("PropHealthLabel", "", Color.WHITE, Control.PRESET_BOTTOM_LEFT)

	# Player health bar
	player_health_bg   = _make_rect("PlayerHealthBG", Color(0, 0, 0, 0.7), Control.PRESET_BOTTOM_LEFT)
	player_health_fill = _make_rect("PlayerHealthFill", Color.CYAN, Control.PRESET_BOTTOM_LEFT)
	player_health_label = _make_label_anchored("PlayerHealthLabel", "100%", Color.WHITE, Control.PRESET_BOTTOM_LEFT)

	_update_ui_scale()
	get_viewport().size_changed.connect(_update_ui_scale)

# ---------- Helpers ----------
func _make_label(p_name: String) -> Label:
	var lbl = Label.new()
	lbl.name = p_name
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.visible = false
	add_child(lbl)
	return lbl

func _make_label_anchored(p_name: String, p_text: String, p_color: Color, anchor: int) -> Label:
	var lbl = Label.new()
	lbl.name = p_name
	lbl.text = p_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(anchor)
	lbl.add_theme_color_override("font_color", p_color)
	lbl.visible = false
	add_child(lbl)
	return lbl

func _make_rect(p_name: String, p_color: Color, anchor: int) -> ColorRect:
	var rect = ColorRect.new()
	rect.name = p_name
	rect.color = p_color
	rect.set_anchors_preset(anchor)
	rect.visible = false
	add_child(rect)
	return rect

# ---------- Frame update ----------
func _process(_delta: float) -> void:
	if not player or not player.has_method("capture_flag"):
		_hide_all()
		return

	# Flag
	var flag = player.carried_flag
	flag_bg.visible = flag != null
	flag_label.visible = flag != null

	# Prop health
	_update_prop_health()
	
	# Player health
	_update_player_health()

func _update_prop_health() -> void:
	# Look inside interaction controller if it exists
	var obj = player.get_grabbed_object() if player.has_method("get_grabbed_object") else null
	if player.has_method("get") and player.get("interaction") != null:
		obj = player.interaction.grabbed_object
	elif player.get("grabbed_object") != null:
		obj = player.grabbed_object   # fallback for non‑refactored players
	
	if obj and obj.has_method("take_damage"):
		var pct = clamp(obj.health / obj.max_health, 0.0, 1.0)
		prop_health_fill.size.x = prop_health_bg.size.x * pct
		prop_health_label.text = "Prop: %d%%" % int(pct * 100)
		
		prop_health_fill.color = Color.GREEN if pct > 0.6 else (Color.YELLOW if pct > 0.3 else Color.RED)
		
		prop_health_bg.visible = true
		prop_health_fill.visible = true
		prop_health_label.visible = true
	else:
		prop_health_bg.visible = false
		prop_health_fill.visible = false
		prop_health_label.visible = false

func _update_player_health() -> void:
	var pct = clamp(player_health / player_max_health, 0.0, 1.0)
	player_health_fill.size.x = player_health_bg.size.x * pct
	player_health_label.text = "Player: %d%%" % int(pct * 100)
	
	player_health_fill.color = Color.CYAN if pct > 0.6 else (Color.YELLOW if pct > 0.3 else Color.RED)
	
	player_health_bg.visible = true
	player_health_fill.visible = true
	player_health_label.visible = true

func _hide_all() -> void:
	flag_bg.visible = false
	flag_label.visible = false
	prop_health_bg.visible = false
	prop_health_fill.visible = false
	prop_health_label.visible = false
	player_health_bg.visible = false
	player_health_fill.visible = false
	player_health_label.visible = false

# ---------- Scaling ----------
func _update_ui_scale() -> void:
	var vp = get_viewport().get_visible_rect().size
	var base_h = 1080.0
	var scale = vp.y / base_h

	# Weld
	_apply_scale(held_label, 28, Vector2(0, 60), scale)
	_apply_scale(hover_label, 22, Vector2(0, -50), scale)

	# Flag (bottom‑center)
	var flag_font = int(36 * scale)
	flag_label.add_theme_font_size_override("font_size", flag_font)
	var bg_w = flag_font * 4.0
	var bg_h = flag_font * 1.5
	flag_bg.size = Vector2(bg_w, bg_h)
	flag_label.size = Vector2(bg_w, bg_h)
	var flag_x = (vp.x - bg_w) / 2.0
	var flag_y = vp.y - bg_h - 30 * scale
	flag_bg.position = Vector2(flag_x, flag_y)
	flag_label.position = Vector2(flag_x, flag_y)

	# Prop health bar (bottom‑left, offset by export)
	_position_bar(prop_health_bg, prop_health_fill, prop_health_label, prop_bar_offset, scale, "Prop:")

	# Player health bar (bottom‑left, above prop bar)
	_position_bar(player_health_bg, player_health_fill, player_health_label, player_bar_offset, scale, "Player:")

func _position_bar(bg: ColorRect, fill: ColorRect, label: Label, offset: Vector2, scale: float, text_prefix: String) -> void:
	var vp = get_viewport().get_visible_rect().size
	var w = bar_width * scale
	var h = bar_height * scale
	var x = offset.x * scale
	var y = vp.y - offset.y * scale

	bg.size = Vector2(w, h)
	bg.position = Vector2(x, y)
	fill.size = Vector2(w, h)
	fill.position = Vector2(x, y)
	label.add_theme_font_size_override("font_size", int(18 * scale))
	label.size = Vector2(w, h)
	label.position = Vector2(x, y)

func _apply_scale(lbl: Label, ref_font: int, ref_pos: Vector2, scale: float) -> void:
	lbl.add_theme_font_size_override("font_size", int(ref_font * scale))
	lbl.position = ref_pos * scale

# ---------- Public API for other scripts ----------
func set_player_health(current: float, maximum: float) -> void:
	player_health = current
	player_max_health = maximum
