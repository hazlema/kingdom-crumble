extends GutTest


func _spawn(frozen: bool) -> Crate:
	var c: Crate = load("res://scenes/crate.tscn").instantiate()
	c.position = Vector2(1000, 569)
	c.freeze = frozen
	c.gravity_scale = 0.0
	add_child_autofree(c)
	return c


func test_emits_once_when_displaced_past_line() -> void:
	var c := _spawn(false)
	watch_signals(c)
	await wait_physics_frames(2)
	assert_signal_emit_count(c, "knocked_out", 0)
	c.position += Vector2(60, 0)
	await wait_physics_frames(2)
	assert_signal_emit_count(c, "knocked_out", 1)
	c.position += Vector2(60, 0)
	await wait_physics_frames(2)
	assert_signal_emit_count(c, "knocked_out", 1)


func test_frozen_crate_never_emits() -> void:
	var c := _spawn(true)
	watch_signals(c)
	c.position += Vector2(200, 0)
	await wait_physics_frames(3)
	assert_signal_emit_count(c, "knocked_out", 0)


func test_tipped_crate_emits() -> void:
	var c := _spawn(false)
	watch_signals(c)
	c.rotation = deg_to_rad(90)
	await wait_physics_frames(2)
	assert_signal_emit_count(c, "knocked_out", 1)


func test_dead_stays_dead_even_back_on_its_grave() -> void:
	var c := _spawn(false)
	await wait_physics_frames(2)
	assert_true(c.is_standing(), "starts standing")
	c.position += Vector2(60, 0)
	await wait_physics_frames(2)
	assert_false(c.is_standing(), "displaced past the line = knocked out")
	c.position -= Vector2(60, 0)
	c.rotation = 0.0
	await wait_physics_frames(2)
	assert_false(c.is_standing(), "physics parked it back home — still dead, no resurrection")
