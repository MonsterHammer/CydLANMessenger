extends Node

const _D = preload("res://scripts/network/definitions.gd")

signal user_added(user)
signal user_removed(user_id)
signal message_received(type, user_id, user_name, body)
signal user_status_changed(user_id, status)
signal user_typing(user_id, user_name, state)
signal user_avatar_changed(user_id)
signal user_info_received(user_id, info)
signal delivery_state_changed(user_id, message_id, state)
signal file_transfer_requested(transfer)
signal file_transfer_updated(transfer)
signal connection_state_changed

var local_user: Dictionary = {}
var user_list: Array = []
var group_list: Array = []
var network: Node = null

var _settings: Dictionary = {}
var _msg_id: int = 0
var _received_list: Array = []
var _pending_list: Array = []
var _avatar_send_map: Dictionary = {}
var _outgoing_files: Dictionary = {}
var _incoming_files: Dictionary = {}
var _started := false
var _announce_pending := false
var _pending_check_accumulator := 0.0

func init_config(settings: Dictionary = {}) -> void:
	_settings = settings.duplicate(true)
	if network:
		network.init_config(_settings)

func start() -> void:
	if not network or _started:
		return
	_connect_network_signals()
	network.start()
	_started = true
	# This mirrors the original LAN Messenger startup sequence and clears a stale
	# entry for the same ID before announcing the current session.
	_send_depart()
	_announce_pending = true

func stop() -> void:
	if not _started:
		return
	_send_depart()
	_started = false
	if network:
		network.stop()

func _connect_network_signals() -> void:
	if not network.broadcast_received.is_connected(_receive_broadcast):
		network.broadcast_received.connect(_receive_broadcast)
	if not network.new_connection.is_connected(_on_new_connection):
		network.new_connection.connect(_on_new_connection)
	if not network.connection_lost.is_connected(_on_connection_lost):
		network.connection_lost.connect(_on_connection_lost)
	if not network.message_received.is_connected(_receive_message):
		network.message_received.connect(_receive_message)
	if not network.progress_received.is_connected(_receive_progress):
		network.progress_received.connect(_receive_progress)
	if not network.web_message_received.is_connected(_receive_web_message):
		network.web_message_received.connect(_receive_web_message)
	if not network.connection_state_changed.is_connected(_on_network_state_changed):
		network.connection_state_changed.connect(_on_network_state_changed)

func _process(delta: float) -> void:
	if _announce_pending:
		_announce_pending = false
		_send_announce()
	_pending_check_accumulator += delta
	if _pending_check_accumulator >= 0.25:
		_pending_check_accumulator = 0.0
		_check_pending_messages()

func network_is_connected() -> bool:
	return network.is_connected if network else false

func can_receive() -> bool:
	return network.can_receive if network else false

func get_user(user_id: String) -> Dictionary:
	for user in user_list:
		if user.get("id", "") == user_id:
			return user
	return {}

func user_count() -> int:
	return user_list.size()

func refresh() -> void:
	if not _started:
		return
	_send_announce()
	for user in user_list.duplicate():
		send_message(_D.MessageType.MT_Ping, user.get("id", ""), XmlMessage.new())

func send_message(msg_type: int, user_id: String, xml_message: XmlMessage) -> int:
	if not _started:
		return -1
	_msg_id += 1
	var message_id := _msg_id
	_send_packet(msg_type, message_id, user_id, xml_message, false)
	return message_id

func send_broadcast_message(text: String) -> int:
	if not _started or text.strip_edges().is_empty():
		return -1
	_msg_id += 1
	var xml := XmlMessage.new()
	xml.add_data(_D.XN_BROADCAST, text)
	var payload := Message.add_header(_D.MessageType.MT_Broadcast, _msg_id, _local_id(), "", xml)
	network.send_broadcast(payload)
	return _msg_id

func send_chat_state(user_id: String, state: String) -> void:
	if not state in _D.ChatStateNames:
		return
	var xml := XmlMessage.new()
	xml.add_data(_D.XN_CHATSTATE, state)
	send_message(_D.MessageType.MT_ChatState, user_id, xml)

