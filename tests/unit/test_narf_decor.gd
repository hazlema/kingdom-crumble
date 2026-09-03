extends GutTest

# NarfKit's founding citizen: living scenery. Kit rule — no host-game
# references; everything through exports.


func _piece(b: NarfDecor.Behavior) -> NarfDecor:
	var d := NarfDecor.new()
	d.behavior = b
	d.speed = 1.0
	d.movement = 10.0
	add_child_autofree(d)
	return d


func test_spin_turns_continuously() -> void:
	var d := _piece(NarfDecor.Behavior.SPIN)
	var r0 := d.rotation
	await wait_seconds(0.3)
	assert_gt(d.rotation, r0, "the wheel turns")


func test_sway_oscillates_around_home() -> void:
	var d := _piece(NarfDecor.Behavior.SWAY)
	d.rotation = 0.5
	d._home_rotation = 0.5
	await wait_seconds(0.3)
	assert_between(d.rotation, 0.5 - deg_to_rad(10.5), 0.5 + deg_to_rad(10.5), "tilts near home")


func test_bob_moves_vertically_within_movement() -> void:
	var d := _piece(NarfDecor.Behavior.BOB)
	await wait_seconds(0.3)
	assert_between(d.position.y, -10.5, 10.5, "bobs around home")


func test_none_sits_perfectly_still() -> void:
	var d := _piece(NarfDecor.Behavior.NONE)
	d.rotation = 1.0
	await wait_seconds(0.2)
	assert_eq(d.rotation, 1.0)


func test_pivot_anchors_put_the_named_point_on_the_origin() -> void:
	var d := NarfDecor.new()
	var img := Image.create(40, 20, false, Image.FORMAT_RGBA8)
	d.texture = ImageTexture.create_from_image(img)
	add_child_autofree(d)
	var expect := {
		NarfDecor.Pivot.TOP_LEFT: Vector2(0, 0),
		NarfDecor.Pivot.TOP_CENTER: Vector2(-20, 0),
		NarfDecor.Pivot.TOP_RIGHT: Vector2(-40, 0),
		NarfDecor.Pivot.CENTER_LEFT: Vector2(0, -10),
		NarfDecor.Pivot.CENTER: Vector2(-20, -10),
		NarfDecor.Pivot.CENTER_RIGHT: Vector2(-40, -10),
		NarfDecor.Pivot.LOWER_LEFT: Vector2(0, -20),
		NarfDecor.Pivot.LOWER_CENTER: Vector2(-20, -20),
		NarfDecor.Pivot.LOWER_RIGHT: Vector2(-40, -20),
	}
	for p in expect:
		d.pivot = p
		assert_eq(d.offset, expect[p], "pivot %d anchors correctly" % p)
	assert_false(d.centered, "pivot mode owns placement")


func _stepper(b: NarfDecor.Behavior, home: Vector2) -> NarfDecor:
	var d := NarfDecor.new()
	d.behavior = b
	d.speed = 1.0
	d.travel = 100.0
	add_child_autofree(d)
	d.position = home
	d._home_pos = home
	return d


func test_drift_horizontal_pingpongs_in_range() -> void:
	var d := _stepper(NarfDecor.Behavior.DRIFT, Vector2(500, 300))
	d.axis = NarfDecor.DriftAxis.HORIZONTAL
	var max_dx := 0.0
	var y_moved := false
	for i in 200:
		d._process(1.0 / 60.0)
		max_dx = maxf(max_dx, absf(d.position.x - 500.0))
		y_moved = y_moved or not is_equal_approx(d.position.y, 300.0)
	assert_between(max_dx, 50.0, 100.5, "roams its range, never past it")
	assert_false(y_moved, "horizontal drift leaves y alone")


func test_drift_vertical_pingpongs_in_range() -> void:
	var d := _stepper(NarfDecor.Behavior.DRIFT, Vector2(500, 300))
	d.axis = NarfDecor.DriftAxis.VERTICAL
	var max_dy := 0.0
	var x_moved := false
	for i in 200:
		d._process(1.0 / 60.0)
		max_dy = maxf(max_dy, absf(d.position.y - 300.0))
		x_moved = x_moved or not is_equal_approx(d.position.x, 500.0)
	assert_between(max_dy, 50.0, 100.5, "roams its range, never past it")
	assert_false(x_moved, "vertical drift leaves x alone")


func test_wander_never_escapes_the_roam_circle() -> void:
	var d := _stepper(NarfDecor.Behavior.WANDER, Vector2(400, 400))
	d.speed = 2.0
	d._rng.seed = 12345
	var worst := 0.0
	for i in 600:
		d._process(1.0 / 60.0)
		worst = maxf(worst, d.position.distance_to(Vector2(400, 400)))
	assert_between(worst, 1.0, 100.5, "actually roams, but stays inside travel radius")


func test_wander_flies_nose_first_and_lands_level() -> void:
	var d := _stepper(NarfDecor.Behavior.WANDER, Vector2(400, 400))
	d.speed = 2.0
	d.tilt = 10.0
	d._rng.seed = 777
	var tilt_ok := true
	var checked_hops := 0
	for i in 600:
		d._process(1.0 / 60.0)
		var off := absf(angle_difference(d.rotation, d._home_rotation))
		tilt_ok = tilt_ok and off <= deg_to_rad(10.0) + 0.001
		if d._hop_active:
			assert_eq(d.flip_h, d._hop_target.x < d._hop_start.x, "faces its heading")
		else:
			checked_hops += 1
			assert_almost_eq(angle_difference(d.rotation, d._home_rotation), 0.0, 0.001, "level at rest")
	assert_true(tilt_ok, "banking never exceeds the tilt dial")
	assert_gt(checked_hops, 0, "at least one hop completed during the test")


func test_rehome_reanchors_motion_to_current_spot() -> void:
	var d := _stepper(NarfDecor.Behavior.DRIFT, Vector2(100, 100))
	d.axis = NarfDecor.DriftAxis.HORIZONTAL
	d.position = Vector2(900, 500)  # host moved the piece after spawn
	d.rehome()
	for i in 30:
		d._process(1.0 / 60.0)
	assert_between(d.position.x, 800.0, 1000.0, "animates around the NEW home")
	assert_eq(d.position.y, 500.0, "no snap back to the birth spot")
