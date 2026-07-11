extends Node

const _D = preload("res://scripts/network/definitions.gd")

signal user_added(user)
signal user_removed(user_id)
signal message_received(type, user_id, user_name, body)
signal user_status_changed(user_id, status)
signal user_typing(user_id, user_name, state)
signal connection_state_changed
signal user_avatar_changed(user_id)

const PENDING_TIMEOUT_MS := 10_000
const MAX_RETRIES := 1
const MAX_RECEIVED_TRACKING := 1000

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
var _startup_broadcast_pending: bool = false
var _pending_check_elapsed: float = 0.0


func init_config(settings: Dictionary = {}) -> void:
	_settings = settings
	if network:
		network.init_config(_settings)


func start() -> void:
	if _started or not network:
		return
	network.broadcast_received.connect(_receive_broadcast)
	network.new_connection.connect(_on_new_connection)
	network.connection_lost.connect(_on_connection_lost)
	network.message_received.connect(_receive_message)
	network.progress_received.connect(_receive_progress)
	network.web_message_received.connect(_receive_web_message)
	network.connection_state_changed.connect(_on_network_state_changed)
	network.start()
	_started = true
	_startup_broadcast_pending = true


func _process(delta: float) -> void:
	if _startup_broadcast_pending:
		_startup_broadcast_pending = false
		# Match LAN Messenger startup semantics: clear stale presence first,
		# then announce the new session.
		_send_depart()
		_send_announce()

	_pending_check_elapsed += delta
	if _pending_check_elapsed >= 1.0:
		_pending_check_elapsed = 0.0
		_check_pending_messages()


func stop() -> void:
	if not _started:
		return
	_send_depart()
	_started = false
	_pending_list.clear()
	if network:
		network.stop()


func network_is_connected() -> bool:
	return network.is_connected if network else false


func can_receive() -> bool:
	return network.can_receive if network else false


func get_user(user_id: String) -> Dictionary:
	for user in user_list:
		if user["id"] == user_id:
			return user
	return {}


func send_message(msg_type: int, user_id: String, pMessage: XmlMessage) -> void:
	if not _started or user_id.is_empty():
		return
	_msg_id += 1
	var message := pMessage if pMessage else XmlMessage.new()
	_prepare_message(msg_type, _msg_id, false, user_id, message)
	if _requires_ack_tracking(msg_type, message):
		_add_pending_msg(_msg_id, msg_type, user_id, message)


func send_web_message(msg_type: int, pMessage: XmlMessage) -> void:
	if not network:
		return
	_msg_id += 1
	var message := pMessage if pMessage else XmlMessage.new()
	var xml := Message.add_header(msg_type, _msg_id, _local_id(), "", message)
	network.send_web_message("", xml)


func refresh() -> void:
	if not _started:
		return
	_send_announce()
	for user in user_list:
		send_message(_D.MessageType.MT_Ping, user["id"], XmlMessage.new())


func settings_changed() -> void:
	if network:
		network.settings_changed()


func user_count() -> int:
	return user_list.size()


# -- Broadcast handling -----------------------------------------------------


func _send_announce() -> void:
	if not _started or not network_is_connected():
		return
	_msg_id += 1
	var xml := Message.add_header(
		_D.MessageType.MT_Announce, _msg_id, _local_id(), "", XmlMessage.new()
	)
	network.send_broadcast(xml)


func _send_depart() -> void:
	if not network or not network_is_connected():
		return
	_msg_id += 1
	var xml := Message.add_header(
		_D.MessageType.MT_Depart, _msg_id, _local_id(), "", XmlMessage.new()
	)
	network.send_broadcast(xml)


func _receive_broadcast(pHeader, data: String) -> void:
	var header := Message.get_header(data)
	if header.is_empty():
		return
	header["address"] = str(pHeader.get("address", ""))
	if not _loopback and header["userId"] == _local_id():
		return

	match header["type"]:
		_D.MessageType.MT_Announce:
			_process_announce(header["userId"], header["address"])
		_D.MessageType.MT_Depart:
			_process_depart(header["userId"])
		# Kept as a compatibility extension for existing CydLAN builds.
		_D.MessageType.MT_Broadcast:
			_process_broadcast_msg(header["message"], header["userId"])
		_D.MessageType.MT_Status:
			var broadcast_message: XmlMessage = header["message"] as XmlMessage
			if not broadcast_message:
				return
			var status: String = broadcast_message.data(_D.XN_STATUS)
			if _update_user(header["userId"], "status", status):
				user_status_changed.emit(header["userId"], status)


