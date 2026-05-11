extends Node

signal user_added(user)
signal user_removed(user_id)
signal message_received(type, user_id, user_name, body)
signal connection_state_changed

var local_user: Dictionary = {}
var user_list: Array = []
var group_list: Array = []

var network: Node = null
var _settings: Dictionary = {}
var _msg_id: int = 0
var _received_list: Array = []
var _pending_list: Array = []
var _file_list: Array = []
var _folder_list: Array = []
var _loopback: bool = false
var _user_group_map: Dictionary = {}
var _started: bool = false

func init_config(settings: Dictionary = {}) -> void:
	_settings = settings

func start() -> void:
	if not network: return
	network.broadcast_received.connect(_receive_broadcast)
	network.new_connection.connect(_on_new_connection)
	network.connection_lost.connect(_on_connection_lost)
	network.message_received.connect(_receive_message)
	network.progress_received.connect(_receive_progress)
	network.web_message_received.connect(_receive_web_message)
	network.connection_state_changed.connect(_on_network_state_changed)
	network.start()
	_started = true
	_send_announce()

func stop() -> void:
	_started = false
	if network: network.stop()

func is_connected() -> bool:
	return network.is_connected if network else false

func can_receive() -> bool:
	return network.can_receive if network else false

func get_user(user_id: String) -> Dictionary:
	for u in user_list:
		if u["id"] == user_id: return u
	return {}

func send_message(msg_type: int, user_id: String, pMessage: XmlMessage) -> void:
	if not _started: return
	_msg_id += 1
	var mid = _msg_id
	_prepare_message(msg_type, mid, false, user_id, pMessage)
	_add_pending_msg(mid, msg_type, user_id, pMessage)

func send_web_message(msg_type: int, pMessage: XmlMessage) -> void:
	if not network: return
	_msg_id += 1
	var mid = _msg_id
	var sz = Message.add_header(msg_type, mid, _local_id(), "", pMessage)
	network.send_web_message("", sz)

func settings_changed() -> void:
	if network: network.settings_changed()

func user_count() -> int:
	return user_list.size()

# -- Internal: Broadcast handling --

func _send_announce() -> void:
	_msg_id += 1
	var msg = XmlMessage.new()
	msg.add_data(XN_NAME, local_user.get("name", ""))
	msg.add_data(XN_VERSION, local_user.get("version", ""))
	msg.add_data(XN_ADDRESS, local_user.get("address", ""))
	msg.add_data(XN_STATUS, local_user.get("status", ""))
	msg.add_data(XN_AVATAR, str(local_user.get("avatar", 0)))
	msg.add_data(XN_NOTE, local_user.get("note", ""))
	msg.add_data(XN_USERCAPS, str(local_user.get("caps", 0)))
	msg.add_data(XN_GROUP, local_user.get("group", "General"))
	_prepare_message(MessageType.MT_Announce, _msg_id, false, "", msg)

func _receive_broadcast(pHeader, data: String) -> void:
	var msg = XmlMessage.new(data)
	if not msg.is_valid():
		return
	var type_str = msg.header(XN_TYPE)
	var type_idx = Helper.index_of(MessageTypeNames, type_str)
	if type_idx < 0: return

	match type_idx:
		MessageType.MT_Announce:
			_process_announce(msg, pHeader["address"])
		MessageType.MT_Depart:
			_process_depart(msg)
		MessageType.MT_Broadcast:
			_process_broadcast_msg(msg, msg.header(XN_FROM))

func _process_announce(pMessage: XmlMessage, address: String) -> void:
	var user_id = pMessage.header(XN_FROM)
	if user_id.is_empty(): return
	if user_id == _local_id(): return

	var user_name = pMessage.data(XN_NAME)
	var version = pMessage.data(XN_VERSION)
	var status = pMessage.data(XN_STATUS)
	var avatar = pMessage.data(XN_AVATAR)
	var note = pMessage.data(XN_NOTE)
	var caps = pMessage.data(XN_USERCAPS)
	var group = pMessage.data(XN_GROUP)

	_add_user(user_id, version, address, user_name, status, avatar, note, caps, group)
	user_added.emit({ "id": user_id, "name": user_name, "address": address, "status": status })
	network.add_connection(user_id, address)

