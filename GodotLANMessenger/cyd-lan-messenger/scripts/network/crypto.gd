extends Node

var public_key: PackedByteArray
var _rsa: CryptoKey = null
var _encrypt_map: Dictionary = {}
var _decrypt_map: Dictionary = {}

func generate_rsa() -> PackedByteArray:
	var crypto = Crypto.new()
	_rsa = crypto.generate_rsa(1024)
	var temp = "user://temp_pubkey.pem"
	_rsa.save(temp, true)
	var f = FileAccess.open(temp, FileAccess.READ)
	if f:
		var x509_pem = f.get_buffer(f.get_length())
		f.close()
		DirAccess.remove_absolute(temp)
		public_key = _pem_convert_x509_to_pkcs1(x509_pem)
	else:
		DirAccess.remove_absolute(temp)
	return public_key

func generate_aes(user_id: String, pub_key: PackedByteArray) -> PackedByteArray:
	print("CydLAN: Crypto generating AES for ", user_id, " public key bytes=", pub_key.size())
	var key_data = _generate_random_bytes(32)
	var combined = _evp_bytes_to_key(key_data, 48, 5)
	var aes_key = combined.slice(0, 32)
	var aes_iv = combined.slice(32, 48)
	var crypto = Crypto.new()
	var peer_key = CryptoKey.new()
	var x509_key = pub_key
	var original_key_path = "user://peer_original_pubkey_" + user_id.md5_text() + ".pem"
	var original_file = FileAccess.open(original_key_path, FileAccess.WRITE)
	if not original_file:
		print("CydLAN: Crypto failed to write original peer public key temp file")
		return PackedByteArray()
	original_file.store_buffer(pub_key)
	original_file.close()
	if pub_key.size() > 0 and pub_key[0] == 0x2D:
		var pem_text = pub_key.get_string_from_utf8()
		if pem_text.begins_with("-----BEGIN RSA PUBLIC KEY"):
			x509_key = _pem_convert_pkcs1_to_x509(pub_key)
	var key_path = "user://peer_pubkey_" + user_id.md5_text() + ".pem"
	var file = FileAccess.open(key_path, FileAccess.WRITE)
	if not file:
		print("CydLAN: Crypto failed to write peer public key temp file")
		return PackedByteArray()
	file.store_buffer(x509_key)
	file.close()
	var load_error = peer_key.load(key_path, true)
	if load_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(key_path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(original_key_path))
		print("CydLAN: Crypto failed to load peer public key error=", load_error)
		return PackedByteArray()
	var encrypted = _rsa_oaep_encrypt_with_powershell(user_id, original_key_path, combined)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(key_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(original_key_path))
	if encrypted.is_empty():
		encrypted = crypto.encrypt(peer_key, combined)
	if encrypted.is_empty():
		print("CydLAN: Crypto RSA encrypt returned empty session key")
		return PackedByteArray()
	print("CydLAN: Crypto encrypted session key bytes=", encrypted.size())
	_encrypt_map[user_id] = { "key": aes_key, "iv": aes_iv }
	_decrypt_map[user_id] = { "key": aes_key, "iv": aes_iv }
	return encrypted

func _rsa_oaep_encrypt_with_powershell(user_id: String, public_key_path: String, data: PackedByteArray) -> PackedByteArray:
	var data_path = "user://session_key_" + user_id.md5_text() + ".bin"
	var data_file = FileAccess.open(data_path, FileAccess.WRITE)
	if not data_file:
		return PackedByteArray()
	data_file.store_buffer(data)
	data_file.close()
	var script_path = ProjectSettings.globalize_path("res://scripts/network/rsa_oaep_encrypt.ps1")
	var output: Array = []
	var args = [
		"-NoProfile",
		"-ExecutionPolicy",
		"Bypass",
		"-File",
		script_path,
		ProjectSettings.globalize_path(public_key_path),
		ProjectSettings.globalize_path(data_path)
	]
	var exit_code = OS.execute("powershell.exe", args, output, true)
	if exit_code != 0:
		output.clear()
		exit_code = OS.execute("pwsh", args, output, true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(data_path))
	if exit_code != 0 or output.is_empty():
		print("CydLAN: Crypto PowerShell OAEP failed exit=", exit_code, " output=", output)
		return PackedByteArray()
	var b64 = "".join(output).strip_edges()
	var encrypted = Marshalls.base64_to_raw(b64)
	if encrypted == null:
		return PackedByteArray()
	print("CydLAN: Crypto used local PowerShell OAEP")
	return encrypted

