extends SceneTree

const D = preload("res://scripts/network/definitions.gd")

var failures: Array[String] = []

func _init() -> void:
	_test_legacy_constants()
	_test_xml_round_trip()
	_test_message_header()
	_test_datagram_header()
	_test_file_request_shape()
	if failures.is_empty():
		print("CydLAN protocol compatibility tests passed")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _test_legacy_constants() -> void:
	_expect(D.APP_MARKER == "lmcmessage", "Legacy XML marker changed")
	_expect(D.DatagramTypeNames == ["", "BRDCST", "PUBKEY", "HNDSHK", "MESSAG"], "Legacy datagram names changed")
	_expect(D.MessageTypeNames[D.MessageType.MT_Announce] == "announce", "Announce message name changed")
	_expect(D.MessageTypeNames[D.MessageType.MT_Message] == "message", "Direct message name changed")
	_expect(D.MessageTypeNames[D.MessageType.MT_File] == "file", "File message name changed")
	_expect(D.FileOpNames[D.FileOp.FO_Request] == "request", "File request operation changed")
	_expect(D.FileModeNames[D.FileMode.FM_Send] == "send", "File send mode changed")

func _test_xml_round_trip() -> void:
	var xml := XmlMessage.new()
	xml.add_header(D.XN_FROM, "ABCUser")
	xml.add_data(D.XN_MESSAGE, "A < B & C > D")
	var restored := XmlMessage.new(xml.get_xml())
	_expect(restored.is_valid(), "Generated XML is invalid")
	_expect(restored.header(D.XN_FROM) == "ABCUser", "XML header did not round-trip")
	_expect(restored.data(D.XN_MESSAGE) == "A < B & C > D", "XML escaping is not legacy-compatible")

func _test_message_header() -> void:
	var xml := XmlMessage.new()
	xml.add_data(D.XN_MESSAGE, "hello")
	var payload := Message.add_header(D.MessageType.MT_Message, 42, "LOCAL", "REMOTE", xml)
	var parsed := Message.get_header(payload)
	_expect(parsed.get("type", -1) == D.MessageType.MT_Message, "Message type header mismatch")
	_expect(parsed.get("id", -1) == 42, "Message ID header mismatch")
	_expect(parsed.get("userId", "") == "LOCAL", "Message sender header mismatch")
	_expect((parsed.get("message") as XmlMessage).header(D.XN_TO) == "REMOTE", "Message recipient header mismatch")

func _test_datagram_header() -> void:
	var clear := "payload".to_utf8_buffer()
	var framed := Datagram.add_header(D.DatagramType.DT_Message, clear)
	_expect(framed.slice(0, 6).get_string_from_utf8() == "MESSAG", "TCP datagram marker mismatch")
	_expect(Datagram.get_data(framed).get_string_from_utf8() == "payload", "TCP datagram payload mismatch")

func _test_file_request_shape() -> void:
	var xml := XmlMessage.new()
	xml.add_data(D.XN_FILEID, "0123456789abcdef0123456789abcdef")
	xml.add_data(D.XN_FILENAME, "report.pdf")
	xml.add_data(D.XN_FILESIZE, "1024")
	xml.add_data(D.XN_FILETYPE, D.FileTypeNames[D.FileType.FT_Normal])
	xml.add_data(D.XN_MODE, D.FileModeNames[D.FileMode.FM_Send])
	xml.add_data(D.XN_FILEOP, D.FileOpNames[D.FileOp.FO_Request])
	_expect(xml.data(D.XN_FILEID).length() == 32, "Legacy file ID must be 32 characters")
	_expect(xml.data(D.XN_FILETYPE) == "normal", "Legacy file type mismatch")
	_expect(xml.data(D.XN_MODE) == "send", "Legacy file mode mismatch")
	_expect(xml.data(D.XN_FILEOP) == "request", "Legacy file operation mismatch")
