extends GutTest


func _level() -> Level:
	Level.next_layout = LevelLayout.new()  # empty field
	var l: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(l)
	return l


func test_multishot_fires_three_fanned_stones() -> void:
	var l := _level()
	l.pending_buffs = [&"multishot"] as Array[StringName]
	l._on_fired(Vector2(900, -300))
	assert_eq(l._active_stones.size(), 3)
	var vels := {}
	for s in l._active_stones:
		vels[s.linear_velocity] = true
	assert_eq(vels.size(), 3, "velocities drift apart")
	assert_eq(l.pending_buffs.size(), 0)


func test_charges_consume_one_per_type() -> void:
	var l := _level()
	l.pending_buffs = [&"exploding", &"exploding"] as Array[StringName]
	l._on_fired(Vector2(900, -300))
	assert_eq(l._active_stones.size(), 1)
	assert_true(l._active_stones[0].exploding)
	assert_eq(l.pending_buffs, [&"exploding"] as Array[StringName])


func test_combo_applies_to_every_stone() -> void:
	var l := _level()
	l.pending_buffs = [&"multishot", &"super_bounce", &"exploding"] as Array[StringName]
	l._on_fired(Vector2(900, -300))
	assert_eq(l._active_stones.size(), 3)
	for s in l._active_stones:
		assert_true(s.exploding and s.super_bounce)


func test_multishot_exploding_volley_does_not_self_detonate() -> void:
	# C1 regression: multishot+exploding volley must not immediately
	# self-detonate when the three stones spawn at the same launch point.
	var l := _level()
	l.pending_buffs = [&"multishot", &"exploding"] as Array[StringName]
	l._on_fired(Vector2(900, -300))
	assert_eq(l._active_stones.size(), 3)
	# Step physics to let any spurious contact signals fire.
	await wait_physics_frames(15)
	# At least one stone must still exist (not freed by self-detonation).
	var alive := 0
	for s in l._active_stones:
		if is_instance_valid(s):
			alive += 1
	assert_gt(alive, 0, "all volley stones detonated at launch — C1 self-detonate bug")
	# The lead stone must have travelled more than 150 px from the launch point.
	var lead: Stone = l._active_stones[0]
	if is_instance_valid(lead):
		assert_gt(
			lead.global_position.x,
			150.0,
			"lead stone has not advanced — launched but did not travel"
		)
