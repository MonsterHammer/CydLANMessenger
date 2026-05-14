extends Control
const _D = preload("res://scripts/network/definitions.gd")
const _LanMessenger = preload("res://scripts/network/lan_messenger.gd")

@onready var user_list: ItemList = %UserItemList
@onready var chat_log: RichTextLabel = %ChatLog
@onready var message_input: TextEdit = %MessageInput
@onready var send_btn: Button = %SendButton

var _user_id_map: Dictionary = {}
var _messaging: Node = null
var _net_started: bool = false

func _ready():
	send_btn.pressed.connect(_on_send_pressed)
	chat_log.text = "CYD LAN Messenger started.\nClick Refresh to start."

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