func set_local_status(status: String) -> void:
	if not status in _D.statusCode:
		return
	local_user["status"] = status
	var xml := XmlMessage.new()
	xml.add_data(_D.XN_STATUS, status)
	_send_to_all(_D.MessageType.MT_Status, xml)
	_send_announce()

func announce_profile_changes(profile: Dictionary) -> void:
	if profile.has("status"):
		set_local_status(str(profile["status"]))
	if profile.has("name"):
		var name_xml := XmlMessage.new()
		name_xml.add_data(_D.XN_NAME, str(profile["name"]))
		_send_to_all(_D.MessageType.MT_UserName, name_xml)
	if profile.has("note"):
		var note_xml := XmlMessage.new()
		note_xml.add_data(_D.XN_NOTE, str(profile["note"]))
		_send_to_all(_D.MessageType.MT_Note, note_xml)
	_send_announce()

func request_user_info(user_id: String) -> int:
	var xml := XmlMessage.new()
	xml.add_data(_D.XN_QUERYOP, _D.QueryOpNames[_D.QueryOp.QO_Get])
	return send_message(_D.MessageType.MT_Query, user_id, xml)

func send_file(user_id: String, file_path: String) -> String:
	if not FileAccess.file_exists(file_path):
		return ""
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return ""
	var file_size := file.get_length()
	file.close()
	var file_id := (str(Time.get_unix_time_from_system()) + _local_id() + user_id + file_path).md5_text()
	var transfer := {
		"id": file_id,
		"user_id": user_id,
		"name": file_path.get_file(),
		"path": file_path,
		"size": file_size,
		"transferred": 0,
		"mode": "send",
		"status": "request"
	}
	_outgoing_files[file_id] = transfer
	var xml := _file_xml(transfer, _D.FileMode.FM_Send, _D.FileOp.FO_Request)
	send_message(_D.MessageType.MT_File, user_id, xml)
	file_transfer_updated.emit(transfer.duplicate(true))
	return file_id

func accept_file(user_id: String, file_id: String, destination_path: String = "") -> bool:
	if not _incoming_files.has(file_id):
		return false
	var transfer: Dictionary = _incoming_files[file_id]
	if transfer.get("user_id", "") != user_id:
		return false
	if destination_path.is_empty():
		destination_path = _unique_download_path(str(transfer.get("name", "file")))
	transfer["path"] = destination_path
	transfer["status"] = "accepted"
	_incoming_files[file_id] = transfer
	var xml := _file_xml(transfer, _D.FileMode.FM_Receive, _D.FileOp.FO_Accept)
	network.init_receive_file(user_id, get_user(user_id).get("address", ""), xml.get_xml())
	send_message(_D.MessageType.MT_File, user_id, xml)
	file_transfer_updated.emit(transfer.duplicate(true))
	return true

func decline_file(user_id: String, file_id: String) -> void:
	if not _incoming_files.has(file_id):
		return
	var transfer: Dictionary = _incoming_files[file_id]
	transfer["status"] = "declined"
	var xml := _file_xml(transfer, _D.FileMode.FM_Receive, _D.FileOp.FO_Decline)
	send_message(_D.MessageType.MT_File, user_id, xml)
	file_transfer_updated.emit(transfer.duplicate(true))
	_incoming_files.erase(file_id)

func cancel_file(user_id: String, file_id: String) -> void:
	var transfer: Dictionary = _outgoing_files.get(file_id, _incoming_files.get(file_id, {}))
	if transfer.is_empty():
		return
	var mode := _D.FileMode.FM_Send if transfer.get("mode", "") == "send" else _D.FileMode.FM_Receive
	var xml := _file_xml(transfer, mode, _D.FileOp.FO_Cancel)
	network.file_operation(mode, user_id, xml.get_xml())
	send_message(_D.MessageType.MT_File, user_id, xml)
	transfer["status"] = "cancelled"
	file_transfer_updated.emit(transfer.duplicate(true))

