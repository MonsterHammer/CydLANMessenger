extends Node
signal message_received(type, user_id, pMessage)
signal connection_state_changed

var local_user: Dictionary = {}
var user_list: Array = []
var group_list: Array = []

var _network: Node = null
var _settings: Dictionary = {}
var _msg_id: int = 0
var _received_list: Array = []
var _pending_list: Array = []
var _file_list: Array = []
var _folder_list: Array = []
var _n_timeout: int = 0
var _n_max_retry: int = 5
var _loopback: bool = false
var _user_group_map: Dictionary = {}

func _init():
	_network = preload("network_manager.gd").new()

func init_config(settings: Dictionary = {}) -> void:
	_settings = settings
	_network.init_config(_settings)

func start() -> void:
	_network.broadcast_received.connect(_receive_broadcast)
	_network.new_connection.connect(_new_connection)
	_network.connection_lost.connect(_connection_lost)
	_network.message_received.connect(_receive_message)
	_network.progress_received.connect(_receive_progress)
	_network.web_message_received.connect(_receive_web_message)
	_network.connection_state_changed.connect(_network_connection_state_changed)
	_network.start()

func stop() -> void:
	_network.stop()

func is_connected() -> bool:
	return _network.is_connected

func can_receive() -> bool:
	return _network.can_receive

func set_loopback(on: bool) -> void:
	_loopback = on

func get_user(user_id: String) -> Dictionary:
	for u in user_list:
		if u["id"] == user_id: return u
	return {}

func send_broadcast(type: int, pMessage: XmlMessage) -> void:
	_prepare_broadcast(type, pMessage)

func send_message(msg_type: int, user_id: String, pMessage: XmlMessage) -> void:
	_msg_id += 1
	var msg_id = _msg_id
	_prepare_message(msg_type, msg_id, false, user_id, pMessage)
	_add_pending_msg(msg_id, msg_type, user_id, pMessage)

func send_web_message(msg_type: int, pMessage: XmlMessage) -> void:
	_prepare_broadcast(msg_type, pMessage)

func settings_changed() -> void:
	_network.settings_changed()

func update_group(op: int, value1, value2) -> void:
	pass

func save_groups() -> void:
	pass

func user_count() -> int:
	return user_list.size()

func _create_user_id(address: String, user_name: String) -> String:
	return address + DELIMITER + user_name

func _get_user_name() -> String:
	return _settings.get("user_name", Helper.get_logon_name())

func _load_groups() -> void:
	pass

func _get_user_info(pMessage: XmlMessage) -> void:
	pass

func _send_user_data(type: int, op: int, user_id: String, address: String) -> void:
	pass

func _prepare_broadcast(type: int, pMessage: XmlMessage) -> void:
	pass

func _prepare_message(type: int, msg_id: int, retry: bool, user_id: String, pMessage: XmlMessage) -> void:
	var szMessage = Message.add_header(type, msg_id, _local_id(), user_id, pMessage)
	var user = get_user(user_id)
	_network.send_message(user_id, user.get("address", ""), szMessage)

func _prepare_file(type: int, msg_id: int, retry: bool, user_id: String, pMessage: XmlMessage) -> void:
	var szMessage = Message.add_header(type, msg_id, _local_id(), user_id, pMessage)
	var user = get_user(user_id)
	_network.init_send_file(user_id, user.get("address", ""), szMessage)

func _prepare_folder(type: int, msg_id: int, retry: bool, user_id: String, pMessage: XmlMessage) -> void:
	var szMessage = Message.add_header(type, msg_id, _local_id(), user_id, pMessage)
	var user = get_user(user_id)
	_network.init_send_file(user_id, user.get("address", ""), szMessage)

