class_name Datagram
const _D = preload("res://scripts/network/definitions.gd")

static func add_header(type: int, data: PackedByteArray) -> PackedByteArray:
	var header_str = _D.DatagramTypeNames[type]
	var header_bytes = header_str.to_utf8_buffer()
	var result = header_bytes + data
	return result

static func get_header(data: PackedByteArray) -> Dictionary:
	if data.size() < 6:
		return {}
	var type_str = data.slice(0, 6).get_string_from_utf8()
	var type_idx = Helper.index_of(_D.DatagramTypeNames, type_str)
	if type_idx < 0:
		return {}
	return { "type": type_idx, "userId": "", "address": "" }

static func get_data(data: PackedByteArray) -> PackedByteArray:
	if data.size() > 6:
		return data.slice(6)
	return PackedByteArray()