func _send_to_all(msg_type: int, xml_message: XmlMessage) -> void:
	for user in user_list:
		send_message(msg_type, user.get("id", ""), xml_message.clone())

func _send_packet(msg_type: int, message_id: int, user_id: String, xml_message: XmlMessage, retry: bool) -> void:
	if not xml_message:
		xml_message = XmlMessage.new()
	var user := get_user(user_id)
	if user.is_empty():
		if msg_type == _D.MessageType.MT_Message:
			delivery_state_changed.emit(user_id, message_id, "failed")
		return
	if _requires_ack(msg_type, xml_message) and not retry:
		_pending_list.append({
			"id": message_id,
			"type": msg_type,
			"user_id": user_id,
			"xml": xml_message.clone(),
			"retries": 0,
			"sent_at": Time.get_ticks_msec()
		})
		if msg_type == _D.MessageType.MT_Message:
			delivery_state_changed.emit(user_id, message_id, "sending")
	var payload := Message.add_header(msg_type, message_id, _local_id(), user_id, xml_message)
	network.send_message(user_id, user.get("address", ""), payload)

func _requires_ack(msg_type: int, xml_message: XmlMessage) -> bool:
	if msg_type in [_D.MessageType.MT_Message, _D.MessageType.MT_Ping]:
		return true
	return msg_type == _D.MessageType.MT_Query and xml_message.data(_D.XN_QUERYOP) == _D.QueryOpNames[_D.QueryOp.QO_Get]

func _check_pending_messages() -> void:
	var timeout_ms := maxi(500, int(_settings.get("retry_timeout_ms", 2500)))
	var max_retries := clampi(int(_settings.get("max_retries", 3)), 0, 10)
	var now := Time.get_ticks_msec()
	for index in range(_pending_list.size() - 1, -1, -1):
		var pending: Dictionary = _pending_list[index]
		if now - int(pending.get("sent_at", now)) < timeout_ms:
			continue
		if int(pending.get("retries", 0)) < max_retries:
			pending["retries"] = int(pending.get("retries", 0)) + 1
			pending["sent_at"] = now
			_pending_list[index] = pending
			_send_packet(pending["type"], pending["id"], pending["user_id"], pending["xml"].clone(), true)
			continue
		_pending_list.remove_at(index)
		if pending["type"] == _D.MessageType.MT_Message:
			delivery_state_changed.emit(pending["user_id"], pending["id"], "failed")
		elif pending["type"] == _D.MessageType.MT_Ping:
			_remove_user(pending["user_id"], true)

func _remove_pending_message(message_id: int) -> void:
	for index in range(_pending_list.size() - 1, -1, -1):
		if int(_pending_list[index].get("id", -1)) == message_id:
			var pending: Dictionary = _pending_list[index]
			_pending_list.remove_at(index)
			if pending.get("type", -1) == _D.MessageType.MT_Message:
				delivery_state_changed.emit(pending.get("user_id", ""), message_id, "delivered")
			return

func _send_announce() -> void:
	if not network_is_connected():
		return
	_msg_id += 1
	var xml := XmlMessage.new()
	xml.add_data(_D.XN_NAME, local_user.get("name", ""))
	xml.add_data(_D.XN_VERSION, local_user.get("version", "1.2.39"))
	xml.add_data(_D.XN_ADDRESS, local_user.get("address", ""))
	xml.add_data(_D.XN_STATUS, local_user.get("status", "chat"))
	xml.add_data(_D.XN_AVATAR, str(local_user.get("avatar", 0)))
	xml.add_data(_D.XN_NOTE, local_user.get("note", ""))
	xml.add_data(_D.XN_USERCAPS, str(local_user.get("caps", 0)))
	xml.add_data(_D.XN_GROUP, local_user.get("group", _D.GRP_DEFAULT))
	network.send_broadcast(Message.add_header(_D.MessageType.MT_Announce, _msg_id, _local_id(), "", xml))

func _send_depart() -> void:
	if not network or not network_is_connected():
		return
	_msg_id += 1
	network.send_broadcast(Message.add_header(_D.MessageType.MT_Depart, _msg_id, _local_id(), "", XmlMessage.new()))

