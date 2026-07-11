extends Node

var public_key: PackedByteArray = PackedByteArray()

var _rsa: CryptoKey = null
var _encrypt_map: Dictionary = {}
var _decrypt_map: Dictionary = {}


func generate_rsa() -> PackedByteArray:
	var crypto := Crypto.new()
	_rsa = crypto.generate_rsa(1024)
	if not _rsa:
		return PackedByteArray()

	var key_path := "user://cydlan_public_key.pem"
	if _rsa.save(key_path, true) != OK:
		return PackedByteArray()
	var file := FileAccess.open(key_path, FileAccess.READ)
	if file:
		var x509_pem := file.get_buffer(file.get_length())
		file.close()
		public_key = _pem_convert_x509_to_pkcs1(x509_pem)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(key_path))
	return public_key


func generate_aes(user_id: String, peer_public_key: PackedByteArray) -> PackedByteArray:
	if user_id.is_empty() or peer_public_key.is_empty():
		return PackedByteArray()

	var crypto := Crypto.new()
	var key_seed := crypto.generate_random_bytes(32)
	if key_seed.size() != 32:
		return PackedByteArray()
	var key_iv := _evp_bytes_to_key(key_seed, 48, 5)
	if key_iv.size() != 48:
		return PackedByteArray()

	var original_key_path := "user://cydlan_peer_original_" + user_id.md5_text() + ".pem"
	var original_file := FileAccess.open(original_key_path, FileAccess.WRITE)
	if not original_file:
		return PackedByteArray()
	original_file.store_buffer(peer_public_key)
	original_file.close()

	var encrypted := _rsa_oaep_encrypt_with_powershell(user_id, original_key_path, key_iv)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(original_key_path))

	# LAN Messenger uses RSA_PKCS1_OAEP_PADDING. Do not silently establish a
	# session with another padding mode because it looks connected locally but
	# can never interoperate with the original client.
	if encrypted.is_empty():
		push_warning("CydLAN: RSA-OAEP session-key encryption failed")
		return PackedByteArray()

	_store_session(user_id, key_iv)
	return encrypted


func retrieve_aes(user_id: String, encrypted: PackedByteArray) -> void:
	if user_id.is_empty() or encrypted.is_empty() or not _rsa:
		return
	var key_iv := _rsa_oaep_decrypt_with_powershell(user_id, encrypted)
	if key_iv.size() != 48:
		push_warning("CydLAN: RSA-OAEP session-key decryption failed for %s" % user_id)
		return
	_store_session(user_id, key_iv)


func has_session(user_id: String) -> bool:
	return _encrypt_map.has(user_id) and _decrypt_map.has(user_id)


func clear_session(user_id: String) -> void:
	_encrypt_map.erase(user_id)
	_decrypt_map.erase(user_id)


func encrypt(user_id: String, clear_data: PackedByteArray) -> PackedByteArray:
	var params = _encrypt_map.get(user_id)
	if not params or clear_data.is_empty():
		return PackedByteArray()
	var context := AESContext.new()
	if context.start(AESContext.MODE_CBC_ENCRYPT, params["key"], params["iv"]) != OK:
		return PackedByteArray()
	var result := context.update(_pad_pkcs7(clear_data, 16))
	context.finish()
	return result


func decrypt(user_id: String, cipher_data: PackedByteArray) -> PackedByteArray:
	var params = _decrypt_map.get(user_id)
	if not params or cipher_data.is_empty() or cipher_data.size() % 16 != 0:
		return PackedByteArray()
	var context := AESContext.new()
	if context.start(AESContext.MODE_CBC_DECRYPT, params["key"], params["iv"]) != OK:
		return PackedByteArray()
	var padded := context.update(cipher_data)
	context.finish()
	return _unpad_pkcs7(padded)


func _store_session(user_id: String, key_iv: PackedByteArray) -> void:
	if key_iv.size() != 48:
		return
	var parameters := {"key": key_iv.slice(0, 32), "iv": key_iv.slice(32, 48)}
	_encrypt_map[user_id] = parameters
	_decrypt_map[user_id] = parameters.duplicate(true)


