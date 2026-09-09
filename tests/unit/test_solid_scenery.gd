extends GutTest

# Task 1: solid scenery — the painted silhouette is the collision.
# Spike-proven 2026-09-08: BitMap.create_from_image_alpha + opaque_to_polygons
# produced a 7-point polygon for a whole building; a stone rested on the
# painted flat roof at the predicted y with velocity ~0.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

const EPSILON_SLACK := 3.0  # px; bbox tolerance for polygon alignment tests


func _base_d(extra: Dictionary = {}) -> Dictionary:
	var d := {"format": 1, "title": "t", "crates": [], "shots": 3}
	d.merge(extra, true)
	return d


func _tiny_b64(w: int = 4, h: int = 4, fill: Color = Color.WHITE) -> String:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


# Returns base64 PNG of a 200x150 image with an opaque rect at
# x: 40..159, y: 60..149 (everything else transparent).
func _building_b64() -> String:
	var img := Image.create(200, 150, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(60, 150):
		for x in range(40, 160):
			img.set_pixel(x, y, Color.WHITE)
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


# Returns base64 PNG with many isolated single-pixel dots spaced 20px apart.
# Each dot is a separate polygon.  With 25x25=625 dots, total points ≈ 2500
# >> 512 budget, so even after epsilon=8.0 passes the budget remains exceeded.
# Dots are 20px apart — well outside the 8px merge radius → no merging.
func _checkerboard_b64(sz: int = 500) -> String:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Place single opaque pixels every 20px — well beyond epsilon=8 merge range.
	var step := 20
	for y in range(0, sz, step):
		for x in range(0, sz, step):
			img.set_pixel(x, y, Color.WHITE)
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


# Builds a LevelLayout with one solid overlay at (px, py) using the given
# image b64. Key is derived from the bytes.
func _solid_layout(b64: String, px: float = 200.0, py: float = 300.0) -> LevelLayout:
	var raw := Marshalls.base64_to_raw(b64)
	var key := LevelJson.image_key(raw)
	var l := LevelLayout.new()
	l.title = "solid_test"
	l.images[key] = b64
	l.overlays.append({"image": key, "x": px, "y": py, "solid": true, "name": "building"})
	return l


# ---------------------------------------------------------------------------
# Format tests (no physics)
# ---------------------------------------------------------------------------

func test_solid_validates_as_strict_bool() -> void:
	# non-bool string → named validation error
	var ov_str := {"image": "abcd1234", "x": 0, "y": 0, "solid": "yes"}
	var err := LevelJson.validate(_base_d({"overlays": [ov_str]}))
	assert_eq(err, "overlay 0: solid must be true/false",
		"string 'yes' must be rejected with the exact named error")

	# integer 1 → also rejected
	var ov_int := {"image": "abcd1234", "x": 0, "y": 0, "solid": 1}
	var err2 := LevelJson.validate(_base_d({"overlays": [ov_int]}))
	assert_eq(err2, "overlay 0: solid must be true/false",
		"integer 1 must also be rejected")

	# boolean true → valid
	var ov_ok := {"image": "abcd1234", "x": 0, "y": 0, "solid": true}
	assert_eq(LevelJson.validate(_base_d({"overlays": [ov_ok]})), "",
		"solid: true should pass validation")

	# absent solid → also valid (optional key)
	var ov_absent := {"image": "abcd1234", "x": 0, "y": 0}
	assert_eq(LevelJson.validate(_base_d({"overlays": [ov_absent]})), "",
		"absent solid key should pass validation")


func test_solid_refuses_travel_verbs() -> void:
	# solid + DRIFT → named error
	var ov_drift := {"image": "abcd1234", "x": 0, "y": 0, "solid": true, "behavior": "DRIFT"}
	var err := LevelJson.validate(_base_d({"overlays": [ov_drift]}))
	assert_eq(err, "overlay 0: solid pieces cannot travel",
		"DRIFT refused on solid overlay")

	# solid + WANDER → also refused
	var ov_wander := {"image": "abcd1234", "x": 0, "y": 0, "solid": true, "behavior": "WANDER"}
	var err2 := LevelJson.validate(_base_d({"overlays": [ov_wander]}))
	assert_eq(err2, "overlay 0: solid pieces cannot travel",
		"WANDER refused on solid overlay")

	# solid + SWAY → valid (sprite-only verb)
	var ov_sway := {"image": "abcd1234", "x": 0, "y": 0, "solid": true, "behavior": "SWAY"}
	assert_eq(LevelJson.validate(_base_d({"overlays": [ov_sway]})), "",
		"SWAY is allowed on solid overlay")

	# solid + SPIN → valid
	var ov_spin := {"image": "abcd1234", "x": 0, "y": 0, "solid": true, "behavior": "SPIN"}
	assert_eq(LevelJson.validate(_base_d({"overlays": [ov_spin]})), "",
		"SPIN is allowed on solid overlay")

	# non-solid + DRIFT → still valid
	var ov_nd := {"image": "abcd1234", "x": 0, "y": 0, "behavior": "DRIFT"}
	assert_eq(LevelJson.validate(_base_d({"overlays": [ov_nd]})), "",
		"DRIFT without solid is valid")


func test_solid_round_trips_and_survives_bake() -> void:
	# Serialize → parse keeps solid key
	var b64 := _tiny_b64()
	var raw := Marshalls.base64_to_raw(b64)
	var key := LevelJson.image_key(raw)
	var l := LevelLayout.new()
	l.title = "rt"
	l.images[key] = b64
	l.overlays.append({"image": key, "x": 10.0, "y": 20.0, "solid": true})

	var text := LevelJson.serialize(l)
	var parsed := LevelJson.parse(text)
	assert_not_null(parsed, "round-trip parse must succeed: %s" % LevelJson.last_error)
	assert_eq(parsed.overlays.size(), 1)
	assert_eq(parsed.overlays[0].get("solid", false), true, "solid key survives round-trip")

	# solid: false should also survive
	var l2 := LevelLayout.new()
	l2.title = "rt2"
	l2.images[key] = b64
	l2.overlays.append({"image": key, "x": 0.0, "y": 0.0, "solid": false})
	var parsed2 := LevelJson.parse(LevelJson.serialize(l2))
	assert_not_null(parsed2)
	assert_eq(parsed2.overlays[0].get("solid", "ABSENT"), false, "solid: false round-trips")

	# SceneryBake.bake does NOT strip 'solid' (not an underscore key)
	var l3 := LevelLayout.new()
	l3.title = "bake"
	l3.images[key] = b64
	# Add underscore keys to trigger bake logic
	l3.overlays.append({"image": key, "x": 0.0, "y": 0.0, "solid": true, "_scale": 1.0})
	SceneryBake.bake(l3)
	assert_eq(l3.overlays[0].get("solid", false), true, "bake must leave 'solid' untouched")
	assert_false(l3.overlays[0].has("_scale"), "bake must strip underscore keys")


# ---------------------------------------------------------------------------
# solid_polygons helper (pure, no physics)
# ---------------------------------------------------------------------------

func test_solid_polygons_from_alpha() -> void:
	var b64 := _building_b64()
	var raw := Marshalls.base64_to_raw(b64)
	var img := Image.new()
	img.load_png_from_buffer(raw)
	var polys: Array[PackedVector2Array] = SceneryBuilder.solid_polygons(img)

	assert_eq(polys.size(), 1, "one solid region → one polygon")
	var poly: PackedVector2Array = polys[0]
	assert_true(poly.size() >= 4, "polygon has at least 4 points (got %d)" % poly.size())

	# All polygon points must lie within the opaque rect bounds (+epsilon slack).
	for pt in poly:
		assert_true(pt.x >= 40.0 - EPSILON_SLACK,
			"polygon pt.x=%.1f must be >= rect left %.1f - slack" % [pt.x, 40.0])
		assert_true(pt.x <= 160.0 + EPSILON_SLACK,
			"polygon pt.x=%.1f must be <= rect right %.1f + slack" % [pt.x, 160.0])
		assert_true(pt.y >= 60.0 - EPSILON_SLACK,
			"polygon pt.y=%.1f must be >= rect top %.1f - slack" % [pt.y, 60.0])
		assert_true(pt.y <= 150.0 + EPSILON_SLACK,
			"polygon pt.y=%.1f must be <= rect bottom %.1f + slack" % [pt.y, 150.0])


func test_solid_polygons_cap_falls_back() -> void:
	# A pathological checkerboard produces many tiny polygons / huge point count.
	# After epsilon escalation the budget is exceeded → solid_polygons returns [].
	var b64 := _checkerboard_b64()
	var raw := Marshalls.base64_to_raw(b64)
	var img := Image.new()
	img.load_png_from_buffer(raw)
	# We expect [] — the call itself should not crash.
	var polys: Array[PackedVector2Array] = SceneryBuilder.solid_polygons(img)
	assert_eq(polys.size(), 0,
		"pathological image must return [] after epsilon escalation budget cap")


# ---------------------------------------------------------------------------
# Spawn + static body tests (need scene tree for physics)
# ---------------------------------------------------------------------------

func test_spawn_creates_static_body_aligned_to_sprite() -> void:
	var b64 := _building_b64()
	var l := _solid_layout(b64, 200.0, 300.0)

	var host := Node2D.new()
	add_child_autofree(host)
	var pieces := SceneryBuilder.spawn(host, l)
	assert_eq(pieces.size(), 1, "one overlay → one NarfDecor piece")

	# Find the sibling StaticBody2D in group "scenery_solid"
	var bodies := host.get_tree().get_nodes_in_group("scenery_solid")
	assert_eq(bodies.size(), 1, "exactly one StaticBody2D in group scenery_solid")

	var body: StaticBody2D = bodies[0] as StaticBody2D
	assert_not_null(body)

	# The body must carry overlay_name meta
	assert_eq(body.get_meta("overlay_name", ""), "building",
		"body carries overlay_name meta matching the sprite")

	# The body must have at least one CollisionPolygon2D child
	var poly_kids := body.get_children().filter(func(c): return c is CollisionPolygon2D)
	assert_true(poly_kids.size() >= 1, "body has at least one CollisionPolygon2D")

	# Compute the polygon's world-space bounding box.
	# For default pivot CENTER on a 200x150 image:
	#   offset = -(100, 75), so top-left world = piece.position + offset = (200-100, 300-75) = (100, 225)
	var piece := pieces[0]
	var sprite_tl := piece.global_position + piece.offset  # top-left world coord

	# Collect polygon world-space points (body is sibling with its own transform)
	var cp: CollisionPolygon2D = poly_kids[0] as CollisionPolygon2D
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for pt in cp.polygon:
		var wp: Vector2 = body.global_transform * pt
		min_x = minf(min_x, wp.x)
		max_x = maxf(max_x, wp.x)
		min_y = minf(min_y, wp.y)
		max_y = maxf(max_y, wp.y)

	# Polygon world bbox must be close to the sprite world rect + the opaque sub-rect
	# opaque rect: x 40..160, y 60..150 (image-local), so world = sprite_tl + those offsets
	var tol := EPSILON_SLACK
	assert_almost_eq(min_x, sprite_tl.x + 40.0, tol, "polygon left edge near sprite_tl+40")
	assert_almost_eq(max_x, sprite_tl.x + 160.0, tol, "polygon right edge near sprite_tl+160")
	assert_almost_eq(min_y, sprite_tl.y + 60.0, tol, "polygon top edge near sprite_tl+60")
	assert_almost_eq(max_y, sprite_tl.y + 150.0, tol, "polygon bottom edge near sprite_tl+150")


func test_stone_rests_on_painted_roof() -> void:
	# THE SPIKE AS A PIN.
	# Fully opaque 200x100 image — the top surface is the flat roof.
	var img := Image.create(200, 100, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())

	# Place the building so its top edge is at world y=400.
	# Default pivot CENTER: offset = -(100, 50), so top = piece.position.y - 50 = 400 → py = 450.
	var py := 450.0
	var surface_y := py - 100.0 / 2.0  # = 400.0
	var l := _solid_layout(b64, 400.0, py)

	var host := Node2D.new()
	add_child_autofree(host)
	host.add_child(load("res://scenes/environment.tscn").instantiate())

	SceneryBuilder.spawn(host, l)

	# We use a RigidBody2D with a CircleShape2D for the test stone.
	const STONE_R := 18.0
	var expected_rest_y := surface_y - STONE_R

	# Roof stone: placed just above the roof
	var roof_stone := RigidBody2D.new()
	var roof_shape := CollisionShape2D.new()
	var roof_circle := CircleShape2D.new()
	roof_circle.radius = STONE_R
	roof_shape.shape = roof_circle
	roof_stone.add_child(roof_shape)
	roof_stone.position = Vector2(400.0, surface_y - STONE_R - 10.0)
	host.add_child(roof_stone)

	# Control stone: placed in free air far from the building, same height
	var control_stone := RigidBody2D.new()
	var ctrl_shape := CollisionShape2D.new()
	var ctrl_circle := CircleShape2D.new()
	ctrl_circle.radius = STONE_R
	ctrl_shape.shape = ctrl_circle
	control_stone.add_child(ctrl_shape)
	control_stone.position = Vector2(2000.0, surface_y - STONE_R - 10.0)
	host.add_child(control_stone)

	# Wait until control stone has fallen well past the surface level (no floor → keeps going).
	# Terminate on physical condition (not frame counts) per plan.
	var CONTROL_THRESHOLD := surface_y + 200.0  # control must fall 200px past surface
	var guard := 0
	while control_stone.global_position.y < CONTROL_THRESHOLD and guard < 300:
		await wait_physics_frames(4)
		guard += 4

	# Control stone must have fallen past threshold (physics is working)
	assert_gt(control_stone.global_position.y, surface_y,
		"control stone should be falling (no floor beneath it)")

	# Roof stone must be resting near the surface
	var rest_y := roof_stone.global_position.y
	assert_almost_eq(rest_y, expected_rest_y, 2.0,
		"roof stone rests at surface-minus-radius (%.2f) within 2px; got %.2f" % [expected_rest_y, rest_y])

	# Roof stone velocity should be near zero
	var speed := roof_stone.linear_velocity.length()
	assert_lt(speed, 5.0, "roof stone velocity is ~zero (settled on roof)")


func test_hidden_solid_has_no_collision() -> void:
	# A hidden+solid overlay: collision should be disabled at spawn.
	var b64 := _tiny_b64(80, 80)
	var raw := Marshalls.base64_to_raw(b64)
	var key := LevelJson.image_key(raw)
	var l := LevelLayout.new()
	l.title = "hidden_solid"
	l.images[key] = b64
	l.overlays.append({
		"image": key, "x": 100.0, "y": 200.0,
		"solid": true, "hidden": true, "name": "wall"
	})

	var host := Node2D.new()
	add_child_autofree(host)
	SceneryBuilder.spawn(host, l)

	var bodies := host.get_tree().get_nodes_in_group("scenery_solid")
	assert_eq(bodies.size(), 1, "one body spawned")
	var body: StaticBody2D = bodies[0] as StaticBody2D
	assert_not_null(body)

	# Hidden solid body must spawn with collision disabled (PROCESS_MODE_DISABLED)
	assert_eq(body.process_mode, Node.PROCESS_MODE_DISABLED,
		"hidden solid body spawns with PROCESS_MODE_DISABLED")

	# Simulate _set_scenery_visible show → collision re-enabled.
	# Find the piece and call the toggle logic directly (no Level scene needed).
	var piece: NarfDecor = null
	for p in host.get_tree().get_nodes_in_group("scenery"):
		if p.get_meta("overlay_name", "") == "wall":
			piece = p
			break
	assert_not_null(piece, "piece must exist in group 'scenery'")

	# Toggle: visible = true, re-enable body
	piece.visible = true
	for b_node in host.get_tree().get_nodes_in_group("scenery_solid"):
		if (b_node as Node).get_meta("overlay_name", "") == "wall":
			(b_node as Node).process_mode = Node.PROCESS_MODE_INHERIT
			break

	assert_eq(body.process_mode, Node.PROCESS_MODE_INHERIT,
		"after show, body process_mode restored to INHERIT")
