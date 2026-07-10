extends Control
const _D = preload("res://scripts/network/definitions.gd")
const _LanMessenger = preload("res://scripts/network/lan_messenger.gd")
const ChatBubbleScene = preload("res://SubScenes/ChatBubbles.tscn")

const APP_TITLE := "CydLAN Messenger"
const TRAY_MENU_SHOW := 1; const TRAY_MENU_QUIT := 2
const CTX_MSG := 10; const CTX_INFO := 11; const CTX_FILE := 12; const CTX_BCAST := 13
const CLR_PRIMARY := Color("#1877f2"); const CLR_BUBBLE_SENT := Color("#e7f3ff")
const CLR_BUBBLE_RECV := Color("#ffffff"); const CLR_TEXT := Color("#050505")
const CLR_GREEN := Color("#42b72a"); const CLR_ACTIVE := Color("#1877f2")
const CLR_ST := {"chat": Color("#42b72a"),"busy": Color("#e4a61a"),"dnd": Color("#e4a61a"),"brb": Color("#ff8a00"),"away": Color("#ff8a00"),"gone": Color("#8a8d91")}
const ST_NAMES := {"chat":"Online","busy":"Busy","dnd":"Do Not Disturb","brb":"Be Right Back","away":"Away","gone":"Offline"}
const ST_CODES := ["chat","busy","dnd","brb","away","gone"]
const SMILEYS := {":)":"😊",":D":"😄",":(":"😢",";)":"😉",":p":"😋",":P":"😋",":o":"😮",":O":"😮",":/":"😕",":|":"😐",":'(":"😢",":')":"😂","<3":"❤️","</3":"💔","^^":"😊",":*)":"😳","%-)":"🤔","B)":"😎","8)":"😎",":-?":"🤔"}
const AVATAR_SIZE := 28; const HIST_FILE := "user://chat_history.json"
const CHAT_BUBBLE_MAX_WIDTH_RATIO := 0.75
const SENT_ECHO_IGNORE_SECONDS := 3.0

@onready var title_bar: Panel = %TitleBar
@onready var minimize_btn: Button = %MinimizeBtn; @onready var maximize_btn: Button = %MaximizeBtn; @onready var close_btn: Button = %CloseBtn
@onready var user_vbox: VBoxContainer = %UserVBox; @onready var search_input: LineEdit = %SearchInput
@onready var input_panel = %InputPanel
@onready var message_vbox: VBoxContainer = %MessageVBox; @onready var message_scroll: ScrollContainer = %MessageScroll
@onready var message_input: TextEdit = %MessageInput; @onready var send_btn: Button = %SendButton
@onready var chat_header = %ChatHeader; @onready var chat_user_name: Label = %ChatUserName
@onready var chat_status_label: Label = %ChatStatus; @onready var chat_avatar: ColorRect = %ChatAvatar
@onready var no_chat_label: Label = %NoChatLabel

var _user_item_map: Dictionary = {}; var _user_data_map: Dictionary = {}; var _user_avatar_colors: Dictionary = {}; var _user_avatar_rect_map: Dictionary = {}
var _user_dot_map: Dictionary = {}; var _user_status_map: Dictionary = {}; var _sent_recently: Dictionary = {}
var _messaging: Node = null; var _net_started: bool = false; var _status_indicator: StatusIndicator = null
var _tray_menu: PopupMenu = null; var _allow_quit: bool = false; var _hidden_to_tray: bool = false
var _has_focus: bool = true; var _unread_count: int = 0; var _selected_user_id: String = ""
var _search_text: String = ""; var _message_history: Dictionary = {}; var _maximized: bool = false
var _pre_maximize_rect: Rect2i = Rect2i(); var _dragging: bool = false; var _drag_offset: Vector2 = Vector2()
var _context_uid: String = ""; var _local_status: String = "chat"; var _typing_timer: float = 0.0
var _status_btn: Button = null; var _history_dirty: bool = false

func _ready():
	get_tree().set_auto_accept_quit(false); get_window().min_size = Vector2i(400, 300)
	_setup_window(); _setup_signals(); _setup_tray(); _load_history()
	no_chat_label.visible = true; chat_header.visible = false; input_panel.visible = false
	DisplayServer.window_set_title(APP_TITLE); _setup_status_button(); call_deferred("_on_refresh_button_pressed")

func _setup_window():
	var win = get_window(); win.size = Vector2i(700, 500)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	var ss = DisplayServer.screen_get_size()
	DisplayServer.window_set_position(Vector2i(ss.x / 2 - win.size.x / 2, ss.y / 2 - win.size.y / 2))
	var t = load("res://icon.svg")
	if t: var img = t.get_image(); if img: DisplayServer.set_icon(img)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			if _history_dirty: _save_history()
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

