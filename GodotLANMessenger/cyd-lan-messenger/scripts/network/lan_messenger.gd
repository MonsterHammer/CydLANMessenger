extends Node

const _D = preload("res://scripts/network/definitions.gd")
const _Messaging = preload("res://scripts/network/messaging.gd")
const _NetworkManager = preload("res://scripts/network/network_manager.gd")
const _AppSettings = preload("res://scripts/core/app_settings.gd")

var messaging: Node = null
var settings_overrides: Dictionary = {}
var app_settings: AppSettings = null

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	app_settings = _AppSettings.new()
	app_settings.load_settings()
	app_settings.merge(settings_overrides)

	var address := _get_ip_address()
	var user_id := _make_user_id(address)
	var logon_name := Helper.get_logon_name()
	var display_name := str(app_settings.get_value("display_name", "")).strip_edges()
	if display_name.is_empty():
		display_name = logon_name

	messaging = _Messaging.new()
	add_child(messaging)
	messaging.local_user = {
		"id": user_id,
		"name": display_name,
		"address": address,
		# Keep the legacy protocol version so the original client accepts us.
		"version": "1.2.39",
		"status": str(app_settings.get_value("status", "chat")),
		"avatar": int(app_settings.get_value("avatar", _get_configured_avatar())),
		"group": _D.GRP_DEFAULT,
		"note": str(app_settings.get_value("note", "")),
		"logon": logon_name,
		"host": _host_name(),
		"os": OS.get_name() + " / Godot 4.7",
		"firstname": str(app_settings.get_value("first_name", "")),
		"lastname": str(app_settings.get_value("last_name", "")),
		"about": str(app_settings.get_value("about", "")),
		"caps": _D.UserCap.UC_File | _D.UserCap.UC_GroupMessage | _D.UserCap.UC_Folder
	}

	var port := clampi(int(app_settings.get_value("port", 50000)), 1024, 65535)
	var settings := {
		"port": port,
		"udp_port": port,
		"tcp_port": port,
		"multicast": str(app_settings.get_value("multicast", "239.255.100.100")),
		"broadcast_list": [],
		"user_name": display_name,
		"retry_timeout_ms": int(app_settings.get_value("retry_timeout_ms", 2500)),
		"max_retries": int(app_settings.get_value("max_retries", 3)),
		"download_dir": str(app_settings.get_value("download_dir", "user://downloads")),
		"auto_accept_files": bool(app_settings.get_value("auto_accept_files", false))
	}

	messaging.network = _NetworkManager.new()
	add_child(messaging.network)
	messaging.network.set_local_id(user_id)
	messaging.init_config(settings)
	print("CydLAN: Godot 4.7 client starting on ", address, ":", port)
	messaging.start()

func _exit_tree() -> void:
	if messaging and messaging.has_method("stop"):
		messaging.stop()

func update_profile(profile: Dictionary) -> void:
	if not messaging:
		return
	for key in profile:
		if messaging.local_user.has(key):
			messaging.local_user[key] = profile[key]
		if app_settings:
			match key:
				"name": app_settings.set_value("display_name", profile[key])
				"note": app_settings.set_value("note", profile[key])
				"status": app_settings.set_value("status", profile[key])
				"firstname": app_settings.set_value("first_name", profile[key])
				"lastname": app_settings.set_value("last_name", profile[key])
				"about": app_settings.set_value("about", profile[key])
	if app_settings:
		app_settings.save_settings()
	messaging.announce_profile_changes(profile)

func _get_ip_address() -> String:
	var best := ""
	var fallback := ""
	for interface in IP.get_local_interfaces():
		var addresses: Array = interface.get("addresses", [])
		for raw_address in addresses:
			var address := str(raw_address)
			if address.contains(":") or not address.is_valid_ip_address():
				continue
			if address.begins_with("127.") or address.begins_with("169.254."):
				continue
			if address.begins_with("192.168.56.") or address.begins_with("192.168.137.") or address.begins_with("172.17."):
				if fallback.is_empty():
					fallback = address
				continue
			if address.begins_with("10.") or address.begins_with("192.168."):
				return address
			if address.begins_with("172.") and best.is_empty():
				best = address
	if not best.is_empty():
		return best
	if not fallback.is_empty():
		return fallback
	return "127.0.0.1"

func _make_user_id(address: String) -> String:
	var seed := OS.get_unique_id()
	if seed.is_empty():
		seed = address + "|" + Helper.get_logon_name()
	return seed.md5_text().substr(0, 12).to_upper() + Helper.get_logon_name()

func _host_name() -> String:
	var value := OS.get_environment("COMPUTERNAME")
	if value.is_empty():
		value = OS.get_environment("HOSTNAME")
	return value

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
