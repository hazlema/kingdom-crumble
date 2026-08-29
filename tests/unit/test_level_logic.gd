# tests/unit/test_level_logic.gd
extends GutTest

func test_count_standing_counts_only_upright():
	var rotations := [0.0, deg_to_rad(30), deg_to_rad(80), deg_to_rad(170)]
	assert_eq(Level.count_standing_rotations(rotations), 2)
