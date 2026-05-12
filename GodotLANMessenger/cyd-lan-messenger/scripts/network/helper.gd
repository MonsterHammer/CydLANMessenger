class_name Helper
const _D = preload("res://scripts/network/definitions.gd")
const DELIMITER = _D.DELIMITER
const DELIMITER_ESC = _D.DELIMITER_ESC
static func index_of(array: Array, value: String) -> int:
	for i in range(array.size()):
		if array[i] == value:
			return i
	return -1

static func format_size(size: int) -> String:
	if size < 1024:
		return str(size) + " B"
	elif size < 1024 * 1024:
		return str(snapped(size / 1024.0, 0.1)) + " KB"
	elif size < 1024 * 1024 * 1024:
		return str(snapped(size / (1024.0 * 1024.0), 0.1)) + " MB"
	else:
		return str(snapped(size / (1024.0 * 1024.0 * 1024.0), 0.1)) + " GB"

static func get_uuid() -> String:
	return str(Time.get_unix_time_from_system()) + str(randi())

static func get_logon_name() -> String:
	return OS.get_environment("USERNAME") if OS.get_name() == "Windows" else OS.get_environment("USER")

static func get_host_name() -> String:
	return OS.get_environment("COMPUTERNAME") if OS.get_name() == "Windows" else OS.get_environment("HOSTNAME")

static func get_os_name() -> String:
	match OS.get_name():
		"Windows": return "Windows"
		"macOS": return "Macintosh"
		_: return "Linux"

static func escape_delimiter(data: String) -> String:
	return data.replace(DELIMITER, DELIMITER_ESC)

static func unescape_delimiter(data: String) -> String:
	return data.replace(DELIMITER_ESC, DELIMITER)

static func compare_versions(v1: String, v2: String) -> int:
	var parts1 = v1.split(".")
	var parts2 = v2.split(".")
	var max_len = max(parts1.size(), parts2.size())
	for i in range(max_len):
		var n1 = int(parts1[i]) if i < parts1.size() else 0
		var n2 = int(parts2[i]) if i < parts2.size() else 0
		if n1 < n2: return -1
		if n1 > n2: return 1
	return 0

static func bool_to_string(value: bool) -> String:
	return "true" if value else "false"

static func string_to_bool(value: String) -> bool:
	return value.to_lower() == "true"
