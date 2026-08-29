extends GutTest

func test_fresh_instance_not_active():
	var mode := BackdropMode.new()
	assert_false(mode.active)

func test_first_toggle_dims_and_activates():
	var mode := BackdropMode.new()
	var alpha := mode.toggle()
	assert_almost_eq(alpha, BackdropMode.DIM_ALPHA, 0.0001)
	assert_true(mode.active)

func test_second_toggle_restores_and_deactivates():
	var mode := BackdropMode.new()
	mode.toggle()
	var alpha := mode.toggle()
	assert_almost_eq(alpha, 1.0, 0.0001)
	assert_false(mode.active)
