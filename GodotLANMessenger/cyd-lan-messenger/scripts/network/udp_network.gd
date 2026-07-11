extends Node

const _D = preload("res://scripts/network/definitions.gd")

signal broadcast_received(pHeader, data)
signal connection_state_changed

var is_connected: bool = false
var can_receive: bool = false

var _udp: PacketPeerUDP
var _settings: Dictionary = {}
var _local_id: String = ""
var _crypto = null
var _is_running: bool = false
var _udp_port: int = 0
var _multicast_address: String = "239.255.100.100"
var _broadcast_list: Array = []
var _ip_address: String = ""
var _subnet_mask: String = ""
var _interface_name: String = ""
var _default_broadcast: String = "255.255.255.255"
var _joined_interfaces: Array[String] = []


func _init() -> void:
	_udp = PacketPeerUDP.new()


func init_config(port: int = 0, settings: Dictionary = {}) -> void:
	_settings = settings
	_udp_port = port if port > 0 else int(_settings.get("udp_port", 50000))
	_multicast_address = str(_settings.get("multicast", "239.255.100.100"))
	_broadcast_list = _settings.get("broadcast_list", []).duplicate()


func start() -> void:
	if _is_running:
		return
	var error := _udp.bind(_udp_port, "0.0.0.0")
	if error != OK:
		can_receive = false
		is_connected = false
		push_error("CydLAN: UDP bind failed on port %d (%s)" % [_udp_port, error])
		connection_state_changed.emit()
		return

	_is_running = true
	can_receive = true
	is_connected = true
	_udp.set_broadcast_enabled(true)
	_join_multicast_interfaces()
	print("CydLAN: UDP bound to port ", _udp_port)
	connection_state_changed.emit()


func stop() -> void:
	if not _is_running:
		return
	for interface_name in _joined_interfaces:
		_udp.leave_multicast_group(_multicast_address, interface_name)
	_joined_interfaces.clear()
	_udp.close()
	_is_running = false
	can_receive = false
	is_connected = false
	connection_state_changed.emit()


func set_local_id(id: String) -> void:
	_local_id = id


func set_crypto(crypto) -> void:
	_crypto = crypto


func send_broadcast(data: String) -> void:
	if not _is_running or data.is_empty():
		return
	var bytes := data.to_utf8_buffer()
	for address in _broadcast_destinations():
		if _udp.set_dest_address(address, _udp_port) != OK:
			continue
		_udp.put_packet(bytes)


func settings_changed(settings: Dictionary) -> void:
	var old_multicast := _multicast_address
	_settings = settings
	_multicast_address = str(_settings.get("multicast", "239.255.100.100"))
	_broadcast_list = _settings.get("broadcast_list", []).duplicate()
	if _is_running and old_multicast != _multicast_address:
		for interface_name in _joined_interfaces:
			_udp.leave_multicast_group(old_multicast, interface_name)
		_joined_interfaces.clear()
		_join_multicast_interfaces()


func set_ip_address(address: String, subnet: String, if_name: String = "") -> void:
	_ip_address = address
	_subnet_mask = subnet
	_interface_name = if_name
	_set_default_broadcast()
	if _subnet_mask.is_empty() and not _ip_address.is_empty():
		var parts := _ip_address.split(".")
		if parts.size() == 4:
			_add_broadcast(parts[0] + "." + parts[1] + "." + parts[2] + ".255")
			_add_broadcast(parts[0] + "." + parts[1] + ".255.255")
	_add_broadcast(_default_broadcast)


func _process(_delta: float) -> void:
	if not _is_running:
		return
	while _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet()
		var address := _udp.get_packet_ip()
		_parse_datagram(address, packet)


func _parse_datagram(address: String, data: PackedByteArray) -> void:
	if data.is_empty():
		return
	var header := {"type": _D.DatagramType.DT_Broadcast, "userId": "", "address": address}
	# LAN Messenger UDP payloads are raw XML. Accept the six-byte marker too
	# for compatibility with older CydLAN builds.
	var packet_data := data
	if packet_data.size() >= 6:
		var prefix := packet_data.slice(0, 6).get_string_from_utf8()
		if prefix == _D.DatagramTypeNames[_D.DatagramType.DT_Broadcast]:
			packet_data = packet_data.slice(6)
	var xml := packet_data.get_string_from_utf8()
	if xml.is_empty():
		return
	broadcast_received.emit(header, xml)


func _join_multicast_interfaces() -> void:
	var candidates: Array[String] = []
	if not _interface_name.is_empty():
		candidates.append(_interface_name)
	for interface_data in IP.get_local_interfaces():
		var interface_name := str(interface_data.get("name", ""))
		var addresses = interface_data.get("addresses", [])
		if interface_name.is_empty():
			continue
		if not _ip_address.is_empty() and _ip_address in addresses:
			candidates.push_front(interface_name)
		elif interface_name not in candidates:
			candidates.append(interface_name)

	for interface_name in candidates:
		if interface_name in _joined_interfaces:
			continue
		if _udp.join_multicast_group(_multicast_address, interface_name) == OK:
			_joined_interfaces.append(interface_name)
			print("CydLAN: Joined multicast ", _multicast_address, " on ", interface_name)


func _broadcast_destinations() -> Array[String]:
	var destinations: Array[String] = []
	if not _multicast_address.is_empty():
		destinations.append(_multicast_address)
	for value in _broadcast_list:
		var address := str(value)
		if not address.is_empty() and address not in destinations:
			destinations.append(address)
	if not _default_broadcast.is_empty() and _default_broadcast not in destinations:
		destinations.append(_default_broadcast)
	return destinations


func _add_broadcast(address: String) -> void:
	if not address.is_empty() and address not in _broadcast_list:
		_broadcast_list.append(address)


func _set_default_broadcast() -> void:
	if _ip_address.is_empty() or _subnet_mask.is_empty():
		_default_broadcast = "255.255.255.255"
		return
	var ip_parts := _ip_address.split(".")
	var mask_parts := _subnet_mask.split(".")
	if ip_parts.size() != 4 or mask_parts.size() != 4:
		_default_broadcast = "255.255.255.255"
		return
	var values: Array[String] = []
	for i in range(4):
		var ip_byte := int(ip_parts[i])
		var mask_byte := int(mask_parts[i])
		values.append(str(ip_byte | (~mask_byte & 0xFF)))
	_default_broadcast = ".".join(values)
