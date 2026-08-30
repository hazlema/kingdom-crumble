extends GutTest

func test_cell_to_world_ground_row_matches_proven_stack():
	assert_eq(EditorGrid.cell_to_world(Vector2i(0, 0)), Vector2(640, 568))
	assert_eq(EditorGrid.cell_to_world(Vector2i(0, 1)), Vector2(640, 504))

func test_world_to_cell_roundtrip():
	for c in [Vector2i(0, 0), Vector2i(5, 3), Vector2i(EditorGrid.cols() - 1, 7)]:
		assert_eq(EditorGrid.world_to_cell(EditorGrid.cell_to_world(c)), c)

func test_zone_bounds():
	assert_true(EditorGrid.in_zone(Vector2i(0, 0)))
	assert_false(EditorGrid.in_zone(Vector2i(-1, 0)))
	assert_false(EditorGrid.in_zone(Vector2i(0, EditorGrid.MAX_ROWS)))
	assert_false(EditorGrid.in_zone(Vector2i(EditorGrid.cols(), 0)))
