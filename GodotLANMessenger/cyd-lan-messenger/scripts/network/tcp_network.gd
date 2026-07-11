extends Node

const _D = preload("res://scripts/network/definitions.gd")
const _MsgStream = preload("msg_stream.gd")
const _FileSender = preload("file_sender.gd")
const _FileReceiver = preload("file_receiver.gd")

signal new_connection(user_id, address)
signal connection_lost(user_id)
signal message_received(pHeader, data)
signal progress_received(user_id, data)

const CONNECT_DELAY_FAST_MS := 100
const CONNECT_DELAY_FALLBACK_MS := 400
const IDENTIFY_TIMEOUT_MS := 3000
const MAX_IDENTITY_BYTES := 512
const MAX_QUEUED_MESSAGES_PER_USER := 256

var is_running: bool = false
var local_id: String = ""

var _server: TCPServer = null
var _send_list: Array = []
var _receive_list: Array = []
var _message_map: Dictionary = {}
var _pending_message_map: Dictionary = {}
var _scheduled_connections: Dictionary = {}
var _connecting_users: Dictionary = {}
var _handshake_complete: Dictionary = {}
var _loc_msg_stream: Node = null
var _tcp_port: int = 0
var _crypto = null
var _pending_sockets: Array = []


func _init() -> void:
	_server = TCPServer.new()


func init_config(port: int = 0, settings: Dictionary = {}) -> void:
	_tcp_port = port if port > 0 else int(settings.get("tcp_port", 50000))


func start() -> void:
	if is_running:
		return
	var error := _server.listen(_tcp_port)
	if error != OK:
		push_error("CydLAN: TCP server failed to listen on port %d (%s)" % [_tcp_port, error])
		is_running = false
		return
	print("CydLAN: TCP listening on port ", _tcp_port)
	is_running = true


func stop() -> void:
	if _server:
		_server.stop()

	if _loc_msg_stream and is_instance_valid(_loc_msg_stream):
		_loc_msg_stream.stop()
		_loc_msg_stream.queue_free()
	_loc_msg_stream = null

	for stream in _message_map.values():
		if stream and is_instance_valid(stream):
			stream.stop()
			stream.queue_free()
	_message_map.clear()
	_scheduled_connections.clear()
	_connecting_users.clear()
	_handshake_complete.clear()
	_pending_message_map.clear()

	for pending in _pending_sockets:
		var socket: StreamPeerTCP = pending.get("socket")
		if socket:
			socket.disconnect_from_host()
	_pending_sockets.clear()

	for sender in _send_list:
		if sender and is_instance_valid(sender):
			sender.stop()
			sender.queue_free()
	_send_list.clear()
	for receiver in _receive_list:
		if receiver and is_instance_valid(receiver):
			receiver.stop()
			receiver.queue_free()
	_receive_list.clear()

	is_running = false


func set_local_id(id: String) -> void:
	local_id = id


func set_crypto(crypto) -> void:
	_crypto = crypto


func add_connection(user_id: String, address: String) -> void:
	if not is_running:
		return
	user_id = user_id.strip_edges()
	address = address.strip_edges()
	if user_id.is_empty() or address.is_empty() or user_id == local_id:
		return
	if _has_live_stream(user_id) or _connecting_users.has(user_id):
		return
	if _scheduled_connections.has(user_id):
		_scheduled_connections[user_id]["address"] = address
		return

	# The original client connects immediately after an announce. A short,
	# deterministic grace period lets an original LAN Messenger peer connect
	# first and prevents two Godot peers from opening crossed duplicate streams.
	var delay := CONNECT_DELAY_FAST_MS
	if local_id.naturalnocasecmp_to(user_id) > 0:
		delay = CONNECT_DELAY_FALLBACK_MS
	_scheduled_connections[user_id] = {"address": address, "due": Time.get_ticks_msec() + delay}


func send_message(receiver_id: String, address: String, data: String) -> void:
	if not is_running or receiver_id.is_empty() or data.is_empty():
		return
	var stream = _message_map.get(receiver_id)
	if not _stream_is_usable(stream):
		_queue_message(receiver_id, data)
		add_connection(receiver_id, address)
		return
	_send_or_queue_message(receiver_id, data)


func _send_or_queue_message(receiver_id: String, data: String) -> void:
	var stream = _message_map.get(receiver_id)
	if not _stream_is_usable(stream):
		_queue_message(receiver_id, data)
		return

	var clear_data := data.to_utf8_buffer()
	var cipher_data := clear_data
	if _crypto and receiver_id != local_id:
		cipher_data = _crypto.encrypt(receiver_id, clear_data)
	if cipher_data.is_empty():
		_queue_message(receiver_id, data)
		return

	stream.send_message(Datagram.add_header(_D.DatagramType.DT_Message, cipher_data))


