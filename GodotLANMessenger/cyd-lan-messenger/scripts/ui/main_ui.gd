extends Control
const _D = preload("res://scripts/network/definitions.gd")
const _LanMessenger = preload("res://scripts/network/lan_messenger.gd")

const APP_TITLE := "CydLAN Messenger"
const TRAY_MENU_SHOW := 1
const TRAY_MENU_QUIT := 2
const WINDOW_W := 600
const WINDOW_H := 400
const CLR_PRIMARY := Color("#0084FF")
const CLR_BG := Color("#efeae2")
const CLR_SIDEBAR := Color("#FFFFFF")
const CLR_TITLE_BG := Color("#1C1E21")
const CLR_BUBBLE_SENT := Color("#0084FF")
const CLR_BUBBLE_RECV := Color("#E4E6EB")
const CLR_TEXT := Color("#050505")
const CLR_SECONDARY := Color("#65676B")
const CLR_GREEN := Color("#31A24C")
const CLR_ACTIVE := Color("#E7F3FF")
const CLR_BORDER := Color(0.88, 0.88, 0.88)

const AVATAR_SIZE := 28

@onready var title_bar: Panel = %TitleBar
@onready var minimize_btn: TextureButton = %MinimizeBtn
@onready var maximize_btn: TextureButton = %MaximizeBtn
@onready var close_btn: TextureButton = %CloseBtn
@onready var user_vbox: VBoxContainer = %UserVBox
@onready var search_input: LineEdit = %SearchInput
@onready var message_vbox: VBoxContainer = %MessageVBox
@onready var message_scroll: ScrollContainer = %MessageScroll
@onready var message_input: TextEdit = %MessageInput
@onready var send_btn: Button = %SendButton
@onready var chat_header: Panel = %ChatHeader
@onready var chat_user_name: Label = %ChatUserName
@onready var chat_status: Label = %ChatStatus
@onready var chat_avatar: ColorRect = %ChatAvatar
@onready var no_chat_label: Label = %NoChatLabel
@onready var input_panel: Panel = %InputPanel
@onready var left_sidebar: Panel = %LeftSidebar
@onready var chat_view: Panel = %ChatView

var _user_item_map: Dictionary = {}
var _user_data_map: Dictionary = {}
var _user_avatar_colors: Dictionary = {}
var _messaging: Node = null
var _net_started: bool = false
var _status_indicator: StatusIndicator = null
var _tray_menu: PopupMenu = null
var _allow_quit: bool = false
var _hidden_to_tray: bool = false
var _has_focus: bool = true
var _unread_count: int = 0
var _selected_user_id: String = ""
var _search_text: String = ""
var _message_history: Dictionary = {}
var _maximized: bool = false
var _pre_maximize_rect: Rect2i = Rect2i()
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2()

func _ready():
	get_tree().set_auto_accept_quit(false)
	get_window().min_size = Vector2i(400, 300)
	_setup_window()
	_apply_styling()
	_setup_signals()
	_setup_tray()
	no_chat_label.visible = true
	chat_header.visible = false
	input_panel.visible = false
	DisplayServer.window_set_title(APP_TITLE)

func _setup_window():
	var win = get_window()
	win.size = Vector2i(WINDOW_W, WINDOW_H)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	var ss = DisplayServer.screen_get_size()
	DisplayServer.window_set_position(Vector2i(ss.x / 2 - WINDOW_W / 2, ss.y / 2 - WINDOW_H / 2))
	var icon_tex = load("res://icon.svg")
	if icon_tex:
		var img = icon_tex.get_image()
		if img:
			DisplayServer.set_icon(img)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			if _allow_quit:
				get_tree().quit()
			else:
				_hide_to_tray()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_has_focus = true
			_clear_unread()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_has_focus = false

func _setup_signals():
	search_input.text_changed.connect(_on_search_changed)
	send_btn.pressed.connect(_on_send_pressed)
	minimize_btn.pressed.connect(_on_minimize_pressed)
	maximize_btn.pressed.connect(_on_maximize_pressed)
	close_btn.pressed.connect(_on_close_pressed)
	title_bar.gui_input.connect(_on_title_gui_input)

