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


func _spawn_frozen_crate() -> Crate:
	var c: Crate = load("res://scenes/crate.tscn").instantiate()
	c.position = Vector2(1000, 569)
	c.freeze = true
	add_child_autofree(c)
	return c


func test_scooted_upright_crate_counts_as_knocked_out():
	# Bottom-row crates slide along the ground instead of tipping — a
	# solid hit that shoves one off its spot must still clear it.
	var c := _spawn_frozen_crate()
	assert_true(c.is_standing(), "undisturbed crate should be standing")
	c.position += Vector2(20, 0)
	assert_true(c.is_standing(), "a small shuffle should not count as a kill")
	c.position += Vector2(40, 0)
	assert_false(c.is_standing(), "scooted 60px off home — knocked out")
	assert_eq(Level.count_standing([c]), 0)


func test_count_standing_mixes_tilt_and_displacement():
	var upright := _spawn_frozen_crate()
	var tipped := _spawn_frozen_crate()
	tipped.rotation = deg_to_rad(90)
	assert_eq(Level.count_standing([upright, tipped]), 1)