func _queue_message(receiver_id: String, data: String) -> void:
	if not _pending_message_map.has(receiver_id):
		_pending_message_map[receiver_id] = []
	var queue: Array = _pending_message_map[receiver_id]
	if queue.size() >= MAX_QUEUED_MESSAGES_PER_USER:
		queue.pop_front()
	queue.append(data)


func _flush_pending_messages(receiver_id: String) -> void:
	if not _pending_message_map.has(receiver_id):
		return
	var queued: Array = _pending_message_map[receiver_id]
	_pending_message_map.erase(receiver_id)
	for data in queued:
		_send_or_queue_message(receiver_id, data)


func init_send_file(receiver_id: String, address: String, data: String) -> void:
	var msg := XmlMessage.new(data)
	if not msg.is_valid():
		return
	var file_type := Helper.index_of(_D.FileTypeNames, msg.data(_D.XN_FILETYPE))
	var sender = _FileSender.new(
		msg.data(_D.XN_FILEID),
		local_id,
		receiver_id,
		msg.data(_D.XN_FILEPATH),
		msg.data(_D.XN_FILENAME),
		int(msg.data(_D.XN_FILESIZE)),
		address,
		_tcp_port,
		file_type
	)
	sender.progress_updated.connect(_on_file_progress_updated)
	_send_list.append(sender)
	add_child(sender)
	sender.init_send()


func init_receive_file(sender_id: String, address: String, data: String) -> void:
	var msg := XmlMessage.new(data)
	if not msg.is_valid():
		return
	var file_type := Helper.index_of(_D.FileTypeNames, msg.data(_D.XN_FILETYPE))
	var receiver = _FileReceiver.new(
		msg.data(_D.XN_FILEID),
		sender_id,
		msg.data(_D.XN_FILEPATH),
		msg.data(_D.XN_FILENAME),
		int(msg.data(_D.XN_FILESIZE)),
		address,
		_tcp_port,
		file_type
	)
	receiver.progress_updated.connect(_on_file_progress_updated)
	_receive_list.append(receiver)
	add_child(receiver)


func file_operation(mode: int, user_id: String, data: String) -> void:
	var msg := XmlMessage.new(data)
	if not msg.is_valid():
		return
	var file_op := Helper.index_of(_D.FileOpNames, msg.data(_D.XN_FILEOP))
	var file_id := msg.data(_D.XN_FILEID)
	if mode == _D.FileMode.FM_Send:
		var sender = _get_sender(file_id, user_id)
		if sender and file_op in [_D.FileOp.FO_Cancel, _D.FileOp.FO_Abort]:
			sender.stop()
			_remove_sender(sender)
	else:
		var receiver = _get_receiver(file_id, user_id)
		if receiver and file_op in [_D.FileOp.FO_Cancel, _D.FileOp.FO_Abort]:
			receiver.stop()
			_remove_receiver(receiver)


func _process(_delta: float) -> void:
	if not _server or not is_running:
		return
	_accept_pending_connections()
	_start_due_connections()
	_process_identity_sockets()


func _accept_pending_connections() -> void:
	while _server.is_connection_available():
		var socket := _server.take_connection()
		if not socket:
			continue
		print("CydLAN: TCP incoming socket from ", socket.get_connected_host())
		_pending_sockets.append(
			{
				"socket": socket,
				"buffer": PackedByteArray(),
				"last_read": 0,
				"deadline": Time.get_ticks_msec() + IDENTIFY_TIMEOUT_MS
			}
		)


func _start_due_connections() -> void:
	var now := Time.get_ticks_msec()
	for user_id in _scheduled_connections.keys():
		var item: Dictionary = _scheduled_connections[user_id]
		if now < int(item["due"]):
			continue
		_scheduled_connections.erase(user_id)
		if _has_live_stream(user_id) or _connecting_users.has(user_id):
			continue
		_begin_outgoing_connection(user_id, str(item["address"]))


func _begin_outgoing_connection(user_id: String, address: String) -> void:
	if not is_running or user_id.is_empty() or address.is_empty():
		return
	var stale = _message_map.get(user_id)
	if stale and is_instance_valid(stale):
		stale.stop()
		stale.queue_free()
	_message_map.erase(user_id)
	_handshake_complete.erase(user_id)
	if _crypto and _crypto.has_method("clear_session"):
		_crypto.clear_session(user_id)
	_connecting_users[user_id] = true
	var stream = _MsgStream.new(local_id, user_id, address, _tcp_port)
	_connect_stream_signals(stream)
	add_child(stream)
	_message_map[user_id] = stream
	stream.init_client()