func _on_title_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var pos = get_global_mouse_position()
		for btn in [minimize_btn, maximize_btn, close_btn]:
			var r = Rect2(btn.global_position, btn.size)
			if r.has_point(pos):
				return
		_dragging = event.pressed
		if _dragging:
			_drag_offset = DisplayServer.mouse_get_position() - Vector2i(DisplayServer.window_get_position())
	elif event is InputEventMouseMotion and _dragging:
		DisplayServer.window_set_position(DisplayServer.mouse_get_position() - Vector2i(_drag_offset))

func _on_minimize_pressed():
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)

func _on_maximize_pressed():
	if _maximized:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(_pre_maximize_rect.size))
		DisplayServer.window_set_position(_pre_maximize_rect.position)
		_maximized = false
		maximize_btn.texture_normal = load("res://Assets/NavIcons/Stop.png")
	else:
		_pre_maximize_rect = Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		_maximized = true
		maximize_btn.texture_normal = load("res://Assets/NavIcons/Stop Squared.png")

func _on_close_pressed():
	if _allow_quit:
		get_tree().quit()
	else:
		_hide_to_tray()

func _apply_styling():
	var root_s = StyleBoxFlat.new()
	root_s.bg_color = CLR_BG
	add_theme_stylebox_override("panel", root_s)

	var ts = StyleBoxFlat.new()
	ts.bg_color = CLR_TITLE_BG
	ts.set_corner_radius_all(0)
	title_bar.add_theme_stylebox_override("panel", ts)

	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP

	var tbs = StyleBoxFlat.new()
	tbs.bg_color = Color.TRANSPARENT
	var tb_hbox = title_bar.get_node("TitleHBox")
	tb_hbox.add_theme_constant_override("separation", 0)
	tb_hbox.mouse_filter = Control.MOUSE_FILTER_PASS

	var tl = title_bar.get_node("TitleHBox/TitleLabel")
	tl.add_theme_color_override("font_color", Color.WHITE)

	var ssb = StyleBoxFlat.new()
	ssb.bg_color = CLR_BORDER
	ssb.set_corner_radius_all(0)
	var v = StyleBoxFlat.new()
	v.bg_color = Color.TRANSPARENT

	minimize_btn.add_theme_stylebox_override("normal", v)
	minimize_btn.add_theme_stylebox_override("hover", v)
	minimize_btn.add_theme_stylebox_override("pressed", v)
	minimize_btn.add_theme_stylebox_override("disabled", v)
	minimize_btn.texture_normal = load("res://Assets/NavIcons/Subtract.png")

	maximize_btn.add_theme_stylebox_override("normal", v)
	maximize_btn.add_theme_stylebox_override("hover", v)
	maximize_btn.add_theme_stylebox_override("pressed", v)
	maximize_btn.add_theme_stylebox_override("disabled", v)
	maximize_btn.texture_normal = load("res://Assets/NavIcons/Stop.png")

	close_btn.add_theme_stylebox_override("normal", v)
	close_btn.add_theme_stylebox_override("hover", v)
	close_btn.add_theme_stylebox_override("pressed", v)
	close_btn.add_theme_stylebox_override("disabled", v)
	close_btn.texture_normal = load("res://Assets/NavIcons/Close.png")

	var sidebar_s = StyleBoxFlat.new()
	sidebar_s.bg_color = CLR_SIDEBAR
	sidebar_s.set_corner_radius_all(0)
	sidebar_s.border_width_right = 1
	sidebar_s.border_color = CLR_BORDER
	left_sidebar.add_theme_stylebox_override("panel", sidebar_s)

	var sb_vbox = left_sidebar.get_node("SidebarVBox")
	sb_vbox.add_theme_constant_override("separation", 0)

	search_input.add_theme_color_override("font_color", CLR_TEXT)
	search_input.add_theme_color_override("placeholder_color", CLR_SECONDARY)
	search_input.add_theme_color_override("caret_color", CLR_PRIMARY)
	search_input.add_theme_constant_override("minimum_character_width", 0)
	var search_bg = StyleBoxFlat.new()
	search_bg.bg_color = Color(0.9, 0.9, 0.9)
	search_bg.set_corner_radius_all(0)
	search_bg.content_margin_left = 8
	search_bg.content_margin_right = 8
	search_bg.content_margin_top = 4
	search_bg.content_margin_bottom = 4
	search_input.add_theme_stylebox_override("normal", search_bg)
	search_input.add_theme_stylebox_override("focus", search_bg)
	search_input.add_theme_font_size_override("font_size", 12)

	var sb_border = StyleBoxFlat.new()
	sb_border.bg_color = CLR_BORDER
	sb_border.set_corner_radius_all(0)
	sb_border.border_width_bottom = 1
	sb_border.border_color = CLR_BORDER

	var us = left_sidebar.get_node("SidebarVBox/UserScroll")
	var us_bg = StyleBoxFlat.new()
	us_bg.bg_color = CLR_SIDEBAR
	us.add_theme_stylebox_override("panel", us_bg)
	us.get_v_scroll_bar().add_theme_constant_override("scroll", 4)
	us.scroll_horizontal = 0

	var cvs = StyleBoxFlat.new()
	cvs.bg_color = CLR_BG
	cvs.set_corner_radius_all(0)
	chat_view.add_theme_stylebox_override("panel", cvs)

	var chs = StyleBoxFlat.new()
	chs.bg_color = CLR_SIDEBAR
	chs.set_corner_radius_all(0)
	chs.border_width_bottom = 1
	chs.border_color = CLR_BORDER
	chat_header.add_theme_stylebox_override("panel", chs)

	var ch_hbox = chat_header.get_node("ChatHeaderHBox")
	ch_hbox.add_theme_constant_override("separation", 8)

	chat_user_name.add_theme_color_override("font_color", CLR_TEXT)
	chat_status.add_theme_color_override("font_color", CLR_GREEN)

	var ca_style = StyleBoxFlat.new()
	ca_style.set_corner_radius_all(AVATAR_SIZE / 2)
	ca_style.bg_color = Color("#E4E6EB")
	chat_avatar.add_theme_stylebox_override("panel", ca_style)
	chat_avatar.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)

	no_chat_label.add_theme_color_override("font_color", CLR_SECONDARY)
	no_chat_label.add_theme_font_size_override("font_size", 13)

	var istyle = StyleBoxFlat.new()
	istyle.bg_color = CLR_SIDEBAR
	istyle.set_corner_radius_all(0)
	istyle.border_width_top = 1
	istyle.border_color = CLR_BORDER
	input_panel.add_theme_stylebox_override("panel", istyle)

	var ih = input_panel.get_node("InputHBox")
	ih.add_theme_constant_override("separation", 4)

	message_input.add_theme_color_override("font_color", CLR_TEXT)
	message_input.add_theme_color_override("placeholder_color", CLR_SECONDARY)
	message_input.add_theme_color_override("caret_color", CLR_PRIMARY)
	message_input.add_theme_constant_override("minimum_character_width", 0)
	var input_bg = StyleBoxFlat.new()
	input_bg.bg_color = Color(0.94, 0.94, 0.94)
	input_bg.set_corner_radius_all(0)
	input_bg.content_margin_left = 8
	input_bg.content_margin_right = 8
	input_bg.content_margin_top = 6
	input_bg.content_margin_bottom = 6
	message_input.add_theme_stylebox_override("normal", input_bg)
	message_input.add_theme_stylebox_override("focus", input_bg)
	message_input.add_theme_font_size_override("font_size", 12)

	send_btn.add_theme_color_override("font_color", CLR_PRIMARY)
	send_btn.add_theme_font_size_override("font_size", 16)
	var btn_n = StyleBoxFlat.new()
	btn_n.bg_color = Color.TRANSPARENT
	send_btn.add_theme_stylebox_override("normal", btn_n)
	send_btn.add_theme_stylebox_override("hover", btn_n)
	send_btn.add_theme_stylebox_override("pressed", btn_n)
	send_btn.add_theme_stylebox_override("disabled", btn_n)

	message_scroll.scroll_horizontal = 0
	var msbg = StyleBoxFlat.new()
	msbg.bg_color = Color.TRANSPARENT
	message_scroll.add_theme_stylebox_override("panel", msbg)

