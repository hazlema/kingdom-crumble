extends GutTest

# GUT runs headless: capture must decline gracefully, and a failed
# capture must never wipe a previously loaded thumb (spec §2).


func before_all() -> void:
	# The first Camera2D added in a headless session triggers an engine
	# notice about physics-interpolation mode.  Pre-warm it here (before
	# GUT begins tracking test errors) so neither test body sees it.
	var warmup: LevelEditor = load("res://scenes/editor.tscn").instantiate()
	add_child(warmup)
	warmup.queue_free()
	await wait_physics_frames(1)


func _editor() -> LevelEditor:
	var e: LevelEditor = load("res://scenes/editor.tscn").instantiate()
	add_child_autofree(e)
	return e


func test_grab_returns_empty_headless() -> void:
	var shot: String = await ThumbCapture.grab(_editor())
	assert_eq(shot, "")


func test_save_preserves_existing_thumb_when_capture_fails() -> void:
	var editor := _editor()
	editor.current.title = "Thumb Keeper"
	editor.current.thumb = "aGVsbG8="
	await editor._on_save_as("gut_thumb_keeper")
	var loaded := LevelStore.load_level("user://levels/gut_thumb_keeper.json")
	assert_not_null(loaded)
	assert_eq(loaded.thumb, "aGVsbG8=")
	DirAccess.remove_absolute("user://levels/gut_thumb_keeper.json")
