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
var _out_data_len: int = 0
var _in_data_len: int = 0
var _reading: bool = false
var _connected_once: bool = false

func _init(p_local_id: String = "", p_peer_id: String = "", p_peer_address: String = "", p_port: int = 0):
	_local_id = p_local_id
	peer_id = p_peer_id
	peer_address = p_peer_address
	_port = p_port

func init_client() -> void:
	_socket = StreamPeerTCP.new()
	_socket.connect_to_host(peer_address, _port)

func init_server(socket: StreamPeerTCP) -> void:
	_socket = socket
	_connected_once = true

func stop() -> void:
	if _socket and _socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_socket.disconnect_from_host()

func send_message(data: PackedByteArray) -> void:
	if not _socket or _socket.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var data_len = 4 + data.size()
	_out_data_len += data_len
	_out_data.resize(data_len)
	_out_data.encode_u32(0, data.size())
	for i in range(data.size()):
		_out_data[i + 4] = data[i]
	_socket.put_data(_out_data)

func _process(delta):
	if not _socket:
		return
	var status = _socket.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED and not _connected_once:
		_connected_once = true
		_on_connected()
		return
	if status in [StreamPeerTCP.STATUS_NONE, StreamPeerTCP.STATUS_ERROR]:
		if _connected_once:
			_on_disconnected()
		return
	if status == StreamPeerTCP.STATUS_CONNECTED:
		var avail = _socket.get_available_bytes()
		if avail > 0:
			_on_ready_read()

func _on_connected() -> void:
	var id_bytes = _local_id.to_utf8_buffer()
	var prefix = "MSG".to_utf8_buffer()
	var data = prefix + id_bytes
	_out_data_len = data.size()
	_socket.put_data(data)

func _on_disconnected() -> void:
	connection_lost.emit(peer_id)

func _on_ready_read() -> void:
	var available = _socket.get_available_bytes()
	while available > 0:
		if not _reading:
			_reading = true
			var result = _socket.get_data(4)
			if result["error"] != OK: return
			_in_data_len = result["data"].decode_u32(0)
			_in_data = PackedByteArray()
			var chunk = _socket.get_data(_in_data_len)
			if chunk["error"] != OK: return
			_in_data.append_array(chunk["data"])
			_in_data_len -= chunk["data"].size()
			available -= 4 + chunk["data"].size()
			if _in_data_len == 0:
				_reading = false
				message_received.emit(peer_id, peer_address, _in_data)
		else:
			var chunk = _socket.get_data(_in_data_len)
			if chunk["error"] != OK: return
			_in_data.append_array(chunk["data"])
			_in_data_len -= chunk["data"].size()
			available -= chunk["data"].size()
			if _in_data_len == 0:
				_reading = false
				message_received.emit(peer_id, peer_address, _in_data)
