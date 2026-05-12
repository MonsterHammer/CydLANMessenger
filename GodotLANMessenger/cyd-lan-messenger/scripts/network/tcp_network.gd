extends Node
const _D = preload("res://scripts/network/definitions.gd")
signal new_connection(user_id, address)
signal connection_lost(user_id)
signal message_received(pHeader, data)
signal progress_received(user_id, data)

var is_running: bool = false
var local_id: String = ""
var _server: TCPServer = null
var _send_list: Array = []
var _receive_list: Array = []
var _message_map: Dictionary = {}
var _loc_msg_stream: Node = null
var _tcp_port: int = 0
var _crypto = null
var _pending_sockets: Array = []

func _init():
	_server = TCPServer.new()

func init_config(port: int = 0, settings: Dictionary = {}) -> void:
	_tcp_port = port if port > 0 else settings.get("tcp_port", 12112)

func start() -> void:
	if _server.listen(_tcp_port) != OK:
		push_error("TCP server failed to listen on port ", _tcp_port)
	is_running = true

func stop() -> void:
	_server.stop()
	if _loc_msg_stream:
		_loc_msg_stream.stop()
	for user_id in _message_map:
		var stream = _message_map[user_id]
		if stream: stream.stop()
	_message_map.clear()
	is_running = false

func set_local_id(id: String) -> void:
	local_id = id

func set_crypto(crypto) -> void:
	_crypto = crypto

func add_connection(user_id: String, address: String) -> void:
	if not is_running: return
	var stream = preload("msg_stream.gd").new(local_id, user_id, address, _tcp_port)
	stream.connection_lost.connect(_on_msg_stream_connection_lost)
	stream.message_received.connect(_on_receive_message)
	if user_id == local_id:
		_loc_msg_stream = stream
	else:
		_message_map[user_id] = stream
	stream.init_client()
	add_child(stream)

func send_message(receiver_id: String, data: String) -> void:
	if not is_running: return
	var stream = _loc_msg_stream if receiver_id == local_id else _message_map.get(receiver_id, null)
	if not stream: return
	var clear_data = data.to_utf8_buffer()
	var cipher_data = clear_data
	if _crypto:
		cipher_data = _crypto.encrypt(receiver_id, clear_data)
	if cipher_data.is_empty(): return
	cipher_data = Datagram.add_header(_D.DatagramType.DT_Message, cipher_data)
	stream.send_message(cipher_data)

func init_send_file(receiver_id: String, address: String, data: String) -> void:
	var msg = XmlMessage.new(data)
	var file_type = Helper.index_of(_D.FileTypeNames, msg.data(_D.XN_FILETYPE))
	var sender = preload("file_sender.gd").new(
		msg.data(_D.XN_FILEID), local_id, receiver_id,
		msg.data(_D.XN_FILEPATH), msg.data(_D.XN_FILENAME),
		int(msg.data(_D.XN_FILESIZE)), address, _tcp_port, file_type)
	sender.progress_updated.connect(_on_file_progress_updated)
	_send_list.append(sender)
	add_child(sender)
	sender.init_send()

func init_receive_file(sender_id: String, address: String, data: String) -> void:
	var msg = XmlMessage.new(data)
	var file_type = Helper.index_of(_D.FileTypeNames, msg.data(_D.XN_FILETYPE))
	var receiver = preload("file_receiver.gd").new(
		msg.data(_D.XN_FILEID), sender_id,
		msg.data(_D.XN_FILEPATH), msg.data(_D.XN_FILENAME),
		int(msg.data(_D.XN_FILESIZE)), address, _tcp_port, file_type)
	receiver.progress_updated.connect(_on_file_progress_updated)
	_receive_list.append(receiver)
	add_child(receiver)

func file_operation(mode: int, user_id: String, data: String) -> void:
	var msg = XmlMessage.new(data)
	var file_op = Helper.index_of(_D.FileOpNames, msg.data(_D.XN_FILEOP))
	var fid = msg.data(_D.XN_FILEID)
	if mode == _D.FileMode.FM_Send:
		var sender = _get_sender(fid, user_id)
		if not sender: return
		match file_op:
			_D.FileOp.FO_Cancel, _D.FileOp.FO_Abort:
				sender.stop()
				_remove_sender(sender)
	else:
		var receiver = _get_receiver(fid, user_id)
		if not receiver: return
		match file_op:
			_D.FileOp.FO_Cancel, _D.FileOp.FO_Abort:
				receiver.stop()
				_remove_receiver(receiver)