func _receive_broadcast(header, data: String) -> void:
	var message := XmlMessage.new(data)
	if not message.is_valid():
		return
	var msg_type := Helper.index_of(_D.MessageTypeNames, message.header(_D.XN_TYPE))
	if msg_type < 0:
		return
	var user_id := message.header(_D.XN_FROM)
	if user_id.is_empty() or user_id == _local_id():
		return
	match msg_type:
		_D.MessageType.MT_Announce:
			_process_announce(message, header.get("address", ""))
		_D.MessageType.MT_Depart:
			_remove_user(user_id, true)
		_D.MessageType.MT_Broadcast:
			var body := message.data(_D.XN_BROADCAST)
			if body.is_empty():
				body = message.data(_D.XN_MESSAGE)
			message_received.emit(msg_type, user_id, _user_name(user_id), body)
		_D.MessageType.MT_Status:
			_update_user(user_id, "status", message.data(_D.XN_STATUS))
			user_status_changed.emit(user_id, message.data(_D.XN_STATUS))

func _process_announce(message: XmlMessage, address: String) -> void:
	var user_id := message.header(_D.XN_FROM)
	var announced_address := message.data(_D.XN_ADDRESS)
	if not announced_address.is_empty():
		address = announced_address
	var user := {
		"id": user_id,
		"version": message.data(_D.XN_VERSION),
		"address": address,
		"name": message.data(_D.XN_NAME),
		"status": message.data(_D.XN_STATUS),
		"avatar": int(message.data(_D.XN_AVATAR)) if message.data(_D.XN_AVATAR).is_valid_int() else 0,
		"group": message.data(_D.XN_GROUP),
		"note": message.data(_D.XN_NOTE),
		"caps": int(message.data(_D.XN_USERCAPS)) if message.data(_D.XN_USERCAPS).is_valid_int() else 0
	}
	if str(user["name"]).is_empty():
		user["name"] = user_id
	var added := _upsert_user(user)
	if added:
		user_added.emit(user.duplicate(true))
	network.add_connection.call_deferred(user_id, address)

func _receive_message(transport_header, data: String) -> void:
	var parsed := Message.get_header(data)
	if parsed.is_empty():
		return
	parsed["address"] = transport_header.get("address", "")
	if not _add_received_message(parsed["id"], parsed["userId"]):
		return
	_process_message(parsed["type"], parsed)

func _process_message(msg_type: int, header: Dictionary) -> void:
	var message: XmlMessage = header.get("message")
	if not message:
		return
	var user_id := str(header.get("userId", ""))
	var name := _user_name(user_id)
	match msg_type:
		_D.MessageType.MT_Message:
			message_received.emit(msg_type, user_id, name, message.data(_D.XN_MESSAGE))
			_send_acknowledge(user_id, int(header["id"]))
		_D.MessageType.MT_GroupMessage:
			var body := message.data(_D.XN_GROUPMESSAGE)
			if body.is_empty(): body = message.data(_D.XN_MESSAGE)
			message_received.emit(msg_type, user_id, name, body)
		_D.MessageType.MT_PublicMessage:
			message_received.emit(msg_type, user_id, name, message.data(_D.XN_MESSAGE))
		_D.MessageType.MT_Status:
			var status := message.data(_D.XN_STATUS)
			_update_user(user_id, "status", status)
			user_status_changed.emit(user_id, status)
		_D.MessageType.MT_UserName:
			_update_user(user_id, "name", message.data(_D.XN_NAME))
		_D.MessageType.MT_Note:
			_update_user(user_id, "note", message.data(_D.XN_NOTE))
		_D.MessageType.MT_ChatState:
			user_typing.emit(user_id, name, message.data(_D.XN_CHATSTATE))
		_D.MessageType.MT_UserData:
			_process_user_data(user_id, header.get("address", ""), message)
		_D.MessageType.MT_Query:
			_process_query(user_id, int(header["id"]), message)
		_D.MessageType.MT_Ping:
			_send_acknowledge(user_id, int(header["id"]))
		_D.MessageType.MT_Acknowledge:
			_remove_pending_message(int(message.data(_D.XN_MESSAGEID)))
		_D.MessageType.MT_File, _D.MessageType.MT_Avatar:
			_process_file_message(msg_type, user_id, header.get("address", ""), message)
		_D.MessageType.MT_Folder:
			message_received.emit(msg_type, user_id, name, message.get_xml())

