extends Control

const _D = preload("res://scripts/network/definitions.gd")
const _LanMessenger = preload("res://scripts/network/lan_messenger.gd")
const ChatBubbleScene = preload("res://SubScenes/ChatBubbles.tscn")

const APP_TITLE := "CydLAN Messenger"
const APP_VERSION := "2.0 · Godot 4.7"
const HIST_FILE := "user://chat_history.json"
const CHAT_BUBBLE_MAX_WIDTH_RATIO := 0.72
const SENT_ECHO_IGNORE_SECONDS := 3.0
const AVATAR_SIZE := 32

const TRAY_SHOW := 1
const TRAY_BROADCAST := 2
const TRAY_HISTORY := 3
const TRAY_SETTINGS := 4
const TRAY_QUIT := 5
const CTX_MESSAGE := 10
const CTX_FILE := 11
const CTX_INFO := 12

const C_BG := Color("#0b1118")
const C_SURFACE := Color("#111923")
const C_SURFACE_2 := Color("#17212d")
const C_BORDER := Color("#243244")
const C_TEXT := Color("#eef3f8")
const C_MUTED := Color("#91a0b3")
const C_PRIMARY := Color("#5b8cff")
const C_PRIMARY_HOVER := Color("#76a0ff")
const C_GREEN := Color("#38c977")
const C_WARNING := Color("#f6ad55")
const C_DANGER := Color("#ff6b72")
const STATUS_COLORS := {
	"chat": C_GREEN,
	"busy": C_WARNING,
	"dnd": C_DANGER,
	"brb": C_WARNING,
	"away": C_WARNING,
	"gone": C_MUTED
}
const STATUS_NAMES := {
	"chat": "Online",
	"busy": "Busy",
	"dnd": "Do Not Disturb",
	"brb": "Be Right Back",
	"away": "Away",
	"gone": "Offline"
}
const STATUS_CODES := ["chat", "busy", "dnd", "brb", "away", "gone"]
const SMILEYS := {
	":)": "😊", ":D": "😄", ":(": "😢", ";)": "😉", ":p": "😋", ":P": "😋",
	":o": "😮", ":O": "😮", ":/": "😕", ":|": "😐", ":'(": "😢", ":')": "😂",
	"<3": "❤️", "</3": "💔", "^^": "😊", "B)": "😎", "8)": "😎"
}

@onready var title_bar: Panel = %TitleBar
@onready var minimize_btn: Button = %MinimizeBtn
@onready var maximize_btn: Button = %MaximizeBtn
@onready var close_btn: Button = %CloseBtn
@onready var user_vbox: VBoxContainer = %UserVBox
@onready var search_input: LineEdit = %SearchInput
@onready var input_panel: PanelContainer = %InputPanel
@onready var message_vbox: VBoxContainer = %MessageVBox
@onready var message_scroll: ScrollContainer = %MessageScroll
@onready var message_input: TextEdit = %MessageInput
@onready var send_btn: Button = %SendButton
@onready var chat_header: PanelContainer = %ChatHeader
@onready var chat_user_name: Label = %ChatUserName
@onready var chat_status_label: Label = %ChatStatus
@onready var chat_avatar: ColorRect = %ChatAvatar
@onready var no_chat_label: Label = %NoChatLabel
@onready var left_sidebar: Panel = %LeftSidebar
@onready var chat_view: PanelContainer = %ChatView
@onready var files_history: Panel = %FilesHistory

var _lan_node: Node = null
var _messaging: Node = null
var _net_started := false
var _status_indicator: StatusIndicator = null
var _tray_menu: PopupMenu = null
var _allow_quit := false
var _hidden_to_tray := false
var _has_focus := true
var _unread_count := 0
var _selected_user_id := ""
var _search_text := ""
var _message_history: Dictionary = {}
var _history_dirty := false
var _user_item_map: Dictionary = {}
var _user_data_map: Dictionary = {}
var _user_avatar_colors: Dictionary = {}
var _user_avatar_rect_map: Dictionary = {}
var _user_dot_map: Dictionary = {}
var _user_status_map: Dictionary = {}
var _sent_recently: Dictionary = {}
var _context_user_id := ""
var _local_status := "chat"
var _incoming_typing_timer := 0.0
var _outgoing_typing_timer := 0.0
var _typing_state := "active"
var _maximized := false
var _pre_maximize_rect := Rect2i()
var _dragging := false
var _drag_offset := Vector2()
var _status_button: Button = null
var _network_label: Label = null
var _contact_count_label: Label = null
var _info_dialog: AcceptDialog = null
var _info_requested_user := ""

func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	get_window().min_size = Vector2i(760, 480)
	_setup_window()
	_apply_polished_theme()
	_setup_actions()
	_setup_signals()
	_setup_tray()
	_load_history()
	_set_empty_state(true)
	DisplayServer.window_set_title(APP_TITLE)
	call_deferred("_on_refresh_button_pressed")

func _setup_window() -> void:
	var window := get_window()
	window.size = Vector2i(960, 640)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	var screen_size := DisplayServer.screen_get_size()
	DisplayServer.window_set_position(Vector2i((screen_size.x - window.size.x) / 2, (screen_size.y - window.size.y) / 2))
	var texture: Texture2D = load("res://icon.svg") as Texture2D
	if texture:
		var image: Image = texture.get_image()
		if image:
			DisplayServer.set_icon(image)

