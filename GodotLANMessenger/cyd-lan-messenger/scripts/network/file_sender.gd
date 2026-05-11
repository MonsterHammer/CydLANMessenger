extends Node
signal progress_updated(mode, op, type, id, user_id, data)

var id: String = ""
var peer_id: String = ""
var type: int = FileType.FT_Normal

var _local_id: String = ""
var _file_path: String = ""
var _file_name: String = ""
var _file_size: int = 0
var _address: String = ""
var _port: int = 0
var _sent_bytes: int = 0
var _socket: StreamPeerTCP = null
var _file: FileAccess = null
var _buffer: PackedByteArray
var _active: bool = false
var _milestone: int = 0
var _mile: int = 0
var _timer: float = 0.0

const BUFFER_SIZE = 65535

func _init(sz_id: String, sz_local_id: String, sz_peer_id: String, sz_file_path: String,
		sz_file_name: String, n_file_size: int, sz_address: String, n_port: int, n_type: int):
	id = sz_id
	_local_id = sz_local_id
	peer_id = sz_peer_id
	_file_path = sz_file_path
	_file_name = sz_file_name
	_file_size = n_file_size
	_address = sz_address
	_port = n_port
	type = n_type
	_mile = max(1, _file_size / 36)
	_milestone = _mile

func init_send() -> void:
	_socket = StreamPeerTCP.new()
	if _socket.connect_to_host(_address, _port) != OK:
		push_error("FileSender: Failed to connect")

func stop() -> void:
	_active = false
	if _file:
		_file.close()
	if _socket and _socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_socket.disconnect_from_host()

func _process(delta):
	if not _socket:
		return
	var status = _socket.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED and not _active and not _file:
		_on_connected()
	elif status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
		if _active:
			_on_disconnected()
		return
	if status == StreamPeerTCP.STATUS_CONNECTED and _socket.get_available_bytes() > 0 and _active:
		_on_ready_read()
	if _active and _timer > 0:
		_timer -= delta
		if _timer <= 0:
			_on_timer_timeout()

func _on_connected() -> void:
	var data = id.to_utf8_buffer()
	data.append_array(_local_id.to_utf8_buffer())
	var prefix = "FILE".to_utf8_buffer()
	data = prefix + data
	_socket.put_data(data)
	_send_file()

func _on_disconnected() -> void:
	if _active:
		progress_updated.emit(FileMode.FM_Send, FileOp.FO_Error, type, id, peer_id, "")

func _on_ready_read() -> void:
	_send_file()

func _on_timer_timeout() -> void:
	if not _active: return
	if _file:
		var transferred = str(_file.get_position())
		progress_updated.emit(FileMode.FM_Send, FileOp.FO_Progress, type, id, peer_id, transferred)

func _send_file() -> void:
	if not _file:
		_file = FileAccess.open(_file_path, FileAccess.READ)
		if not _file:
			_socket.disconnect_from_host()
			progress_updated.emit(FileMode.FM_Send, FileOp.FO_Error, type, id, peer_id, "")
			return
		_buffer = PackedByteArray()
		_buffer.resize(BUFFER_SIZE)
		_active = true
		_timer = PROGRESS_TIMEOUT / 1000.0
	var unsent = _file_size - _file.get_position()
	if unsent == 0:
		_active = false
		_file.close()
		_socket.disconnect_from_host()
		progress_updated.emit(FileMode.FM_Send, FileOp.FO_Complete, type, id, peer_id, _file_path)
		return
	var to_send = mini(BUFFER_SIZE, unsent)
	var bytes_read = _file.get_buffer(to_send)
	_socket.put_data(bytes_read)