func _process_user_data(user_id: String, address: String, message: XmlMessage) -> void:
	if message.data(_D.XN_QUERYOP) == _D.QueryOpNames[_D.QueryOp.QO_Get]:
		_send_user_data(user_id, _D.QueryOp.QO_Result)
	var actual_id := message.data(_D.XN_USERID)
	if actual_id.is_empty(): actual_id = user_id
	var actual_address := message.data(_D.XN_ADDRESS)
	if actual_address.is_empty(): actual_address = address
	var user := {
		"id": actual_id,
		"version": message.data(_D.XN_VERSION),
		"address": actual_address,
		"name": message.data(_D.XN_NAME),
		"status": message.data(_D.XN_STATUS),
		"avatar": int(message.data(_D.XN_AVATAR)) if message.data(_D.XN_AVATAR).is_valid_int() else 0,
		"group": message.data(_D.XN_GROUP),
		"note": message.data(_D.XN_NOTE),
		"caps": int(message.data(_D.XN_USERCAPS)) if message.data(_D.XN_USERCAPS).is_valid_int() else 0
	}
	var added := _upsert_user(user)
	if added:
		user_added.emit(user.duplicate(true))
	_send_avatar_init(actual_id)

func _send_user_data(user_id: String, query_op: int) -> void:
	var xml := XmlMessage.new()
	for pair in [
		[_D.XN_USERID, local_user.get("id", "")], [_D.XN_NAME, local_user.get("name", "")],
		[_D.XN_ADDRESS, local_user.get("address", "")], [_D.XN_VERSION, local_user.get("version", "")],
		[_D.XN_STATUS, local_user.get("status", "")], [_D.XN_AVATAR, str(local_user.get("avatar", 0))],
		[_D.XN_NOTE, local_user.get("note", "")], [_D.XN_USERCAPS, str(local_user.get("caps", 0))],
		[_D.XN_GROUP, local_user.get("group", _D.GRP_DEFAULT)]
	]:
		xml.add_data(pair[0], str(pair[1]))
	xml.add_data(_D.XN_QUERYOP, _D.QueryOpNames[query_op])
	send_message(_D.MessageType.MT_UserData, user_id, xml)

func _process_query(user_id: String, incoming_id: int, message: XmlMessage) -> void:
	var op := message.data(_D.XN_QUERYOP)
	if op == _D.QueryOpNames[_D.QueryOp.QO_Get]:
		var reply := _build_user_info()
		reply.add_data(_D.XN_MESSAGEID, str(incoming_id))
		reply.add_data(_D.XN_QUERYOP, _D.QueryOpNames[_D.QueryOp.QO_Result])
		send_message(_D.MessageType.MT_Query, user_id, reply)
	elif op == _D.QueryOpNames[_D.QueryOp.QO_Result]:
		_remove_pending_message(int(message.data(_D.XN_MESSAGEID)))
		var info := _xml_to_user_info(message)
		user_info_received.emit(user_id, info)
		message_received.emit(_D.MessageType.MT_Query, user_id, _user_name(user_id), message.get_xml())

func _build_user_info() -> XmlMessage:
	var xml := XmlMessage.new()
	for pair in [
		[_D.XN_USERID, local_user.get("id", "")], [_D.XN_NAME, local_user.get("name", "")],
		[_D.XN_ADDRESS, local_user.get("address", "")], [_D.XN_VERSION, local_user.get("version", "")],
		[_D.XN_STATUS, local_user.get("status", "")], [_D.XN_NOTE, local_user.get("note", "")],
		[_D.XN_LOGON, local_user.get("logon", "")], [_D.XN_HOST, local_user.get("host", "")],
		[_D.XN_OS, local_user.get("os", "")], [_D.XN_FIRSTNAME, local_user.get("firstname", "")],
		[_D.XN_LASTNAME, local_user.get("lastname", "")], [_D.XN_ABOUT, local_user.get("about", "")]
	]:
		xml.add_data(pair[0], str(pair[1]))
	return xml