func _rsa_oaep_encrypt_with_powershell(
	user_id: String, public_key_path: String, data: PackedByteArray
) -> PackedByteArray:
	var data_path := "user://cydlan_session_" + user_id.md5_text() + ".bin"
	var data_file := FileAccess.open(data_path, FileAccess.WRITE)
	if not data_file:
		return PackedByteArray()
	data_file.store_buffer(data)
	data_file.close()

	var script_path := ProjectSettings.globalize_path("res://scripts/network/rsa_oaep_encrypt.ps1")
	var output: Array = []
	var args := [
		"-NoProfile",
		"-ExecutionPolicy",
		"Bypass",
		"-File",
		script_path,
		ProjectSettings.globalize_path(public_key_path),
		ProjectSettings.globalize_path(data_path)
	]
	var exit_code := OS.execute("powershell.exe", args, output, true)
	if exit_code != 0:
		output.clear()
		exit_code = OS.execute("pwsh", args, output, true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(data_path))
	if exit_code != 0 or output.is_empty():
		return PackedByteArray()
	return Marshalls.base64_to_raw("".join(output).strip_edges())


func _rsa_oaep_decrypt_with_powershell(
	user_id: String, cipher_data: PackedByteArray
) -> PackedByteArray:
	var key_path := "user://cydlan_private_" + user_id.md5_text() + ".pem"
	if _rsa.save(key_path, false) != OK:
		return PackedByteArray()
	var data_path := "user://cydlan_session_cipher_" + user_id.md5_text() + ".bin"
	var data_file := FileAccess.open(data_path, FileAccess.WRITE)
	if not data_file:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(key_path))
		return PackedByteArray()
	data_file.store_buffer(cipher_data)
	data_file.close()

	var script_path := ProjectSettings.globalize_path("res://scripts/network/rsa_oaep_decrypt.ps1")
	var output: Array = []
	var args := [
		"-NoProfile",
		"-ExecutionPolicy",
		"Bypass",
		"-File",
		script_path,
		ProjectSettings.globalize_path(key_path),
		ProjectSettings.globalize_path(data_path)
	]
	var exit_code := OS.execute("powershell.exe", args, output, true)
	if exit_code != 0:
		output.clear()
		exit_code = OS.execute("pwsh", args, output, true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(data_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(key_path))
	if exit_code != 0 or output.is_empty():
		return PackedByteArray()
	return Marshalls.base64_to_raw("".join(output).strip_edges())


static func _evp_bytes_to_key(
	data: PackedByteArray, required_size: int, rounds: int
) -> PackedByteArray:
	var result := PackedByteArray()
	var previous := PackedByteArray()
	while result.size() < required_size:
		var digest := _sha1(previous + data)
		for _round in range(1, rounds):
			digest = _sha1(digest)
		result.append_array(digest)
		previous = digest
	return result.slice(0, required_size)


static func _sha1(data: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA1)
	context.update(data)
	return context.finish()


static func _pad_pkcs7(data: PackedByteArray, block_size: int) -> PackedByteArray:
	var padding_size := block_size - (data.size() % block_size)
	var result := data.duplicate()
	var original_size := result.size()
	result.resize(original_size + padding_size)
	for index in range(original_size, result.size()):
		result[index] = padding_size
	return result


static func _unpad_pkcs7(data: PackedByteArray) -> PackedByteArray:
	if data.is_empty():
		return PackedByteArray()
	var padding_size := int(data[data.size() - 1])
	if padding_size < 1 or padding_size > 16 or padding_size > data.size():
		return PackedByteArray()
	for index in range(data.size() - padding_size, data.size()):
		if int(data[index]) != padding_size:
			return PackedByteArray()
	return data.slice(0, data.size() - padding_size)


static func _pem_decode(pem: PackedByteArray) -> PackedByteArray:
	if pem.is_empty():
		return PackedByteArray()
	var text := pem.get_string_from_utf8()
	var base64 := ""
	for source_line in text.split("\n"):
		var line := source_line.strip_edges()
		if line.is_empty() or line.begins_with("-----"):
			continue
		base64 += line
	if base64.is_empty():
		return PackedByteArray()
	return Marshalls.base64_to_raw(base64)


static func _pem_encode(der: PackedByteArray, marker: String) -> PackedByteArray:
	if der.is_empty():
		return PackedByteArray()
	var base64 := Marshalls.raw_to_base64(der)
	var lines := PackedStringArray()
	lines.append("-----BEGIN " + marker + "-----")
	var offset := 0
	while offset < base64.length():
		lines.append(base64.substr(offset, 64))
		offset += 64
	lines.append("-----END " + marker + "-----")
	lines.append("")
	return "\n".join(lines).to_utf8_buffer()


static func _asn1_read_tlv(data: PackedByteArray, offset: int) -> Dictionary:
	if offset >= data.size():
		return {"tag": 0, "length": 0, "value_start": offset, "total": 0}
	var tag := int(data[offset])
	var length_offset := offset + 1
	if length_offset >= data.size():
		return {"tag": tag, "length": 0, "value_start": length_offset, "total": 0}
	var length := 0
	var encoded_length_bytes := 1
	if data[length_offset] < 0x80:
		length = int(data[length_offset])
	else:
		var count := int(data[length_offset] & 0x7F)
		if count < 1 or count > 4:
			return {"tag": tag, "length": 0, "value_start": length_offset, "total": 0}
		encoded_length_bytes = count + 1
		for index in range(count):
			var data_index := length_offset + 1 + index
			if data_index >= data.size():
				return {"tag": tag, "length": 0, "value_start": data_index, "total": 0}
			length = (length << 8) | int(data[data_index])
	var value_start := length_offset + encoded_length_bytes
	if value_start + length > data.size():
		return {"tag": tag, "length": 0, "value_start": value_start, "total": 0}
	return {
		"tag": tag,
		"length": length,
		"value_start": value_start,
		"total": value_start + length - offset
	}


static func _pem_convert_x509_to_pkcs1(x509_pem: PackedByteArray) -> PackedByteArray:
	var der := _pem_decode(x509_pem)
	if der.size() < 30:
		return x509_pem
	var outer := _asn1_read_tlv(der, 0)
	if outer["tag"] != 0x30:
		return x509_pem
	var position := int(outer["value_start"])
	var algorithm := _asn1_read_tlv(der, position)
	if algorithm["tag"] != 0x30:
		return x509_pem
	position = int(algorithm["value_start"]) + int(algorithm["length"])
	var bit_string := _asn1_read_tlv(der, position)
	if bit_string["tag"] != 0x03 or bit_string["length"] < 2:
		return x509_pem
	var inner_start := int(bit_string["value_start"]) + 1
	var inner_length := int(bit_string["length"]) - 1
	return _pem_encode(der.slice(inner_start, inner_start + inner_length), "RSA PUBLIC KEY")


static func _make_tlv(tag: int, value: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray([tag])
	var length := value.size()
	if length < 0x80:
		result.append(length)
	elif length < 0x100:
		result.append_array(PackedByteArray([0x81, length]))
	elif length < 0x10000:
		result.append_array(PackedByteArray([0x82, (length >> 8) & 0xFF, length & 0xFF]))
	else:
		result.append_array(
			PackedByteArray([0x83, (length >> 16) & 0xFF, (length >> 8) & 0xFF, length & 0xFF])
		)
	result.append_array(value)
	return result


static func _pem_convert_pkcs1_to_x509(pkcs1_pem: PackedByteArray) -> PackedByteArray:
	var der := _pem_decode(pkcs1_pem)
	if der.size() < 20 or der[0] != 0x30:
		return pkcs1_pem
	var algorithm := PackedByteArray(
		[0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00]
	)
	var bit_string := _make_tlv(0x03, PackedByteArray([0x00]) + der)
	return _pem_encode(_make_tlv(0x30, algorithm + bit_string), "PUBLIC KEY")