func _setup_tray() -> void:
	_tray_menu = PopupMenu.new()
	_tray_menu.name = "TrayMenu"
	_tray_menu.add_item("Show", TRAY_MENU_SHOW)
	_tray_menu.add_separator()
	_tray_menu.add_item("Quit", TRAY_MENU_QUIT)
	_tray_menu.id_pressed.connect(_on_tray_menu_id_pressed)
	add_child(_tray_menu)
	_status_indicator = StatusIndicator.new()
	_status_indicator.name = "TrayIndicator"
	_status_indicator.tooltip = APP_TITLE
	var icon = load("res://icon.svg")
	if icon:
		_status_indicator.icon = icon
	_status_indicator.menu = NodePath("../TrayMenu")
	_status_indicator.visible = true
	_status_indicator.pressed.connect(_on_status_indicator_pressed)
	add_child(_status_indicator)

func _hide_to_tray() -> void:
	_hidden_to_tray = true
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	_update_tray_tooltip()

func _restore_from_tray() -> void:
	_hidden_to_tray = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_move_to_foreground()
	_clear_unread()

func _show_minimized_for_unread() -> void:
	if _hidden_to_tray:
		_hidden_to_tray = false
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	DisplayServer.window_request_attention()

func _on_status_indicator_pressed(mouse_button: int, mouse_position: Vector2i) -> void:
	if mouse_button == MOUSE_BUTTON_LEFT:
		_restore_from_tray()

