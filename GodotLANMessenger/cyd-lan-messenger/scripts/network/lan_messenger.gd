extends Node

var messaging: Node = null
var network: Node = null

func _ready():
	network = preload("network_manager.gd").new()
	messaging = preload("messaging.gd").new()
	add_child(network)
	add_child(messaging)
	messaging._network = network

	var settings = {
		"port": 12111,
		"udp_port": 12111,
		"tcp_port": 12112,
		"multicast": "225.0.0.37",
		"broadcast_list": [],
		"user_name": Helper.get_logon_name()
	}
	messaging.init_config(settings)
	messaging.local_user = {
		"id": Helper.get_uuid(),
		"name": Helper.get_logon_name(),
		"address": network.ip_address,
		"version": "1.2.39",
		"status": "chat",
		"avatar": 0,
		"group": "General",
		"note": "",
		"caps": UserCap.UC_File | UserCap.UC_Folder
	}
	network.set_local_id(messaging.local_user["id"])
	messaging.start()

func _process(delta):
	pass
