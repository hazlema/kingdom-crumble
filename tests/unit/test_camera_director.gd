extends GutTest


func test_firing_always_grabs_camera():
	for m in [CameraDirector.Mode.AIM, CameraDirector.Mode.SCOUT]:
		assert_eq(CameraDirector.next_mode(m, "fired"), CameraDirector.Mode.FOLLOW)


func test_settle_returns_home():
	assert_eq(
		CameraDirector.next_mode(CameraDirector.Mode.FOLLOW, "settled"), CameraDirector.Mode.AIM
	)


func test_scout_only_from_aim():
	assert_eq(
		CameraDirector.next_mode(CameraDirector.Mode.AIM, "scout_input"), CameraDirector.Mode.SCOUT
	)
	assert_eq(
		CameraDirector.next_mode(CameraDirector.Mode.FOLLOW, "scout_input"),
		CameraDirector.Mode.FOLLOW
	)


func test_aim_input_snaps_back_from_scout():
	assert_eq(
		CameraDirector.next_mode(CameraDirector.Mode.SCOUT, "aim_input"), CameraDirector.Mode.AIM
	)


func _cam() -> CameraDirector:
	var c := CameraDirector.new()
	c.position = Vector2(960, 160)
	add_child_autofree(c)
	return c


func test_aim_sits_home_without_focus():
	var c := _cam()
	c.aim_focus = Vector2.INF
	c._physics_process(0.016)
	assert_eq(c.global_position, Vector2(960, 160))


func test_aim_pans_to_keep_arrow_end_in_frame():
	var c := _cam()
	c.aim_focus = Vector2(3000, 600)
	c._physics_process(0.016)
	assert_gt(c.global_position.x, 960.0, "camera should pan toward the arrow end")
	var half_w: float = c.get_viewport_rect().size.x * 0.5
	assert_lt(
		absf(3000.0 - c.global_position.x),
		half_w - CameraDirector.AIM_EDGE_MARGIN + 1.0,
		"arrow end must stay inside the frame margin"
	)


func test_aim_midpoint_for_short_shots():
	var c := _cam()
	c.aim_focus = Vector2(1400, 600)
	c._physics_process(0.016)
	assert_almost_eq(c.global_position.x, (960.0 + 1400.0) * 0.5, 1.0)


func test_scout_overshoot_is_clamped():
	# pan position must never drift past the limits — the display pins
	# and panning back through invisible overshoot feels like a dead cam
	var c := _cam()
	c.limit_left = -400
	c.limit_top = -1400
	c.limit_right = 3400
	c.limit_bottom = 700
	c.global_position = Vector2(99999, 99999)
	c._clamp_to_limits()
	var half: Vector2 = c.get_viewport_rect().size * 0.5
	assert_almost_eq(c.global_position.x, 3400.0 - half.x, 1.0)
	assert_almost_eq(c.global_position.y, 700.0 - half.y, 1.0)
	c.global_position = Vector2(-99999, -99999)
	c._clamp_to_limits()
	assert_almost_eq(c.global_position.x, -400.0 + half.x, 1.0)
	assert_almost_eq(c.global_position.y, -1400.0 + half.y, 1.0)
