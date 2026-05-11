extends Node

var public_key: PackedByteArray
var _rsa: CryptoKey = null
var _encrypt_map: Dictionary = {}
var _decrypt_map: Dictionary = {}

func generate_rsa() -> PackedByteArray:
	var crypto = Crypto.new()
	_rsa = crypto.generate_rsa(2048)
	public_key = _rsa.save_to_buffer(CryptoKey.MODE_PUBLIC)
	return public_key

func generate_aes(user_id: String, pub_key: PackedByteArray) -> PackedByteArray:
	var aes_key = _generate_random_bytes(32)
	var aes_iv = _generate_random_bytes(16)
	var combined = aes_key + aes_iv
	var crypto = Crypto.new()
	var peer_key = CryptoKey.new()
	peer_key.load_from_buffer(pub_key, CryptoKey.MODE_PUBLIC)
	var encrypted = crypto.encrypt(peer_key, combined)
	_encrypt_map[user_id] = { "key": aes_key, "iv": aes_iv }
	return encrypted

func retrieve_aes(user_id: String, encrypted: PackedByteArray) -> void:
	var crypto = Crypto.new()
	var combined = crypto.decrypt(_rsa, encrypted)
	if combined.size() < 48: return
	var aes_key = combined.slice(0, 32)
	var aes_iv = combined.slice(32, 48)
	_encrypt_map[user_id] = { "key": aes_key, "iv": aes_iv }
	_decrypt_map[user_id] = { "key": aes_key, "iv": aes_iv }

func encrypt(user_id: String, clear_data: PackedByteArray) -> PackedByteArray:
	var params = _encrypt_map.get(user_id, _encrypt_map.get(user_id, null))
	if not params: return PackedByteArray()
	var ctx = AESContext.new()
	ctx.start(AESContext.CBC_ENCRYPT, params["key"], params["iv"])
	var padded = _pad_pkcs7(clear_data, 16)
	var result = ctx.update(padded)
	ctx.finish()
	return result

func decrypt(user_id: String, cipher_data: PackedByteArray) -> PackedByteArray:
	var params = _decrypt_map.get(user_id, _encrypt_map.get(user_id, null))
	if not params: return PackedByteArray()
	var ctx = AESContext.new()
	ctx.start(AESContext.CBC_DECRYPT, params["key"], params["iv"])
	var result = ctx.update(cipher_data)
	ctx.finish()
	return _unpad_pkcs7(result)

static func _generate_random_bytes(size: int) -> PackedByteArray:
	var result = PackedByteArray()
	result.resize(size)
	for i in range(size):
		result[i] = randi() % 256
	return result

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
