extends Node

const _D = preload("res://scripts/network/definitions.gd")
const _Messaging = preload("res://scripts/network/messaging.gd")
const _NetworkManager = preload("res://scripts/network/network_manager.gd")

var messaging: Node = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	messaging = _Messaging.new()
	add_child(messaging)

	var address := _get_ip_address()
	var user_id := _make_user_id(address)
	var avatar := _get_configured_avatar()

	messaging.local_user = {
		"id": user_id,
		"name": Helper.get_logon_name(),
		"address": address,
		"version": "1.2.39",
		"status": "chat",
		"avatar": avatar,
		"group": _D.GRP_DEFAULT,
		"note": "",
		"caps": _D.UserCap.UC_File | _D.UserCap.UC_GroupMessage | _D.UserCap.UC_Folder
	}

	var settings := {
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
	print(
		"CydLAN: Starting with IP=",
		address,
		" user_id=",
		user_id,
		" multicast=",
		settings["multicast"],
		" ports=",
		settings["udp_port"],
		"/",
		settings["tcp_port"]
	)
	# Never kill another process that owns the LAN Messenger port. The old
	# cleanup routine could terminate another Godot/editor instance and create
	# an external restart loop. A bind conflict is now reported normally.
	messaging.start()


func _exit_tree() -> void:
	if messaging and is_instance_valid(messaging):
		messaging.stop()


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


func _make_user_id(address: String) -> String:
	# LAN Messenger IDs are stable, delimiter-free identifiers. Godot does not
	# expose adapter MAC addresses, so preserve the existing compatible scheme.
	return address.replace(".", "") + Helper.get_logon_name()


func _get_configured_avatar() -> int:
	for path in _avatar_config_paths():
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if not file:
			continue
		while not file.eof_reached():
			var line := file.get_line().strip_edges()
			if line.begins_with("Avatar="):
				var value := line.trim_prefix("Avatar=").strip_edges()
				file.close()
				return int(value) if value.is_valid_int() else 0
		file.close()
	return 0


func _avatar_config_paths() -> Array[String]:
	var paths: Array[String] = ["user://LAN Messenger.ini"]
	if OS.get_name() == "Windows":
		var app_data := OS.get_environment("APPDATA")
		if not app_data.is_empty():
			paths.append(app_data.path_join("LAN Messenger").path_join("LAN Messenger.ini"))
	return paths
