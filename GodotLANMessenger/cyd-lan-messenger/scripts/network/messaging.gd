extends Node
const _D = preload("res://scripts/network/definitions.gd")

signal user_added(user)
signal user_removed(user_id)
signal message_received(type, user_id, user_name, body)
signal user_status_changed(user_id, status)
signal user_typing(user_id, user_name, state)
signal connection_state_changed
signal user_avatar_changed(user_id)

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
var _avatar_send_map: Dictionary = {}
var _loopback: bool = false
var _user_group_map: Dictionary = {}
var _started: bool = false
var _announce_pending: bool = false

func init_config(settings: Dictionary = {}) -> void:
	_settings = settings
	if network:
		network.init_config(_settings)

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
	_announce_pending = true

func _process(delta):
	if _announce_pending:
		_announce_pending = false
		_send_announce()

func stop() -> void:
	_started = false
	if network: network.stop()

func network_is_connected() -> bool:
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

func refresh() -> void:
	if _started:
		_send_announce()
		for u in user_list:
			send_message(_D.MessageType.MT_Ping, u["id"], XmlMessage.new())

func settings_changed() -> void:
	if network: network.settings_changed()

func user_count() -> int:
	return user_list.size()

# -- Internal: Broadcast handling --

func _send_announce() -> void:
	_msg_id += 1
	var msg = XmlMessage.new()
	msg.add_data(_D.XN_NAME, local_user.get("name", ""))
	msg.add_data(_D.XN_VERSION, local_user.get("version", ""))
	msg.add_data(_D.XN_ADDRESS, local_user.get("address", ""))
	msg.add_data(_D.XN_STATUS, local_user.get("status", ""))
	msg.add_data(_D.XN_AVATAR, str(local_user.get("avatar", 0)))
	msg.add_data(_D.XN_NOTE, local_user.get("note", ""))
	msg.add_data(_D.XN_USERCAPS, str(local_user.get("caps", 0)))
	msg.add_data(_D.XN_GROUP, local_user.get("group", "General"))
	_prepare_message(_D.MessageType.MT_Announce, _msg_id, false, "", msg)

func _receive_broadcast(pHeader, data: String) -> void:
	var msg = XmlMessage.new(data)
	if not msg.is_valid():
		return
	var type_str = msg.header(_D.XN_TYPE)
	var type_idx = Helper.index_of(_D.MessageTypeNames, type_str)
	if type_idx < 0: return

	match type_idx:
		_D.MessageType.MT_Announce:
			_process_announce(msg, pHeader["address"])
		_D.MessageType.MT_Depart:
			_process_depart(msg)
		_D.MessageType.MT_Broadcast:
			_process_broadcast_msg(msg, msg.header(_D.XN_FROM))
		_D.MessageType.MT_Status:
			var uid = msg.header(_D.XN_FROM)
			if uid.is_empty() or uid == _local_id(): return
			var new_status = msg.data(_D.XN_STATUS)
			_update_user(uid, "status", new_status)
			user_status_changed.emit(uid, new_status)

func _process_announce(pMessage: XmlMessage, address: String) -> void:
	var user_id = pMessage.header(_D.XN_FROM)
	if user_id.is_empty(): return
	if user_id == _local_id(): return
	print("CydLAN: Processing announce from ", user_id, " at ", address)

	var user_name = pMessage.data(_D.XN_NAME)
	var version = pMessage.data(_D.XN_VERSION)
	var status = pMessage.data(_D.XN_STATUS)
	var avatar = pMessage.data(_D.XN_AVATAR)
	var note = pMessage.data(_D.XN_NOTE)
	var caps = pMessage.data(_D.XN_USERCAPS)
	var group = pMessage.data(_D.XN_GROUP)

	if user_name.is_empty():
		user_name = user_id
	var was_added = _add_user(user_id, version, address, user_name, status, avatar, note, caps, group)
	if was_added:
		user_added.emit({ "id": user_id, "name": user_name, "address": address, "status": status })
	network.add_connection.call_deferred(user_id, address)

func _process_depart(pMessage: XmlMessage) -> void:
	var user_id = pMessage.header(_D.XN_FROM)
	if user_id.is_empty(): return
	_remove_user(user_id)
	user_removed.emit(user_id)

func _process_broadcast_msg(pMessage: XmlMessage, user_id: String) -> void:
	var body = pMessage.data(_D.XN_BROADCAST) if pMessage.data_exists(_D.XN_BROADCAST) else pMessage.data(_D.XN_MESSAGE)
	var sender = get_user(user_id)
	var name = sender.get("name", user_id) if not sender.is_empty() else user_id
	message_received.emit(_D.MessageType.MT_Broadcast, user_id, name, body)

# -- Internal: Direct message handling --

