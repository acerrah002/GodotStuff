extends CanvasLayer

enum Team { RED, BLUE }

@export var game_duration := 300.0

var blue_score := 0
var red_score := 0
var time_left := 0.0

var blue_label: Label
var red_label: Label
var timer_label: Label

func _ready() -> void:
	_create_labels()
	time_left = game_duration
	_update_display()
	add_to_group("scoreboard")
	_update_ui_scale()
	get_viewport().size_changed.connect(_update_ui_scale)

func _create_labels() -> void:
	blue_label = _make_label("BlueScore", "BLUE: 0", Color.BLUE)
	red_label = _make_label("RedScore", "RED: 0", Color.RED)
	timer_label = _make_label("TimerLabel", "05:00", Color.WHITE)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Blue: top-left
	blue_label.anchor_left = 0.0
	blue_label.anchor_top = 0.0
	blue_label.anchor_right = 0.0
	blue_label.anchor_bottom = 0.0

	# Red: top-right
	red_label.anchor_left = 1.0
	red_label.anchor_top = 0.0
	red_label.anchor_right = 1.0
	red_label.anchor_bottom = 0.0

	# Timer: center-top
	timer_label.anchor_left = 0.5
	timer_label.anchor_top = 0.0
	timer_label.anchor_right = 0.5
	timer_label.anchor_bottom = 0.0

func _make_label(p_name: String, p_text: String, p_color: Color) -> Label:
	var lbl = Label.new()
	lbl.name = p_name
	lbl.text = p_text
	lbl.add_theme_color_override("font_color", p_color)
	add_child(lbl)
	return lbl

func _update_ui_scale() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var base_height = 1080.0
	var ui_scale = viewport_size.y / base_height

	var font_size_small = int(36 * ui_scale)
	var font_size_big = int(40 * ui_scale)
	var margin = int(20 * ui_scale)

	blue_label.add_theme_font_size_override("font_size", font_size_small)
	red_label.add_theme_font_size_override("font_size", font_size_small)
	timer_label.add_theme_font_size_override("font_size", font_size_big)

	# Offsets from the anchors
	blue_label.offset_left = margin
	blue_label.offset_top = margin
	blue_label.offset_right = margin + 200 * ui_scale
	blue_label.offset_bottom = margin + font_size_small * 2

	red_label.offset_left = -margin - 200 * ui_scale
	red_label.offset_top = margin
	red_label.offset_right = -margin
	red_label.offset_bottom = margin + font_size_small * 2

	timer_label.offset_left = -150 * ui_scale
	timer_label.offset_top = margin
	timer_label.offset_right = 150 * ui_scale
	timer_label.offset_bottom = margin + font_size_big * 2

func _process(delta: float) -> void:
	if game_duration > 0 and time_left > 0:
		time_left -= delta
		if time_left < 0: time_left = 0
		_update_display()

func add_score(team: Team, amount: int = 1) -> void:
	match team:
		Team.RED:   red_score += amount
		Team.BLUE:  blue_score += amount
	_update_display()

func _update_display() -> void:
	blue_label.text = "BLUE: %d" % blue_score
	red_label.text = "RED: %d" % red_score
	timer_label.text = _format_time(time_left)

func _format_time(seconds: float) -> String:
	var mins = int(seconds / 60)
	var secs = int(seconds) % 60
	return "%02d:%02d" % [mins, secs]

# ---------- Health bars (optional) ----------
# If you kept the health bar logic inside this script, make sure to
# rename any local "scale" / "offset" variables there as well.
