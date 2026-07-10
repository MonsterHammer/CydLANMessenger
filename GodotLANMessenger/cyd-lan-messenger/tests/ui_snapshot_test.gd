extends SceneTree

const OUTPUT_PATH := "res://tests/output/ui_snapshot.png"

var _main = null
var _finished := false

func _init() -> void:
	call_deferred("_setup_preview")

func _setup_preview() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if not packed:
		_finish_with_error("Unable to load the main scene")
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

	# Signals keep the coroutine state alive without relying on an awaited method
	# invoked through call_deferred, which can be discarded by the main loop.
	create_timer(0.8).timeout.connect(_capture_snapshot)
	create_timer(8.0).timeout.connect(_on_capture_timeout)

func _capture_snapshot() -> void:
	if _finished:
		return
	var output_dir := ProjectSettings.globalize_path("res://tests/output")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if error != OK:
		_finish_with_error("Unable to save UI snapshot: %s" % error_string(error))
		return
	_finished = true
	print("Saved rendered UI snapshot to ", OUTPUT_PATH)
	quit(0)

func _on_capture_timeout() -> void:
	if not _finished:
		_finish_with_error("UI snapshot timed out")

func _finish_with_error(message: String) -> void:
	if _finished:
		return
	_finished = true
	push_error(message)
	quit(1)
