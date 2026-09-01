extends GutTest

const TEST_PATH := "user://test_jump_progress.cfg"

func before_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Progress.use_path(TEST_PATH)

func after_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Progress.use_path("user://progress.cfg")

func _dialog() -> LevelJumpDialog:
	var d: LevelJumpDialog = load("res://scenes/ui/level_jump_dialog.tscn").instantiate()
	add_child_autofree(d)
	return d

func test_open_builds_one_button_per_entry() -> void:
	var d := _dialog()
	d.open("chill")
	var chain := LevelChain.entries()
	assert_eq(d.get_node("%List").get_child_count(), chain.size())
	assert_true(d.visible)

func test_first_button_unlocked_rest_follow_progress() -> void:
	var d := _dialog()
	d.open("chill")
	var buttons := d.get_node("%List").get_children()
	assert_false(buttons[0].disabled, "first level is always playable")
	if buttons.size() > 1:
		var chain := LevelChain.entries()
		var expect_locked := not Progress.is_cleared("chill", chain[0]["stem"])
		assert_eq(buttons[1].disabled, expect_locked)

func test_pick_emits_path_and_hides() -> void:
	var d := _dialog()
	d.open("chill")
	var chain := LevelChain.entries()
	watch_signals(d)
	d.get_node("%List").get_child(0).pressed.emit()
	assert_signal_emitted_with_parameters(d, "level_picked", [chain[0]["path"]])
	assert_false(d.visible)