func _process_identity_sockets() -> void:
	var now := Time.get_ticks_msec()
	for index in range(_pending_sockets.size() - 1, -1, -1):
		var item: Dictionary = _pending_sockets[index]
		var socket: StreamPeerTCP = item["socket"]
		if not socket:
			_pending_sockets.remove_at(index)
			continue
		socket.poll()
		var status := socket.get_status()
		if status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
			_pending_sockets.remove_at(index)
			continue
		if now >= int(item["deadline"]):
			socket.disconnect_from_host()
			_pending_sockets.remove_at(index)
			continue

		var available := socket.get_available_bytes()
		if available > 0:
			var result := socket.get_partial_data(min(available, MAX_IDENTITY_BYTES))
			if result[0] != OK or result[1].is_empty():
				continue
			var buffer: PackedByteArray = item["buffer"]
			buffer.append_array(result[1])
			item["buffer"] = buffer
			item["last_read"] = now
			_pending_sockets[index] = item
			if buffer.size() > MAX_IDENTITY_BYTES:
				socket.disconnect_from_host()
				_pending_sockets.remove_at(index)
			continue

		var buffered: PackedByteArray = item["buffer"]
		if not buffered.is_empty() and now - int(item["last_read"]) >= 15:
			if _route_identified_socket(socket, buffered):
				_pending_sockets.remove_at(index)


func _route_identified_socket(socket: StreamPeerTCP, buffer: PackedByteArray) -> bool:
	if buffer.size() >= 4 and buffer.slice(0, 4).get_string_from_utf8() == "FILE":
		if buffer.size() < 37:
			return false
		var file_id := buffer.slice(4, 36).get_string_from_utf8()
		var user_id := buffer.slice(36).get_string_from_utf8()
		if not _valid_peer_id(user_id):
			socket.disconnect_from_host()
			return true
		_add_file_socket(file_id, user_id, socket)
		return true

	if buffer.size() >= 3 and buffer.slice(0, 3).get_string_from_utf8() == "MSG":
		var user_id := buffer.slice(3).get_string_from_utf8()
		if user_id.is_empty():
			return false
		if not _valid_peer_id(user_id):
			socket.disconnect_from_host()
			return true
		_add_msg_socket(user_id, socket)
		return true

	if buffer.size() >= 4:
		socket.disconnect_from_host()
		return true
	return false


func _valid_peer_id(user_id: String) -> bool:
	if user_id.is_empty() or user_id.length() > 256:
		return false
	return not (
		user_id.contains("\n")
		or user_id.contains("\r")
		or user_id.contains("\t")
		or user_id.contains("\u0000")
	)


func _add_msg_socket(user_id: String, socket: StreamPeerTCP) -> void:
	var address := socket.get_connected_host()
	_scheduled_connections.erase(user_id)
	_connecting_users.erase(user_id)
	_handshake_complete.erase(user_id)
	if _crypto and _crypto.has_method("clear_session"):
		_crypto.clear_session(user_id)

	var existing = _message_map.get(user_id)
	if _stream_is_usable(existing):
		# Keep an already connected stream. This makes repeated announces and
		# crossed connection attempts harmless instead of replacing live state.
		if existing.is_connected():
			socket.disconnect_from_host()
			return
		existing.stop()
		existing.queue_free()

	var stream = _MsgStream.new(local_id, user_id, address, _tcp_port)
	_connect_stream_signals(stream)
	add_child(stream)
	_message_map[user_id] = stream
	stream.init_server(socket)
	print("CydLAN: TCP incoming MSG stream from ", _display_peer_id(user_id))
	_send_public_key(user_id)


func _add_file_socket(file_id: String, user_id: String, socket: StreamPeerTCP) -> void:
	var receiver = _get_receiver(file_id, user_id)
	if receiver:
		receiver.init_receive(socket)
	else:
		socket.disconnect_from_host()


func _connect_stream_signals(stream: Node) -> void:
	stream.connection_established.connect(_on_stream_established)
	stream.connection_lost.connect(_on_msg_stream_connection_lost)
	stream.message_received.connect(_on_receive_message)


func _on_stream_established(user_id: String, stream: Node) -> void:
	if _message_map.get(user_id) == stream:
		_connecting_users.erase(user_id)


func _on_msg_stream_connection_lost(user_id: String, stream: Node, was_connected: bool) -> void:
	if _message_map.get(user_id) != stream:
		if is_instance_valid(stream):
			stream.queue_free()
		return
	_message_map.erase(user_id)
	_connecting_users.erase(user_id)
	_handshake_complete.erase(user_id)
	if _crypto and _crypto.has_method("clear_session"):
		_crypto.clear_session(user_id)
	if is_instance_valid(stream):
		stream.queue_free()
	if was_connected:
		connection_lost.emit(user_id)


