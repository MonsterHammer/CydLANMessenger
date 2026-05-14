extends Control
const _D = preload("res://scripts/network/definitions.gd")
const _LanMessenger = preload("res://scripts/network/lan_messenger.gd")

const APP_TITLE := "CydLANMessenger"
const TRAY_MENU_SHOW := 1
const TRAY_MENU_QUIT := 2

@onready var user_list: ItemList = %UserItemList
@onready var chat_log: RichTextLabel = %ChatLog
@onready var message_input: TextEdit = %MessageInput
@onready var send_btn: Button = %SendButton

var _user_id_map: Dictionary = {}
var _messaging: Node = null
var _net_started: bool = false
var _status_indicator: StatusIndicator = null
var _tray_menu: PopupMenu = null
var _allow_quit: bool = false
var _hidden_to_tray: bool = false
var _has_focus: bool = true
var _unread_count: int = 0

func _ready():
	get_tree().set_auto_accept_quit(false)
	DisplayServer.window_set_title(APP_TITLE)
	send_btn.pressed.connect(_on_send_pressed)
	chat_log.text = "CYD LAN Messenger started.\nClick Refresh to start."
	_setup_tray()

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

func _on_refresh_button_pressed():
	if not _net_started:
		_net_start()
	elif _messaging:
		_messaging.refresh()
		chat_log.text += "\nRefreshing..."
	await get_tree().process_frame
	_sync_user_list()

func _net_start():
	var inst = _LanMessenger.new()
	add_child(inst)
	_messaging = inst.messaging
	if not _messaging:
		chat_log.text += "\nNetwork module failed to initialize"
		return
	_net_started = true
	_messaging.user_added.connect(_on_user_added)
	_messaging.user_removed.connect(_on_user_removed)
	_messaging.message_received.connect(_on_message_received)
	chat_log.text += "\nLocal: " + _messaging.local_user.get("name", "unknown")
	_sync_user_list()

func _sync_user_list() -> void:
	if not _messaging:
		return
	for user in _messaging.user_list:
		_on_user_added(user)

func _on_user_added(user: Dictionary):
	var uid = user.get("id", "")
	if uid.is_empty():
		return
	if _user_id_map.has(uid): return
	var name = user.get("name", "").strip_edges()
	var address = user.get("address", "").strip_edges()
	if name.is_empty():
		name = uid
	var label = name
	if not address.is_empty():
		label += " (" + address + ")"
	var idx = user_list.add_item(label)
	_user_id_map[uid] = idx
	chat_log.text += "\n" + label + " connected"

func _on_user_removed(user_id: String):
	if not _user_id_map.has(user_id): return
	var idx = _user_id_map[user_id]
	var name = user_list.get_item_text(idx)
	user_list.remove_item(idx)
	_user_id_map.erase(user_id)
	for key in _user_id_map:
		if _user_id_map[key] > idx:
			_user_id_map[key] -= 1
	chat_log.text += "\n" + name + " disconnected"

func _on_send_pressed():
	var text = message_input.text.strip_edges()
	if text.is_empty(): return
	var sel = user_list.get_selected_items()
	if sel.size() == 0:
		chat_log.text += "\nSelect a user to message"
		return
	var name = user_list.get_item_text(sel[0])
	var uid = ""
	for key in _user_id_map:
		if _user_id_map[key] == sel[0]:
			uid = key
			break
	if _messaging and not uid.is_empty():
		var xml = XmlMessage.new()
		xml.add_data(_D.XN_MESSAGE, text)
		_messaging.send_message(_D.MessageType.MT_Message, uid, xml)
	chat_log.text += "\nMe: " + text
	message_input.text = ""
	message_input.grab_focus()

func _on_message_received(type: int, user_id: String, name: String, body: String):
	chat_log.text += "\n" + name + ": " + body
	if not _has_focus or _hidden_to_tray:
		_mark_unread(name)