func _process_depart(pMessage: XmlMessage) -> void:
	var user_id = pMessage.header(XN_FROM)
	if user_id.is_empty(): return
	_remove_user(user_id)
	user_removed.emit(user_id)

func _process_broadcast_msg(pMessage: XmlMessage, user_id: String) -> void:
	var body = pMessage.data(XN_BROADCAST) if pMessage.data_exists(XN_BROADCAST) else pMessage.data(XN_MESSAGE)
	var sender = get_user(user_id)
	var name = sender.get("name", user_id) if not sender.is_empty() else user_id
	message_received.emit(MessageType.MT_Broadcast, user_id, name, body)

# -- Internal: Direct message handling --

func _prepare_message(type: int, msg_id: int, retry: bool, user_id: String, pMessage: XmlMessage) -> void:
	if not pMessage:
		pMessage = XmlMessage.new()
	var sz = Message.add_header(type, msg_id, _local_id(), user_id, pMessage)
	if type == MessageType.MT_Announce or type == MessageType.MT_Depart:
		network.send_broadcast(sz)
	else:
		var user = get_user(user_id)
		var address = user.get("address", "")
		network.send_message(user_id, address, sz)

func _receive_message(pHeader, data: String) -> void:
	var header = Message.get_header(data)
	if header.is_empty(): return
	if not _add_received_msg(header["id"], header["userId"]):
		return
	_process_message(header["type"], header)

func _process_message(msg_type: int, pHeader) -> void:
	var pMessage = pHeader.get("message")
	if not pMessage: return
	var uid = pHeader["userId"]
	var user = get_user(uid)
	var name = user.get("name", uid) if not user.is_empty() else uid

	match msg_type:
		MessageType.MT_Message:
			var body = pMessage.data(XN_MESSAGE)
			message_received.emit(msg_type, uid, name, body)
		MessageType.MT_GroupMessage:
			var body = pMessage.data(XN_GROUPMESSAGE) if pMessage.data_exists(XN_GROUPMESSAGE) else pMessage.data(XN_MESSAGE)
			message_received.emit(msg_type, uid, name, body)
		MessageType.MT_PublicMessage:
			var body = pMessage.data(XN_MESSAGE)
			message_received.emit(msg_type, uid, name, body)
		MessageType.MT_Status:
			_update_user(uid, "status", pMessage.data(XN_STATUS))
		MessageType.MT_UserName:
			_update_user(uid, "name", pMessage.data(XN_NAME))
		MessageType.MT_Note:
			_update_user(uid, "note", pMessage.data(XN_NOTE))
		MessageType.MT_ChatState:
			message_received.emit(msg_type, uid, name, pMessage.data(XN_CHATSTATE))
		MessageType.MT_File, MessageType.MT_Folder:
			var fid = pMessage.data(XN_FILEID)
			var ftype_str = pMessage.data(XN_FILETYPE)
			var mode_str = pMessage.data(XN_MODE)
			var op_str = pMessage.data(XN_FILEOP)
			message_received.emit(msg_type, uid, name, op_str)
		MessageType.MT_UserData:
			var qop = pMessage.data(XN_QUERYOP)
			if qop == QueryOpNames[QueryOp.QO_Get]:
				_prepare_message(MessageType.MT_UserData, _msg_id + 1, false, uid, _build_user_data_reply())
				_msg_id += 1
			elif qop == QueryOpNames[QueryOp.QO_Result]:
				var av = pMessage.data(XN_AVATAR)
				pMessage.remove_header(XN_TIME)
				message_received.emit(msg_type, uid, name, pMessage.to_string())