func _on_file_progress_updated(
	mode: int, op: int, file_type: int, file_id: String, user_id: String, data: String
) -> void:
	var msg := XmlMessage.new()
	msg.add_header(_D.XN_FROM, user_id)
	msg.add_header(_D.XN_TO, local_id)
	msg.add_data(_D.XN_MODE, _D.FileModeNames[mode])
	msg.add_data(_D.XN_FILETYPE, _D.FileTypeNames[file_type])
	msg.add_data(_D.XN_FILEOP, _D.FileOpNames[op])
	msg.add_data(_D.XN_FILEID, file_id)
	if op in [_D.FileOp.FO_Complete, _D.FileOp.FO_Error]:
		msg.add_data(_D.XN_FILEPATH, data)
		if mode == _D.FileMode.FM_Send:
			_remove_sender(_get_sender(file_id, user_id))
		else:
			_remove_receiver(_get_receiver(file_id, user_id))
	elif op == _D.FileOp.FO_Progress:
		msg.add_data(_D.XN_FILESIZE, data)
	progress_received.emit(user_id, msg.get_xml())


func _on_receive_message(user_id: String, address: String, data: PackedByteArray) -> void:
	var header := Datagram.get_header(data)
	if header.is_empty():
		return
	header["userId"] = user_id
	header["address"] = address
	var cipher_data := Datagram.get_data(data)

	match header["type"]:
		_D.DatagramType.DT_PublicKey:
			_send_session_key(user_id, cipher_data)
		_D.DatagramType.DT_Handshake:
			if _handshake_complete.has(user_id):
				return
			_ensure_key()
			if _crypto:
				_crypto.retrieve_aes(user_id, cipher_data)
			if _crypto and _crypto.has_method("has_session") and not _crypto.has_session(user_id):
				push_warning("CydLAN: Invalid handshake from %s" % _display_peer_id(user_id))
				return
			_handshake_complete[user_id] = true
			print("CydLAN: TCP handshake complete with ", _display_peer_id(user_id))
			_flush_pending_messages(user_id)
			new_connection.emit(user_id, address)
		_D.DatagramType.DT_Message:
			var clear_data := cipher_data
			if _crypto and user_id != local_id:
				clear_data = _crypto.decrypt(user_id, cipher_data)
			if clear_data.is_empty():
				push_warning("CydLAN: TCP decrypt failed from %s" % _display_peer_id(user_id))
				return
			message_received.emit(header, clear_data.get_string_from_utf8())


func _ensure_key() -> void:
	if _crypto and _crypto.public_key.is_empty():
		_crypto.generate_rsa()


func _send_public_key(user_id: String) -> void:
	_ensure_key()
	var stream = _message_map.get(user_id)
	if not _stream_is_usable(stream):
		return
	var public_key: PackedByteArray = _crypto.public_key if _crypto else PackedByteArray()
	if public_key.is_empty():
		return
	stream.send_message(Datagram.add_header(_D.DatagramType.DT_PublicKey, public_key))


func _send_session_key(user_id: String, public_key: PackedByteArray) -> void:
	var stream = _message_map.get(user_id)
	if not _stream_is_usable(stream) or not _crypto:
		return
	var session_key: PackedByteArray = _crypto.generate_aes(user_id, public_key)
	if session_key.is_empty():
		push_warning("CydLAN: Failed to create session key for %s" % _display_peer_id(user_id))
		return
	stream.send_message(Datagram.add_header(_D.DatagramType.DT_Handshake, session_key))
	_flush_pending_messages(user_id)


func _has_live_stream(user_id: String) -> bool:
	return _stream_is_usable(_message_map.get(user_id))


func _stream_is_usable(stream) -> bool:
	return stream != null and is_instance_valid(stream) and stream.is_alive()


func _display_peer_id(user_id: String) -> String:
	var clean_id := user_id.strip_edges()
	while not clean_id.is_empty() and _is_hex_prefix_char(clean_id.substr(0, 1)):
		clean_id = clean_id.substr(1)
	return clean_id if not clean_id.is_empty() else user_id


func _is_hex_prefix_char(value: String) -> bool:
	return (
		value.is_valid_int()
		or value in ["A", "B", "C", "D", "E", "F", "a", "b", "c", "d", "e", "f"]
	)


func _get_sender(file_id: String, user_id: String):
	for sender in _send_list:
		if sender.id == file_id and sender.peer_id == user_id:
			return sender
	return null


func _get_receiver(file_id: String, user_id: String):
	for receiver in _receive_list:
		if receiver.id == file_id and receiver.peer_id == user_id:
			return receiver
	return null


func _remove_sender(sender) -> void:
	if not sender:
		return
	var index := _send_list.find(sender)
	if index >= 0:
		_send_list.remove_at(index)
	if is_instance_valid(sender):
		sender.queue_free()


func _remove_receiver(receiver) -> void:
	if not receiver:
		return
	var index := _receive_list.find(receiver)
	if index >= 0:
		_receive_list.remove_at(index)
	if is_instance_valid(receiver):
		receiver.queue_free()
