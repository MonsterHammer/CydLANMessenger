extends Control
const _D = preload("res://scripts/network/definitions.gd")
const _LanMessenger = preload("res://scripts/network/lan_messenger.gd")

const APP_TITLE := "CydLAN Messenger"
const TRAY_MENU_SHOW := 1; const TRAY_MENU_QUIT := 2
const CTX_MSG := 10; const CTX_INFO := 11; const CTX_FILE := 12; const CTX_BCAST := 13
const CLR_PRIMARY := Color("#fab283"); const CLR_BUBBLE_SENT := Color("#fab283")
const CLR_BUBBLE_RECV := Color("#303030"); const CLR_TEXT := Color("#e0e0e0")
const CLR_GREEN := Color("#7fd88f"); const CLR_ACTIVE := Color("#303030")
const CLR_ST := {"chat": Color("#7fd88f"),"busy": Color("#e06c75"),"dnd": Color("#e06c75"),"brb": Color("#f5a742"),"away": Color("#f5a742"),"gone": Color("#6a6a6a")}
const ST_NAMES := {"chat":"Online","busy":"Busy","dnd":"Do Not Disturb","brb":"Be Right Back","away":"Away","gone":"Offline"}
const AVATAR_SIZE := 28

@onready var title_bar: Panel = %TitleBar
@onready var minimize_btn: Button = %MinimizeBtn; @onready var maximize_btn: Button = %MaximizeBtn; @onready var close_btn: Button = %CloseBtn
@onready var user_vbox: VBoxContainer = %UserVBox; @onready var search_input: LineEdit = %SearchInput
@onready var message_vbox: VBoxContainer = %MessageVBox; @onready var message_scroll: ScrollContainer = %MessageScroll
@onready var message_input: TextEdit = %MessageInput; @onready var send_btn: Button = %SendButton
@onready var chat_header: Panel = %ChatHeader; @onready var chat_user_name: Label = %ChatUserName
@onready var chat_status_label: Label = %ChatStatus; @onready var chat_avatar: ColorRect = %ChatAvatar
@onready var no_chat_label: Label = %NoChatLabel; @onready var input_panel: Panel = %InputPanel

var _user_item_map: Dictionary = {}; var _user_data_map: Dictionary = {}; var _user_avatar_colors: Dictionary = {}
var _user_dot_map: Dictionary = {}; var _user_status_map: Dictionary = {}; var _sent_recently: Dictionary = {}
var _messaging: Node = null; var _net_started: bool = false; var _status_indicator: StatusIndicator = null
var _tray_menu: PopupMenu = null; var _allow_quit: bool = false; var _hidden_to_tray: bool = false
var _has_focus: bool = true; var _unread_count: int = 0; var _selected_user_id: String = ""
var _search_text: String = ""; var _message_history: Dictionary = {}; var _maximized: bool = false
var _pre_maximize_rect: Rect2i = Rect2i(); var _dragging: bool = false; var _drag_offset: Vector2 = Vector2()
var _context_uid: String = ""; var _local_status: String = "chat"; var _typing_timer: float = 0.0

func _ready():
	get_tree().set_auto_accept_quit(false); get_window().min_size = Vector2i(400, 300)
	_setup_window(); _setup_signals(); _setup_tray()
	no_chat_label.visible = true; chat_header.visible = false; input_panel.visible = false
	DisplayServer.window_set_title(APP_TITLE); call_deferred("_on_refresh_button_pressed")

func _setup_window():
	var win = get_window(); win.size = Vector2i(600, 400)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	var ss = DisplayServer.screen_get_size()
	DisplayServer.window_set_position(Vector2i(ss.x / 2 - 300, ss.y / 2 - 200))
	var t = load("res://icon.svg")
	if t: var img = t.get_image(); if img: DisplayServer.set_icon(img)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			if _allow_quit: get_tree().quit()
			else: _hide_to_tray()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN: _has_focus = true; _clear_unread()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT: _has_focus = false

func _process(delta):
	if _selected_user_id and _typing_timer > 0:
		_typing_timer -= delta
		if _typing_timer <= 0:
			var s = _user_status_map.get(_selected_user_id, "chat")
			chat_status_label.text = ST_NAMES.get(s, "Online"); chat_status_label.add_theme_color_override("font_color", CLR_GREEN if s == "chat" else CLR_ST.get(s, CLR_GREEN))

