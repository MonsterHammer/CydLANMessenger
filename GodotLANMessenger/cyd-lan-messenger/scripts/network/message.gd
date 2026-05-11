class_name Message

static func add_header(type: int, id: int, local_id: String, peer_id: String, msg: XmlMessage) -> String:
	if not msg:
		msg = XmlMessage.new()
	msg.remove_header(XN_TIME)
	msg.add_header(XN_FROM, local_id)
	if not peer_id.is_empty():
		msg.add_header(XN_TO, peer_id)
	msg.add_header(XN_MESSAGEID, str(id))
	msg.add_header(XN_TYPE, MessageTypeNames[type])
	return msg.to_string()

static func get_header(text: String) -> Dictionary:
	var msg = XmlMessage.new(text)
	if not msg.is_valid():
		return {}
	msg.add_header(XN_TIME, str(Time.get_unix_time_from_system() * 1000))
	var type_str = msg.header(XN_TYPE)
	var type_idx = Helper.index_of(MessageTypeNames, type_str)
	if type_idx < 0:
		return {}
	return {
		"type": type_idx,
		"id": int(msg.header(XN_MESSAGEID)),
		"userId": msg.header(XN_FROM),
		"address": "",
		"message": msg
	}
