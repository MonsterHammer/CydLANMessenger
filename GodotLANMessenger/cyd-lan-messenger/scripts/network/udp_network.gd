extends Node

const _D = preload("res://scripts/network/definitions.gd")

signal broadcast_received(header, data)
signal connection_state_changed

var is_connected := false
var can_receive := false

var _udp: PacketPeerUDP
var _settings: Dictionary = {}
var _local_id := ""
var _crypto = null
var _is_running := false
var _udp_port := 0
var _multicast_address := "239.255.100.100"
var _broadcast_list: Array = []
var _ip_address := ""
var _subnet_mask := ""
var _interface_name := ""
var _default_broadcast := "255.255.255.255"
var _joined_interfaces: Array[String] = []

func _init() -> void:
	_udp = PacketPeerUDP.new()

func init_config(port: int = 0, settings: Dictionary = {}) -> void:
	_settings = settings
	_udp_port = port if port > 0 else int(_settings.get("udp_port", 50000))
	_multicast_address = str(_settings.get("multicast", "239.255.100.100"))
	_broadcast_list = _settings.get("broadcast_list", []).duplicate()

func start() -> void:
	# Bind explicitly to IPv4 because the legacy client uses QUdpSocket::AnyIPv4.
	var error := _udp.bind(_udp_port, "0.0.0.0", 262144)
	if error != OK:
		push_error("CydLAN: UDP bind failed on port %d (error %d)" % [_udp_port, error])
		return
	_udp.set_broadcast_enabled(true)
	_is_running = true
	is_connected = true
	can_receive = true
	_join_multicast_interfaces()
	print("CydLAN: UDP listening on port ", _udp_port, "; multicast interfaces=", _joined_interfaces)
	connection_state_changed.emit()

func stop() -> void:
	for interface_name in _joined_interfaces:
		_udp.leave_multicast_group(_multicast_address, interface_name)
	_joined_interfaces.clear()
	_udp.close()
	_is_running = false
	is_connected = false
	can_receive = false
	connection_state_changed.emit()

func set_local_id(id: String) -> void:
	_local_id = id

func set_crypto(crypto) -> void:
	_crypto = crypto

func send_broadcast(data: String) -> void:
	if not _is_running:
		return
	var bytes := data.to_utf8_buffer()
	var destinations: Array[String] = [_multicast_address, _default_broadcast]
	for address in _broadcast_list:
		if not str(address) in destinations:
			destinations.append(str(address))
	for destination in destinations:
		if destination.is_empty():
			continue
		if _udp.set_dest_address(destination, _udp_port) == OK:
			_udp.put_packet(bytes)

func settings_changed(settings: Dictionary) -> void:
	_settings = settings
	_broadcast_list = _settings.get("broadcast_list", []).duplicate()
	if not _default_broadcast in _broadcast_list:
		_broadcast_list.append(_default_broadcast)

func set_ip_address(address: String, subnet: String, interface_name: String = "") -> void:
	_ip_address = address
	_subnet_mask = subnet
	_interface_name = interface_name
	_set_default_broadcast()
	if _subnet_mask.is_empty() and not _ip_address.is_empty():
		var parts := _ip_address.split(".")
		if parts.size() == 4:
			for candidate in [
				parts[0] + "." + parts[1] + "." + parts[2] + ".255",
				parts[0] + "." + parts[1] + ".255.255",
				parts[0] + ".255.255.255"
			]:
				if not candidate in _broadcast_list:
					_broadcast_list.append(candidate)
	if not _default_broadcast in _broadcast_list:
		_broadcast_list.append(_default_broadcast)

func _process(_delta: float) -> void:
	if not _is_running:
		return
	while _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet()
		_parse_datagram(_udp.get_packet_ip(), packet)

func _parse_datagram(address: String, data: PackedByteArray) -> void:
	var header := {"type": _D.DatagramType.DT_Broadcast, "userId": "", "address": address}
	var packet_data := data
	if packet_data.size() >= 6 and packet_data.slice(0, 6).get_string_from_utf8() == _D.DatagramTypeNames[_D.DatagramType.DT_Broadcast]:
		packet_data = packet_data.slice(6)
	broadcast_received.emit(header, packet_data.get_string_from_utf8())

func _join_multicast_interfaces() -> void:
	_joined_interfaces.clear()
	for interface in IP.get_local_interfaces():
		var interface_name := str(interface.get("name", ""))
		if interface_name.is_empty():
			continue
		var has_ipv4 := false
		for raw_address in interface.get("addresses", []):
			var address := str(raw_address)
			if not address.contains(":") and address.is_valid_ip_address() and not address.begins_with("127."):
				has_ipv4 = true
				break
		if has_ipv4 and _udp.join_multicast_group(_multicast_address, interface_name) == OK:
			_joined_interfaces.append(interface_name)
	if _joined_interfaces.is_empty() and not _interface_name.is_empty():
		if _udp.join_multicast_group(_multicast_address, _interface_name) == OK:
			_joined_interfaces.append(_interface_name)

func _set_default_broadcast() -> void:
	if _ip_address.is_empty() or _subnet_mask.is_empty():
		return
	var ip_parts := _ip_address.split(".")
	var mask_parts := _subnet_mask.split(".")
	if ip_parts.size() != 4 or mask_parts.size() != 4:
		return
	var parts: Array[String] = []
	for index in range(4):
		parts.append(str(int(ip_parts[index]) | (~int(mask_parts[index]) & 0xFF)))
	_default_broadcast = ".".join(parts)
