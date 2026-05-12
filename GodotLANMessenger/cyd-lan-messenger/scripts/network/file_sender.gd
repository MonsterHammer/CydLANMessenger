extends Node
const _D = preload("res://scripts/network/definitions.gd")
signal progress_updated(mode, op, type, id, user_id, data)

var id: String = ""
var peer_id: String = ""
var type: int = _D.FileType.FT_Normal

var _local_id: String = ""
var _file_path: String = ""
var _file_name: String = ""
var _file_size: int = 0
var _address: String = ""
var _port: int = 0
var _socket: StreamPeerTCP = null
var _file: FileAccess = null
var _active: bool = false
var _handshake_sent: bool = false
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

func init_send() -> void:
	_socket = StreamPeerTCP.new()
	_socket.connect_to_host(_address, _port)

func stop() -> void:
	_active = false
	if _file and _file.is_open(): _file.close()
	if _socket and _socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_socket.disconnect_from_host()

func _process(delta):
	if not _socket: return
	var status = _socket.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED and not _handshake_sent:
		_handshake_sent = true
		var data = "FILE".to_utf8_buffer() + id.to_utf8_buffer() + _local_id.to_utf8_buffer()
		_socket.put_data(data)
	elif status in [StreamPeerTCP.STATUS_NONE, StreamPeerTCP.STATUS_ERROR]:
		if _active:
			_on_disconnected()
		return
	if status == StreamPeerTCP.STATUS_CONNECTED:
		var avail = _socket.get_available_bytes()
		if avail > 0 and _handshake_sent:
			_on_ready_read()
	if _active and _timer > 0:
		_timer -= delta
		if _timer <= 0:
			_on_timer_timeout()

func _on_disconnected() -> void:
	if _active:
		progress_updated.emit(_D.FileMode.FM_Send, _D.FileOp.FO_Error, type, id, peer_id, "")

func _on_ready_read() -> void:
	if not _file:
		_send_file()
	# Else: continue was triggered by next chunk; handle in _process via bytesWritten equivalent

func _on_timer_timeout() -> void:
	if not _active: return
	if _file:
		progress_updated.emit(_D.FileMode.FM_Send, _D.FileOp.FO_Progress, type, id, peer_id, str(_file.get_position()))

func _send_file() -> void:
	if not _file:
		_file = FileAccess.open(_file_path, FileAccess.READ)
		if not _file:
			_socket.disconnect_from_host()
			progress_updated.emit(_D.FileMode.FM_Send, _D.FileOp.FO_Error, type, id, peer_id, "")
			return
		_active = true
		_timer = _D.PROGRESS_TIMEOUT / 1000.0
	var unsent = _file_size - _file.get_position()
	if unsent == 0:
		_active = false
		_file.close()
		_socket.disconnect_from_host()
		progress_updated.emit(_D.FileMode.FM_Send, _D.FileOp.FO_Complete, type, id, peer_id, _file_path)
		return
	var to_send = mini(BUFFER_SIZE, unsent)
	var chunk = _file.get_buffer(to_send)
	if chunk.size() > 0:
		_socket.put_data(chunk)