func _process_announce(user_id: String, address: String) -> void:
	if user_id.is_empty() or address.is_empty() or user_id == _local_id():
		return
	# The original LAN Messenger does not add a user from an announce. It
	# opens one TCP connection, completes the encrypted handshake, exchanges
	# user data, and only then exposes the peer to the UI.
	if get_user(user_id).is_empty():
		network.add_connection(user_id, address)


func _process_depart(user_id: String) -> void:
	if _remove_user(user_id):
		_remove_all_pending_msg(user_id)
		user_removed.emit(user_id)


func _process_broadcast_msg(pMessage: XmlMessage, user_id: String) -> void:
	var body := pMessage.data(_D.XN_BROADCAST)
	if body.is_empty():
		body = pMessage.data(_D.XN_MESSAGE)
	var user := get_user(user_id)
	var name: String = str(user.get("name", user_id)) if not user.is_empty() else user_id
	message_received.emit(_D.MessageType.MT_Broadcast, user_id, name, body)


# -- Direct message handling -----------------------------------------------


func _prepare_message(
	msg_type: int, msg_id: int, _retry: bool, user_id: String, pMessage: XmlMessage
) -> void:
	if not network or not network_is_connected():
		return
	var user := get_user(user_id)
	if user.is_empty():
		return
	var xml := Message.add_header(msg_type, msg_id, _local_id(), user_id, pMessage)
	network.send_message(user_id, str(user.get("address", "")), xml)


func _send_direct(msg_type: int, user_id: String, address: String, pMessage: XmlMessage) -> void:
	if not network or not network_is_connected():
		return
	if user_id.is_empty() or address.is_empty():
		return
	_msg_id += 1
	var xml := Message.add_header(msg_type, _msg_id, _local_id(), user_id, pMessage)
	network.send_message(user_id, address, xml)


func _receive_message(pHeader, data: String) -> void:
	var header := Message.get_header(data)
	if header.is_empty():
		return
	var transport_user := str(pHeader.get("userId", ""))
	if transport_user.is_empty() or header["userId"] != transport_user:
		push_warning("CydLAN: Rejected message with mismatched transport identity")
		return
	header["address"] = str(pHeader.get("address", ""))
	var direct_message: XmlMessage = header["message"] as XmlMessage
	if not direct_message:
		return
	var intended_for: String = direct_message.header(_D.XN_TO)
	if not intended_for.is_empty() and intended_for != _local_id():
		return
	_process_message(header["type"], header)


func _process_message(msg_type: int, pHeader: Dictionary) -> void:
	var pMessage: XmlMessage = pHeader.get("message")
	if not pMessage:
		return
	var user_id: String = pHeader["userId"]
	var address: String = pHeader.get("address", "")
	var user := get_user(user_id)
	var name: String = str(user.get("name", user_id)) if not user.is_empty() else user_id

	match msg_type:
		_D.MessageType.MT_Message:
			var body := pMessage.data(_D.XN_MESSAGE)
			if _add_received_msg(pHeader["id"], user_id):
				message_received.emit(msg_type, user_id, name, body)
			# Duplicate chat messages are deliberately acknowledged too. This
			# stops a sender retrying forever when the first ACK was lost.
			_send_acknowledge(user_id, pHeader["id"])
		_D.MessageType.MT_GroupMessage:
			var body := pMessage.data(_D.XN_GROUPMESSAGE)
			if body.is_empty():
				body = pMessage.data(_D.XN_MESSAGE)
			message_received.emit(msg_type, user_id, name, body)
		_D.MessageType.MT_PublicMessage:
			message_received.emit(msg_type, user_id, name, pMessage.data(_D.XN_MESSAGE))
		_D.MessageType.MT_Status:
			var status := pMessage.data(_D.XN_STATUS)
			if _update_user(user_id, "status", status):
				user_status_changed.emit(user_id, status)
		_D.MessageType.MT_UserName:
			_update_user(user_id, "name", pMessage.data(_D.XN_NAME))
		_D.MessageType.MT_Note:
			_update_user(user_id, "note", pMessage.data(_D.XN_NOTE))
		_D.MessageType.MT_ChatState:
			user_typing.emit(user_id, name, pMessage.data(_D.XN_CHATSTATE))
		_D.MessageType.MT_File, _D.MessageType.MT_Folder:
			var file_id := pMessage.data(_D.XN_FILEID)
			var file_type := pMessage.data(_D.XN_FILETYPE)
			var mode := pMessage.data(_D.XN_MODE)
			var operation := pMessage.data(_D.XN_FILEOP)
			if file_type == _D.FileTypeNames[_D.FileType.FT_Avatar]:
				_process_avatar_file(user_id, pMessage, file_id, mode, operation)
				return
			message_received.emit(msg_type, user_id, name, operation)
		_D.MessageType.MT_UserData:
			var query_operation := pMessage.data(_D.XN_QUERYOP)
			if query_operation == _D.QueryOpNames[_D.QueryOp.QO_Get]:
				_send_user_data_result(user_id, address)
				_process_user_data(user_id, pMessage, address)
			elif query_operation == _D.QueryOpNames[_D.QueryOp.QO_Result]:
				_process_user_data(user_id, pMessage, address)
		_D.MessageType.MT_Ping:
			_send_acknowledge(user_id, pHeader["id"])
		_D.MessageType.MT_Acknowledge:
			_remove_pending_msg(int(pMessage.data(_D.XN_MESSAGEID)))


