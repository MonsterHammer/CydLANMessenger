class_name AppSettings
extends RefCounted

const SETTINGS_PATH := "user://cyd_lan_messenger.cfg"

var values: Dictionary = {
	"display_name": "",
	"note": "",
	"status": "chat",
	"avatar": 0,
	"download_dir": "user://downloads",
	"auto_accept_files": false,
	"minimize_to_tray": true,
	"show_timestamps": true,
	"port": 50000,
	"multicast": "239.255.100.100",
	"retry_timeout_ms": 2500,
	"max_retries": 3,
	"first_name": "",
	"last_name": "",
	"about": ""
}

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for key in values.keys():
		values[key] = cfg.get_value("settings", key, values[key])

func save_settings() -> Error:
	var cfg := ConfigFile.new()
	for key in values.keys():
		cfg.set_value("settings", key, values[key])
	return cfg.save(SETTINGS_PATH)

func get_value(key: String, fallback = null):
	return values.get(key, fallback)

func set_value(key: String, value) -> void:
	values[key] = value

func merge(overrides: Dictionary) -> void:
	for key in overrides:
		values[key] = overrides[key]
