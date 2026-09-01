extends GutTest


func test_launch_velocity_at_zero_charge_uses_min_speed():
	var v := Trebuchet.launch_velocity(45.0, 0.0, 400.0, 1400.0)
	assert_almost_eq(v.length(), 400.0, 0.1)


func test_launch_velocity_at_full_charge_uses_max_speed():
	var v := Trebuchet.launch_velocity(45.0, 1.0, 400.0, 1400.0)
	assert_almost_eq(v.length(), 1400.0, 0.1)


func test_launch_velocity_points_up_and_right():
	var v := Trebuchet.launch_velocity(45.0, 0.5, 400.0, 1400.0)
	assert_gt(v.x, 0.0)
	assert_lt(v.y, 0.0)  # up is -y in Godot


func test_charge_clamps():
	var v := Trebuchet.launch_velocity(45.0, 7.0, 400.0, 1400.0)
	assert_almost_eq(v.length(), 1400.0, 0.1)