func _prepare_message(type: int, msg_id: int, retry: bool, user_id: String, pMessage: XmlMessage) -> void:
	if not pMessage:
		pMessage = XmlMessage.new()
	var sz = Message.add_header(type, msg_id, _local_id(), user_id, pMessage)
	if type == _D.MessageType.MT_Announce or type == _D.MessageType.MT_Depart:
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
		_D.MessageType.MT_Message:
			var body = pMessage.data(_D.XN_MESSAGE)
			message_received.emit(msg_type, uid, name, body)
			_send_acknowledge(uid, pHeader["id"])
		_D.MessageType.MT_GroupMessage:
			var body = pMessage.data(_D.XN_GROUPMESSAGE) if pMessage.data_exists(_D.XN_GROUPMESSAGE) else pMessage.data(_D.XN_MESSAGE)
			message_received.emit(msg_type, uid, name, body)
		_D.MessageType.MT_PublicMessage:
			var body = pMessage.data(_D.XN_MESSAGE)
			message_received.emit(msg_type, uid, name, body)
		_D.MessageType.MT_Status:
			var new_status = pMessage.data(_D.XN_STATUS)
			_update_user(uid, "status", new_status)
			user_status_changed.emit(uid, new_status)
		_D.MessageType.MT_UserName:
			_update_user(uid, "name", pMessage.data(_D.XN_NAME))
		_D.MessageType.MT_Note:
			_update_user(uid, "note", pMessage.data(_D.XN_NOTE))
		_D.MessageType.MT_ChatState:
			var state = pMessage.data(_D.XN_CHATSTATE)
			user_typing.emit(uid, name, state)
		_D.MessageType.MT_File, _D.MessageType.MT_Folder:
			var fid = pMessage.data(_D.XN_FILEID)
			var ftype_str = pMessage.data(_D.XN_FILETYPE)
			var mode_str = pMessage.data(_D.XN_MODE)
			var op_str = pMessage.data(_D.XN_FILEOP)
			if ftype_str == _D.FileTypeNames[_D.FileType.FT_Avatar]:
				_process_avatar_file(uid, pMessage, fid, mode_str, op_str)
				return
			message_received.emit(msg_type, uid, name, op_str)
		_D.MessageType.MT_UserData:
			var qop = pMessage.data(_D.XN_QUERYOP)
			if qop == _D.QueryOpNames[_D.QueryOp.QO_Get]:
				_prepare_message(_D.MessageType.MT_UserData, _msg_id + 1, false, uid, _build_user_data_reply())
				_msg_id += 1
			elif qop == _D.QueryOpNames[_D.QueryOp.QO_Result]:
				_process_user_data_result(uid, pMessage)
		_D.MessageType.MT_Ping:
			_send_acknowledge(uid, pHeader["id"])
		_D.MessageType.MT_Acknowledge:
			_remove_pending_msg(int(pMessage.data(_D.XN_MESSAGEID)))

func _build_user_data_reply() -> XmlMessage:
	var msg = XmlMessage.new()
	msg.add_header(_D.XN_TYPE, _D.MessageTypeNames[_D.MessageType.MT_UserData])
	msg.add_data(_D.XN_QUERYOP, _D.QueryOpNames[_D.QueryOp.QO_Result])
	msg.add_data(_D.XN_USERID, local_user.get("id", ""))
	msg.add_data(_D.XN_ADDRESS, local_user.get("address", ""))
	msg.add_data(_D.XN_NAME, local_user.get("name", ""))
	msg.add_data(_D.XN_VERSION, local_user.get("version", ""))
	msg.add_data(_D.XN_STATUS, local_user.get("status", ""))
	msg.add_data(_D.XN_AVATAR, str(local_user.get("avatar", 0)))
	msg.add_data(_D.XN_NOTE, local_user.get("note", ""))
	msg.add_data(_D.XN_USERCAPS, str(local_user.get("caps", 0)))
	return msg

func _process_user_data_result(peer_id: String, pMessage: XmlMessage) -> void:
	var user_id = pMessage.data(_D.XN_USERID)
	if user_id.is_empty():
		user_id = peer_id
	var user_name = pMessage.data(_D.XN_NAME)
	if user_name.is_empty():
		user_name = user_id
	var address = pMessage.data(_D.XN_ADDRESS)
	var was_added = _add_user(
		user_id,
		pMessage.data(_D.XN_VERSION),
		address,
		user_name,
		pMessage.data(_D.XN_STATUS),
		pMessage.data(_D.XN_AVATAR),
		pMessage.data(_D.XN_NOTE),
		pMessage.data(_D.XN_USERCAPS)
	)
	if was_added:
		user_added.emit({
			"id": user_id,
			"name": user_name,
			"address": address,
			"status": pMessage.data(_D.XN_STATUS)
		})
	_send_avatar_init(user_id)

# -- Internal: File handling --

