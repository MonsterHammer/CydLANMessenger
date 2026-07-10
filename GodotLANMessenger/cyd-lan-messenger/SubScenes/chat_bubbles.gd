extends PanelContainer

const SENT_COLOR := Color("#376fd8")
const RECEIVED_COLOR := Color("#182330")
const SENT_TEXT := Color.WHITE
const RECEIVED_TEXT := Color("#eef3f8")
const MUTED_TEXT := Color("#a9b6c6")
const MIN_WIDTH := 86.0
const TEXT_PADDING := 22.0

@onready var message_label: Label = $BoxHeader/LabelChat2
@onready var time_label: Label = $BoxHeader/LabelTime

var _message_text := ""
var _message_time := ""
var _is_sent := false
var _max_width := 300.0

func _ready() -> void:
	_apply()

func configure(text: String, is_sent: bool, time: String, max_width: float) -> void:
	_message_text = text
	_message_time = time
	_is_sent = is_sent
	_max_width = maxf(MIN_WIDTH, max_width)
	if is_node_ready(): _apply()

func _apply() -> void:
	message_label.text = _message_text
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_color_override("font_color", SENT_TEXT if _is_sent else RECEIVED_TEXT)
	message_label.custom_minimum_size.x = _message_width(_message_text)
	time_label.text = _message_time
	time_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.68) if _is_sent else MUTED_TEXT)
	var style := StyleBoxFlat.new()
	style.bg_color = SENT_COLOR if _is_sent else RECEIVED_COLOR
	style.border_color = Color(1, 1, 1, 0.06)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	if _is_sent: style.corner_radius_top_right = 4
	else: style.corner_radius_top_left = 4
	style.corner_detail = 7
	style.content_margin_left = 13
	style.content_margin_top = 9
	style.content_margin_right = 13
	style.content_margin_bottom = 7
	add_theme_stylebox_override("panel", style)

func _message_width(text: String) -> float:
	var font := get_theme_default_font()
	var font_size := 12
	var longest_line := 0.0
	for line in text.split("\n"):
		longest_line = maxf(longest_line, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	return clampf(longest_line + TEXT_PADDING, MIN_WIDTH, _max_width)