func _build_user_data(query_operation: String) -> XmlMessage:
	var msg := XmlMessage.new()
	msg.add_data(_D.XN_QUERYOP, query_operation)
	msg.add_data(_D.XN_USERID, local_user.get("id", ""))
	msg.add_data(_D.XN_NAME, local_user.get("name", ""))
	msg.add_data(_D.XN_ADDRESS, local_user.get("address", ""))
	msg.add_data(_D.XN_VERSION, local_user.get("version", ""))
	msg.add_data(_D.XN_STATUS, local_user.get("status", ""))
	msg.add_data(_D.XN_AVATAR, str(local_user.get("avatar", 0)))
	msg.add_data(_D.XN_NOTE, local_user.get("note", ""))
	msg.add_data(_D.XN_USERCAPS, str(local_user.get("caps", 0)))
	msg.add_data(_D.XN_GROUP, str(local_user.get("group", _D.GRP_DEFAULT)))
	return msg


func _send_user_data_query(user_id: String, address: String) -> void:
	_send_direct(
		_D.MessageType.MT_UserData,
		user_id,
		address,
		_build_user_data(_D.QueryOpNames[_D.QueryOp.QO_Get])
	)


func _send_user_data_result(user_id: String, address: String) -> void:
	_send_direct(
		_D.MessageType.MT_UserData,
		user_id,
		address,
		_build_user_data(_D.QueryOpNames[_D.QueryOp.QO_Result])
	)


func _process_user_data(
	transport_user_id: String, pMessage: XmlMessage, fallback_address: String
) -> void:
	var user_id := pMessage.data(_D.XN_USERID)
	if user_id.is_empty():
		user_id = transport_user_id
	if user_id != transport_user_id or user_id == _local_id():
		return

	var user_name := pMessage.data(_D.XN_NAME)
	if user_name.is_empty():
		user_name = user_id
	var address := pMessage.data(_D.XN_ADDRESS)
	if address.is_empty():
		address = fallback_address
	var was_added := _add_user(
		user_id,
		pMessage.data(_D.XN_VERSION),
		address,
		user_name,
		pMessage.data(_D.XN_STATUS),
		pMessage.data(_D.XN_AVATAR),
		pMessage.data(_D.XN_NOTE),
		pMessage.data(_D.XN_USERCAPS),
		pMessage.data(_D.XN_GROUP)
	)
	if was_added:
		user_added.emit(get_user(user_id).duplicate(true))
		_send_avatar_init(user_id)


# -- File and avatar handling ----------------------------------------------


func _send_avatar_init(user_id: String) -> void:
	var path := _local_avatar_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var size := file.get_length()
	file.close()

	var file_id := (str(Time.get_unix_time_from_system()) + _local_id() + user_id).md5_text()
	var msg := XmlMessage.new()
	msg.add_data(_D.XN_FILEID, file_id)
	msg.add_data(_D.XN_FILEPATH, path)
	msg.add_data(_D.XN_FILENAME, path.get_file())
	msg.add_data(_D.XN_FILESIZE, str(size))
	msg.add_data(_D.XN_FILETYPE, _D.FileTypeNames[_D.FileType.FT_Avatar])
	msg.add_data(_D.XN_MODE, _D.FileModeNames[_D.FileMode.FM_Send])
	msg.add_data(_D.XN_FILEOP, _D.FileOpNames[_D.FileOp.FO_Init])
	_avatar_send_map[file_id] = msg
	_msg_id += 1
	_prepare_message(_D.MessageType.MT_File, _msg_id, false, user_id, msg)


