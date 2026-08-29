extends GutTest

func test_upright_is_standing():
	assert_true(Crate.is_standing_rotation(0.0))
	assert_true(Crate.is_standing_rotation(deg_to_rad(30)))
	assert_true(Crate.is_standing_rotation(deg_to_rad(-44)))

func test_tipped_is_not_standing():
	assert_false(Crate.is_standing_rotation(deg_to_rad(46)))
	assert_false(Crate.is_standing_rotation(deg_to_rad(90)))
	assert_false(Crate.is_standing_rotation(deg_to_rad(180)))

func test_full_turn_wraps_to_standing():
	assert_true(Crate.is_standing_rotation(TAU))