func _setup_status_button():
	_status_btn = Button.new(); _status_btn.flat = true; _status_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_status_btn.add_theme_color_override("font_color", CLR_GREEN); _status_btn.add_theme_font_size_override("font_size", 11)
	_status_btn.text = "● Online"; _status_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var sidebar_header = title_bar.get_node("../BodyHBox/LeftSidebar/SidebarVBox/SearchHBox")
	sidebar_header.add_child(_status_btn)
	_status_btn.pressed.connect(_show_status_menu)

func _show_status_menu():
	var m = PopupMenu.new(); m.name = "StatusMenu"
	for i in range(ST_CODES.size()):
		var code = ST_CODES[i]; var label = ST_NAMES[code]; var dot = ""
		if code == "chat": dot = "● "
		elif code in ["busy","dnd"]: dot = "● "
		elif code in ["brb","away"]: dot = "● "
		else: dot = "● "
		m.add_item(dot + label, i)
		if code == _local_status: m.set_item_checked(i, true)
	m.id_pressed.connect(func(id): _change_status(ST_CODES[id]))
	m.focus_exited.connect(func(): m.queue_free())
	add_child(m); m.popup_on_parent(Rect2(_status_btn.global_position + Vector2(0, 20), Vector2(160, 10)))

func _change_status(code: String):
	_local_status = code; _status_btn.text = "● " + ST_NAMES[code]
	var clr = CLR_ST.get(code, CLR_GREEN)
	_status_btn.add_theme_color_override("font_color", clr)
	if _messaging:
		_messaging.local_user["status"] = code
		print("CydLAN: Status change to ", code, " user_list has ", _messaging.user_list.size(), " users")
		for u in _messaging.user_list:
			var xml = XmlMessage.new(); xml.add_data(_D.XN_STATUS, code)
			print("CydLAN: Sending status to ", u.get("id", "???"))
			_messaging.send_message(_D.MessageType.MT_Status, u["id"], xml)
		var bxml = XmlMessage.new(); bxml.add_data(_D.XN_STATUS, code)
		var sz = Message.add_header(_D.MessageType.MT_Status, 0, _messaging.local_user.get("id", ""), "", bxml)
		if _messaging.network and _messaging.network.has_method("send_broadcast"):
			_messaging.network.send_broadcast(sz)

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
	if _unread_count > 0: var d = " unread message"; if _unread_count != 1: d += "s"; _status_indicator.tooltip = APP_TITLE + "\n" + str(_unread_count) + d + (("\nLatest: " + n) if not n.is_empty() else "")
	else: _status_indicator.tooltip = APP_TITLE

func _gc(n: String) -> Color: return _user_avatar_colors.get(n) if _user_avatar_colors.has(n) else Color.from_hsv(abs(n.hash()) % 360 / 360.0, 0.45, 0.7)
func _sc(s: String) -> Color: return CLR_ST.get(s, CLR_GREEN)
func _sn(s: String) -> String: return ST_NAMES.get(s, "Online")

func _parse_smileys(text: String) -> String:
	var r = text
	for code in SMILEYS: r = r.replace(code, SMILEYS[code])
	return r

func _display_name(user: Dictionary, uid: String = "") -> String:
	var name = str(user.get("name", "")).strip_edges()
	if not name.is_empty() and name != uid:
		return name
	var clean_uid = uid.strip_edges()
	while not clean_uid.is_empty() and _is_hex_prefix_char(clean_uid.substr(0, 1)):
		clean_uid = clean_uid.substr(1)
	return clean_uid if not clean_uid.is_empty() else uid

func _is_hex_prefix_char(value: String) -> bool:
	return value.is_valid_int() or value in ["A", "B", "C", "D", "E", "F", "a", "b", "c", "d", "e", "f"]

func _apply_avatar(target: ColorRect, uid: String, fallback_name: String) -> void:
	var user = _user_data_map.get(uid, {})
	target.color = _gc(fallback_name)
	var style = StyleBoxFlat.new()
	style.bg_color = target.color
	style.set_corner_radius_all(AVATAR_SIZE / 2)
	style.corner_detail = 6
	target.add_theme_stylebox_override("panel", style)
	var texture_rect = target.get_node_or_null("AvatarTexture") as TextureRect
	if not texture_rect:
		texture_rect = TextureRect.new()
		texture_rect.name = "AvatarTexture"
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		target.add_child(texture_rect)
	var texture = _load_avatar_texture(uid, int(user.get("avatar", 0)))
	texture_rect.texture = texture
	texture_rect.visible = texture != null
	if texture:
		target.color = Color.TRANSPARENT
		style.bg_color = Color.TRANSPARENT
		target.add_theme_stylebox_override("panel", style)

