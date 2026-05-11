extends Control

@onready var user_list: ItemList = %UserItemList
@onready var chat_log: RichTextLabel = %ChatLog
@onready var message_input: TextEdit = %MessageInput
@onready var send_btn: Button = %SendButton

var _user_id_map: Dictionary = {}

func _ready():
	send_btn.pressed.connect(_on_send_pressed)

	var msg = LanMessenger.messaging
	if not msg: return

	msg.user_added.connect(_on_user_added)
	msg.user_removed.connect(_on_user_removed)
	msg.message_received.connect(_on_message_received)

	chat_log.text = "[color=#8e9297]CYD LAN Messenger started.\nLocal: %s\nWaiting for peers on port 12111:12112...[/color]" % LanMessenger.messaging.local_user.get("name", "unknown")

	for user in msg.user_list:
		_on_user_added(user)

func _on_user_added(user: Dictionary):
	var uid = user.get("id", "")
	if _user_id_map.has(uid): return
	var name = user.get("name", uid)
	var idx = user_list.add_item(name)
	_user_id_map[uid] = idx
	chat_log.text += "\n[color=#43b581]%s connected (%s)[/color]" % [name, user.get("address", "")]

func _on_user_removed(user_id: String):
	if not _user_id_map.has(user_id): return
	var idx = _user_id_map[user_id]
	var name = user_list.get_item_text(idx)
	user_list.remove_item(idx)
	_user_id_map.erase(user_id)
	for key in _user_id_map:
		if _user_id_map[key] > idx:
			_user_id_map[key] -= 1
	chat_log.text += "\n[color=#f04747]%s disconnected[/color]" % name

func _on_send_pressed():
	var text = message_input.text.strip_edges()
	if text.is_empty(): return
	var sel = user_list.get_selected_items()
	if sel.size() == 0:
		chat_log.text += "\n[color=#faa61a]Select a user to message[/color]"
		return

	var name = user_list.get_item_text(sel[0])
	var uid = ""
	for key in _user_id_map:
		if _user_id_map[key] == sel[0]:
			uid = key
			break

	var msg = LanMessenger.messaging
	if msg and not uid.is_empty():
		var xml = XmlMessage.new()
		xml.add_data(XN_MESSAGE, text)
		msg.send_message(MessageType.MT_Message, uid, xml)

	chat_log.text += "\n[b][color=#f0c644]Me[/color][/b]: " + text
	message_input.text = ""
	message_input.grab_focus()

func _on_message_received(type: int, user_id: String, name: String, body: String):
	if type == MessageType.MT_Broadcast:
		chat_log.text += "\n[color=#faa61a][Broadcast from %s][/color]: %s" % [name, body]
	elif type == MessageType.MT_ChatState:
		chat_log.text += "\n[color=#8e9297]* %s is %s[/color]" % [name, body]
	elif type == MessageType.MT_Status:
		chat_log.text += "\n[color=#8e9297]* %s status: %s[/color]" % [name, body]
	elif type == MessageType.MT_File or type == MessageType.MT_Folder:
		chat_log.text += "\n[color=#00aff4][File from %s]: %s[/color]" % [name, body]
	else:
		chat_log.text += "\n[b][color=#40444b]%s[/color][/b]: %s" % [name, body]