func _setup_signals():
	search_input.text_changed.connect(_on_search_changed); send_btn.pressed.connect(_on_send_pressed)
	minimize_btn.pressed.connect(_on_minimize_pressed); maximize_btn.pressed.connect(_on_maximize_pressed)
	close_btn.pressed.connect(_on_close_pressed); title_bar.gui_input.connect(_on_title_gui_input)

func _on_title_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var pos = get_global_mouse_position()
		for b in [minimize_btn, maximize_btn, close_btn]:
			if Rect2(b.global_position, b.size).has_point(pos): return
		_dragging = event.pressed
		if _dragging: _drag_offset = DisplayServer.mouse_get_position() - Vector2i(DisplayServer.window_get_position())
	elif event is InputEventMouseMotion and _dragging:
		DisplayServer.window_set_position(DisplayServer.mouse_get_position() - Vector2i(_drag_offset))

func _on_minimize_pressed(): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
func _on_maximize_pressed():
	var icon = maximize_btn.get_node("TextureRect") as TextureRect
	if _maximized:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(_pre_maximize_rect.size))
		DisplayServer.window_set_position(_pre_maximize_rect.position); _maximized = false
		if icon: icon.texture = load("res://Assets/NavIcons/Stop.png")
	else:
		_pre_maximize_rect = Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED); _maximized = true
		if icon: icon.texture = load("res://Assets/NavIcons/Stop Squared.png")
func _on_close_pressed():
	if _allow_quit: get_tree().quit()
	else: _hide_to_tray()

func _setup_tray():
	_tray_menu = PopupMenu.new(); _tray_menu.name = "TrayMenu"
	_tray_menu.add_item("Show", TRAY_MENU_SHOW); _tray_menu.add_separator(); _tray_menu.add_item("Quit", TRAY_MENU_QUIT)
	_tray_menu.id_pressed.connect(_on_tray_menu_id_pressed); add_child(_tray_menu)
	_status_indicator = StatusIndicator.new(); _status_indicator.name = "TrayIndicator"; _status_indicator.tooltip = APP_TITLE
	var ic = load("res://icon.svg")
	if ic: _status_indicator.icon = ic
	_status_indicator.menu = NodePath("../TrayMenu"); _status_indicator.visible = true
	_status_indicator.pressed.connect(_on_status_indicator_pressed); add_child(_status_indicator)

func _hide_to_tray():
	_hidden_to_tray = true; DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED); _update_tray_tooltip()
func _restore_from_tray():
	_hidden_to_tray = false; DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_move_to_foreground(); _clear_unread()
func _show_minimized_for_unread():
	if _hidden_to_tray: _hidden_to_tray = false; DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	DisplayServer.window_request_attention()
func _on_status_indicator_pressed(b: int, _p: Vector2i) -> void: if b == MOUSE_BUTTON_LEFT: _restore_from_tray()
func _on_tray_menu_id_pressed(id: int) -> void:
	match id:
		TRAY_MENU_SHOW: _restore_from_tray()
		TRAY_MENU_QUIT: _allow_quit = true; get_tree().quit()

func _mark_unread(n: String): _unread_count += 1; _update_tray_tooltip(n); DisplayServer.window_set_title("[%d] %s" % [_unread_count, APP_TITLE]); _show_minimized_for_unread()
func _clear_unread(): if _unread_count == 0: return; _unread_count = 0; DisplayServer.window_set_title(APP_TITLE); _update_tray_tooltip()
func _update_tray_tooltip(n: String = ""):
	if not _status_indicator: return
	if _unread_count > 0:
		var d = " unread message"
		if _unread_count != 1: d += "s"
		var suffix = "\nLatest: " + n if not n.is_empty() else ""
		_status_indicator.tooltip = APP_TITLE + "\n" + str(_unread_count) + d + suffix
	else: _status_indicator.tooltip = APP_TITLE

func _gc(n: String) -> Color: return _user_avatar_colors.get(n) if _user_avatar_colors.has(n) else Color.from_hsv(abs(n.hash()) % 360 / 360.0, 0.45, 0.7)
func _sc(s: String) -> Color: return CLR_ST.get(s, CLR_GREEN)
func _sn(s: String) -> String: return ST_NAMES.get(s, "Online")