func _build_user_data_reply() -> XmlMessage:
	var msg = XmlMessage.new()
	msg.add_header(XN_TYPE, MessageTypeNames[MessageType.MT_UserData])
	msg.add_data(XN_QUERYOP, QueryOpNames[QueryOp.QO_Result])
	msg.add_data(XN_NAME, local_user.get("name", ""))
	msg.add_data(XN_VERSION, local_user.get("version", ""))
	msg.add_data(XN_STATUS, local_user.get("status", ""))
	msg.add_data(XN_AVATAR, str(local_user.get("avatar", 0)))
	msg.add_data(XN_NOTE, local_user.get("note", ""))
	msg.add_data(XN_USERCAPS, str(local_user.get("caps", 0)))
	return msg

# -- Internal: File handling --

func _prepare_file(type: int, msg_id: int, retry: bool, user_id: String, pMessage: XmlMessage) -> void:
	var user = get_user(user_id)
	var sz = Message.add_header(type, msg_id, _local_id(), user_id, pMessage)
	network.init_send_file(user_id, user.get("address", ""), sz)

# -- Internal: User management --

func _add_user(uid, version, address, name, status, avatar, note, caps, group_name = "") -> bool:
	if uid == _local_id(): return false
	for u in user_list:
		if u["id"] == uid:
			u["address"] = address
			u["name"] = name
			u["status"] = status
			return false
	user_list.append({
		"id": uid, "version": version, "address": address,
		"name": name, "status": status,
		"avatar": int(avatar) if avatar.is_valid_int() else 0,
		"group": group_name, "note": note, "caps": int(caps) if caps.is_valid_int() else 0
	})
	return true

func _update_user(uid: String, field: String, value: String) -> void:
	for i in range(user_list.size()):
		if user_list[i]["id"] == uid:
			user_list[i][field] = value
			return

func _remove_user(uid: String) -> void:
	for i in range(user_list.size() - 1, -1, -1):
		if user_list[i]["id"] == uid:
			user_list.remove_at(i)
			return

# -- Internal: Message tracking --

func _add_received_msg(msg_id: int, user_id: String) -> bool:
	for r in _received_list:
		if r["msgId"] == msg_id and r["userId"] == user_id: return false
	_received_list.append({ "msgId": msg_id, "userId": user_id })
	if _received_list.size() > 100:
		_received_list.pop_front()
	return true

func _add_pending_msg(msg_id: int, type: int, user_id: String, pMessage: XmlMessage) -> void:
	_pending_list.append({
		"msgId": msg_id, "active": false,
		"type": type, "userId": user_id, "xmlMessage": pMessage, "retry": 0
	})

func _remove_pending_msg(msg_id: int) -> void:
	for i in range(_pending_list.size() - 1, -1, -1):
		if _pending_list[i]["msgId"] == msg_id:
			_pending_list.remove_at(i)
			return

func _remove_all_pending_msg(user_id: String) -> void:
	for i in range(_pending_list.size() - 1, -1, -1):
		if _pending_list[i]["userId"] == user_id:
			_pending_list.remove_at(i)

# -- Signal handlers from network --

func _on_new_connection(user_id: String, address: String) -> void:
	for u in user_list:
		if u["id"] == user_id:
			u["address"] = address
			return

func _on_connection_lost(user_id: String) -> void:
	_remove_all_pending_msg(user_id)

func _receive_progress(user_id: String, data: String) -> void:
	var msg = XmlMessage.new(data)
	var uid = msg.header(XN_FROM)
	var user = get_user(uid)
	var name = user.get("name", uid)
	message_received.emit(MessageType.MT_File, uid, name, msg.to_string())

func _receive_web_message(data: String) -> void:
	message_received.emit(MessageType.MT_WebFailed, "", "", data)

func _on_network_state_changed() -> void:
	connection_state_changed.emit()

func _local_id() -> String:
	return local_user.get("id", "")
