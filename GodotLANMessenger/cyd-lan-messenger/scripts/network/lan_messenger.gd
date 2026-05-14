extends Node

const _D = preload("res://scripts/network/definitions.gd")
const _Messaging = preload("res://scripts/network/messaging.gd")
const _NetworkManager = preload("res://scripts/network/network_manager.gd")

var messaging: Node = null

func _ready():
	if Engine.is_editor_hint():
		return
	
	messaging = _Messaging.new()
	add_child(messaging)

	var address = _get_ip_address()
	var user_id = _make_user_id(address)

	messaging.local_user = {
		"id": user_id,
		"name": Helper.get_logon_name(),
		"address": address,
		"version": "1.2.39",
		"status": "chat",
		"avatar": 0,
		"group": "General",
		"note": "",
		"caps": _D.UserCap.UC_File | _D.UserCap.UC_Folder
	}

	var settings = {
		"port": 50000,
		"udp_port": 50000,
		"tcp_port": 50000,
		"multicast": "239.255.100.100",
		"broadcast_list": [],
		"user_name": Helper.get_logon_name()
	}

	messaging.network = _NetworkManager.new()
	add_child(messaging.network)
	messaging.network.set_local_id(user_id)
	messaging.init_config(settings)
	print("CydLAN: Starting with IP=", address, " user_id=", user_id, " multicast=", settings["multicast"], " ports=", settings["port"], "/", settings["tcp_port"])
	_clear_stale_port_owner(int(settings["tcp_port"]))
	messaging.start()

func _clear_stale_port_owner(port: int) -> void:
	if OS.get_name() != "Windows":
		return
	var project_path = ProjectSettings.globalize_path("res://").rstrip("\\/")
	var exe_path = OS.get_executable_path()
	var script = """
$port = %d
$currentPid = %d
$projectPath = '%s'
$exePath = '%s'
$owners = @()
$owners += Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess
$owners += Get-NetUDPEndpoint -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess
$owners | Sort-Object -Unique | ForEach-Object {
	if ($_ -eq $currentPid) { return }
	$p = Get-CimInstance Win32_Process -Filter "ProcessId=$_" -ErrorAction SilentlyContinue
	if (-not $p) { return }
	$cmd = [string]$p.CommandLine
	$path = [string]$p.ExecutablePath
	$isSameProject = $cmd.Contains($projectPath)
	$isSameExecutable = ($path -eq $exePath)
	if ($isSameProject -or $isSameExecutable) {
		Stop-Process -Id $_ -Force
		Write-Output "Stopped stale CydLAN process PID $_ on port $port"
	}
}
""" % [port, OS.get_process_id(), project_path.replace("'", "''"), exe_path.replace("'", "''")]
	var output: Array = []
	var args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script]
	var exit_code = OS.execute("powershell.exe", args, output, true)
	if exit_code != 0:
		output.clear()
		exit_code = OS.execute("pwsh", args, output, true)
	for line in output:
		if not str(line).strip_edges().is_empty():
			print("CydLAN: ", line)

func _get_ip_address() -> String:
	var addrs = IP.get_local_addresses()
	var fallback = ""
	for a in addrs:
		if a.contains(":") or not a.is_valid_ip_address():
			continue
		if a.begins_with("127.") or a.begins_with("169."):
			continue
		if a.begins_with("172.17.") or a.begins_with("192.168.56.") or a.begins_with("192.168.137."):
			continue
		if a.begins_with("172."):
			if fallback.is_empty():
				fallback = a
			continue
		return a
	if not fallback.is_empty():
		return fallback
	return "127.0.0.1"

func _make_user_id(address: String) -> String:
	return address.replace(".", "") + Helper.get_logon_name()
