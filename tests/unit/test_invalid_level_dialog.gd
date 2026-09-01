extends GutTest

# The owner's failed-load dialog: bomb, message, five-second fuse, quit.
# (Test must finish well inside the fuse — the timer quits the process.)

func test_dialog_assembles_with_message_and_fuse() -> void:
	var d: Control = load("res://scenes/ui/invalid_level.tscn").instantiate()
	add_child(d)
	await wait_frames(2)
	var label: Label = d.get_node("Panel/MarginContainer/VBoxContainer/Label")
	assert_eq(label.text, "Level Failed To Load")
	var fuse_lit := false
	for c in d.get_children():
		if c is Timer and not c.is_stopped():
			fuse_lit = true
	assert_true(fuse_lit, "the five-second fuse should be running")
	d.free()