func _on_tray_menu_id_pressed(id: int) -> void:
	match id:
		TRAY_MENU_SHOW:
			_restore_from_tray()
		TRAY_MENU_QUIT:
			_allow_quit = true
			get_tree().quit()

func _mark_unread(sender_name: String) -> void:
	_unread_count += 1
	_update_tray_tooltip(sender_name)
	DisplayServer.window_set_title("[" + str(_unread_count) + "] " + APP_TITLE)
	_show_minimized_for_unread()

func _clear_unread() -> void:
	if _unread_count == 0:
		return
	_unread_count = 0
	DisplayServer.window_set_title(APP_TITLE)
	_update_tray_tooltip()

func _update_tray_tooltip(sender_name: String = "") -> void:
	if not _status_indicator:
		return
	if _unread_count > 0:
		var detail = " unread message"
		if _unread_count != 1:
			detail += "s"
		if not sender_name.is_empty():
			_status_indicator.tooltip = APP_TITLE + "\n" + str(_unread_count) + detail + "\nLatest: " + sender_name
		else:
			_status_indicator.tooltip = APP_TITLE + "\n" + str(_unread_count) + detail
	else:
		_status_indicator.tooltip = APP_TITLE

func _get_avatar_color(name: String) -> Color:
	if _user_avatar_colors.has(name):
		return _user_avatar_colors[name]
	var h = abs(name.hash()) % 360 / 360.0
	var c = Color.from_hsv(h, 0.45, 0.7)
	_user_avatar_colors[name] = c
	return c

func _on_refresh_button_pressed():
	if not _net_started:
		_net_start()
	elif _messaging:
		_messaging.refresh()
	await get_tree().process_frame
	_sync_existing_users()

func _net_start():
	var inst = _LanMessenger.new()
	add_child(inst)
	_messaging = inst.messaging
	if not _messaging:
		return
	_net_started = true
	_messaging.user_added.connect(_on_user_added)
	_messaging.user_removed.connect(_on_user_removed)
	_messaging.message_received.connect(_on_message_received)
	_sync_existing_users()

func _sync_existing_users():
	if not _messaging:
		return
	for user in _messaging.user_list:
		_on_user_added(user)

func _on_user_added(user: Dictionary):
	var uid = user.get("id", "")
	if uid.is_empty() or _user_item_map.has(uid):
		return
	var name = user.get("name", "").strip_edges()
	if name.is_empty():
		name = uid
	_user_data_map[uid] = user
	var item = _create_user_item(uid, name)
	user_vbox.add_child(item)
	_user_item_map[uid] = item

func _on_user_removed(user_id: String):
	if _user_item_map.has(user_id):
		var item = _user_item_map[user_id]
		user_vbox.remove_child(item)
		item.queue_free()
		_user_item_map.erase(user_id)
		_user_data_map.erase(user_id)
	if _selected_user_id == user_id:
		_selected_user_id = ""
		no_chat_label.visible = true
		chat_header.visible = false
		input_panel.visible = false

