extends Node
signal progress_updated(mode, op, type, id, user_id, data)

var id: String = ""
var peer_id: String = ""
var type: int = FileType.FT_Normal

var _file_path: String = ""
var _file_name: String = ""
var _file_size: int = 0
var _address: String = ""
var _port: int = 0
var _socket: StreamPeerTCP = null
var _file: FileAccess = null
var _buffer: PackedByteArray
var _active: bool = false
var _milestone: int = 0
var _mile: int = 0
var _timer: float = 0.0
var _num_timeouts: int = 0
var _last_position: int = 0

const BUFFER_SIZE = 65535

func _init(sz_id: String, sz_peer_id: String, sz_file_path: String, sz_file_name: String,
		n_file_size: int, sz_address: String, n_port: int, n_type: int):
	id = sz_id
	peer_id = sz_peer_id
	_file_path = sz_file_path
	_file_name = sz_file_name
	_file_size = n_file_size
	_address = sz_address
	_port = n_port
	type = n_type
	_mile = max(1, _file_size / 36)
	_milestone = _mile

func init_receive(socket: StreamPeerTCP) -> void:
	_socket = socket
	_receive_file()
	var start = "START".to_utf8_buffer()
	_socket.put_data(start)

func stop() -> void:
	var delete_file = false
	_active = false
	if _file and _file.is_open():
		delete_file = _file.get_position() < _file_size
		_file.close()
	if _socket and _socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_socket.disconnect_from_host()
	if delete_file:
		DirAccess.remove_absolute(_file_path)

func _process(delta):
	if not _socket or not _active:
		return
	if _socket.get_status() == StreamPeerTCP.STATUS_NONE or _socket.get_status() == StreamPeerTCP.STATUS_ERROR:
		_on_disconnected()
		return
	if _socket.get_available_bytes() > 0:
		_on_ready_read()
	if _timer > 0:
		_timer -= delta
		if _timer <= 0:
			_on_timer_timeout()

func _on_disconnected() -> void:
	if _active:
		progress_updated.emit(FileMode.FM_Receive, FileOp.FO_Error, type, id, peer_id, "")

func _on_ready_read() -> void:
	if not _active: return
	var bytes_received = _socket.get_data(BUFFER_SIZE)
	if bytes_received[0] != OK: return
	_file.store_buffer(bytes_received[1])
	var unreceived = _file_size - _file.get_position()
	if unreceived == 0:
		_active = false
		_file.close()
		_socket.disconnect_from_host()
		progress_updated.emit(FileMode.FM_Receive, FileOp.FO_Complete, type, id, peer_id, _file_path)

func _on_timer_timeout() -> void:
	if not _active: return
	var pos = _file.get_position()
	if _last_position < pos:
		_last_position = pos
		_num_timeouts = 0
	else:
		_num_timeouts += 1
		if _num_timeouts > 20:
			progress_updated.emit(FileMode.FM_Receive, FileOp.FO_Error, type, id, peer_id, "")
			stop()
			return
	var transferred = str(_file.get_position())
	progress_updated.emit(FileMode.FM_Receive, FileOp.FO_Progress, type, id, peer_id, transferred)

func _receive_file() -> void:
	var dir = _file_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	_file = FileAccess.open(_file_path, FileAccess.WRITE)
	if _file:
		_buffer = PackedByteArray()
		_buffer.resize(BUFFER_SIZE)
		_active = true
		_timer = PROGRESS_TIMEOUT / 1000.0
	else:
		_socket.disconnect_from_host()
		progress_updated.emit(FileMode.FM_Receive, FileOp.FO_Error, type, id, peer_id, _file_path)
