extends Control

@onready var peer_list: ItemList = %PeerList
@onready var status_label: Label = %StatusLabel
@onready var send_btn: Button = %SendBtn
@onready var refresh_btn: Button = %RefreshBtn

const PORT = 50000
const BROADCAST_INTERVAL = 3.0

var _udp: PacketPeerUDP
var _peers: Dictionary = {}
var _timer: float = 0.0
var _local_name: String = ""

func _ready():
	_udp = PacketPeerUDP.new()
	_local_name = OS.get_environment("USERNAME") if OS.get_name() == "Windows" else OS.get_environment("USER")
	status_label.text = "Initializing..."
	send_btn.pressed.connect(_on_send_pressed)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	_start_udp()

func _start_udp():
	if _udp.bind(PORT, "*") == OK:
		_udp.set_broadcast_enabled(true)
		status_label.text = "Listening on port " + str(PORT)
		print("LAN Test: UDP bound to port ", PORT)
		_send_broadcast()
	else:
		status_label.text = "Failed to bind port " + str(PORT)

func _send_broadcast():
	var msg = "LAN_TEST:" + _local_name
	var bytes = msg.to_utf8_buffer()
	_udp.set_dest_address("255.255.255.255", PORT)
	_udp.put_packet(bytes)

func _process(delta):
	_timer += delta
	if _timer >= BROADCAST_INTERVAL:
		_timer = 0.0
		_send_broadcast()

	if _udp.get_available_packet_count() > 0:
		var packet = _udp.get_packet()
		var addr = _udp.get_packet_ip()
		var text = packet.get_string_from_utf8()
		if text.begins_with("LAN_TEST:"):
			var name = text.trim_prefix("LAN_TEST:")
			if not _peers.has(addr):
				_peers[addr] = name
				var idx = peer_list.add_item(addr + " - " + name)
				status_label.text = "Found: " + name + " at " + addr

func _on_refresh_pressed():
	_peers.clear()
	peer_list.clear()
	_timer = BROADCAST_INTERVAL
	_send_broadcast()
	status_label.text = "Refreshing..."

func _on_send_pressed():
	_send_broadcast()
	status_label.text = "Broadcast sent"

func _exit_tree():
	if _udp:
		_udp.close()
