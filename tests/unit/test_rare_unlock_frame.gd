extends GutTest


func test_skunk_frames_builds_from_sheet() -> void:
	var frames := RareUnlockFrame.skunk_frames()
	assert_not_null(frames)
	assert_gt(frames.get_frame_count(&"default"), 0)


func test_show_unlock_displays_then_frees() -> void:
	var f: RareUnlockFrame = load("res://scenes/ui/rare_unlock_frame.tscn").instantiate()
	add_child(f)
	f.show_unlock("Rare Unlock", RareUnlockFrame.skunk_frames())
	await wait_frames(2)
	assert_eq(f.get_node("%Title").text, "Rare Unlock")
	assert_true(f.get_node("%Anim").is_playing())
	await wait_seconds(6.0)
	assert_false(is_instance_valid(f), "ceremony cleans up after itself")