func _create_user_item(uid: String, name: String) -> Button:
	var btn = Button.new()
	btn.flat = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size.y = 44
	btn.add_theme_constant_override("outline_size", 0)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	var nbg = StyleBoxFlat.new()
	nbg.bg_color = Color.TRANSPARENT
	nbg.set_corner_radius_all(0)
	var hbg = StyleBoxFlat.new()
	hbg.bg_color = Color(0, 0, 0, 0.05)
	hbg.set_corner_radius_all(0)
	var pbg = StyleBoxFlat.new()
	pbg.bg_color = Color(0, 0, 0, 0.08)
	pbg.set_corner_radius_all(0)
	btn.add_theme_stylebox_override("normal", nbg)
	btn.add_theme_stylebox_override("hover", hbg)
	btn.add_theme_stylebox_override("pressed", pbg)

	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.add_child(hbox)

	var av_container = Control.new()
	av_container.custom_minimum_size = Vector2(40, 44)
	av_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	av_container.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	av_container.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.add_child(av_container)

	var avatar = ColorRect.new()
	avatar.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	var ac = _get_avatar_color(name)
	var as_ = StyleBoxFlat.new()
	as_.bg_color = ac
	as_.set_corner_radius_all(AVATAR_SIZE / 2)
	as_.corner_detail = 6
	avatar.add_theme_stylebox_override("panel", as_)
	avatar.mouse_filter = Control.MOUSE_FILTER_PASS
	av_container.add_child(avatar)
	avatar.position = Vector2(6, 8)

	var dot = ColorRect.new()
	dot.custom_minimum_size = Vector2(9, 9)
	var ds = StyleBoxFlat.new()
	ds.bg_color = CLR_GREEN
	ds.set_corner_radius_all(5)
	ds.corner_detail = 4
	ds.border_width_left = 2
	ds.border_width_right = 2
	ds.border_width_top = 2
	ds.border_width_bottom = 2
	ds.border_color = CLR_SIDEBAR
	dot.add_theme_stylebox_override("panel", ds)
	dot.mouse_filter = Control.MOUSE_FILTER_PASS
	dot.position = Vector2(24, 26)
	av_container.add_child(dot)

	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.add_child(vb)

	var nl = Label.new()
	nl.text = name
	nl.add_theme_font_size_override("font_size", 13)
	nl.add_theme_color_override("font_color", CLR_TEXT)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.add_child(nl)

	var sl = Label.new()
	sl.text = "Online"
	sl.add_theme_font_size_override("font_size", 10)
	sl.add_theme_color_override("font_color", CLR_GREEN)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.add_child(sl)

	btn.pressed.connect(func():
		_select_user(uid)
	)
	btn.set_meta("uid", uid)

	if not _search_text.is_empty():
		btn.visible = name.to_lower().contains(_search_text.to_lower())

	return btn

func _select_user(uid: String):
	if uid.is_empty() or uid == _selected_user_id:
		return
	_selected_user_id = uid
	no_chat_label.visible = false
	chat_header.visible = true
	input_panel.visible = true
	message_input.grab_focus()

	var user = _user_data_map.get(uid, {})
	var name = user.get("name", "").strip_edges()
	if name.is_empty():
		name = uid
	chat_user_name.text = name
	chat_status.text = "Online"

	var ac = _get_avatar_color(name)
	var st = StyleBoxFlat.new()
	st.bg_color = ac
	st.set_corner_radius_all(AVATAR_SIZE / 2)
	st.corner_detail = 6
	chat_avatar.add_theme_stylebox_override("panel", st)

	for uid_key in _user_item_map:
		var item = _user_item_map[uid_key]
		var is_active = uid_key == uid
		if is_active:
			var ast = StyleBoxFlat.new()
			ast.bg_color = CLR_ACTIVE
			ast.set_corner_radius_all(0)
			item.add_theme_stylebox_override("normal", ast)
			item.add_theme_stylebox_override("hover", ast)
		else:
			var ns = StyleBoxFlat.new()
			ns.bg_color = Color.TRANSPARENT
			ns.set_corner_radius_all(0)
			item.add_theme_stylebox_override("normal", ns)
			var hs = StyleBoxFlat.new()
			hs.bg_color = Color(0, 0, 0, 0.05)
			hs.set_corner_radius_all(0)
			item.add_theme_stylebox_override("hover", hs)
	_show_history(uid)
	_scroll_to_bottom()

func _show_history(uid: String):
	for c in message_vbox.get_children():
		c.queue_free()
	if _message_history.has(uid):
		for entry in _message_history[uid]:
			_add_bubble_raw(entry.text, entry.is_sent, entry.sender)

func _on_search_changed(text: String):
	_search_text = text.strip_edges()
	for uid in _user_item_map:
		var item = _user_item_map[uid]
		var user = _user_data_map.get(uid, {})
		var name = user.get("name", "").strip_edges()
		if name.is_empty():
			name = uid
		if _search_text.is_empty():
			item.visible = true
		else:
			item.visible = name.to_lower().contains(_search_text.to_lower())