func _rsa_oaep_decrypt_with_powershell(user_id: String, cipher_data: PackedByteArray) -> PackedByteArray:
	var key_path = "user://privkey_" + user_id.md5_text() + ".pem"
	_rsa.save(key_path, false)
	var data_path = "user://session_key_cipher_" + user_id.md5_text() + ".bin"
	var data_file = FileAccess.open(data_path, FileAccess.WRITE)
	if not data_file:
		return PackedByteArray()
	data_file.store_buffer(cipher_data)
	data_file.close()
	var script_path = ProjectSettings.globalize_path("res://scripts/network/rsa_oaep_decrypt.ps1")
	var output: Array = []
	var args = [
		"-NoProfile",
		"-ExecutionPolicy",
		"Bypass",
		"-File",
		script_path,
		ProjectSettings.globalize_path(key_path),
		ProjectSettings.globalize_path(data_path)
	]
	var exit_code = OS.execute("powershell.exe", args, output, true)
	if exit_code != 0:
		output.clear()
		exit_code = OS.execute("pwsh", args, output, true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(data_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(key_path))
	if exit_code != 0 or output.is_empty():
		print("CydLAN: Crypto PowerShell OAEP decrypt failed exit=", exit_code)
		return PackedByteArray()
	var b64 = "".join(output).strip_edges()
	var decrypted = Marshalls.base64_to_raw(b64)
	if decrypted == null:
		return PackedByteArray()
	print("CydLAN: Crypto used PowerShell OAEP decrypt")
	return decrypted

func retrieve_aes(user_id: String, encrypted: PackedByteArray) -> void:
	print("CydLAN: Crypto retrieving AES for ", user_id, " encrypted bytes=", encrypted.size())
	var crypto = Crypto.new()
	var combined = crypto.decrypt(_rsa, encrypted)
	if combined.size() < 48:
		print("CydLAN: Crypto PKCS1 decrypt failed, trying OAEP decrypt via PowerShell")
		combined = _rsa_oaep_decrypt_with_powershell(user_id, encrypted)
	if combined.size() < 48:
		print("CydLAN: Crypto RSA decrypt failed/short result bytes=", combined.size())
		return
	var aes_key = combined.slice(0, 32)
	var aes_iv = combined.slice(32, 48)
	_encrypt_map[user_id] = { "key": aes_key, "iv": aes_iv }
	_decrypt_map[user_id] = { "key": aes_key, "iv": aes_iv }

func encrypt(user_id: String, clear_data: PackedByteArray) -> PackedByteArray:
	var params = _encrypt_map.get(user_id, _decrypt_map.get(user_id, null))
	if not params: return PackedByteArray()
	var ctx = AESContext.new()
	ctx.start(AESContext.MODE_CBC_ENCRYPT, params["key"], params["iv"])
	var padded = _pad_pkcs7(clear_data, 16)
	var result = ctx.update(padded)
	ctx.finish()
	return result

func decrypt(user_id: String, cipher_data: PackedByteArray) -> PackedByteArray:
	var params = _decrypt_map.get(user_id, _encrypt_map.get(user_id, null))
	if not params: return PackedByteArray()
	var ctx = AESContext.new()
	ctx.start(AESContext.MODE_CBC_DECRYPT, params["key"], params["iv"])
	var result = ctx.update(cipher_data)
	ctx.finish()
	return _unpad_pkcs7(result)

static func _generate_random_bytes(size: int) -> PackedByteArray:
	var result = PackedByteArray()
	result.resize(size)
	for i in range(size):
		result[i] = randi() % 256
	return result

static func _evp_bytes_to_key(data: PackedByteArray, size: int, rounds: int) -> PackedByteArray:
	var result = PackedByteArray()
	var previous = PackedByteArray()
	while result.size() < size:
		var digest_input = previous + data
		var digest = _sha1(digest_input)
		for i in range(1, rounds):
			digest = _sha1(digest)
		result.append_array(digest)
		previous = digest
	return result.slice(0, size)

static func _sha1(data: PackedByteArray) -> PackedByteArray:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(data)
	return ctx.finish()

static func _pad_pkcs7(data: PackedByteArray, block_size: int) -> PackedByteArray:
	var pad_len = block_size - (data.size() % block_size)
	var result = data.duplicate()
	result.resize(result.size() + pad_len)
	for i in range(pad_len):
		result[result.size() - pad_len + i] = pad_len
	return result

static func _unpad_pkcs7(data: PackedByteArray) -> PackedByteArray:
	if data.size() == 0: return data
	var pad_len = data[data.size() - 1]
	if pad_len > 16 or pad_len > data.size(): return data
	return data.slice(0, data.size() - pad_len)

static func _pem_decode(pem: PackedByteArray) -> PackedByteArray:
	if pem.is_empty():
		return PackedByteArray()
	var text = pem.get_string_from_utf8()
	if text.is_empty():
		return PackedByteArray()
	var lines = text.split("\n")
	var b64 = ""
	for line in lines:
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("-----"):
			continue
		b64 += line
	if b64.is_empty():
		return PackedByteArray()
	var result = Marshalls.base64_to_raw(b64)
	if result == null:
		return PackedByteArray()
	return result

static func _pem_encode(der: PackedByteArray, marker: String) -> PackedByteArray:
	if der.is_empty():
		return PackedByteArray()
	var b64 = Marshalls.raw_to_base64(der)
	var lines = PackedStringArray()
	lines.append("-----BEGIN " + marker + "-----")
	var i = 0
	while i < b64.length():
		lines.append(b64.substr(i, 64))
		i += 64
	lines.append("-----END " + marker + "-----")
	lines.append("")
	return ("\n".join(lines)).to_utf8_buffer()

static func _asn1_read_tlv(data: PackedByteArray, offset: int) -> Dictionary:
	if offset >= data.size():
		return { "tag": 0, "length": 0, "value_start": offset, "total": 0 }
	var tag = data[offset]
	var len_start = offset + 1
	if len_start >= data.size():
		return { "tag": tag, "length": 0, "value_start": len_start, "total": 0 }
	var length = 0
	var len_bytes = 1
	if data[len_start] < 0x80:
		length = data[len_start]
	else:
		len_bytes = data[len_start] & 0x7F
		if len_bytes < 1:
			len_bytes = 1
		for j in range(len_bytes):
			var idx = len_start + 1 + j
			if idx >= data.size():
				break
			length = (length << 8) | data[idx]
		len_bytes += 1
	var value_start = len_start + len_bytes
	var total = value_start + length - offset
	return { "tag": tag, "length": length, "value_start": value_start, "total": total }

static func _pem_convert_x509_to_pkcs1(x509_pem: PackedByteArray) -> PackedByteArray:
	var der = _pem_decode(x509_pem)
	if der.size() < 30:
		return x509_pem
	var outer = _asn1_read_tlv(der, 0)
	if outer.tag != 0x30:
		return x509_pem
	var pos = outer.value_start
	var alg_id = _asn1_read_tlv(der, pos)
	if alg_id.tag != 0x30:
		return x509_pem
	pos = alg_id.value_start + alg_id.length
	var bit_str = _asn1_read_tlv(der, pos)
	if bit_str.tag != 0x03:
		return x509_pem
	var inner_start = bit_str.value_start + 1
	var inner_len = bit_str.length - 1
	var pkcs1_der = der.slice(inner_start, inner_start + inner_len)
	return _pem_encode(pkcs1_der, "RSA PUBLIC KEY")

static func _make_tlv(tag: int, value: PackedByteArray) -> PackedByteArray:
	var result = PackedByteArray()
	result.append(tag)
	var len = value.size()
	if len < 0x80:
		result.append(len)
	elif len < 0x100:
		result.append(0x81)
		result.append(len)
	elif len < 0x10000:
		result.append(0x82)
		result.append((len >> 8) & 0xFF)
		result.append(len & 0xFF)
	else:
		result.append(0x83)
		result.append((len >> 16) & 0xFF)
		result.append((len >> 8) & 0xFF)
		result.append(len & 0xFF)
	result.append_array(value)
	return result

static func _pem_convert_pkcs1_to_x509(pkcs1_pem: PackedByteArray) -> PackedByteArray:
	var der = _pem_decode(pkcs1_pem)
	if der.size() < 20 or der[0] != 0x30:
		return pkcs1_pem
	var alg_id = PackedByteArray([0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00])
	var bit_str_inner = PackedByteArray([0x00]) + der
	var bit_str = _make_tlv(0x03, bit_str_inner)
	var outer = _make_tlv(0x30, alg_id + bit_str)
	return _pem_encode(outer, "PUBLIC KEY")