func _process(delta):
	if not _server or not is_running:
		return
	if _server.is_connection_available():
		var socket = _server.take_connection()
		_pending_sockets.append(socket)

	if _pending_sockets.size() > 0:
		var i = 0
		while i < _pending_sockets.size():
			var sock = _pending_sockets[i]
			if sock.get_available_bytes() >= 3:
				var result = sock.get_data(64)
				if result["error"] == OK:
					var prefix = result["data"]
					if prefix.size() >= 3 and prefix.slice(0, 3).get_string_from_utf8() == "MSG":
						var user_id = prefix.slice(3).get_string_from_utf8()
						_add_msg_socket(user_id, sock)
					elif prefix.size() >= 4 and prefix.slice(0, 4).get_string_from_utf8() == "FILE":
						var file_id = prefix.slice(4, 36).get_string_from_utf8()
						var user_id = prefix.slice(36).get_string_from_utf8()
						_add_file_socket(file_id, user_id, sock)
				_pending_sockets.remove_at(i)
			else:
				i += 1

func _on_msg_stream_connection_lost(user_id: String) -> void:
	connection_lost.emit(user_id)

func _on_file_progress_updated(mode: int, op: int, ftype: int, fid: String, user_id: String, data: String) -> void:
	var msg = XmlMessage.new()
	msg.add_header(_D.XN_FROM, user_id)
	msg.add_header(_D.XN_TO, local_id)
	msg.add_data(_D.XN_MODE, _D.FileModeNames[mode])
	msg.add_data(_D.XN_FILETYPE, _D.FileTypeNames[ftype])
	msg.add_data(_D.XN_FILEOP, _D.FileOpNames[op])
	msg.add_data(_D.XN_FILEID, fid)
	match op:
		_D.FileOp.FO_Complete, _D.FileOp.FO_Error:
			msg.add_data(_D.XN_FILEPATH, data)
			if mode == _D.FileMode.FM_Send:
				_remove_sender(_get_sender(fid, user_id))
			else:
				_remove_receiver(_get_receiver(fid, user_id))
		_D.FileOp.FO_Progress:
			msg.add_data(_D.XN_FILESIZE, data)
	var sz = msg.get_xml()
	progress_received.emit(user_id, sz)

func _on_receive_message(user_id: String, address: String, data: PackedByteArray) -> void:
	var pHeader = Datagram.get_header(data)
	if pHeader.is_empty(): return
	pHeader["userId"] = user_id
	pHeader["address"] = address
	var cipher_data = Datagram.get_data(data)
	match pHeader["type"]:
		_D.DatagramType.DT_PublicKey:
			_send_session_key(user_id, cipher_data)
		_D.DatagramType.DT_Handshake:
			if _crypto: _crypto.retrieve_aes(user_id, cipher_data)
			new_connection.emit(user_id, address)
		_D.DatagramType.DT_Message:
			var clear_data = cipher_data
			if _crypto: clear_data = _crypto.decrypt(user_id, cipher_data)
			if clear_data.is_empty(): return
			var sz = clear_data.get_string_from_utf8()
			message_received.emit(pHeader, sz)

func _add_msg_socket(user_id: String, socket) -> void:
	var address = socket.get_connected_host()
	var stream = preload("msg_stream.gd").new(local_id, user_id, address, _tcp_port)
	stream.connection_lost.connect(_on_msg_stream_connection_lost)
	stream.message_received.connect(_on_receive_message)
	_message_map[user_id] = stream
	stream.init_server(socket)
	add_child(stream)
	_send_public_key(user_id)

func _add_file_socket(file_id: String, user_id: String, socket) -> void:
	var receiver = _get_receiver(file_id, user_id)
	if receiver:
		receiver.init_receive(socket)

func _send_public_key(user_id: String) -> void:
	var stream = _message_map.get(user_id, null)
	if not stream: return
	var public_key = _crypto.public_key if _crypto else PackedByteArray()
	public_key = Datagram.add_header(_D.DatagramType.DT_PublicKey, public_key)
	stream.send_message(public_key)

func _send_session_key(user_id: String, public_key: PackedByteArray) -> void:
	var stream = _loc_msg_stream if user_id == local_id else _message_map.get(user_id, null)
	if not stream: return
	var session_key = PackedByteArray()
	if _crypto: session_key = _crypto.generate_aes(user_id, public_key)
	session_key = Datagram.add_header(_D.DatagramType.DT_Handshake, session_key)
	stream.send_message(session_key)

func _get_sender(fid: String, uid: String):
	for s in _send_list:
		if s.id == fid and s.peer_id == uid: return s
	return null

func _get_receiver(fid: String, uid: String):
	for r in _receive_list:
		if r.id == fid and r.peer_id == uid: return r
	return null

func _remove_sender(s):
	var idx = _send_list.find(s)
	if idx >= 0: _send_list.remove_at(idx)
	s.queue_free()

func _remove_receiver(r):
	var idx = _receive_list.find(r)
	if idx >= 0: _receive_list.remove_at(idx)
	r.queue_free()
