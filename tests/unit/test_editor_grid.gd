extends GutTest


func test_cell_to_world_matches_crate_rest_geometry():
	# resting center 569 (ground 600 - half height 31), stack pitch 63
	assert_eq(EditorGrid.cell_to_world(Vector2i(0, 0)), Vector2(640, 569))
	assert_eq(EditorGrid.cell_to_world(Vector2i(0, 1)), Vector2(640, 506))


func test_old_64px_saves_snap_to_new_rows():
	# pre-fix files stacked at y 568/504/440/376 — must land on rows 0-3
	for old in [[568.0, 0], [504.0, 1], [440.0, 2], [376.0, 3]]:
		assert_eq(EditorGrid.world_to_cell(Vector2(640, old[0])).y, int(old[1]))


func test_world_to_cell_roundtrip():
	for c in [Vector2i(0, 0), Vector2i(5, 3), Vector2i(EditorGrid.cols() - 1, 7)]:
		assert_eq(EditorGrid.world_to_cell(EditorGrid.cell_to_world(c)), c)


func test_zone_bounds():
	assert_true(EditorGrid.in_zone(Vector2i(0, 0)))
	assert_false(EditorGrid.in_zone(Vector2i(-1, 0)))
	assert_false(EditorGrid.in_zone(Vector2i(0, EditorGrid.MAX_ROWS)))
	assert_false(EditorGrid.in_zone(Vector2i(EditorGrid.cols(), 0)))