func _xml_to_user_info(message: XmlMessage) -> Dictionary:
	return {
		"id": message.data(_D.XN_USERID), "name": message.data(_D.XN_NAME),
		"address": message.data(_D.XN_ADDRESS), "version": message.data(_D.XN_VERSION),
		"status": message.data(_D.XN_STATUS), "note": message.data(_D.XN_NOTE),
		"logon": message.data(_D.XN_LOGON), "host": message.data(_D.XN_HOST),
		"os": message.data(_D.XN_OS), "first_name": message.data(_D.XN_FIRSTNAME),
		"last_name": message.data(_D.XN_LASTNAME), "about": message.data(_D.XN_ABOUT)
	}

func _process_file_message(msg_type: int, user_id: String, address: String, message: XmlMessage) -> void:
	var file_type := Helper.index_of(_D.FileTypeNames, message.data(_D.XN_FILETYPE))
	if file_type == _D.FileType.FT_Avatar:
		_process_avatar_file(user_id, message, message.data(_D.XN_FILEID), message.data(_D.XN_MODE), message.data(_D.XN_FILEOP))
		return
	var operation := Helper.index_of(_D.FileOpNames, message.data(_D.XN_FILEOP))
	var remote_mode := Helper.index_of(_D.FileModeNames, message.data(_D.XN_MODE))
	var local_mode := _D.FileMode.FM_Receive if remote_mode == _D.FileMode.FM_Send else _D.FileMode.FM_Send
	var file_id := message.data(_D.XN_FILEID)
	match operation:
		_D.FileOp.FO_Request:
			var transfer := {
				"id": file_id, "user_id": user_id, "name": message.data(_D.XN_FILENAME),
				"path": "", "size": int(message.data(_D.XN_FILESIZE)), "transferred": 0,
				"mode": "receive", "status": "request"
			}
			_incoming_files[file_id] = transfer
			file_transfer_requested.emit(transfer.duplicate(true))
			if bool(_settings.get("auto_accept_files", false)):
				accept_file(user_id, file_id)
		_D.FileOp.FO_Accept:
			if local_mode == _D.FileMode.FM_Send and _outgoing_files.has(file_id):
				var transfer: Dictionary = _outgoing_files[file_id]
				transfer["status"] = "transferring"
				_outgoing_files[file_id] = transfer
				var send_xml := _file_xml(transfer, _D.FileMode.FM_Send, _D.FileOp.FO_Accept)
				network.init_send_file(user_id, address, send_xml.get_xml())
				file_transfer_updated.emit(transfer.duplicate(true))
		_D.FileOp.FO_Decline:
			if _outgoing_files.has(file_id):
				var transfer: Dictionary = _outgoing_files[file_id]
				transfer["status"] = "declined"
				file_transfer_updated.emit(transfer.duplicate(true))
				_outgoing_files.erase(file_id)
		_D.FileOp.FO_Cancel, _D.FileOp.FO_Abort:
			network.file_operation(local_mode, user_id, message.get_xml())
			var transfer: Dictionary = _outgoing_files.get(file_id, _incoming_files.get(file_id, {}))
			if not transfer.is_empty():
				transfer["status"] = "cancelled" if operation == _D.FileOp.FO_Cancel else "failed"
				file_transfer_updated.emit(transfer.duplicate(true))

func _file_xml(transfer: Dictionary, mode: int, operation: int) -> XmlMessage:
	var xml := XmlMessage.new()
	xml.add_data(_D.XN_FILEID, str(transfer.get("id", "")))
	xml.add_data(_D.XN_FILEPATH, str(transfer.get("path", "")))
	xml.add_data(_D.XN_FILENAME, str(transfer.get("name", "")))
	xml.add_data(_D.XN_FILESIZE, str(transfer.get("size", 0)))
	xml.add_data(_D.XN_FILETYPE, _D.FileTypeNames[_D.FileType.FT_Normal])
	xml.add_data(_D.XN_MODE, _D.FileModeNames[mode])
	xml.add_data(_D.XN_FILEOP, _D.FileOpNames[operation])
	return xml