func _apply_polished_theme() -> void:
	var app_font: Font = load("res://Assets/Fonts/Inter/static/Inter_18pt-Regular.ttf") as Font
	if app_font:
		var app_theme := Theme.new()
		app_theme.default_font = app_font
		theme = app_theme
	files_history.visible = false
	var background := get_node("Background") as PanelContainer
	background.add_theme_stylebox_override("panel", _style(C_BG, 10, C_BORDER, 1))
	title_bar.add_theme_stylebox_override("panel", _style(C_SURFACE, 10, C_BORDER, 1, true, false))
	left_sidebar.add_theme_stylebox_override("panel", _style(C_SURFACE, 0, C_BORDER, 1))
	chat_view.add_theme_stylebox_override("panel", _style(C_BG, 0, C_BORDER, 0))
	chat_header.add_theme_stylebox_override("panel", _style(C_SURFACE, 0, C_BORDER, 1))
	input_panel.add_theme_stylebox_override("panel", _style(C_SURFACE, 0, C_BORDER, 1))
	message_scroll.add_theme_stylebox_override("panel", _style(C_BG, 0))
	search_input.add_theme_stylebox_override("normal", _style(C_SURFACE_2, 8, C_BORDER, 1))
	search_input.add_theme_stylebox_override("focus", _style(C_SURFACE_2, 8, C_PRIMARY, 1))
	search_input.add_theme_color_override("font_color", C_TEXT)
	search_input.add_theme_color_override("font_placeholder_color", C_MUTED)
	search_input.placeholder_text = "Search people"
	message_input.add_theme_color_override("font_color", C_TEXT)
	message_input.add_theme_color_override("font_placeholder_color", C_MUTED)
	message_input.placeholder_text = "Write a message — Enter to send, Shift+Enter for a new line"
	chat_user_name.add_theme_color_override("font_color", C_TEXT)
	no_chat_label.add_theme_color_override("font_color", C_MUTED)
	no_chat_label.text = "Choose a person to start messaging"
	_style_window_button(minimize_btn)
	_style_window_button(maximize_btn)
	_style_window_button(close_btn, true)
	_style_primary_button(send_btn)

func _setup_actions() -> void:
	_setup_sidebar_actions()
	_setup_chat_actions()
	_setup_status_bar()

func _setup_sidebar_actions() -> void:
	var sidebar_vbox := left_sidebar.get_node("SidebarVBox") as VBoxContainer
	var toolbar := HBoxContainer.new()
	toolbar.name = "SidebarActions"
	toolbar.custom_minimum_size.y = 40
	toolbar.add_theme_constant_override("separation", 6)
	var broadcast_button := _action_button("Broadcast", "Send one announcement to everyone")
	var history_button := _action_button("History", "Open saved conversations")
	var settings_button := _action_button("Settings", "Profile and network preferences")
	broadcast_button.pressed.connect(_show_broadcast_dialog)
	history_button.pressed.connect(_show_history_dialog)
	settings_button.pressed.connect(_show_settings_dialog)
	toolbar.add_child(broadcast_button)
	toolbar.add_child(history_button)
	toolbar.add_child(settings_button)
	sidebar_vbox.add_child(toolbar)
	sidebar_vbox.move_child(toolbar, 1)

	_status_button = Button.new()
	_status_button.flat = true
	_status_button.text = "● Online"
	_status_button.tooltip_text = "Change presence"
	_status_button.add_theme_color_override("font_color", C_GREEN)
	_status_button.add_theme_font_size_override("font_size", 11)
	_status_button.pressed.connect(_show_status_menu)
	var search_row := sidebar_vbox.get_node("SearchHBox") as HBoxContainer
	search_row.add_child(_status_button)

func _setup_chat_actions() -> void:
	var header_row := chat_header.get_node("ChatHeaderHBox") as HBoxContainer
	var file_button := _icon_button("＋ File", "Send a file")
	var info_button := _icon_button("Info", "View user information")
	file_button.pressed.connect(func():
		if not _selected_user_id.is_empty(): _send_file_to(_selected_user_id)
	)
	info_button.pressed.connect(func():
		if not _selected_user_id.is_empty(): _show_info(_selected_user_id)
	)
	header_row.add_child(file_button)
	header_row.move_child(file_button, maxi(0, header_row.get_child_count() - 2))
	header_row.add_child(info_button)
	header_row.move_child(info_button, maxi(0, header_row.get_child_count() - 2))

