extends SceneTree

const OUTPUT_PATH := "res://tests/output/ui_snapshot.png"

var _main = null
var _frame_count := 0
var _exit_code := 0

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if not packed:
		push_error("Unable to load the main scene")
		_exit_code = 1
		return

	_main = packed.instantiate()
	root.add_child(_main)

	# Populate a deterministic legacy-compatible preview so the snapshot checks
	# the contact list, selected conversation, action buttons and chat bubbles.
	_main.call("_on_user_added", {
		"id": "legacy-alice",
		"name": "Alice · Legacy LAN Messenger",
		"address": "192.168.1.21",
		"status": "chat",
		"version": "1.2.39",
		"avatar": 1,
		"note": "Available",
		"group": "General",
		"caps": 7
	})
	_main.call("_on_user_added", {
		"id": "legacy-ben",
		"name": "Ben",
		"address": "192.168.1.22",
		"status": "away",
		"version": "1.2.39",
		"avatar": 2,
		"note": "Back soon",
		"group": "General",
		"caps": 7
	})
	_main.call("_on_user_added", {
		"id": "legacy-carla",
		"name": "Carla",
		"address": "192.168.1.23",
		"status": "busy",
		"version": "1.2.39",
		"avatar": 3,
		"note": "In a meeting",
		"group": "General",
		"caps": 7
	})
	_main.call("_select_user", "legacy-alice")
	_main.call("_add_bubble", "The upgraded client found the old LAN Messenger peer.", false, "Alice", "10:41")
	_main.call("_add_bubble", "Great — encrypted messaging and file transfer are ready.", true, "You", "10:42")
	_main.call("_add_bubble", "This interface is much cleaner now 😊", false, "Alice", "10:42")

func _process(_delta: float) -> bool:
	if _exit_code != 0:
		return true
	_frame_count += 1
	if _frame_count < 20:
		return false

	var output_dir := ProjectSettings.globalize_path("res://tests/output")
	DirAccess.make_dir_recursive_absolute(output_dir)
	RenderingServer.force_draw(true)
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if error != OK:
		push_error("Unable to save UI snapshot: %s" % error_string(error))
		_exit_code = 1
	else:
		print("Saved rendered UI snapshot to ", OUTPUT_PATH)
	return true

func _finalize() -> void:
	if _exit_code != 0:
		OS.set_restart_on_exit(false)
