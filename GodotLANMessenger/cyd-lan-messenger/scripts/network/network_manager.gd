extends Node
signal connection_state_changed
signal broadcast_received(pHeader, data)
signal new_connection(user_id, address)
signal connection_lost(user_id)
signal message_received(pHeader, data)
signal progress_received(user_id, data)
signal web_message_received(data)

var ip_address: String = ""
var subnet_mask: String = ""
var is_connected: bool = false
var can_receive: bool = false

var _udp: Node = null
var _tcp: Node = null
var _web: Node = null
var _crypto: Node = null
var _settings: Dictionary = {}
var _pTimer: float = 0.0
var _interface_name: String = ""
var _local_id: String = ""

func _init():
	_udp = preload("udp_network.gd").new()
	_tcp = preload("tcp_network.gd").new()
	_web = preload("web_network.gd").new()
	_crypto = preload("crypto.gd").new()

func init_config(settings: Dictionary = {}) -> void:
	_settings = settings
	ip_address = _get_ip_address()
	var port = int(_settings.get("port", 0))
	_udp.init_config(port, _settings)
	_tcp.init_config(port, _settings)

func start() -> void:
	_crypto.generate_rsa()
	_udp.set_crypto(_crypto)
	_tcp.set_crypto(_crypto)
	if is_connected:
		_udp.set_ip_address(ip_address, subnet_mask)
		_udp.start()
		_tcp.start()
		can_receive = _udp.can_receive

func stop() -> void:
	_udp.stop()
	_tcp.stop()

func set_local_id(id: String) -> void:
	_local_id = id
	_udp.set_local_id(id)
	_tcp.set_local_id(id)

func send_broadcast(data: String) -> void:
	_udp.send_broadcast(data)

func add_connection(user_id: String, address: String) -> void:
	_tcp.add_connection(user_id, address)

func send_message(receiver_id: String, address: String, data: String) -> void:
	_tcp.send_message(receiver_id, data)

func init_send_file(receiver_id: String, address: String, data: String) -> void:
	_tcp.init_send_file(receiver_id, address, data)

func init_receive_file(sender_id: String, address: String, data: String) -> void:
	_tcp.init_receive_file(sender_id, address, data)

func file_operation(mode: int, user_id: String, data: String) -> void:
	_tcp.file_operation(mode, user_id, data)

func send_web_message(url: String, data: String) -> void:
	_web.send_message(url, data)

func settings_changed() -> void:
	_udp.settings_changed(_settings)

func physical_address() -> String:
	return ""

func _process(delta):
	_pTimer += delta
	if _pTimer >= 2.0:
		_pTimer = 0.0
		var prev = is_connected
		is_connected = _check_connectivity()
		if prev != is_connected:
			if is_connected:
				_udp.set_ip_address(ip_address, subnet_mask)
				_udp.start()
				_tcp.start()
				can_receive = _udp.can_receive
			else:
				_udp.stop()
				_tcp.stop()
			connection_state_changed.emit()

func _get_ip_address() -> String:
	var ip = IP.get_local_addresses()
	for addr in ip:
		if addr.begins_with("192.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	return "127.0.0.1"

func _check_connectivity() -> bool:
	return not _get_ip_address().is_empty() and _get_ip_address() != "127.0.0.1"