func _receive_progress(_user_id: String, data: String) -> void:
	var message := XmlMessage.new(data)
	var user_id := message.header(_D.XN_FROM)
	var file_id := message.data(_D.XN_FILEID)
	var file_type := Helper.index_of(_D.FileTypeNames, message.data(_D.XN_FILETYPE))
	if file_type == _D.FileType.FT_Avatar:
		_process_avatar_file(user_id, message, file_id, message.data(_D.XN_MODE), message.data(_D.XN_FILEOP))
		return
	var mode := message.data(_D.XN_MODE)
	var operation := Helper.index_of(_D.FileOpNames, message.data(_D.XN_FILEOP))
	var transfer: Dictionary = _outgoing_files.get(file_id, {}) if mode == _D.FileModeNames[_D.FileMode.FM_Send] else _incoming_files.get(file_id, {})
	if transfer.is_empty():
		return
	match operation:
		_D.FileOp.FO_Progress:
			transfer["transferred"] = int(message.data(_D.XN_FILESIZE))
			transfer["status"] = "transferring"
		_D.FileOp.FO_Complete:
			transfer["transferred"] = transfer.get("size", 0)
			transfer["status"] = "complete"
			if mode == _D.FileModeNames[_D.FileMode.FM_Receive]:
				transfer["path"] = message.data(_D.XN_FILEPATH)
		_D.FileOp.FO_Error:
			transfer["status"] = "failed"
	file_transfer_updated.emit(transfer.duplicate(true))
	if mode == _D.FileModeNames[_D.FileMode.FM_Send]:
		_outgoing_files[file_id] = transfer
	else:
		_incoming_files[file_id] = transfer

func _send_avatar_init(user_id: String) -> void:
	var path := _local_avatar_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if not file: return
	var size := file.get_length()
	file.close()
	var file_id := (str(Time.get_unix_time_from_system()) + _local_id() + user_id).md5_text()
	var message := XmlMessage.new()
	message.add_data(_D.XN_FILEID, file_id)
	message.add_data(_D.XN_FILEPATH, path)
	message.add_data(_D.XN_FILENAME, path.get_file())
	message.add_data(_D.XN_FILESIZE, str(size))
	message.add_data(_D.XN_FILETYPE, _D.FileTypeNames[_D.FileType.FT_Avatar])
	message.add_data(_D.XN_MODE, _D.FileModeNames[_D.FileMode.FM_Send])
	message.add_data(_D.XN_FILEOP, _D.FileOpNames[_D.FileOp.FO_Init])
	_avatar_send_map[file_id] = message
	send_message(_D.MessageType.MT_Avatar, user_id, message)

func _process_avatar_file(user_id: String, message: XmlMessage, file_id: String, mode: String, operation: String) -> void:
	if operation == _D.FileOpNames[_D.FileOp.FO_Init]:
		var path := _avatar_cache_path(user_id)
		var receive_message := message.clone()
		receive_message.remove_data(_D.XN_FILEPATH)
		receive_message.add_data(_D.XN_FILEPATH, path)
		network.init_receive_file(user_id, get_user(user_id).get("address", ""), receive_message.get_xml())
		var reply := XmlMessage.new()
		reply.add_data(_D.XN_FILEID, file_id)
		reply.add_data(_D.XN_FILETYPE, _D.FileTypeNames[_D.FileType.FT_Avatar])
		reply.add_data(_D.XN_MODE, _D.FileModeNames[_D.FileMode.FM_Receive])
		reply.add_data(_D.XN_FILEOP, _D.FileOpNames[_D.FileOp.FO_Accept])
		send_message(_D.MessageType.MT_Avatar, user_id, reply)
	elif operation == _D.FileOpNames[_D.FileOp.FO_Accept]:
		var send_message: XmlMessage = _avatar_send_map.get(file_id, null)
		if send_message:
			network.init_send_file(user_id, get_user(user_id).get("address", ""), send_message.get_xml())
	elif operation == _D.FileOpNames[_D.FileOp.FO_Complete]:
		_avatar_send_map.erase(file_id)
		if mode == _D.FileModeNames[_D.FileMode.FM_Receive]:
			user_avatar_changed.emit(user_id)

