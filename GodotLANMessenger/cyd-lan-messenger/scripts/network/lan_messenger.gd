extends Node

var messaging: Node = null

func _ready():
	messaging = preload("res://scripts/network/messaging.gd").new()
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
		"caps": UserCap.UC_File | UserCap.UC_Folder
	}

	var settings = {
		"port": 12111,
		"udp_port": 12111,
		"tcp_port": 12112,
		"multicast": "225.0.0.37",
		"broadcast_list": [],
		"user_name": Helper.get_logon_name()
	}

	messaging.network = preload("res://scripts/network/network_manager.gd").new()
	add_child(messaging.network)
	messaging.network.set_local_id(user_id)
	messaging.init_config(settings)
	messaging.start()

func _get_ip_address() -> String:
	var addrs = IP.get_local_addresses()
	for a in addrs:
		if a.begins_with("192.") or a.begins_with("10.") or a.begins_with("172."):
			return a
	return "127.0.0.1"

func _make_user_id(address: String) -> String:
	return address + "||" + Helper.get_logon_name() + "||" + str(Time.get_unix_time_from_system())
