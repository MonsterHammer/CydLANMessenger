extends "res://scripts/ui/main_ui.gd"

@onready var empty_state: Control = %EmptyState
@onready var users_label: Label = %UsersLabel
@onready var connection_detail: Label = %ConnectionDetail

func _ready() -> void:
	super()
	no_chat_label.visible = false
	empty_state.visible = true
	_update_user_count()
	_update_connection_detail()

func _setup_window() -> void:
	var win := get_window()
	win.min_size = Vector2i(820, 520)
	win.size = Vector2i(1040, 680)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	var screen_size := DisplayServer.screen_get_size()
	DisplayServer.window_set_position(Vector2i(
		maxi(0, screen_size.x / 2 - win.size.x / 2),
		maxi(0, screen_size.y / 2 - win.size.y / 2)
	))
	var app_icon = load("res://icon.svg")
	if app_icon:
		var image = app_icon.get_image()
		if image:
			DisplayServer.set_icon(image)

func _update_connection_detail() -> void:
	var shown_ip := "Local network"
	for address in IP.get_local_addresses():
		if address.contains(":"):
			continue
		if address.begins_with("127.") or address == "0.0.0.0":
			continue
		shown_ip = address
		if address.begins_with("192.168.") or address.begins_with("10.") or address.begins_with("172."):
			break
	connection_detail.text = shown_ip + "  •  Legacy protocol ready"

func _on_user_added(user: Dictionary) -> void:
	super(user)
	_update_user_count()

func _on_user_removed(user_id: String) -> void:
	super(user_id)
	_update_user_count()
	if _selected_user_id.is_empty():
		no_chat_label.visible = false
		empty_state.visible = true

func _create_user_item(uid: String, display_name: String) -> Button:
	var button := super(uid, display_name)
	button.custom_minimum_size.y = 58
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.045, 0.065, 0.102, 0.0)
	normal.set_corner_radius_all(9)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.07, 0.105, 0.165, 1.0)
	hover.set_corner_radius_all(9)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.085, 0.16, 0.31, 1.0)
	pressed.set_corner_radius_all(9)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	var row := button.get_child(0) as HBoxContainer
	if row and row.get_child_count() > 1:
		var labels := row.get_child(1) as VBoxContainer
		if labels and labels.get_child_count() > 1:
			(labels.get_child(0) as Label).add_theme_color_override("font_color", Color("#edf4ff"))
			(labels.get_child(1) as Label).add_theme_color_override("font_color", Color("#55d985"))
	return button

func _select_user(uid: String) -> void:
	super(uid)
	if not _selected_user_id.is_empty():
		empty_state.visible = false
		no_chat_label.visible = false

func _update_user_count() -> void:
	var count := _user_item_map.size()
	users_label.text = "LAN USERS  •  %d FOUND" % count