func _on_refresh_button_pressed():
	if not _net_started: _net_start()
	elif _messaging: _messaging.refresh()
	await get_tree().process_frame; _sync_existing_users()

func _net_start():
	var inst = _LanMessenger.new(); add_child(inst); _messaging = inst.messaging
	if not _messaging: return; _net_started = true
	_messaging.user_added.connect(_on_user_added); _messaging.user_removed.connect(_on_user_removed)
	_messaging.message_received.connect(_on_message_received)
	_messaging.user_status_changed.connect(_on_user_status_changed); _messaging.user_typing.connect(_on_user_typing)
	_sync_existing_users()

func _sync_existing_users(): if _messaging: for u in _messaging.user_list: _on_user_added(u)

func _on_user_added(user: Dictionary):
	var uid = user.get("id", "")
	if uid.is_empty() or _user_item_map.has(uid): return
	var name = user.get("name", "").strip_edges(); if name.is_empty(): name = uid
	_user_data_map[uid] = user; _user_status_map[uid] = user.get("status", "chat")
	var item = _create_user_item(uid, name); user_vbox.add_child(item); _user_item_map[uid] = item

func _on_user_removed(user_id: String):
	if _user_item_map.has(user_id):
		var item = _user_item_map[user_id]; user_vbox.remove_child(item); item.queue_free()
		_user_item_map.erase(user_id); _user_data_map.erase(user_id); _user_dot_map.erase(user_id)
	if _selected_user_id == user_id: _selected_user_id = ""; no_chat_label.visible = true; chat_header.visible = false; input_panel.visible = false

func _on_user_status_changed(user_id: String, status: String):
	_user_status_map[user_id] = status
	if _user_item_map.has(user_id) and _user_dot_map.has(user_id):
		var ds = StyleBoxFlat.new(); ds.bg_color = _sc(status); ds.set_corner_radius_all(5); ds.corner_detail = 4
		ds.border_width_left = 2; ds.border_width_right = 2; ds.border_width_top = 2; ds.border_width_bottom = 2; ds.border_color = Color(0.039, 0.039, 0.039, 1)
		_user_dot_map[user_id].add_theme_stylebox_override("panel", ds)
	if user_id == _selected_user_id: chat_status_label.text = _sn(status); chat_status_label.add_theme_color_override("font_color", CLR_GREEN if status == "chat" else _sc(status))

func _on_user_typing(user_id: String, user_name: String, state: String):
	if state == "composing" and user_id == _selected_user_id:
		chat_status_label.text = user_name + " is typing..."; chat_status_label.add_theme_color_override("font_color", CLR_PRIMARY); _typing_timer = 4.0
	elif state in ["paused","active","inactive","gone"] and user_id == _selected_user_id:
		var s = _user_status_map.get(user_id, "chat"); chat_status_label.text = _sn(s); chat_status_label.add_theme_color_override("font_color", CLR_GREEN if s == "chat" else _sc(s))