func _process_avatar_file(
	user_id: String, msg: XmlMessage, file_id: String, mode: String, operation: String
) -> void:
	if operation == _D.FileOpNames[_D.FileOp.FO_Init]:
		var receive_msg := msg.clone()
		receive_msg.remove_data(_D.XN_FILEPATH)
		receive_msg.add_data(_D.XN_FILEPATH, _avatar_cache_path(user_id))
		var peer := get_user(user_id)
		network.init_receive_file(user_id, str(peer.get("address", "")), receive_msg.get_xml())
		var reply := XmlMessage.new()
		reply.add_data(_D.XN_FILEID, file_id)
		reply.add_data(_D.XN_FILETYPE, _D.FileTypeNames[_D.FileType.FT_Avatar])
		reply.add_data(_D.XN_MODE, _D.FileModeNames[_D.FileMode.FM_Receive])
		reply.add_data(_D.XN_FILEOP, _D.FileOpNames[_D.FileOp.FO_Accept])
		_msg_id += 1
		_prepare_message(_D.MessageType.MT_File, _msg_id, false, user_id, reply)
	elif operation == _D.FileOpNames[_D.FileOp.FO_Accept]:
		var send_msg: XmlMessage = _avatar_send_map.get(file_id)
		if send_msg:
			network.init_send_file(
				user_id, str(get_user(user_id).get("address", "")), send_msg.get_xml()
			)
	elif operation == _D.FileOpNames[_D.FileOp.FO_Complete]:
		_avatar_send_map.erase(file_id)
		if mode == _D.FileModeNames[_D.FileMode.FM_Receive]:
			user_avatar_changed.emit(user_id)


func _avatar_cache_path(user_id: String) -> String:
	return "user://cache/avt_" + user_id + ".png"


func _local_avatar_path() -> String:
	var avatar_id := int(local_user.get("avatar", 0))
	var candidates: Array[String] = [
		"user://avt_local.png", "res://Assets/Avatars/avatar_" + str(avatar_id) + ".png"
	]
	if OS.get_name() == "Windows":
		var local_app_data := OS.get_environment("LOCALAPPDATA")
		if not local_app_data.is_empty():
			var original_dir := local_app_data.path_join("LAN Messenger").path_join("LAN Messenger")
			candidates.append(original_dir.path_join("avt_local.png"))
	candidates.append("res://Assets/Avatars/avatar_default.png")
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""


# -- User management --------------------------------------------------------


func _add_user(
	user_id: String,
	version: String,
	address: String,
	name: String,
	status: String,
	avatar: String,
	note: String,
	caps: String,
	group_name: String = ""
) -> bool:
	if user_id.is_empty() or user_id == _local_id():
		return false
	for user in user_list:
		if user["id"] == user_id:
			user["version"] = version
			user["address"] = address
			user["name"] = name
			user["status"] = status
			user["avatar"] = int(avatar) if avatar.is_valid_int() else 0
			user["note"] = note
			user["caps"] = int(caps) if caps.is_valid_int() else 0
			if not group_name.is_empty():
				user["group"] = group_name
			return false
	user_list.append(
		{
			"id": user_id,
			"version": version,
			"address": address,
			"name": name,
			"status": status,
			"avatar": int(avatar) if avatar.is_valid_int() else 0,
			"group": group_name if not group_name.is_empty() else _D.GRP_DEFAULT,
			"note": note,
			"caps": int(caps) if caps.is_valid_int() else 0
		}
	)
	return true


func _update_user(user_id: String, field: String, value) -> bool:
	for user in user_list:
		if user["id"] == user_id:
			if user.get(field) == value:
				return false
			user[field] = value
			return true
	return false


func _remove_user(user_id: String) -> bool:
	for index in range(user_list.size() - 1, -1, -1):
		if user_list[index]["id"] == user_id:
			user_list.remove_at(index)
			return true
	return false


# -- Message tracking -------------------------------------------------------


