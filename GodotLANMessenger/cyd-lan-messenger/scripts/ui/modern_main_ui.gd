extends "res://scripts/ui/main_ui.gd"

@onready var empty_state: Control = %EmptyState
@onready var users_label: Label = %UsersLabel
@onready var connection_detail: Label = %ConnectionDetail

func _ready() -> void:
	super()
	no_chat_label.visible = false
	empty_state.visible = true
	_apply_reference_flattening()
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

func _apply_reference_flattening() -> void:
	# Match the approved reference: restrained radii, flat surfaces, thin separators.
	_set_panel_style($Background, Color("#07101d"), Color("#1b2a3f"), 6, 1)
	_set_panel_style(%TitleBar, Color("#0a1422"), Color("#1b2a3f"), 4, 1)
	_set_panel_style(%LeftSidebar, Color("#0a1422"), Color("#1b2a3f"), 0, 1)
	_set_panel_style(%ChatView, Color("#07111f"), Color.TRANSPARENT, 0, 0)
	_set_panel_style(%FilesHistory, Color("#0a1422"), Color("#1b2a3f"), 0, 1)
	_set_panel_style(%ChatHeader, Color("#0a1422"), Color("#1b2a3f"), 0, 1)
	_set_panel_style(%InputPanel, Color("#0d1928"), Color("#22344d"), 5, 1)

	for node in get_tree().get_nodes_in_group("cydlan_flat_card"):
		if node is PanelContainer:
			_set_panel_style(node, Color("#0c1726"), Color("#1d2d44"), 5, 1)

	for path in [
		"Background/VBoxContainer/BodyHBox/LeftSidebar/SidebarVBox/SidebarFooter",
		"Background/VBoxContainer/BodyHBox/FilesHistory/RightVBox/SharedCard",
		"Background/VBoxContainer/BodyHBox/FilesHistory/RightVBox/HistoryCard",
		"Background/VBoxContainer/BodyHBox/FilesHistory/RightVBox/SecurityCard"
	]:
		var card := get_node_or_null(path)
		if card is PanelContainer:
			_set_panel_style(card, Color("#0c1726"), Color("#1d2d44"), 5, 1)

	var brand := get_node_or_null("Background/VBoxContainer/TitleBar/TitleHBox/BrandBadge")
	if brand is PanelContainer:
		_set_panel_style(brand, Color("#185ee8"), Color("#2b72f2"), 5, 1)

	var empty_badge := get_node_or_null("Background/VBoxContainer/BodyHBox/ChatView/VBoxContainer/EmptyState/EmptyVBox/BadgeCenter/EmptyBadge")
	if empty_badge is PanelContainer:
		_set_panel_style(empty_badge, Color("#0c1a2d"), Color("#264064"), 8, 1)

	_flatten_button(%SearchRefreshBtn, 4)
	_flatten_button(%MinimizeBtn, 3)
	_flatten_button(%MaximizeBtn, 3)
	_flatten_button(%CloseBtn, 3)
	_flatten_button(%SendButton, 5, Color("#185ee8"))

func _set_panel_style(control: Control, background: Color, border: Color, radius: int, border_width: int) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.set_corner_radius_all(radius)
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_color = border
	style.shadow_size = 0
	control.add_theme_stylebox_override("panel", style)

func _flatten_button(button: Button, radius: int, background: Color = Color.TRANSPARENT) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = background
	normal.set_corner_radius_all(radius)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color("#12233a") if background == Color.TRANSPARENT else background.lightened(0.08)
	hover.set_corner_radius_all(radius)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color("#182c47") if background == Color.TRANSPARENT else background.darkened(0.08)
	pressed.set_corner_radius_all(radius)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)

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
	normal.bg_color = Color.TRANSPARENT
	normal.set_corner_radius_all(4)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color("#101f33")
	hover.set_corner_radius_all(4)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color("#142a48")
	pressed.set_corner_radius_all(4)
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
