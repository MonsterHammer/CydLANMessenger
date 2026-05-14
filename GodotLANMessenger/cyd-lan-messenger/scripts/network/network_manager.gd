extends Node

const _UdpNetwork = preload("res://scripts/network/udp_network.gd")
const _TcpNetwork = preload("res://scripts/network/tcp_network.gd")
const _WebNetwork = preload("res://scripts/network/web_network.gd")
const _Crypto = preload("res://scripts/network/crypto.gd")

signal connection_state_changed
signal broadcast_received(pHeader, data)
signal new_connection(user_id, address)
signal connection_lost(user_id)
signal message_received(pHeader, data)
signal progress_received(user_id, data)
signal web_message_received(data)

var ip_address: String = ""
var subnet_mask: String = ""
var interface_name: String = ""
var is_connected: bool = false
var can_receive: bool = false

var udp: Node = null
var tcp: Node = null
var web: Node = null
var crypto: Node = null

var _settings: Dictionary = {}
var _local_id: String = ""
var _started: bool = false

func _ready():
	udp = _UdpNetwork.new()
	tcp = _TcpNetwork.new()
	web = _WebNetwork.new()
	crypto = _Crypto.new()

	add_child(udp)
	add_child(tcp)
	add_child(web)
	add_child(crypto)

	udp.broadcast_received.connect(_on_udp_broadcast)
	tcp.new_connection.connect(_on_tcp_new_connection)
	tcp.connection_lost.connect(_on_tcp_connection_lost)
	tcp.message_received.connect(_on_tcp_message)
	tcp.progress_received.connect(_on_tcp_progress)
	web.message_received.connect(_on_web_message)

func init_config(settings: Dictionary = {}) -> void:
	_settings = settings
	ip_address = _get_ip_address()
	var port = int(_settings.get("port", 0))
	var udp_port = int(_settings.get("udp_port", 12111))
	var tcp_port = int(_settings.get("tcp_port", 12112))
	udp.init_config(udp_port, _settings)
	tcp.init_config(tcp_port, _settings)

func start() -> void:
	udp.set_crypto(crypto)
	tcp.set_crypto(crypto)
	udp.set_local_id(_local_id)
	tcp.set_local_id(_local_id)
	is_connected = _check_connectivity()
	if is_connected:
		udp.set_ip_address(ip_address, subnet_mask, interface_name)
		var all_ips = IP.get_local_addresses()
		for a in all_ips:
			if a.contains(":") or not a.is_valid_ip_address():
				continue
			if a.begins_with("127.") or a.begins_with("169."):
				continue
			if a.begins_with("192.168.56.") or a.begins_with("192.168.137."):
				continue
			if a == ip_address:
				continue
			var parts = a.split(".")
			if parts.size() == 4:
				var candidates = [
					parts[0] + "." + parts[1] + "." + parts[2] + ".255",
					parts[0] + "." + parts[1] + ".255.255"
				]
				for c in candidates:
					if not c in udp._broadcast_list:
						udp._broadcast_list.append(c)
		udp.start()
		tcp.start()
		can_receive = udp.can_receive
	_started = true

func stop() -> void:
	_started = false
	udp.stop()
	tcp.stop()

func set_local_id(id: String) -> void:
	_local_id = id
	if udp: udp.set_local_id(id)
	if tcp: tcp.set_local_id(id)

func send_broadcast(data: String) -> void:
	if udp: udp.send_broadcast(data)

func add_connection(user_id: String, address: String) -> void:
	if tcp: tcp.add_connection(user_id, address)

func send_message(receiver_id: String, address: String, data: String) -> void:
	if tcp: tcp.send_message(receiver_id, address, data)

func init_send_file(receiver_id: String, address: String, data: String) -> void:
	if tcp: tcp.init_send_file(receiver_id, address, data)

func init_receive_file(sender_id: String, address: String, data: String) -> void:
	if tcp: tcp.init_receive_file(sender_id, address, data)

func file_operation(mode: int, user_id: String, data: String) -> void:
	if tcp: tcp.file_operation(mode, user_id, data)

func send_web_message(url: String, data: String) -> void:
	if web: web.send_message(url, data)

func settings_changed() -> void:
	if udp: udp.settings_changed(_settings)

func _process(delta):
	pass

func _on_udp_broadcast(pHeader, data: String) -> void:
	broadcast_received.emit(pHeader, data)

func _on_tcp_new_connection(user_id: String, address: String) -> void:
	new_connection.emit(user_id, address)

func _on_tcp_connection_lost(user_id: String) -> void:
	connection_lost.emit(user_id)

func _on_tcp_message(pHeader, data: String) -> void:
	message_received.emit(pHeader, data)

func _on_tcp_progress(user_id: String, data: String) -> void:
	progress_received.emit(user_id, data)

func _on_web_message(data: String) -> void:
	web_message_received.emit(data)

func _get_ip_address() -> String:
	var addrs = IP.get_local_addresses()
	var fallback = ""
	for a in addrs:
		if a.contains(":") or not a.is_valid_ip_address():
			continue
		if a.begins_with("127.") or a.begins_with("169."):
			continue
		if a.begins_with("172.17.") or a.begins_with("192.168.56.") or a.begins_with("192.168.137."):
			continue
		if a.begins_with("172."):
			if fallback.is_empty():
				fallback = a
			continue
		return a
	if not fallback.is_empty():
		return fallback
	return "127.0.0.1"

func _check_connectivity() -> bool:
	return not ip_address.is_empty() and ip_address != "127.0.0.1"