func _add_received_msg(msg_id: int, user_id: String) -> bool:
	for received in _received_list:
		if received["msgId"] == msg_id and received["userId"] == user_id:
			return false
	_received_list.append({"msgId": msg_id, "userId": user_id})
	if _received_list.size() > MAX_RECEIVED_TRACKING:
		_received_list.pop_front()
	return true


func _requires_ack_tracking(msg_type: int, pMessage: XmlMessage) -> bool:
	if msg_type == _D.MessageType.MT_Message or msg_type == _D.MessageType.MT_Ping:
		return true
	return (
		msg_type == _D.MessageType.MT_Query
		and pMessage.data(_D.XN_QUERYOP) == _D.QueryOpNames[_D.QueryOp.QO_Get]
	)


func _add_pending_msg(msg_id: int, msg_type: int, user_id: String, pMessage: XmlMessage) -> void:
	_pending_list.append(
		{
			"msgId": msg_id,
			"type": msg_type,
			"userId": user_id,
			"xmlMessage": pMessage.clone(),
			"retry": 0,
			"deadline": Time.get_ticks_msec() + PENDING_TIMEOUT_MS
		}
	)


func _check_pending_messages() -> void:
	if not _started:
		return
	var now := Time.get_ticks_msec()
	for index in range(_pending_list.size() - 1, -1, -1):
		var pending: Dictionary = _pending_list[index]
		if now < int(pending["deadline"]):
			continue
		if int(pending["retry"]) < MAX_RETRIES:
			pending["retry"] = int(pending["retry"]) + 1
			pending["deadline"] = now + PENDING_TIMEOUT_MS
			_pending_list[index] = pending
			_prepare_message(
				int(pending["type"]),
				int(pending["msgId"]),
				true,
				str(pending["userId"]),
				pending["xmlMessage"]
			)
			continue

		_pending_list.remove_at(index)
		var user_id := str(pending["userId"])
		if int(pending["type"]) == _D.MessageType.MT_Message:
			var user := get_user(user_id)
			message_received.emit(
				_D.MessageType.MT_Failed,
				user_id,
				str(user.get("name", user_id)),
				pending["xmlMessage"].data(_D.XN_MESSAGE)
			)
		elif int(pending["type"]) == _D.MessageType.MT_Ping:
			if _remove_user(user_id):
				user_removed.emit(user_id)


func _remove_pending_msg(msg_id: int) -> void:
	for index in range(_pending_list.size() - 1, -1, -1):
		if int(_pending_list[index]["msgId"]) == msg_id:
			_pending_list.remove_at(index)
			return


func _remove_all_pending_msg(user_id: String) -> void:
	for index in range(_pending_list.size() - 1, -1, -1):
		if _pending_list[index]["userId"] == user_id:
			_pending_list.remove_at(index)


# -- Network signal handlers ------------------------------------------------


func _on_new_connection(user_id: String, address: String) -> void:
	_send_user_data_query(user_id, address)


func _send_acknowledge(user_id: String, msg_id: int) -> void:
	var reply := XmlMessage.new()
	reply.add_data(_D.XN_MESSAGEID, str(msg_id))
	var user := get_user(user_id)
	if user.is_empty():
		return
	_send_direct(_D.MessageType.MT_Acknowledge, user_id, str(user.get("address", "")), reply)


func _on_connection_lost(user_id: String) -> void:
	_remove_all_pending_msg(user_id)
	if _remove_user(user_id):
		user_removed.emit(user_id)


func _receive_progress(user_id: String, data: String) -> void:
	var msg := XmlMessage.new(data)
	if not msg.is_valid():
		return
	var sender_id := msg.header(_D.XN_FROM)
	if sender_id.is_empty():
		sender_id = user_id
	var user := get_user(sender_id)
	var name: String = str(user.get("name", sender_id))
	if msg.data(_D.XN_FILETYPE) == _D.FileTypeNames[_D.FileType.FT_Avatar]:
		_process_avatar_file(
			sender_id, msg, msg.data(_D.XN_FILEID), msg.data(_D.XN_MODE), msg.data(_D.XN_FILEOP)
		)
		return
	message_received.emit(_D.MessageType.MT_File, sender_id, name, msg.get_xml())


func _receive_web_message(data: String) -> void:
	message_received.emit(_D.MessageType.MT_WebFailed, "", "", data)


func _on_network_state_changed() -> void:
	connection_state_changed.emit()


func _local_id() -> String:
	return str(local_user.get("id", ""))
