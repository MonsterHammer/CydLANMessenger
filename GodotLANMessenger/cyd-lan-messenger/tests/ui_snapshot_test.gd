extends SceneTree

const OUTPUT_PATH := "res://tests/output/ui_snapshot.png"

func _init() -> void:
	call_deferred("_capture_snapshot")

func _capture_snapshot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if not packed:
		push_error("Unable to load the main scene")
		quit(1)
		return

	var main = packed.instantiate()
	root.add_child(main)
	for _frame in range(12):
		await process_frame

	# Populate a deterministic legacy-compatible preview so the snapshot checks
	# the contact list, selected conversation, action buttons and chat bubbles.
	main.call("_on_user_added", {
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
	main.call("_on_user_added", {
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
	main.call("_on_user_added", {
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
	main.call("_select_user", "legacy-alice")
	main.call("_add_bubble", "The upgraded client found the old LAN Messenger peer.", false, "Alice", "10:41")
	main.call("_add_bubble", "Great — encrypted messaging and file transfer are ready.", true, "You", "10:42")
	main.call("_add_bubble", "This interface is much cleaner now 😊", false, "Alice", "10:42")

	for _frame in range(12):
		await process_frame

	var output_dir := ProjectSettings.globalize_path("res://tests/output")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if error != OK:
		push_error("Unable to save UI snapshot: %s" % error_string(error))
		quit(1)
		return
	print("Saved rendered UI snapshot to ", OUTPUT_PATH)
	quit(0)