func _on_new_connection(user_id: String, _address: String) -> void:
	_send_user_data(user_id, _D.QueryOp.QO_Get)

func _on_connection_lost(user_id: String) -> void:
	_remove_user(user_id, true)

func _send_acknowledge(user_id: String, message_id: int) -> void:
	var reply := XmlMessage.new()
	reply.add_data(_D.XN_MESSAGEID, str(message_id))
	send_message(_D.MessageType.MT_Acknowledge, user_id, reply)

func _receive_web_message(data: String) -> void:
	message_received.emit(_D.MessageType.MT_WebFailed, "", "", data)

func _on_network_state_changed() -> void:
	connection_state_changed.emit()

func _upsert_user(user: Dictionary) -> bool:
	var user_id := str(user.get("id", ""))
	if user_id.is_empty() or user_id == _local_id():
		return false
	for index in range(user_list.size()):
		if user_list[index].get("id", "") == user_id:
			for key in user:
				if not str(user[key]).is_empty() or key in ["avatar", "caps"]:
					user_list[index][key] = user[key]
			return false
	user_list.append(user.duplicate(true))
	return true

func _update_user(user_id: String, field: String, value) -> void:
	for index in range(user_list.size()):
		if user_list[index].get("id", "") == user_id:
			user_list[index][field] = value
			return

func _remove_user(user_id: String, emit_signal := false) -> void:
	for index in range(user_list.size() - 1, -1, -1):
		if user_list[index].get("id", "") == user_id:
			user_list.remove_at(index)
			for pending_index in range(_pending_list.size() - 1, -1, -1):
				if _pending_list[pending_index].get("user_id", "") == user_id:
					_pending_list.remove_at(pending_index)
			if emit_signal:
				user_removed.emit(user_id)
			return

func _add_received_message(message_id: int, user_id: String) -> bool:
	for received in _received_list:
		if received.get("id", -1) == message_id and received.get("user_id", "") == user_id:
			return false
	_received_list.append({"id": message_id, "user_id": user_id})
	if _received_list.size() > 256:
		_received_list.pop_front()
	return true

func _user_name(user_id: String) -> String:
	var user := get_user(user_id)
	var name := str(user.get("name", "")).strip_edges()
	return name if not name.is_empty() else user_id

func _local_id() -> String:
	return str(local_user.get("id", ""))

func _avatar_cache_path(user_id: String) -> String:
	return "user://cache/avt_" + user_id.validate_filename() + ".png"

func _local_avatar_path() -> String:
	var avatar_id := int(local_user.get("avatar", 0))
	var candidates: Array[String] = ["user://avt_local.png", "res://Assets/Avatars/avatar_" + str(avatar_id) + ".png"]
	if OS.get_name() == "Windows":
		var local_app_data := OS.get_environment("LOCALAPPDATA")
		if not local_app_data.is_empty():
			candidates.append(local_app_data.path_join("LAN Messenger").path_join("LAN Messenger").path_join("avt_local.png"))
	candidates.append("res://Assets/Avatars/avatar_default.png")
	for path in candidates:
		if FileAccess.file_exists(path): return path
	return ""

func _unique_download_path(file_name: String) -> String:
	var base_dir := str(_settings.get("download_dir", "user://downloads"))
	var safe_name := file_name.validate_filename()
	if safe_name.is_empty(): safe_name = "received_file"
	var candidate := base_dir.path_join(safe_name)
	var index := 1
	while FileAccess.file_exists(candidate):
		candidate = base_dir.path_join(safe_name.get_basename() + " (" + str(index) + ")." + safe_name.get_extension())
		index += 1
	return candidate
