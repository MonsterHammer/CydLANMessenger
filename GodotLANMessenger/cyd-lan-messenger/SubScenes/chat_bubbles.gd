extends PanelContainer

const CLR_SENT := Color("#123f91")
const CLR_RECEIVED := Color("#101b2b")
const CLR_SENT_TEXT := Color("#f5f8ff")
const CLR_RECEIVED_TEXT := Color("#e7edf7")
const CLR_SENT_TIME := Color(0.72, 0.82, 1.0, 0.7)
const CLR_RECEIVED_TIME := Color(0.5, 0.59, 0.72, 0.76)
const MIN_WIDTH := 78.0
const TEXT_PADDING := 18.0

@onready var message_label: Label = $BoxHeader/LabelChat2
@onready var time_label: Label = $BoxHeader/LabelTime

var _message_text := ""
var _message_time := ""
var _is_sent := false
var _max_width := 260.0

func _ready() -> void:
	_apply()

func configure(text: String, is_sent: bool, time: String, max_width: float) -> void:
	_message_text = text
	_message_time = time
	_is_sent = is_sent
	_max_width = max(MIN_WIDTH, max_width)
	if is_node_ready():
		_apply()

func _apply() -> void:
	message_label.text = _message_text
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_color_override("font_color", CLR_SENT_TEXT if _is_sent else CLR_RECEIVED_TEXT)
	message_label.custom_minimum_size.x = _message_width(_message_text)

	time_label.text = _message_time
	time_label.add_theme_color_override("font_color", CLR_SENT_TIME if _is_sent else CLR_RECEIVED_TIME)

	var style := StyleBoxFlat.new()
	style.bg_color = CLR_SENT if _is_sent else CLR_RECEIVED
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color("#245fc0") if _is_sent else Color("#223149")
	style.set_corner_radius_all(5)
	if _is_sent:
		style.corner_radius_bottom_right = 2
	else:
		style.corner_radius_bottom_left = 2
	style.corner_detail = 4
	style.content_margin_left = 12
	style.content_margin_top = 8
	style.content_margin_right = 12
	style.content_margin_bottom = 7
	style.shadow_size = 0
	add_theme_stylebox_override("panel", style)

func _message_width(text: String) -> float:
	var font = get_theme_default_font()
	var font_size = 12
	var longest_line := 0.0
	for line in text.split("\n"):
		longest_line = max(longest_line, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	return clamp(longest_line + TEXT_PADDING, MIN_WIDTH, _max_width)
