extends Node
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
var _multicast_address: String = "225.0.0.37"
var _broadcast_list: Array = []
var _ip_address: String = ""
var _subnet_mask: String = ""
var _default_broadcast: String = "255.255.255.255"

func _init():
	_udp = PacketPeerUDP.new()

func init_config(port: int = 0, settings: Dictionary = {}) -> void:
	_settings = settings
	_udp_port = port if port > 0 else _settings.get("udp_port", 12111)
	_multicast_address = _settings.get("multicast", "225.0.0.37")
	_broadcast_list = _settings.get("broadcast_list", [])

func start() -> void:
	if _udp.bind(_udp_port, "*"):
		_is_running = true
		can_receive = true

func stop() -> void:
	_udp.close()
	_is_running = false

func set_local_id(id: String) -> void:
	_local_id = id

func set_crypto(crypto) -> void:
	_crypto = crypto

func send_broadcast(data: String) -> void:
	if not _is_running:
		return
	var bytes = data.to_utf8_buffer()
	_udp.set_dest_address(_multicast_address, _udp_port)
	_udp.put_packet(bytes)
	for addr in _broadcast_list:
		_udp.set_dest_address(addr, _udp_port)
		_udp.put_packet(bytes)
	_udp.set_dest_address(_default_broadcast, _udp_port)
	_udp.put_packet(bytes)

func settings_changed(settings: Dictionary) -> void:
	_settings = settings
	_broadcast_list = _settings.get("broadcast_list", [])
	if not _default_broadcast in _broadcast_list:
		_broadcast_list.append(_default_broadcast)

func set_ip_address(address: String, subnet: String) -> void:
	_ip_address = address
	_subnet_mask = subnet
	_set_default_broadcast()
	if not _default_broadcast in _broadcast_list:
		_broadcast_list.append(_default_broadcast)

func _process(delta):
	if not _is_running:
		return
	if _udp.get_available_packet_count() > 0:
		var packet = _udp.get_packet()
		var address = _udp.get_packet_ip()
		_parse_datagram(address, packet)

func _parse_datagram(address: String, data: PackedByteArray) -> void:
	var pHeader = { "type": DatagramType.DT_Broadcast, "userId": "", "address": address }
	var szData = data.get_string_from_utf8()
	broadcast_received.emit(pHeader, szData)

func _set_default_broadcast() -> void:
	if _ip_address.is_empty() or _subnet_mask.is_empty():
		return
	var ip_parts = _ip_address.split(".")
	var mask_parts = _subnet_mask.split(".")
	if ip_parts.size() != 4 or mask_parts.size() != 4:
		return
	var broadcast = ""
	for i in range(4):
		var ip_b = int(ip_parts[i])
		var mask_b = int(mask_parts[i])
		var b = ip_b | (~mask_b & 0xFF)
		if i > 0: broadcast += "."
		else: broadcast = str(b)
	_default_broadcast = broadcast