func _setup_status_bar() -> void:
	var root_vbox := title_bar.get_parent() as VBoxContainer
	var status_bar := PanelContainer.new()
	status_bar.name = "StatusBar"
	status_bar.custom_minimum_size.y = 28
	status_bar.add_theme_stylebox_override("panel", _style(C_SURFACE, 0, C_BORDER, 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	status_bar.add_child(row)
	_network_label = Label.new()
	_network_label.text = "Starting LAN service…"
	_network_label.add_theme_color_override("font_color", C_WARNING)
	_network_label.add_theme_font_size_override("font_size", 10)
	_contact_count_label = Label.new()
	_contact_count_label.text = "0 people"
	_contact_count_label.add_theme_color_override("font_color", C_MUTED)
	_contact_count_label.add_theme_font_size_override("font_size", 10)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var version_label := Label.new()
	version_label.text = APP_VERSION
	version_label.add_theme_color_override("font_color", C_MUTED)
	version_label.add_theme_font_size_override("font_size", 10)
	row.add_child(_network_label)
	row.add_child(_contact_count_label)
	row.add_child(spacer)
	row.add_child(version_label)
	root_vbox.add_child(status_bar)

func _setup_signals() -> void:
	search_input.text_changed.connect(_on_search_changed)
	send_btn.pressed.connect(_on_send_pressed)
	message_input.gui_input.connect(_on_message_input_gui)
	message_input.text_changed.connect(_on_message_input_changed)
	minimize_btn.pressed.connect(_on_minimize_pressed)
	maximize_btn.pressed.connect(_on_maximize_pressed)
	close_btn.pressed.connect(_on_close_pressed)
	title_bar.gui_input.connect(_on_title_gui_input)

func _process(delta: float) -> void:
	if not _selected_user_id.is_empty() and _incoming_typing_timer > 0.0:
		_incoming_typing_timer -= delta
		if _incoming_typing_timer <= 0.0:
			_restore_selected_status()
	if _outgoing_typing_timer > 0.0:
		_outgoing_typing_timer -= delta
		if _outgoing_typing_timer <= 0.0 and _typing_state == "composing":
			_send_typing_state("paused")

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			if _history_dirty: _save_history()
			if _allow_quit: get_tree().quit()
			else: _hide_to_tray()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_has_focus = true
			_clear_unread()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_has_focus = false

func _net_start() -> void:
	_lan_node = _LanMessenger.new()
	add_child(_lan_node)
	await get_tree().process_frame
	_messaging = _lan_node.messaging
	if not _messaging:
		_network_label.text = "LAN service failed to start"
		_network_label.add_theme_color_override("font_color", C_DANGER)
		return
	_net_started = true
	_local_status = str(_messaging.local_user.get("status", "chat"))
	_connect_messaging_signals()
	_sync_existing_users()
	_network_label.text = "LAN service active on port 50000"
	_network_label.add_theme_color_override("font_color", C_GREEN)
	_update_status_button()

func _connect_messaging_signals() -> void:
	_messaging.user_added.connect(_on_user_added)
	_messaging.user_removed.connect(_on_user_removed)
	_messaging.message_received.connect(_on_message_received)
	_messaging.user_status_changed.connect(_on_user_status_changed)
	_messaging.user_typing.connect(_on_user_typing)
	_messaging.user_avatar_changed.connect(_on_user_avatar_changed)
	_messaging.user_info_received.connect(_on_user_info_received)
	_messaging.delivery_state_changed.connect(_on_delivery_state_changed)
	_messaging.file_transfer_requested.connect(_on_file_transfer_requested)
	_messaging.file_transfer_updated.connect(_on_file_transfer_updated)
	_messaging.connection_state_changed.connect(_on_connection_state_changed)

func _on_refresh_button_pressed() -> void:
	if not _net_started:
		await _net_start()
	elif _messaging:
		_messaging.refresh()
		_network_label.text = "Refreshing LAN contacts…"
		await get_tree().create_timer(0.8).timeout
		_network_label.text = "LAN service active on port 50000"

func _sync_existing_users() -> void:
	if not _messaging: return
	for user in _messaging.user_list:
		_on_user_added(user)

func _on_user_added(user: Dictionary) -> void:
	var user_id := str(user.get("id", ""))
	if user_id.is_empty(): return
	_user_data_map[user_id] = user.duplicate(true)
	_user_status_map[user_id] = str(user.get("status", "chat"))
	if _user_item_map.has(user_id):
		_refresh_user_item(user_id)
		return
	var item := _create_user_item(user_id, _display_name(user, user_id))
	user_vbox.add_child(item)
	_user_item_map[user_id] = item
	_update_contact_count()

func _on_user_removed(user_id: String) -> void:
	if _user_item_map.has(user_id):
		var item: Control = _user_item_map[user_id]
		item.queue_free()
	_user_item_map.erase(user_id)
	_user_data_map.erase(user_id)
	_user_dot_map.erase(user_id)
	_user_avatar_rect_map.erase(user_id)
	_user_status_map.erase(user_id)
	if _selected_user_id == user_id:
		_selected_user_id = ""
		_set_empty_state(true)
	_update_contact_count()

func _create_user_item(user_id: String, display_name: String) -> Button:
	var button := Button.new()
	button.flat = true
	button.custom_minimum_size.y = 54
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_stylebox_override("normal", _style(Color.TRANSPARENT, 8))
	button.add_theme_stylebox_override("hover", _style(C_SURFACE_2, 8))
	button.add_theme_stylebox_override("pressed", _style(C_PRIMARY.darkened(0.35), 8))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation", 10)
	button.add_child(row)
	var avatar_holder := Control.new()
	avatar_holder.custom_minimum_size = Vector2(42, 48)
	avatar_holder.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(avatar_holder)
	var avatar := ColorRect.new()
	avatar.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	avatar.position = Vector2(5, 8)
	avatar.mouse_filter = Control.MOUSE_FILTER_PASS
	avatar_holder.add_child(avatar)
	_user_avatar_rect_map[user_id] = avatar
	_apply_avatar(avatar, user_id, display_name)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.position = Vector2(28, 31)
	dot.mouse_filter = Control.MOUSE_FILTER_PASS
	avatar_holder.add_child(dot)
	_user_dot_map[user_id] = dot
	_update_status_dot(user_id)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	labels.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(labels)
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = display_name
	name_label.add_theme_color_override("font_color", C_TEXT)
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	labels.add_child(name_label)
	var status_label := Label.new()
	status_label.name = "Status"
	status_label.text = _status_name(_user_status_map.get(user_id, "chat"))
	status_label.add_theme_color_override("font_color", C_MUTED)
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.mouse_filter = Control.MOUSE_FILTER_PASS
	labels.add_child(status_label)
	button.pressed.connect(func(): _select_user(user_id))
	button.gui_input.connect(func(event): _on_user_gui(event, user_id))
	button.set_meta("user_id", user_id)
	return button

func _refresh_user_item(user_id: String) -> void:
	if not _user_item_map.has(user_id): return
	var button: Button = _user_item_map[user_id]
	var user: Dictionary = _user_data_map.get(user_id, {})
	var labels := button.get_child(0).get_child(1) as VBoxContainer
	(labels.get_node("Name") as Label).text = _display_name(user, user_id)
	(labels.get_node("Status") as Label).text = _status_name(_user_status_map.get(user_id, "chat"))
	_apply_avatar(_user_avatar_rect_map[user_id], user_id, _display_name(user, user_id))
	_update_status_dot(user_id)

func _on_user_gui(event: InputEvent, user_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_context_user_id = user_id
		var menu := PopupMenu.new()
		menu.add_item("Send Message", CTX_MESSAGE)
		menu.add_item("Send File…", CTX_FILE)
		menu.add_separator()
		menu.add_item("User Information", CTX_INFO)
		menu.id_pressed.connect(_on_context_action)
		menu.focus_exited.connect(func(): menu.queue_free())
		add_child(menu)
		menu.popup_on_parent(Rect2(get_global_mouse_position(), Vector2(180, 10)))

func _on_context_action(action_id: int) -> void:
	match action_id:
		CTX_MESSAGE: _select_user(_context_user_id)
		CTX_FILE: _send_file_to(_context_user_id)
		CTX_INFO: _show_info(_context_user_id)

func _select_user(user_id: String) -> void:
	if user_id.is_empty(): return
	if not _selected_user_id.is_empty() and _selected_user_id != user_id:
		_send_typing_state("inactive")
	_selected_user_id = user_id
	_set_empty_state(false)
	var user: Dictionary = _user_data_map.get(user_id, {})
	var name := _display_name(user, user_id)
	chat_user_name.text = name
	_restore_selected_status()
	_apply_avatar(chat_avatar, user_id, name)
	for id in _user_item_map:
		var item: Button = _user_item_map[id]
		item.add_theme_stylebox_override("normal", _style(C_PRIMARY.darkened(0.55), 8) if id == user_id else _style(Color.TRANSPARENT, 8))
	for child in message_vbox.get_children():
		child.queue_free()
	for entry in _message_history.get(user_id, []):
		_add_bubble(str(entry.get("text", "")), bool(entry.get("is_sent", false)), str(entry.get("sender", "")), str(entry.get("time", "")))
	message_input.grab_focus()
	_send_typing_state("active")
	_scroll_bottom()

func _set_empty_state(empty: bool) -> void:
	no_chat_label.visible = empty
	chat_header.visible = not empty
	input_panel.visible = not empty
	message_scroll.visible = not empty

func _on_send_pressed() -> void:
	var text := message_input.text.strip_edges()
	if text.is_empty() or _selected_user_id.is_empty(): return
	var message_id := -1
	if _messaging:
		var xml := XmlMessage.new()
		xml.add_data(_D.XN_MESSAGE, text)
		message_id = _messaging.send_message(_D.MessageType.MT_Message, _selected_user_id, xml)
	var timestamp := Time.get_time_string_from_system(false)
	_sent_recently[text] = Time.get_unix_time_from_system() + SENT_ECHO_IGNORE_SECONDS
	var display := _parse_smileys(text)
	_add_to_history(_selected_user_id, display, true, "Me", timestamp, message_id)
	_add_bubble(display, true, "Me", timestamp)
	message_input.clear()
	message_input.grab_focus()
	_send_typing_state("active")

func _on_message_input_gui(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and not event.shift_pressed:
		get_viewport().set_input_as_handled()
		_on_send_pressed()

func _on_message_input_changed() -> void:
	if _selected_user_id.is_empty() or not _messaging: return
	if not message_input.text.is_empty():
		if _typing_state != "composing": _send_typing_state("composing")
		_outgoing_typing_timer = 1.6
	elif _typing_state == "composing":
		_send_typing_state("active")

func _send_typing_state(state: String) -> void:
	if _selected_user_id.is_empty() or not _messaging: return
	_typing_state = state
	_messaging.send_chat_state(_selected_user_id, state)

func _on_message_received(message_type: int, user_id: String, user_name: String, body: String) -> void:
	if _messaging and _messaging.local_user.get("id", "") == user_id: return
	if message_type in [_D.MessageType.MT_File, _D.MessageType.MT_Folder, _D.MessageType.MT_Query]: return
	var timestamp := Time.get_time_string_from_system(false)
	if _sent_recently.get(body, 0.0) > Time.get_unix_time_from_system(): return
	var display := _parse_smileys(body)
	if message_type == _D.MessageType.MT_Broadcast:
		display = "📢 " + display
	_add_to_history(user_id, display, false, user_name, timestamp)
	if user_id == _selected_user_id:
		_add_bubble(display, false, user_name, timestamp)
	if not _has_focus or _hidden_to_tray or user_id != _selected_user_id:
		_mark_unread(user_name)

func _on_user_status_changed(user_id: String, status: String) -> void:
	_user_status_map[user_id] = status
	_update_status_dot(user_id)
	_refresh_user_item(user_id)
	if user_id == _selected_user_id: _restore_selected_status()

func _on_user_typing(user_id: String, user_name: String, state: String) -> void:
	if user_id != _selected_user_id: return
	if state == "composing":
		chat_status_label.text = user_name + " is typing…"
		chat_status_label.add_theme_color_override("font_color", C_PRIMARY_HOVER)
		_incoming_typing_timer = 4.0
	else:
		_restore_selected_status()

func _on_user_avatar_changed(user_id: String) -> void:
	if _user_avatar_rect_map.has(user_id):
		_apply_avatar(_user_avatar_rect_map[user_id], user_id, _display_name(_user_data_map.get(user_id, {}), user_id))
	if user_id == _selected_user_id:
		_apply_avatar(chat_avatar, user_id, _display_name(_user_data_map.get(user_id, {}), user_id))

func _on_delivery_state_changed(user_id: String, _message_id: int, state: String) -> void:
	if user_id != _selected_user_id: return
	match state:
		"sending": _network_label.text = "Sending message…"
		"delivered": _network_label.text = "Message delivered"
		"failed": _network_label.text = "Message could not be delivered"
	_network_label.add_theme_color_override("font_color", C_DANGER if state == "failed" else C_GREEN)

func _send_file_to(user_id: String) -> void:
	if not _messaging: return
	var name := _display_name(_user_data_map.get(user_id, {}), user_id)
	DisplayServer.file_dialog_show(
		"Send a file to " + name, "", "", false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, [],
		func(ok: bool, files: PackedStringArray, _filter: int):
			if ok and not files.is_empty():
				var file_id: String = _messaging.send_file(user_id, files[0])
				if not file_id.is_empty():
					_add_system_history(user_id, "Sending file: " + files[0].get_file())
	)

func _on_file_transfer_requested(transfer: Dictionary) -> void:
	var user_id := str(transfer.get("user_id", ""))
	var sender := _display_name(_user_data_map.get(user_id, {}), user_id)
	var dialog := ConfirmationDialog.new()
	dialog.title = "Incoming file"
	dialog.dialog_text = "%s wants to send:\n%s\n\nSize: %s\nFiles are saved to your configured download folder." % [sender, transfer.get("name", "file"), _format_bytes(int(transfer.get("size", 0)))]
	dialog.ok_button_text = "Accept"
	dialog.cancel_button_text = "Decline"
	dialog.min_size = Vector2(440, 220)
	dialog.confirmed.connect(func():
		_messaging.accept_file(user_id, str(transfer.get("id", "")))
		_add_system_history(user_id, "Accepted file: " + str(transfer.get("name", "file")))
	)
	dialog.canceled.connect(func(): _messaging.decline_file(user_id, str(transfer.get("id", ""))))
	dialog.close_requested.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()
	if not _has_focus: _mark_unread(sender)

func _on_file_transfer_updated(transfer: Dictionary) -> void:
	var user_id := str(transfer.get("user_id", ""))
	var status := str(transfer.get("status", ""))
	var name := str(transfer.get("name", "file"))
	var text := "File %s: %s" % [status, name]
	if status == "transferring":
		var size := maxi(1, int(transfer.get("size", 1)))
		var percent := int(float(transfer.get("transferred", 0)) / float(size) * 100.0)
		text = "Transferring %s — %d%%" % [name, clampi(percent, 0, 100)]
	_network_label.text = text
	_network_label.add_theme_color_override("font_color", C_DANGER if status in ["failed", "declined", "cancelled"] else C_GREEN)
	if status in ["complete", "failed", "declined", "cancelled"]:
		_add_system_history(user_id, text)

func _show_broadcast_dialog() -> void:
	if not _messaging or _messaging.user_count() == 0:
		_show_notice("Broadcast", "No LAN contacts are currently available.")
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Broadcast announcement"
	dialog.ok_button_text = "Send to everyone"
	dialog.min_size = Vector2(520, 300)
	var editor := TextEdit.new()
	editor.placeholder_text = "Write an announcement for everyone on the LAN"
	editor.custom_minimum_size = Vector2(480, 180)
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	dialog.add_child(editor)
	dialog.confirmed.connect(func():
		var text := editor.text.strip_edges()
		if not text.is_empty():
			_messaging.send_broadcast_message(text)
			_network_label.text = "Broadcast sent to LAN"
	)
	dialog.close_requested.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()
	editor.grab_focus()

func _show_history_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Conversation history"
	dialog.ok_button_text = "Close"
	dialog.min_size = Vector2(720, 520)
	var editor := TextEdit.new()
	editor.editable = false
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.custom_minimum_size = Vector2(680, 430)
	var lines: Array[String] = []
	for user_id in _message_history:
		var user_name := _display_name(_user_data_map.get(user_id, {}), user_id)
		lines.append("── " + user_name + " ──")
		for entry in _message_history[user_id]:
			lines.append("[%s] %s: %s" % [entry.get("time", ""), entry.get("sender", ""), entry.get("text", "")])
		lines.append("")
	editor.text = "\n".join(lines) if not lines.is_empty() else "No saved conversations yet."
	dialog.add_child(editor)
	dialog.close_requested.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()

func _show_settings_dialog() -> void:
	if not _lan_node or not _lan_node.app_settings:
		_show_notice("Settings", "Settings are not available until the LAN service starts.")
		return
	var settings = _lan_node.app_settings
	var dialog := ConfirmationDialog.new()
	dialog.title = "CydLAN Messenger settings"
	dialog.ok_button_text = "Save changes"
	dialog.min_size = Vector2(560, 520)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	var name_input := _settings_field(grid, "Display name", str(settings.get_value("display_name", _messaging.local_user.get("name", ""))))
	var note_input := _settings_field(grid, "Status note", str(settings.get_value("note", "")))
	var first_input := _settings_field(grid, "First name", str(settings.get_value("first_name", "")))
	var last_input := _settings_field(grid, "Last name", str(settings.get_value("last_name", "")))
	var about_input := _settings_field(grid, "About", str(settings.get_value("about", "")))
	var download_input := _settings_field(grid, "Download folder", str(settings.get_value("download_dir", "user://downloads")))
	var auto_accept := CheckBox.new()
	auto_accept.text = "Automatically accept incoming files"
	auto_accept.button_pressed = bool(settings.get_value("auto_accept_files", false))
	grid.add_child(Label.new())
	grid.add_child(auto_accept)
	var tray_checkbox := CheckBox.new()
	tray_checkbox.text = "Minimize to system tray when closed"
	tray_checkbox.button_pressed = bool(settings.get_value("minimize_to_tray", true))
	grid.add_child(Label.new())
	grid.add_child(tray_checkbox)
	dialog.add_child(grid)
	dialog.confirmed.connect(func():
		settings.set_value("display_name", name_input.text.strip_edges())
		settings.set_value("note", note_input.text.strip_edges())
		settings.set_value("first_name", first_input.text.strip_edges())
		settings.set_value("last_name", last_input.text.strip_edges())
		settings.set_value("about", about_input.text.strip_edges())
		settings.set_value("download_dir", download_input.text.strip_edges())
		settings.set_value("auto_accept_files", auto_accept.button_pressed)
		settings.set_value("minimize_to_tray", tray_checkbox.button_pressed)
		settings.save_settings()
		_lan_node.update_profile({
			"name": name_input.text.strip_edges(), "note": note_input.text.strip_edges(),
			"firstname": first_input.text.strip_edges(), "lastname": last_input.text.strip_edges(),
			"about": about_input.text.strip_edges()
		})
		_messaging._settings["download_dir"] = download_input.text.strip_edges()
		_messaging._settings["auto_accept_files"] = auto_accept.button_pressed
		_network_label.text = "Settings saved"
	)
	dialog.close_requested.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()

func _show_info(user_id: String) -> void:
	_info_requested_user = user_id
	if _messaging: _messaging.request_user_info(user_id)
	var user: Dictionary = _user_data_map.get(user_id, {})
	_open_info_dialog(user_id, {
		"name": _display_name(user, user_id), "address": user.get("address", ""),
		"version": user.get("version", ""), "status": user.get("status", ""),
		"note": user.get("note", ""), "id": user_id
	}, true)

func _on_user_info_received(user_id: String, info: Dictionary) -> void:
	if user_id != _info_requested_user: return
	_open_info_dialog(user_id, info, false)

func _open_info_dialog(user_id: String, info: Dictionary, loading: bool) -> void:
	if _info_dialog and is_instance_valid(_info_dialog): _info_dialog.queue_free()
	_info_dialog = AcceptDialog.new()
	_info_dialog.title = str(info.get("name", _display_name(_user_data_map.get(user_id, {}), user_id)))
	var full_name := (str(info.get("first_name", "")) + " " + str(info.get("last_name", ""))).strip_edges()
	var lines := [
		"Status: " + _status_name(str(info.get("status", _user_status_map.get(user_id, "chat")))),
		"Address: " + str(info.get("address", "Unknown")),
		"Version: " + str(info.get("version", "Unknown")),
		"Computer: " + str(info.get("host", "")),
		"Operating system: " + str(info.get("os", "")),
		"Logon: " + str(info.get("logon", "")),
		"Name: " + full_name,
		"Note: " + str(info.get("note", "")),
		"About: " + str(info.get("about", "")),
		"ID: " + user_id
	]
	if loading: lines.append("\nRequesting extended details from the legacy client…")
	_info_dialog.dialog_text = "\n".join(lines)
	_info_dialog.min_size = Vector2(480, 360)
	_info_dialog.ok_button_text = "Close"
	_info_dialog.close_requested.connect(func(): _info_dialog.queue_free())
	add_child(_info_dialog)
	_info_dialog.popup_centered()

func _show_status_menu() -> void:
	var menu := PopupMenu.new()
	for index in range(STATUS_CODES.size()):
		var code: String = STATUS_CODES[index]
		menu.add_item("●  " + STATUS_NAMES[code], index)
		menu.set_item_checked(index, code == _local_status)
	menu.id_pressed.connect(func(index): _change_status(STATUS_CODES[index]))
	menu.focus_exited.connect(func(): menu.queue_free())
	add_child(menu)
	menu.popup_on_parent(Rect2(_status_button.global_position + Vector2(0, _status_button.size.y), Vector2(200, 10)))

func _change_status(code: String) -> void:
	_local_status = code
	_update_status_button()
	if _messaging: _messaging.set_local_status(code)
	if _lan_node and _lan_node.app_settings:
		_lan_node.app_settings.set_value("status", code)
		_lan_node.app_settings.save_settings()

func _update_status_button() -> void:
	if not _status_button: return
	_status_button.text = "● " + STATUS_NAMES.get(_local_status, "Online")
	_status_button.add_theme_color_override("font_color", STATUS_COLORS.get(_local_status, C_GREEN))

func _setup_tray() -> void:
	_tray_menu = PopupMenu.new()
	_tray_menu.name = "TrayMenu"
	_tray_menu.add_item("Show CydLAN Messenger", TRAY_SHOW)
	_tray_menu.add_separator()
	_tray_menu.add_item("Broadcast…", TRAY_BROADCAST)
	_tray_menu.add_item("History", TRAY_HISTORY)
	_tray_menu.add_item("Settings", TRAY_SETTINGS)
	_tray_menu.add_separator()
	_tray_menu.add_item("Quit", TRAY_QUIT)
	_tray_menu.id_pressed.connect(_on_tray_action)
	add_child(_tray_menu)
	_status_indicator = StatusIndicator.new()
	_status_indicator.tooltip = APP_TITLE
	var icon := load("res://icon.svg")
	if icon: _status_indicator.icon = icon
	_status_indicator.menu = NodePath("../TrayMenu")
	_status_indicator.visible = true
	_status_indicator.pressed.connect(_on_status_indicator_pressed)
	add_child(_status_indicator)

func _on_tray_action(action_id: int) -> void:
	match action_id:
		TRAY_SHOW: _restore_from_tray()
		TRAY_BROADCAST: _restore_from_tray(); _show_broadcast_dialog()
		TRAY_HISTORY: _restore_from_tray(); _show_history_dialog()
		TRAY_SETTINGS: _restore_from_tray(); _show_settings_dialog()
		TRAY_QUIT: _allow_quit = true; get_tree().quit()

func _hide_to_tray() -> void:
	if _lan_node and _lan_node.app_settings and not bool(_lan_node.app_settings.get_value("minimize_to_tray", true)):
		_allow_quit = true
		get_tree().quit()
		return
	_hidden_to_tray = true
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	_update_tray_tooltip()

func _restore_from_tray() -> void:
	_hidden_to_tray = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_move_to_foreground()
	_clear_unread()

func _on_status_indicator_pressed(button: int, _position: Vector2i) -> void:
	if button == MOUSE_BUTTON_LEFT: _restore_from_tray()

func _mark_unread(sender: String) -> void:
	_unread_count += 1
	DisplayServer.window_set_title("[%d] %s" % [_unread_count, APP_TITLE])
	_update_tray_tooltip(sender)
	DisplayServer.window_request_attention()

func _clear_unread() -> void:
	if _unread_count == 0: return
	_unread_count = 0
	DisplayServer.window_set_title(APP_TITLE)
	_update_tray_tooltip()

func _update_tray_tooltip(sender := "") -> void:
	if not _status_indicator: return
	if _unread_count > 0:
		_status_indicator.tooltip = "%s\n%d unread message%s%s" % [APP_TITLE, _unread_count, "" if _unread_count == 1 else "s", "\nLatest: " + sender if not sender.is_empty() else ""]
	else:
		_status_indicator.tooltip = APP_TITLE

func _on_title_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_position := get_global_mouse_position()
		for button in [minimize_btn, maximize_btn, close_btn]:
			if Rect2(button.global_position, button.size).has_point(mouse_position): return
		_dragging = event.pressed
		if _dragging:
			_drag_offset = DisplayServer.mouse_get_position() - DisplayServer.window_get_position()
	elif event is InputEventMouseMotion and _dragging:
		DisplayServer.window_set_position(DisplayServer.mouse_get_position() - Vector2i(_drag_offset))

func _on_minimize_pressed() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)

func _on_maximize_pressed() -> void:
	var icon := maximize_btn.get_node("TextureRect") as TextureRect
	if _maximized:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(_pre_maximize_rect.size)
		DisplayServer.window_set_position(_pre_maximize_rect.position)
		_maximized = false
		if icon: icon.texture = load("res://Assets/NavIcons/Stop.png")
	else:
		_pre_maximize_rect = Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		_maximized = true
		if icon: icon.texture = load("res://Assets/NavIcons/Stop Squared.png")

func _on_close_pressed() -> void:
	if _allow_quit: get_tree().quit()
	else: _hide_to_tray()

func _on_search_changed(text: String) -> void:
	_search_text = text.strip_edges().to_lower()
	for user_id in _user_item_map:
		var name := _display_name(_user_data_map.get(user_id, {}), user_id).to_lower()
		_user_item_map[user_id].visible = _search_text.is_empty() or name.contains(_search_text)

func _on_connection_state_changed() -> void:
	if not _messaging: return
	_network_label.text = "LAN service active" if _messaging.network_is_connected() else "LAN service offline"
	_network_label.add_theme_color_override("font_color", C_GREEN if _messaging.network_is_connected() else C_DANGER)

func _display_name(user: Dictionary, user_id := "") -> String:
	var name := str(user.get("name", "")).strip_edges()
	return name if not name.is_empty() else user_id

func _status_name(status: String) -> String:
	return STATUS_NAMES.get(status, "Online")

func _restore_selected_status() -> void:
	if _selected_user_id.is_empty(): return
	var status := str(_user_status_map.get(_selected_user_id, "chat"))
	chat_status_label.text = _status_name(status)
	chat_status_label.add_theme_color_override("font_color", STATUS_COLORS.get(status, C_GREEN))

func _update_status_dot(user_id: String) -> void:
	if not _user_dot_map.has(user_id): return
	var style := _style(STATUS_COLORS.get(_user_status_map.get(user_id, "chat"), C_GREEN), 6, C_SURFACE, 2)
	_user_dot_map[user_id].add_theme_stylebox_override("panel", style)

func _apply_avatar(target: ColorRect, user_id: String, fallback_name: String) -> void:
	var user: Dictionary = _user_data_map.get(user_id, {})
	var color := _avatar_color(fallback_name)
	target.color = color
	target.add_theme_stylebox_override("panel", _style(color, AVATAR_SIZE / 2))
	var texture_rect := target.get_node_or_null("AvatarTexture") as TextureRect
	if not texture_rect:
		texture_rect = TextureRect.new()
		texture_rect.name = "AvatarTexture"
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		target.add_child(texture_rect)
	var texture := _load_avatar_texture(user_id, int(user.get("avatar", 0)))
	texture_rect.texture = texture
	texture_rect.visible = texture != null
	if texture: target.color = Color.TRANSPARENT

func _avatar_color(name: String) -> Color:
	if not _user_avatar_colors.has(name):
		_user_avatar_colors[name] = Color.from_hsv(float(abs(name.hash()) % 360) / 360.0, 0.52, 0.82)
	return _user_avatar_colors[name]

func _load_avatar_texture(user_id: String, avatar_id := 0) -> Texture2D:
	for path in _avatar_paths(user_id, avatar_id):
		if path.begins_with("res://"):
			if ResourceLoader.exists(path):
				var imported_texture: Texture2D = load(path) as Texture2D
				if imported_texture:
					return imported_texture
		elif FileAccess.file_exists(path):
			var image := Image.new()
			if image.load(path) == OK:
				return ImageTexture.create_from_image(image)
	return null

func _avatar_paths(user_id: String, avatar_id: int) -> Array[String]:
	var paths: Array[String] = [
		"user://cache/avt_" + user_id.validate_filename() + ".png",
		"res://Assets/Avatars/avatar_" + str(avatar_id) + ".png"
	]
	if OS.get_name() == "Windows":
		var local_app_data := OS.get_environment("LOCALAPPDATA")
		if not local_app_data.is_empty():
			paths.append(local_app_data.path_join("LAN Messenger").path_join("LAN Messenger").path_join("cache").path_join("avt_" + user_id + ".png"))
	paths.append("res://Assets/Avatars/avatar_default.png")
	return paths

func _parse_smileys(text: String) -> String:
	var result := text
	for code in SMILEYS: result = result.replace(code, SMILEYS[code])
	return result

func _add_bubble(text: String, is_sent: bool, _sender := "", timestamp := "") -> void:
	if timestamp.is_empty(): timestamp = Time.get_time_string_from_system(false)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bubble = ChatBubbleScene.instantiate()
	bubble.configure(text, is_sent, timestamp, maxf(220.0, message_scroll.size.x * CHAT_BUBBLE_MAX_WIDTH_RATIO))
	if is_sent:
		var left_spacer := Control.new(); left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(left_spacer)
	row.add_child(bubble)
	if not is_sent:
		var right_spacer := Control.new(); right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(right_spacer)
	message_vbox.add_child(row)
	_scroll_bottom()

func _add_to_history(user_id: String, text: String, is_sent: bool, sender: String, timestamp: String, message_id := -1) -> void:
	if not _message_history.has(user_id): _message_history[user_id] = []
	_message_history[user_id].append({"text": text, "is_sent": is_sent, "sender": sender, "time": timestamp, "message_id": message_id})
	_history_dirty = true

func _add_system_history(user_id: String, text: String) -> void:
	var timestamp := Time.get_time_string_from_system(false)
	_add_to_history(user_id, "• " + text, false, "System", timestamp)
	if user_id == _selected_user_id: _add_bubble("• " + text, false, "System", timestamp)

func _load_history() -> void:
	if not FileAccess.file_exists(HIST_FILE): return
	var file := FileAccess.open(HIST_FILE, FileAccess.READ)
	if not file: return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) == TYPE_DICTIONARY: _message_history = parsed

func _save_history() -> void:
	var file := FileAccess.open(HIST_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_message_history))
		file.close()
		_history_dirty = false

func _scroll_bottom() -> void:
	await get_tree().process_frame
	message_scroll.scroll_vertical = int(message_scroll.get_v_scroll_bar().max_value)

func _update_contact_count() -> void:
	if _contact_count_label:
		var count := _user_item_map.size()
		_contact_count_label.text = "%d person%s" % [count, "" if count == 1 else "s"]

func _settings_field(grid: GridContainer, label_text: String, value: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", C_MUTED)
	var input := LineEdit.new()
	input.text = value
	input.custom_minimum_size.x = 330
	grid.add_child(label)
	grid.add_child(input)
	return input

func _show_notice(title: String, text: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = text
	dialog.ok_button_text = "Close"
	dialog.close_requested.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()

func _format_bytes(value: int) -> String:
	if value < 1024: return str(value) + " B"
	if value < 1024 * 1024: return "%.1f KB" % (float(value) / 1024.0)
	if value < 1024 * 1024 * 1024: return "%.1f MB" % (float(value) / 1048576.0)
	return "%.2f GB" % (float(value) / 1073741824.0)

func _action_button(text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", C_TEXT)
	button.add_theme_stylebox_override("normal", _style(C_SURFACE_2, 7, C_BORDER, 1))
	button.add_theme_stylebox_override("hover", _style(C_PRIMARY.darkened(0.35), 7, C_PRIMARY, 1))
	button.add_theme_stylebox_override("pressed", _style(C_PRIMARY.darkened(0.5), 7, C_PRIMARY, 1))
	return button

func _icon_button(text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.flat = true
	button.add_theme_color_override("font_color", C_MUTED)
	button.add_theme_color_override("font_hover_color", C_TEXT)
	return button

func _style_primary_button(button: Button) -> void:
	button.text = "Send"
	button.custom_minimum_size = Vector2(78, 38)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _style(C_PRIMARY, 9))
	button.add_theme_stylebox_override("hover", _style(C_PRIMARY_HOVER, 9))
	button.add_theme_stylebox_override("pressed", _style(C_PRIMARY.darkened(0.2), 9))

func _style_window_button(button: Button, danger := false) -> void:
	button.add_theme_stylebox_override("normal", _style(Color.TRANSPARENT, 0))
	button.add_theme_stylebox_override("hover", _style(C_DANGER.darkened(0.25) if danger else C_SURFACE_2, 0))
	button.add_theme_stylebox_override("pressed", _style(C_DANGER.darkened(0.4) if danger else C_BORDER, 0))

func _style(color: Color, radius := 0, border_color := Color.TRANSPARENT, border_width := 0, top_round := true, bottom_round := true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius if top_round else 0
	style.corner_radius_top_right = radius if top_round else 0
	style.corner_radius_bottom_left = radius if bottom_round else 0
	style.corner_radius_bottom_right = radius if bottom_round else 0
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style