func _add_pending_msg(msg_id: int, type: int, user_id: String, pMessage: XmlMessage) -> void:
	_pending_list.append({
		"msgId": msg_id, "active": false, "timeStamp": Time.get_datetime_dict_from_system(),
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

func _check_pending_msg() -> void:
	pass

func _resend_message(type: int, msg_id: int, user_id: String, pMessage: XmlMessage) -> void:
	_prepare_message(type, msg_id, true, user_id, pMessage)

func _add_received_msg(msg_id: int, user_id: String) -> bool:
	for r in _received_list:
		if r["msgId"] == msg_id and r["userId"] == user_id: return false
	_received_list.append({ "msgId": msg_id, "userId": user_id })
	if _received_list.size() > 100:
		_received_list.pop_front()
	return true

func _add_user(sz_user_id: String, sz_version: String, sz_address: String, sz_name: String,
		sz_status: String, sz_avatar: String, sz_note: String, sz_caps: String, sz_group: String = "") -> bool:
	if not _loopback and sz_user_id == _local_id():
		return false
	for u in user_list:
		if u["id"] == sz_user_id: return false
	var user = {
		"id": sz_user_id, "version": sz_version, "address": sz_address,
		"name": sz_name, "status": sz_status, "avatar": int(sz_avatar),
		"group": sz_group, "note": sz_note, "caps": int(sz_caps)
	}
	user_list.append(user)
	return true

func _update_user(type: int, sz_user_id: String, sz_user_data: String) -> void:
	pass

func _remove_user(sz_user_id: String) -> void:
	for i in range(user_list.size() - 1, -1, -1):
		if user_list[i]["id"] == sz_user_id:
			user_list.remove_at(i)
			return

func _add_file_transfer(mode: int, user_id: String, pMessage: XmlMessage) -> bool:
	_file_list.append({
		"id": pMessage.data(XN_FILEID), "userId": user_id,
		"path": pMessage.data(XN_FILEPATH), "name": pMessage.data(XN_FILENAME),
		"size": int(pMessage.data(XN_FILESIZE)), "pos": 0, "mode": mode,
		"op": FileOp.FO_Init, "type": FileType.FT_Normal
	})
	return true

func _update_file_transfer(mode: int, file_op: int, user_id: String, pMessage: XmlMessage) -> bool:
	var fid = pMessage.data(XN_FILEID)
	var idx = -1
	for i in range(_file_list.size()):
		if _file_list[i]["id"] == fid and _file_list[i]["userId"] == user_id:
			idx = i
			break
	if idx < 0: return false
	match file_op:
		FileOp.FO_Progress:
			_file_list[idx]["pos"] = pMessage.data(XN_FILESIZE).to_int()
	return true

func _get_free_file_name(file_name: String) -> String:
	return file_name

func _add_folder_transfer(mode: int, user_id: String, pMessage: XmlMessage) -> bool:
	return true

func _update_folder_transfer(mode: int, file_op: int, user_id: String, pMessage: XmlMessage) -> bool:
	return true

func _get_free_folder_name(folder_name: String) -> String:
	return folder_name

func _get_folder_path(folder_id: String, user_id: String, mode: int) -> String:
	return ""

func _local_id() -> String:
	return local_user.get("id", "")

func _receive_broadcast(pHeader, data: String) -> void:
	pass

func _receive_message(pHeader, data: String) -> void:
	var header = Message.get_header(data)
	if header.is_empty(): return
	if not _add_received_msg(header["id"], header["userId"]): return
	_process_message(header["type"], header)

func _receive_web_message(data: String) -> void:
	pass

func _new_connection(user_id: String, address: String) -> void:
	pass

func _connection_lost(user_id: String) -> void:
	_remove_all_pending_msg(user_id)

func _receive_progress(user_id: String, data: String) -> void:
	pass

func _network_connection_state_changed() -> void:
	connection_state_changed.emit()

func _process_message(msg_type: int, pHeader) -> void:
	var pMessage = pHeader.get("message", XmlMessage.new())
	message_received.emit(msg_type, pHeader["userId"], pMessage)