func _load_avatar_texture(uid: String, avatar_id: int = 0) -> Texture2D:
	for path in _avatar_paths(uid, avatar_id):
		if FileAccess.file_exists(path):
			var image = Image.new()
			if image.load(path) == OK:
				return ImageTexture.create_from_image(image)
	return null

func _avatar_paths(uid: String, avatar_id: int = 0) -> Array[String]:
	var paths: Array[String] = [
		"user://cache/avt_" + uid + ".png",
		"res://Assets/Avatars/avatar_" + str(avatar_id) + ".png"
	]
	if OS.get_name() == "Windows":
		var local_app_data = OS.get_environment("LOCALAPPDATA")
		if not local_app_data.is_empty():
			var original_dir = local_app_data.path_join("LAN Messenger").path_join("LAN Messenger")
			paths.append(original_dir.path_join("cache").path_join("avt_" + uid + ".png"))
	paths.append("res://Assets/Avatars/avatar_default.png")
	return paths

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
	if _messaging.has_signal("user_avatar_changed"): _messaging.user_avatar_changed.connect(_on_user_avatar_changed)
	_sync_existing_users()

func _sync_existing_users(): if _messaging: for u in _messaging.user_list: _on_user_added(u)

func _on_user_added(user: Dictionary):
	var uid = user.get("id", "")
	if uid.is_empty() or _user_item_map.has(uid): return
	var name = _display_name(user, uid)
	_user_data_map[uid] = user; _user_status_map[uid] = user.get("status", "chat")
	var item = _create_user_item(uid, name); user_vbox.add_child(item); _user_item_map[uid] = item

func _on_user_removed(user_id: String):
	if _user_item_map.has(user_id):
		var item = _user_item_map[user_id]; user_vbox.remove_child(item); item.queue_free()
		_user_item_map.erase(user_id); _user_data_map.erase(user_id); _user_dot_map.erase(user_id); _user_avatar_rect_map.erase(user_id)
	if _selected_user_id == user_id: _selected_user_id = ""; no_chat_label.visible = true; chat_header.visible = false; input_panel.visible = false

func _on_user_avatar_changed(user_id: String) -> void:
	if _user_avatar_rect_map.has(user_id):
		var user = _user_data_map.get(user_id, {})
		_apply_avatar(_user_avatar_rect_map[user_id], user_id, _display_name(user, user_id))
	if user_id == _selected_user_id:
		var user = _user_data_map.get(user_id, {})
		_apply_avatar(chat_avatar, user_id, _display_name(user, user_id))

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
	_user_avatar_rect_map[uid] = av; _apply_avatar(av, uid, name)
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
		m.add_item("Send Message", CTX_MSG); m.add_separator(); m.add_item("Send File", CTX_FILE); m.add_separator(); m.add_item("User Info", CTX_INFO)
		m.id_pressed.connect(_on_ctx); m.focus_exited.connect(func(): m.queue_free()); add_child(m); m.popup_on_parent(Rect2(get_global_mouse_position(), Vector2(120,10)))

func _on_ctx(id: int):
	match id:
		CTX_MSG: _select_user(_context_uid)
		CTX_FILE: _send_file_to(_context_uid)
		CTX_INFO: _show_info(_context_uid)

func _send_file_to(uid: String):
	var u = _user_data_map.get(uid, {}); var n = _display_name(u, uid)
	DisplayServer.file_dialog_show("Select file to send to " + n, "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, [], func(ok, files, _f):
		if ok and files.size() > 0 and _messaging:
			var path = files[0]; var fa = FileAccess.open(path, FileAccess.READ)
			var sz := 0
			if fa: sz = fa.get_length(); fa.close()
			var xml = XmlMessage.new(); xml.add_data(_D.XN_FILEPATH, path)
			xml.add_data(_D.XN_FILENAME, path.get_file()); xml.add_data(_D.XN_FILESIZE, str(sz))
			xml.add_data(_D.XN_FILETYPE, _D.FileTypeNames[_D.FileType.FT_Normal])
			_messaging.send_message(_D.MessageType.MT_File, uid, xml)
			_add_bubble("[File] " + path.get_file(), true, "Me")
	)

func _show_info(uid: String):
	var u = _user_data_map.get(uid, {}); var n = _display_name(u, uid); var s = _user_status_map.get(uid, "chat")
	var a = u.get("address", "Unknown"); var v = u.get("version", "?")
	var d = AcceptDialog.new(); d.title = n; d.dialog_text = "Status: " + _sn(s) + "\nAddress: " + a + "\nVersion: " + v + "\nID: " + uid; d.min_size = Vector2(300,140); d.ok_button_text = "Close"; add_child(d); d.popup_centered()