func _create_user_item(uid: String, name: String) -> Button:
	var btn = Button.new(); btn.flat = true; btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL; btn.custom_minimum_size.y = 44
	btn.add_theme_constant_override("outline_size", 0); btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var nbg = StyleBoxFlat.new(); nbg.bg_color = Color.TRANSPARENT; nbg.set_corner_radius_all(0)
	var hbg = StyleBoxFlat.new(); hbg.bg_color = Color(0,0,0,0.05); hbg.set_corner_radius_all(0)
	var pbg = StyleBoxFlat.new(); pbg.bg_color = Color(0,0,0,0.08); pbg.set_corner_radius_all(0)
	btn.add_theme_stylebox_override("normal", nbg); btn.add_theme_stylebox_override("hover", hbg); btn.add_theme_stylebox_override("pressed", pbg)
	var hbox = HBoxContainer.new(); hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL; hbox.add_theme_constant_override("separation", 8); hbox.mouse_filter = Control.MOUSE_FILTER_PASS; btn.add_child(hbox)
	var avc = Control.new(); avc.custom_minimum_size = Vector2(40, 44); avc.size_flags_vertical = Control.SIZE_SHRINK_CENTER; avc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; avc.mouse_filter = Control.MOUSE_FILTER_PASS; hbox.add_child(avc)
	var av = ColorRect.new(); av.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE); var ac = _gc(name)
	var as_ = StyleBoxFlat.new(); as_.bg_color = ac; as_.set_corner_radius_all(AVATAR_SIZE/2); as_.corner_detail = 6
	av.add_theme_stylebox_override("panel", as_); av.mouse_filter = Control.MOUSE_FILTER_PASS; avc.add_child(av); av.position = Vector2(6,8)
	var dot = ColorRect.new(); dot.custom_minimum_size = Vector2(9,9)
	var ds = StyleBoxFlat.new(); ds.bg_color = CLR_GREEN; ds.set_corner_radius_all(5); ds.corner_detail = 4; ds.border_width_left = 2; ds.border_width_right = 2; ds.border_width_top = 2; ds.border_width_bottom = 2; ds.border_color = Color(0.039, 0.039, 0.039, 1)
	dot.add_theme_stylebox_override("panel", ds); dot.mouse_filter = Control.MOUSE_FILTER_PASS; dot.position = Vector2(24,26); avc.add_child(dot); _user_dot_map[uid] = dot
	var vb = VBoxContainer.new(); vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL; vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER; vb.mouse_filter = Control.MOUSE_FILTER_PASS; hbox.add_child(vb)
	var nl = Label.new(); nl.text = name; nl.add_theme_font_size_override("font_size", 13); nl.add_theme_color_override("font_color", CLR_TEXT); nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; nl.mouse_filter = Control.MOUSE_FILTER_PASS; vb.add_child(nl)
	var sl = Label.new(); sl.text = "Online"; sl.add_theme_font_size_override("font_size", 10); sl.add_theme_color_override("font_color", CLR_GREEN); sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sl.mouse_filter = Control.MOUSE_FILTER_PASS; vb.add_child(sl)
	btn.pressed.connect(func(): _select_user(uid)); btn.gui_input.connect(func(e): _on_user_gui(e, uid)); btn.set_meta("uid", uid)
	if not _search_text.is_empty(): btn.visible = name.to_lower().contains(_search_text.to_lower())
	return btn

func _on_user_gui(e: InputEvent, uid: String):
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
		_context_uid = uid; var m = PopupMenu.new(); m.name = "Ctx"
		m.add_item("Send Message", CTX_MSG); m.add_separator(); m.add_item("User Info", CTX_INFO)
		m.id_pressed.connect(_on_ctx); m.focus_exited.connect(func(): m.queue_free()); add_child(m); m.popup_on_parent(Rect2(get_global_mouse_position(), Vector2(120,10)))

func _on_ctx(id: int):
	match id:
		CTX_MSG: _select_user(_context_uid)
		CTX_INFO: _show_info(_context_uid)

func _show_info(uid: String):
	var u = _user_data_map.get(uid, {}); var n = u.get("name", uid); var s = _user_status_map.get(uid, "chat")
	var a = u.get("address", "Unknown")
	var d = AcceptDialog.new(); d.title = n; d.dialog_text = "Status: " + _sn(s) + "\nAddress: " + a + "\nID: " + uid; d.min_size = Vector2(300,120); d.ok_button_text = "Close"; add_child(d); d.popup_centered()

func _select_user(uid: String):
	if uid.is_empty() or uid == _selected_user_id: return
	_selected_user_id = uid; no_chat_label.visible = false; chat_header.visible = true; input_panel.visible = true; message_input.grab_focus()
	var u = _user_data_map.get(uid, {}); var n = u.get("name", "").strip_edges(); if n.is_empty(): n = uid
	chat_user_name.text = n; var s = _user_status_map.get(uid, "chat"); chat_status_label.text = _sn(s); chat_status_label.add_theme_color_override("font_color", CLR_GREEN if s == "chat" else _sc(s))
	var st = StyleBoxFlat.new(); st.bg_color = _gc(n); st.set_corner_radius_all(AVATAR_SIZE/2); st.corner_detail = 6; chat_avatar.add_theme_stylebox_override("panel", st)
	for u2 in _user_item_map:
		var it = _user_item_map[u2]; var ia = u2 == uid; var ast = StyleBoxFlat.new(); ast.bg_color = CLR_ACTIVE if ia else Color.TRANSPARENT; ast.set_corner_radius_all(0)
		it.add_theme_stylebox_override("normal", ast); it.add_theme_stylebox_override("hover", ast)
	for c in message_vbox.get_children(): c.queue_free()
	if _message_history.has(uid): for e in _message_history[uid]: _add_bubble(e.text, e.is_sent, e.sender, e.time)
	_scroll_bottom()

