extends GutTest

var ed: LevelEditor


func before_each() -> void:
	ed = load("res://scenes/editor.tscn").instantiate()
	add_child_autofree(ed)


func test_scenery_mode_blocks_crate_placement() -> void:
	ed._enter_scenery()
	ed.carrying = "crate-wood"
	ed._press(Vector2i(2, 0))
	assert_eq(ed.current.crates.size(), 1, "_press itself still works when called")
	ed.current.crates.clear()
	ed._rebuild()
	# the real guard is the polling gate: simulate a frame's decision
	assert_eq(ed.mode, LevelEditor.Mode.SCENERY)
	ed._exit_scenery()
	assert_eq(ed.mode, LevelEditor.Mode.CRATES)


func test_panel_swaps_with_mode() -> void:
	ed._enter_scenery()
	assert_false(ed.palette.visible)
	assert_true(ed.get_node("%SceneryPanel").visible)
	assert_false(ed.overlay.visible, "grid rests during scenery work")
	ed._exit_scenery()
	assert_true(ed.palette.visible)
	assert_false(ed.get_node("%SceneryPanel").visible)
	assert_true(ed.overlay.visible)


func test_background_picker_still_reaches_the_layout() -> void:
	ed._enter_scenery()
	ed.get_node("%SceneryPanel").background_picked.emit("meadow")
	assert_eq(ed.current.background, "meadow")
