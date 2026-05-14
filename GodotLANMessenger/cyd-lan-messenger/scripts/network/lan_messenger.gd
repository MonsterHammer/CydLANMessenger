extends Node

const _D = preload("res://scripts/network/definitions.gd")
const _Messaging = preload("res://scripts/network/messaging.gd")
const _NetworkManager = preload("res://scripts/network/network_manager.gd")

var messaging: Node = null

func _ready():
	if Engine.is_editor_hint():
		return
	
	messaging = _Messaging.new()
	add_child(messaging)

	var address = _get_ip_address()
	var user_id = _make_user_id(address)

	messaging.local_user = {
		"id": user_id,
		"name": Helper.get_logon_name(),
		"address": address,
		"version": "1.2.39",
		"status": "chat",
		"avatar": 0,
		"group": "General",
		"note": "",
		"caps": _D.UserCap.UC_File | _D.UserCap.UC_Folder
	}

	var settings = {
		"port": 50000,
		"udp_port": 50000,
		"tcp_port": 50000,
		"multicast": "239.255.100.100",
		"broadcast_list": [],
		"user_name": Helper.get_logon_name()
	}

	messaging.network = _NetworkManager.new()
	add_child(messaging.network)
	messaging.network.set_local_id(user_id)
	messaging.init_config(settings)
	print("CydLAN: Starting with IP=", address, " user_id=", user_id, " multicast=", settings["multicast"], " ports=", settings["port"], "/", settings["tcp_port"])
	messaging.start()

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

func _make_user_id(address: String) -> String:
	return address.replace(".", "") + Helper.get_logon_name()
