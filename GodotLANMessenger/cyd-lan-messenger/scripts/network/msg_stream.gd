extends Node
signal connection_lost(user_id)
signal message_received(user_id, address, data)

var peer_id: String = ""
var peer_address: String = ""
var _local_id: String = ""
var _port: int = 0
var _socket: StreamPeerTCP = null
var _out_data: PackedByteArray
var _in_data: PackedByteArray
var _send_queue: Array[PackedByteArray] = []
var _out_data_len: int = 0
var _in_data_len: int = 0
var _read_buffer: PackedByteArray = PackedByteArray()
var _connected_once: bool = false

func _init(p_local_id: String = "", p_peer_id: String = "", p_peer_address: String = "", p_port: int = 0):
	_local_id = p_local_id
	peer_id = p_peer_id
	peer_address = p_peer_address
	_port = p_port

func init_client() -> void:
	_socket = StreamPeerTCP.new()
	_socket.connect_to_host(peer_address, _port)
	print("CydLAN: TCP connecting to ", peer_id, " at ", peer_address, ":", _port)

func init_server(socket: StreamPeerTCP) -> void:
	_socket = socket
	_connected_once = true

func stop() -> void:
	if _socket and _socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_socket.disconnect_from_host()

func send_message(data: PackedByteArray) -> void:
	if not _socket or _socket.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_send_queue.append(data)
		return
	_send_framed(data)

func _send_framed(data: PackedByteArray) -> void:
	var data_len = 4 + data.size()
	_out_data_len += data_len
	_out_data.resize(data_len)
	# Big-endian u32 (QDataStream default)
	_out_data[0] = (data.size() >> 24) & 0xFF
	_out_data[1] = (data.size() >> 16) & 0xFF
	_out_data[2] = (data.size() >> 8) & 0xFF
	_out_data[3] = data.size() & 0xFF
	for i in range(data.size()):
		_out_data[i + 4] = data[i]
	_socket.put_data(_out_data)

func _process(delta):
	if not _socket:
		return
	_socket.poll()
	var status = _socket.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED and not _connected_once:
		_connected_once = true
		_on_connected()
	if status in [StreamPeerTCP.STATUS_NONE, StreamPeerTCP.STATUS_ERROR]:
		if _connected_once:
			_on_disconnected()
		return
	if status == StreamPeerTCP.STATUS_CONNECTED:
		var avail = _socket.get_available_bytes()
		if avail > 0:
			_on_ready_read()

func _on_connected() -> void:
	print("CydLAN: TCP connected to ", peer_id, " at ", peer_address)
	var id_bytes = _local_id.to_utf8_buffer()
	var prefix = "MSG".to_utf8_buffer()
	var data = prefix + id_bytes
	_out_data_len = data.size()
	_socket.put_data(data)
	for queued in _send_queue:
		_send_framed(queued)
	_send_queue.clear()

func _on_disconnected() -> void:
	print("CydLAN: TCP disconnected from ", peer_id)
	connection_lost.emit(peer_id)

func _on_ready_read() -> void:
	var available = _socket.get_available_bytes()
	if available <= 0:
		return
	var result = _socket.get_partial_data(available)
	if result[0] != OK or result[1].is_empty():
		return
	_read_buffer.append_array(result[1])
	while _read_buffer.size() >= 4:
		var message_len = (_read_buffer[0] << 24) | (_read_buffer[1] << 16) | (_read_buffer[2] << 8) | _read_buffer[3]
		if message_len < 0:
			_read_buffer.clear()
			return
		if _read_buffer.size() < message_len + 4:
			return
		_in_data = _read_buffer.slice(4, message_len + 4)
		_read_buffer = _read_buffer.slice(message_len + 4)
		message_received.emit(peer_id, peer_address, _in_data)
