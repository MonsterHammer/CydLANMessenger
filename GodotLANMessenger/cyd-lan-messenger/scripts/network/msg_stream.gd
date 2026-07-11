extends Node

signal connection_established(user_id, stream)
signal connection_lost(user_id, stream, was_connected)
signal message_received(user_id, address, data)

const MAX_FRAME_SIZE := 16 * 1024 * 1024

var peer_id: String = ""
var peer_address: String = ""
var is_outgoing: bool = true

var _local_id: String = ""
var _port: int = 0
var _socket: StreamPeerTCP = null
var _send_queue: Array[PackedByteArray] = []
var _read_buffer: PackedByteArray = PackedByteArray()
var _connected_once: bool = false
var _disconnect_notified: bool = false
var _intentional_stop: bool = false


func _init(
	p_local_id: String = "", p_peer_id: String = "", p_peer_address: String = "", p_port: int = 0
) -> void:
	_local_id = p_local_id
	peer_id = p_peer_id
	peer_address = p_peer_address
	_port = p_port


func init_client() -> void:
	is_outgoing = true
	_socket = StreamPeerTCP.new()
	var error := _socket.connect_to_host(peer_address, _port)
	if error != OK:
		push_warning("CydLAN: TCP connect request failed for %s (%s)" % [peer_id, error])
		_notify_disconnected(false)
		return
	print("CydLAN: TCP connecting to ", peer_id, " at ", peer_address, ":", _port)


func init_server(socket: StreamPeerTCP) -> void:
	is_outgoing = false
	_socket = socket
	_connected_once = true


func stop() -> void:
	_intentional_stop = true
	_disconnect_notified = true
	set_process(false)
	if _socket:
		_socket.disconnect_from_host()


func is_alive() -> bool:
	if not _socket:
		return false
	var status := _socket.get_status()
	return status == StreamPeerTCP.STATUS_CONNECTING or status == StreamPeerTCP.STATUS_CONNECTED


func is_socket_connected() -> bool:
	return _socket != null and _socket.get_status() == StreamPeerTCP.STATUS_CONNECTED


func send_message(data: PackedByteArray) -> void:
	if data.is_empty():
		return
	if not is_socket_connected():
		_send_queue.append(data.duplicate())
		return
	_send_framed(data)


func _send_framed(data: PackedByteArray) -> void:
	if data.size() > MAX_FRAME_SIZE:
		push_warning("CydLAN: Refusing oversized TCP frame of %d bytes" % data.size())
		return
	var framed := PackedByteArray()
	framed.resize(4 + data.size())
	framed[0] = (data.size() >> 24) & 0xFF
	framed[1] = (data.size() >> 16) & 0xFF
	framed[2] = (data.size() >> 8) & 0xFF
	framed[3] = data.size() & 0xFF
	for i in range(data.size()):
		framed[i + 4] = data[i]
	var error := _socket.put_data(framed)
	if error != OK:
		push_warning("CydLAN: TCP write failed for %s (%s)" % [peer_id, error])


func _process(_delta: float) -> void:
	if not _socket or _disconnect_notified:
		return

	_socket.poll()
	var status := _socket.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED and not _connected_once:
		_connected_once = true
		_on_connected()
	elif status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
		_notify_disconnected(_connected_once)
		return

	if status == StreamPeerTCP.STATUS_CONNECTED and _socket.get_available_bytes() > 0:
		_on_ready_read()


func _on_connected() -> void:
	print("CydLAN: TCP connected to ", peer_id, " at ", peer_address)
	var identity := "MSG".to_utf8_buffer() + _local_id.to_utf8_buffer()
	var error := _socket.put_data(identity)
	if error != OK:
		push_warning("CydLAN: TCP identity write failed for %s (%s)" % [peer_id, error])
		_notify_disconnected(true)
		return
	connection_established.emit(peer_id, self)
	call_deferred("_flush_send_queue")


func _flush_send_queue() -> void:
	if not is_socket_connected():
		return
	var queued := _send_queue
	_send_queue = []
	for data in queued:
		_send_framed(data)


func _notify_disconnected(was_connected: bool) -> void:
	if _disconnect_notified:
		return
	_disconnect_notified = true
	set_process(false)
	if not _intentional_stop:
		print("CydLAN: TCP disconnected from ", peer_id)
		connection_lost.emit(peer_id, self, was_connected)


func _on_ready_read() -> void:
	var available := _socket.get_available_bytes()
	if available <= 0:
		return
	var result := _socket.get_partial_data(available)
	if result[0] != OK or result[1].is_empty():
		return

	_read_buffer.append_array(result[1])
	while _read_buffer.size() >= 4:
		var message_len := (
			(_read_buffer[0] << 24)
			| (_read_buffer[1] << 16)
			| (_read_buffer[2] << 8)
			| _read_buffer[3]
		)
		if message_len <= 0 or message_len > MAX_FRAME_SIZE:
			push_warning("CydLAN: Invalid TCP frame length %d from %s" % [message_len, peer_id])
			_read_buffer.clear()
			_notify_disconnected(true)
			if _socket:
				_socket.disconnect_from_host()
			return
		if _read_buffer.size() < message_len + 4:
			return

		var payload := _read_buffer.slice(4, message_len + 4)
		_read_buffer = _read_buffer.slice(message_len + 4)
		message_received.emit(peer_id, peer_address, payload)