func _on_send_pressed():
	var text = message_input.text.strip_edges()
	if text.is_empty() or _selected_user_id.is_empty():
		return
	if _messaging:
		var xml = XmlMessage.new()
		xml.add_data(_D.XN_MESSAGE, text)
		_messaging.send_message(_D.MessageType.MT_Message, _selected_user_id, xml)
	_add_to_history(_selected_user_id, text, true, "Me")
	_add_bubble(text, true, "Me")
	message_input.text = ""
	message_input.grab_focus()

func _on_message_received(type: int, user_id: String, name: String, body: String):
	if _messaging and _messaging.local_user.get("id", "") == user_id:
		return
	_add_to_history(user_id, body, false, name)
	if user_id == _selected_user_id:
		_add_bubble(body, false, name)
	if not _has_focus or _hidden_to_tray:
		_mark_unread(name)

func _add_bubble(text: String, is_sent: bool, sender: String = ""):
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var bubble = Panel.new()
	bubble.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var bc = CLR_BUBBLE_SENT if is_sent else CLR_BUBBLE_RECV
	var tc = Color.WHITE if is_sent else CLR_TEXT
	var bs = StyleBoxFlat.new()
	bs.bg_color = bc
	var cr := 14
	if is_sent:
		bs.set_corner_radius_all(cr)
		bs.corner_radius_top_right = 4
	else:
		bs.set_corner_radius_all(cr)
		bs.corner_radius_top_left = 4
	bs.corner_detail = 6
	bs.content_margin_left = 10
	bs.content_margin_right = 10
	bs.content_margin_top = 6
	bs.content_margin_bottom = 6
	bubble.add_theme_stylebox_override("panel", bs)

	if not is_sent and not sender.is_empty():
		var vb = VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bubble.add_child(vb)
		var nl = Label.new()
		nl.text = sender
		nl.add_theme_font_size_override("font_size", 10)
		nl.add_theme_color_override("font_color", CLR_PRIMARY)
		vb.add_child(nl)
		var ml = RichTextLabel.new()
		ml.text = _wrap_text(text)
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ml.fit_content = true
		ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ml.add_theme_color_override("default_color", tc)
		ml.add_theme_font_size_override("font_size", 12)
		ml.scroll_active = false
		ml.mouse_filter = Control.MOUSE_FILTER_PASS
		vb.add_child(ml)
	else:
		var ml = RichTextLabel.new()
		ml.text = _wrap_text(text)
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ml.fit_content = true
		ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ml.add_theme_color_override("default_color", tc)
		ml.add_theme_font_size_override("font_size", 12)
		ml.scroll_active = false
		ml.mouse_filter = Control.MOUSE_FILTER_PASS
		bubble.add_child(ml)

	if is_sent:
		var sp = Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sp)

	bubble.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(bubble)

	if not is_sent:
		var sp = Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sp)

	message_vbox.add_child(row)
	_scroll_to_bottom()

func _add_bubble_raw(text: String, is_sent: bool, sender: String = ""):
	_add_bubble(text, is_sent, sender)

func _add_to_history(uid: String, text: String, is_sent: bool, sender: String):
	if not _message_history.has(uid):
		_message_history[uid] = []
	_message_history[uid].append({
		text = text,
		is_sent = is_sent,
		sender = sender
	})

func _wrap_text(text: String) -> String:
	var max_chars := 45
	if text.length() <= max_chars and not "\n" in text:
		return text
	var raw_lines = text.split("\n")
	var result: Array[String] = []
	for raw_line in raw_lines:
		var words = raw_line.split(" ")
		var current = ""
		for word in words:
			while word.length() > max_chars:
				if not current.is_empty():
					result.append(current)
					current = ""
				result.append(word.substr(0, max_chars))
				word = word.substr(max_chars)
			if word.is_empty():
				continue
			var test = current + (" " if current else "") + word
			if test.length() > max_chars and not current.is_empty():
				result.append(current)
				current = word
			else:
				current = test
		if not current.is_empty():
			result.append(current)
	return "\n".join(result)

func _scroll_to_bottom():
	await get_tree().process_frame
	message_scroll.scroll_vertical = int(message_scroll.get_v_scroll_bar().max_value)