func _select_user(uid: String):
	if uid.is_empty() or uid == _selected_user_id: return
	_selected_user_id = uid; no_chat_label.visible = false; chat_header.visible = true; input_panel.visible = true; message_input.grab_focus()
	var u = _user_data_map.get(uid, {}); var n = _display_name(u, uid)
	chat_user_name.text = n; var s = _user_status_map.get(uid, "chat"); chat_status_label.text = _sn(s); chat_status_label.add_theme_color_override("font_color", CLR_GREEN if s == "chat" else _sc(s))
	_apply_avatar(chat_avatar, uid, n)
	for u2 in _user_item_map: var it = _user_item_map[u2]; var ia = u2 == uid; var ast = StyleBoxFlat.new(); ast.bg_color = CLR_ACTIVE if ia else Color.TRANSPARENT; ast.set_corner_radius_all(0); it.add_theme_stylebox_override("normal", ast); it.add_theme_stylebox_override("hover", ast)
	for c in message_vbox.get_children(): c.queue_free()
	if _message_history.has(uid): for e in _message_history[uid]: _add_bubble(e.text, e.is_sent, e.sender, e.time)
	_scroll_bottom()

func _on_search_changed(t: String):
	_search_text = t.strip_edges()
	for uid in _user_item_map: var it = _user_item_map[uid]; var u = _user_data_map.get(uid, {}); var n = _display_name(u, uid); it.visible = true if _search_text.is_empty() else n.to_lower().contains(_search_text.to_lower())

func _on_send_pressed():
	var text = message_input.text.strip_edges()
	if text.is_empty() or _selected_user_id.is_empty(): return
	if _messaging:
		var xml = XmlMessage.new(); xml.add_data(_D.XN_MESSAGE, text)
		_messaging.send_message(_D.MessageType.MT_Message, _selected_user_id, xml)
	var t = Time.get_time_string_from_system(false)
	_sent_recently[text] = Time.get_unix_time_from_system() + SENT_ECHO_IGNORE_SECONDS
	var display = _parse_smileys(text)
	_add_to_history(_selected_user_id, display, true, "Me", t)
	_add_bubble(display, true, "Me", t)
	message_input.text = ""; message_input.grab_focus()
	await get_tree().create_timer(SENT_ECHO_IGNORE_SECONDS).timeout
	if _sent_recently.get(text, 0.0) <= Time.get_unix_time_from_system(): _sent_recently.erase(text)

func _on_message_received(type: int, user_id: String, name: String, body: String):
	if _messaging and _messaging.local_user.get("id", "") == user_id: return
	if type == _D.MessageType.MT_File or type == _D.MessageType.MT_Folder: return
	var t = Time.get_time_string_from_system(false)
	if _sent_recently.get(body, 0.0) > Time.get_unix_time_from_system(): return
	var display = _parse_smileys(body)
	_add_to_history(user_id, display, false, name, t)
	if user_id == _selected_user_id: _add_bubble(display, false, name, t)
	if not _has_focus or _hidden_to_tray: _mark_unread(name)

func _add_bubble(text: String, is_sent: bool, sender: String = "", ts: String = ""):
	if ts.is_empty(): ts = Time.get_time_string_from_system(false)
	var row = HBoxContainer.new(); row.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_theme_constant_override("separation", 0)
	var bubble = ChatBubbleScene.instantiate()
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_END
	bubble.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bubble.configure(text, is_sent, ts, message_scroll.size.x * CHAT_BUBBLE_MAX_WIDTH_RATIO)
	if is_sent: var sp = Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(sp)
	row.add_child(bubble)
	if not is_sent: var sp = Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(sp)
	message_vbox.add_child(row); _scroll_bottom()

func _add_to_history(uid: String, text: String, is_sent: bool, sender: String, ts: String):
	if not _message_history.has(uid): _message_history[uid] = []
	_message_history[uid].append({text=text, is_sent=is_sent, sender=sender, time=ts})
	_history_dirty = true

func _load_history():
	if not FileAccess.file_exists(HIST_FILE): return
	var f = FileAccess.open(HIST_FILE, FileAccess.READ)
	if not f: return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) == TYPE_DICTIONARY: _message_history = data

func _save_history():
	var f = FileAccess.open(HIST_FILE, FileAccess.WRITE)
	if f: f.store_string(JSON.new().stringify(_message_history)); f.close(); _history_dirty = false

func _scroll_bottom(): await get_tree().process_frame; message_scroll.scroll_vertical = int(message_scroll.get_v_scroll_bar().max_value)
