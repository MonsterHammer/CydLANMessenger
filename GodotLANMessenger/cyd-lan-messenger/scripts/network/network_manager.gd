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


func _ready() -> void:
	udp = _UdpNetwork.new()
	tcp = _TcpNetwork.new()
	web = _WebNetwork.new()
	crypto = _Crypto.new()

	add_child(udp)
	add_child(tcp)
	add_child(web)
	add_child(crypto)

	udp.broadcast_received.connect(_on_udp_broadcast)
	udp.connection_state_changed.connect(_on_transport_state_changed)
	tcp.new_connection.connect(_on_tcp_new_connection)
	tcp.connection_lost.connect(_on_tcp_connection_lost)
	tcp.message_received.connect(_on_tcp_message)
	tcp.progress_received.connect(_on_tcp_progress)
	web.message_received.connect(_on_web_message)


func init_config(settings: Dictionary = {}) -> void:
	_settings = settings
	ip_address = _get_ip_address()
	interface_name = _find_interface_name(ip_address)
	var udp_port := int(_settings.get("udp_port", _settings.get("port", 50000)))
	var tcp_port := int(_settings.get("tcp_port", _settings.get("port", 50000)))
	udp.init_config(udp_port, _settings)
	tcp.init_config(tcp_port, _settings)


func start() -> void:
	if _started:
		return
	_started = true
	udp.set_crypto(crypto)
	tcp.set_crypto(crypto)
	udp.set_local_id(_local_id)
	tcp.set_local_id(_local_id)

	is_connected = _check_connectivity()
	if not is_connected:
		can_receive = false
		connection_state_changed.emit()
		return

	udp.set_ip_address(ip_address, subnet_mask, interface_name)
	_add_directed_broadcast_candidates()
	udp.start()
	tcp.start()
	can_receive = udp.can_receive
	connection_state_changed.emit()


func stop() -> void:
	if not _started:
		return
	_started = false
	if udp:
		udp.stop()
	if tcp:
		tcp.stop()
	is_connected = false
	can_receive = false
	connection_state_changed.emit()


func set_local_id(id: String) -> void:
	_local_id = id
	if udp:
		udp.set_local_id(id)
	if tcp:
		tcp.set_local_id(id)


func send_broadcast(data: String) -> void:
	if _started and udp:
		udp.send_broadcast(data)


func add_connection(user_id: String, address: String) -> void:
	if _started and tcp:
		tcp.add_connection(user_id, address)


func send_message(receiver_id: String, address: String, data: String) -> void:
	if _started and tcp:
		tcp.send_message(receiver_id, address, data)


func init_send_file(receiver_id: String, address: String, data: String) -> void:
	if _started and tcp:
		tcp.init_send_file(receiver_id, address, data)


func init_receive_file(sender_id: String, address: String, data: String) -> void:
	if _started and tcp:
		tcp.init_receive_file(sender_id, address, data)


func file_operation(mode: int, user_id: String, data: String) -> void:
	if _started and tcp:
		tcp.file_operation(mode, user_id, data)


func send_web_message(url: String, data: String) -> void:
	if web:
		web.send_message(url, data)


func settings_changed() -> void:
	if udp:
		udp.settings_changed(_settings)


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


func _on_transport_state_changed() -> void:
	can_receive = udp.can_receive if udp else false
	connection_state_changed.emit()


func _get_ip_address() -> String:
	var fallback := ""
	for address in IP.get_local_addresses():
		if address.contains(":") or not address.is_valid_ip_address():
			continue
		if address.begins_with("127.") or address.begins_with("169.254."):
			continue
		if address.begins_with("172.17."):
			continue
		if address.begins_with("192.168.56.") or address.begins_with("192.168.137."):
			continue
		if address.begins_with("172."):
			if fallback.is_empty():
				fallback = address
			continue
		return address
	return fallback if not fallback.is_empty() else "127.0.0.1"


func _find_interface_name(address: String) -> String:
	if address.is_empty():
		return ""
	for interface_data in IP.get_local_interfaces():
		var addresses = interface_data.get("addresses", [])
		if address in addresses:
			return str(interface_data.get("name", ""))
	return ""


func _add_directed_broadcast_candidates() -> void:
	if ip_address.is_empty():
		return
	var parts := ip_address.split(".")
	if parts.size() != 4:
		return
	var candidates := [
		parts[0] + "." + parts[1] + "." + parts[2] + ".255", parts[0] + "." + parts[1] + ".255.255"
	]
	for candidate in candidates:
		if candidate not in udp._broadcast_list:
			udp._broadcast_list.append(candidate)


func _check_connectivity() -> bool:
	return not ip_address.is_empty() and ip_address != "127.0.0.1"
