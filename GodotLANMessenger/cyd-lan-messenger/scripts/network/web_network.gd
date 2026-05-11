extends Node
signal message_received(data)

var _active: bool = false
var _http: HTTPRequest = null

func _init():
	_http = HTTPRequest.new()

func send_message(url: String, _data: String = "") -> void:
	if _active:
		_raise_error("busy")
		return
	if url.is_empty():
		_raise_error("error")
		return
	_active = true
	_http.request_completed.connect(_on_request_completed)
	_http.request(url)

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_active = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_raise_error("error")
		return
	if response_code >= 300 and response_code < 400:
		for h in headers:
			if h.to_lower().begins_with("location:"):
				var redirect = h.substr(9).strip_edges()
				send_message(redirect)
				return
		_raise_error("error")
		return
	var sz = body.get_string_from_utf8()
	message_received.emit(sz)

func _raise_error(error_type: String) -> void:
	var msg = XmlMessage.new()
	msg.add_header(XN_TYPE, MessageTypeNames[MessageType.MT_WebFailed])
	msg.add_data(XN_ERROR, error_type)
	message_received.emit(msg.to_string())