func _send_avatar_init(user_id: String) -> void:
	var path = _local_avatar_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var size = file.get_length()
	file.close()
	var fid = (str(Time.get_unix_time_from_system()) + _local_id() + user_id).md5_text()
	var msg = XmlMessage.new()
	msg.add_data(_D.XN_FILEID, fid)
	msg.add_data(_D.XN_FILEPATH, path)
	msg.add_data(_D.XN_FILENAME, path.get_file())
	msg.add_data(_D.XN_FILESIZE, str(size))
	msg.add_data(_D.XN_FILETYPE, _D.FileTypeNames[_D.FileType.FT_Avatar])
	msg.add_data(_D.XN_MODE, _D.FileModeNames[_D.FileMode.FM_Send])
	msg.add_data(_D.XN_FILEOP, _D.FileOpNames[_D.FileOp.FO_Init])
	_avatar_send_map[fid] = msg
	_msg_id += 1
	_prepare_message(_D.MessageType.MT_File, _msg_id, false, user_id, msg)

func _process_avatar_file(user_id: String, msg: XmlMessage, fid: String, mode: String, op: String) -> void:
	if op == _D.FileOpNames[_D.FileOp.FO_Init]:
		var path = _avatar_cache_path(user_id)
		var receive_msg = msg.clone()
		receive_msg.remove_data(_D.XN_FILEPATH)
		receive_msg.add_data(_D.XN_FILEPATH, path)
		network.init_receive_file(user_id, msg.header(_D.XN_ADDRESS), receive_msg.get_xml())
		var reply = XmlMessage.new()
		reply.add_data(_D.XN_FILEID, fid)
		reply.add_data(_D.XN_FILETYPE, _D.FileTypeNames[_D.FileType.FT_Avatar])
		reply.add_data(_D.XN_MODE, _D.FileModeNames[_D.FileMode.FM_Receive])
		reply.add_data(_D.XN_FILEOP, _D.FileOpNames[_D.FileOp.FO_Accept])
		_msg_id += 1
		_prepare_message(_D.MessageType.MT_File, _msg_id, false, user_id, reply)
	elif op == _D.FileOpNames[_D.FileOp.FO_Accept]:
		var send_msg: XmlMessage = _avatar_send_map.get(fid, null)
		if send_msg:
			network.init_send_file(user_id, get_user(user_id).get("address", ""), send_msg.get_xml())
	elif op == _D.FileOpNames[_D.FileOp.FO_Complete]:
		_avatar_send_map.erase(fid)
		if mode == _D.FileModeNames[_D.FileMode.FM_Receive]:
			user_avatar_changed.emit(user_id)

func _avatar_cache_path(user_id: String) -> String:
	return "user://cache/avt_" + user_id + ".png"

func _local_avatar_path() -> String:
	var avatar_id = int(local_user.get("avatar", 0))
	var candidates: Array[String] = [
		"user://avt_local.png",
		"res://Assets/Avatars/avatar_" + str(avatar_id) + ".png"
	]
	if OS.get_name() == "Windows":
		var local_app_data = OS.get_environment("LOCALAPPDATA")
		if not local_app_data.is_empty():
			candidates.append(local_app_data.path_join("LAN Messenger").path_join("LAN Messenger").path_join("avt_local.png"))
	candidates.append("res://Assets/Avatars/avatar_default.png")
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""

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
			break
	_send_user_data_query(user_id)

func _send_user_data_query(user_id: String) -> void:
	var msg = XmlMessage.new()
	msg.add_data(_D.XN_USERID, local_user.get("id", ""))
	msg.add_data(_D.XN_NAME, local_user.get("name", ""))
	msg.add_data(_D.XN_ADDRESS, local_user.get("address", ""))
	msg.add_data(_D.XN_VERSION, local_user.get("version", ""))
	msg.add_data(_D.XN_STATUS, local_user.get("status", ""))
	msg.add_data(_D.XN_NOTE, local_user.get("note", ""))
	msg.add_data(_D.XN_USERCAPS, str(local_user.get("caps", 0)))
	msg.add_data(_D.XN_QUERYOP, _D.QueryOpNames[_D.QueryOp.QO_Get])
	_msg_id += 1
	_prepare_message(_D.MessageType.MT_UserData, _msg_id, false, user_id, msg)

func _send_acknowledge(user_id: String, msg_id: int) -> void:
	var reply = XmlMessage.new()
	reply.add_data(_D.XN_MESSAGEID, str(msg_id))
	_msg_id += 1
	_prepare_message(_D.MessageType.MT_Acknowledge, _msg_id, false, user_id, reply)

func _on_connection_lost(user_id: String) -> void:
	_remove_all_pending_msg(user_id)

func _receive_progress(user_id: String, data: String) -> void:
	var msg = XmlMessage.new(data)
	var uid = msg.header(_D.XN_FROM)
	var user = get_user(uid)
	var name = user.get("name", uid)
	if msg.data(_D.XN_FILETYPE) == _D.FileTypeNames[_D.FileType.FT_Avatar]:
		_process_avatar_file(uid, msg, msg.data(_D.XN_FILEID), msg.data(_D.XN_MODE), msg.data(_D.XN_FILEOP))
		return
	message_received.emit(_D.MessageType.MT_File, uid, name, msg.get_xml())

func _receive_web_message(data: String) -> void:
	message_received.emit(_D.MessageType.MT_WebFailed, "", "", data)

func _on_network_state_changed() -> void:
	connection_state_changed.emit()

func _local_id() -> String:
	return local_user.get("id", "")
