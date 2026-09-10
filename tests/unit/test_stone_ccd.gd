extends GutTest

# Regression: a fast stone must not tunnel thin static geometry.
# Root cause of the rare "corner clip → stone vanishes" bug — a 16px
# body with CCD off jumps past thin colliders in one 60Hz step. The
# simulation that found this swept speed x angle; this pins the fix.

const STONE := preload("res://scenes/stone.tscn")


func test_stone_enables_ccd() -> void:
	var s: RigidBody2D = STONE.instantiate()
	add_child_autofree(s)
	await wait_frames(1)
	assert_eq(s.continuous_cd, RigidBody2D.CCD_MODE_CAST_RAY,
		"stone uses ray-cast CCD so fast shots cannot tunnel thin colliders")


func test_fast_stone_does_not_tunnel_thin_floor() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	# A 20px-thin static strip — the torture case for tunneling.
	var floor_body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(4000, 20)
	cs.shape = r
	floor_body.add_child(cs)
	floor_body.global_position = Vector2(1400, 700)
	host.add_child(floor_body)
	# The reproducing shot from the hunt: 3000 px/s, ~85 deg down.
	var stone: RigidBody2D = STONE.instantiate()
	host.add_child(stone)
	var dir := Vector2.DOWN.rotated(deg_to_rad(5.0))
	stone.launch(Vector2(1400, 400), dir * 3000.0)
	var tunneled := false
	for step in 40:
		await wait_physics_frames(1)
		if not is_instance_valid(stone):
			break
		if stone.global_position.y > 760.0:  # below the floor bottom
			tunneled = true
			break
	assert_false(tunneled, "fast steep stone is stopped by the thin floor, not tunneled through")


func test_crate_enables_ccd() -> void:
	# Crate edition of the tunneling fix: boom impulses hurl crates through
	# thin painted solid-scenery walls (owner field report, depot demo).
	var c: RigidBody2D = preload("res://scenes/crate.tscn").instantiate()
	add_child_autofree(c)
	await wait_frames(1)
	assert_eq(c.continuous_cd, RigidBody2D.CCD_MODE_CAST_RAY,
		"crates use ray-cast CCD so boom-launched crates cannot tunnel painted walls")


func test_boom_speed_crate_does_not_tunnel_thin_wall() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	# An 18px-thin vertical wall — a painted depot spire's worth of collider.
	var wall := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(18, 2000)
	cs.shape = r
	wall.add_child(cs)
	wall.global_position = Vector2(2000, 400)
	host.add_child(wall)
	var crate: RigidBody2D = preload("res://scenes/crate.tscn").instantiate()
	host.add_child(crate)
	crate.global_position = Vector2(1700, 400)
	crate.linear_velocity = Vector2(3500.0, 0.0)  # boom-impulse territory
	var tunneled := false
	for step in 40:
		await wait_physics_frames(1)
		if not is_instance_valid(crate):
			break
		if crate.global_position.x > 2060.0:  # past the wall's far side
			tunneled = true
			break
	assert_false(tunneled, "a boom-launched crate is stopped by a thin painted wall")