func _on_search_changed(t: String):
	_search_text = t.strip_edges()
	for uid in _user_item_map:
		var it = _user_item_map[uid]; var u = _user_data_map.get(uid, {}); var n = u.get("name", "").strip_edges(); if n.is_empty(): n = uid
		it.visible = true if _search_text.is_empty() else n.to_lower().contains(_search_text.to_lower())

func _on_send_pressed():
	var text = message_input.text.strip_edges()
	if text.is_empty() or _selected_user_id.is_empty(): return
	if _messaging:
		var xml = XmlMessage.new(); xml.add_data(_D.XN_MESSAGE, text)
		_messaging.send_message(_D.MessageType.MT_Message, _selected_user_id, xml)
	var t = Time.get_time_string_from_system(false)
	_sent_recently[text + t] = true
	_add_to_history(_selected_user_id, text, true, "Me", t)
	_add_bubble(text, true, "Me", t)
	message_input.text = ""; message_input.grab_focus()
	await get_tree().create_timer(2.0).timeout; _sent_recently.erase(text + t)

func _on_message_received(type: int, user_id: String, name: String, body: String):
	if _messaging and _messaging.local_user.get("id", "") == user_id: return
	var t = Time.get_time_string_from_system(false)
	var key = body + t
	if _sent_recently.has(key): return
	_add_to_history(user_id, body, false, name, t)
	if user_id == _selected_user_id: _add_bubble(body, false, name, t)
	if not _has_focus or _hidden_to_tray: _mark_unread(name)

func _add_bubble(text: String, is_sent: bool, sender: String = "", ts: String = ""):
	var row = HBoxContainer.new(); row.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bubble = Panel.new(); bubble.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bc = CLR_BUBBLE_SENT if is_sent else CLR_BUBBLE_RECV; var tc = Color.WHITE if is_sent else CLR_TEXT
	var bs = StyleBoxFlat.new(); bs.bg_color = bc; var cr := 14
	if is_sent: bs.set_corner_radius_all(cr); bs.corner_radius_top_right = 4
	else: bs.set_corner_radius_all(cr); bs.corner_radius_top_left = 4
	bs.corner_detail = 6; bs.content_margin_left = 12; bs.content_margin_right = 12; bs.content_margin_top = 8; bs.content_margin_bottom = 8
	bubble.add_theme_stylebox_override("panel", bs)
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_END

	var content = VBoxContainer.new(); content.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bubble.add_child(content)
	if not is_sent and not sender.is_empty():
		var nl = Label.new(); nl.text = sender; nl.add_theme_font_size_override("font_size", 10); nl.add_theme_color_override("font_color", CLR_PRIMARY); content.add_child(nl)
	var ml = Label.new(); ml.text = text; ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ml.add_theme_color_override("font_color", tc); ml.add_theme_font_size_override("font_size", 12); content.add_child(ml)
	if not ts.is_empty():
		var tl = Label.new(); tl.text = ts; tl.add_theme_font_size_override("font_size", 8); tl.add_theme_color_override("font_color", Color(0.5,0.5,0.5,0.7)); tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; content.add_child(tl)

	if is_sent: var sp = Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(sp)
	row.add_child(bubble)
	if not is_sent: var sp = Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(sp)
	message_vbox.add_child(row); _scroll_bottom()

func _add_to_history(uid: String, text: String, is_sent: bool, sender: String, ts: String):
	if not _message_history.has(uid): _message_history[uid] = []
	_message_history[uid].append({text=text, is_sent=is_sent, sender=sender, time=ts})

func _scroll_bottom():
	await get_tree().process_frame
	message_scroll.scroll_vertical = int(message_scroll.get_v_scroll_bar().max_value)
