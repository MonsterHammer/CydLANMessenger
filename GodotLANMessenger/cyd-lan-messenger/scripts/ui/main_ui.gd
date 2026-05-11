extends Control

@onready var user_list: ItemList = %UserItemList
@onready var chat_log: RichTextLabel = %ChatLog
@onready var message_input: TextEdit = %MessageInput
@onready var send_btn: Button = %SendButton

func _ready():
	send_btn.pressed.connect(_on_send_pressed)
	if LanMessenger and LanMessenger.messaging:
		LanMessenger.messaging.message_received.connect(_on_message_received)
		_update_user_list()
		chat_log.text = "CYD LAN Messenger started.\nWaiting for users on network..."

func _on_send_pressed():
	var text = message_input.text.strip_edges()
	if text.is_empty():
		return
	var selected = user_list.get_selected_items()
	if selected.size() == 0:
		return
	var user_name = user_list.get_item_text(selected[0])
	chat_log.text += "\n[color=#f0c644]Me[/color]: " + text
	message_input.text = ""

func _on_message_received(type: int, user_id: String, pMessage):
	var name = pMessage.header(XN_NAME) if pMessage.header_exists(XN_NAME) else user_id
	var body = pMessage.data(XN_MESSAGE) if pMessage.data_exists(XN_MESSAGE) else ""
	chat_log.text += "\n[color=#5865f2]" + name + "[/color]: " + body

func _update_user_list():
	user_list.clear()
	for user in LanMessenger.messaging.user_list:
		user_list.add_item(user.get("name", user.get("id", "Unknown")))
