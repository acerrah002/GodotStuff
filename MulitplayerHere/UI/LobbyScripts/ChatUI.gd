class_name ChatUI
extends VBoxContainer

signal message_sent(message: String)

var chat_log: RichTextLabel
var input_field: LineEdit
var send_btn: Button

func _ready():
	# Chat title
	var title = Label.new()
	title.text = "Chat"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	add_child(title)

	# Chat log
	chat_log = RichTextLabel.new()
	chat_log.bbcode_enabled = true
	chat_log.scroll_following = true
	chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_log.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	add_child(chat_log)

	# Input row
	var input_row = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 5)

	input_field = LineEdit.new()
	input_field.placeholder_text = "Type a message..."
	input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row.add_child(input_field)

	send_btn = Button.new()
	send_btn.text = "Send"
	send_btn.add_theme_font_size_override("font_size", 16)
	send_btn.custom_minimum_size = Vector2(80, 40)
	send_btn.pressed.connect(_on_send)
	input_row.add_child(send_btn)

	input_field.text_submitted.connect(_on_send)

	add_child(input_row)

	# Make sure the chat log expands
	add_theme_constant_override("separation", 10)

func add_message(sender: String, msg: String):
	chat_log.append_text("[b][color=#5bc0de]%s:[/color][/b] %s\n" % [sender, msg])

func _on_send(text: String = ""):
	var msg = input_field.text.strip_edges()
	if msg.is_empty(): return
	message_sent.emit(msg)
	input_field.clear()
