class_name XmlMessage
var _xml: String

func _init(text: String = "") -> void:
	if text.is_empty():
		_xml = "<" + XN_ROOT + "><" + XN_HEAD + "></" + XN_HEAD + "><" + XN_BODY + "></" + XN_BODY + "></" + XN_ROOT + ">"
	else:
		_xml = text

func add_header(node_name: String, node_value: String) -> bool:
	return _add_xml_node(XN_HEAD, node_name, node_value)

func add_data(node_name: String, node_value: String) -> bool:
	return _add_xml_node(XN_BODY, node_name, node_value)

func header(node_name: String) -> String:
	return _get_xml_node(XN_HEAD, node_name)

func data(node_name: String) -> String:
	return _get_xml_node(XN_BODY, node_name)

func remove_header(node_name: String) -> bool:
	return _remove_xml_node(XN_HEAD, node_name)

func remove_data(node_name: String) -> bool:
	return _remove_xml_node(XN_BODY, node_name)

func header_exists(node_name: String) -> bool:
	return _xml_node_exists(XN_HEAD, node_name)

func data_exists(node_name: String) -> bool:
	return _xml_node_exists(XN_BODY, node_name)

func clone() -> XmlMessage:
	return XmlMessage.new(_xml)

func is_valid() -> bool:
	return _xml.contains("<" + XN_ROOT + ">")

func to_string() -> String:
	return _xml

func _add_xml_node(parent_node: String, node_name: String, node_value: String) -> bool:
	var close_tag = "</" + parent_node + ">"
	var idx = _xml.find(close_tag)
	if idx == -1:
		return false
	var insert = "<" + node_name + ">" + _escape_xml(node_value) + "</" + node_name + ">"
	_xml = _xml.insert(idx, insert)
	return true

func _get_xml_node(parent_node: String, node_name: String) -> String:
	var open = "<" + node_name + ">"
	var close = "</" + node_name + ">"
	var parent_open = "<" + parent_node + ">"
	var parent_close = "</" + parent_node + ">"
	var p_start = _xml.find(parent_open)
	if p_start == -1: return ""
	var p_end = _xml.find(parent_close, p_start)
	if p_end == -1: return ""
	var body = _xml.substr(p_start, p_end - p_start + parent_close.length())
	var n_start = body.find(open)
	if n_start == -1: return ""
	var n_end = body.find(close, n_start)
	if n_end == -1: return ""
	return _unescape_xml(body.substr(n_start + open.length(), n_end - n_start - open.length()))

func _remove_xml_node(parent_node: String, node_name: String) -> bool:
	var open = "<" + node_name + ">"
	var close = "</" + node_name + ">"
	var parent_open = "<" + parent_node + ">"
	var parent_close = "</" + parent_node + ">"
	var p_start = _xml.find(parent_open)
	if p_start == -1: return false
	var p_end = _xml.find(parent_close, p_start)
	if p_end == -1: return false
	var body = _xml.substr(p_start, p_end - p_start + parent_close.length())
	var n_start = body.find(open)
	if n_start == -1: return false
	var n_end = body.find(close, n_start)
	if n_end == -1: return false
	var full = body.substr(n_start, n_end - n_start + close.length())
	var abs_start = p_start + n_start
	_xml = _xml.erase(abs_start, full.length())
	return true

func _xml_node_exists(parent_node: String, node_name: String) -> bool:
	var open = "<" + node_name + ">"
	var parent_open = "<" + parent_node + ">"
	var p_start = _xml.find(parent_open)
	if p_start == -1: return false
	var body = _xml.substr(p_start)
	return body.find(open) != -1

static func _escape_xml(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

static func _unescape_xml(s: String) -> String:
	return s.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")
