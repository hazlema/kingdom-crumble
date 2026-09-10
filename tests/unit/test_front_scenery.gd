extends GutTest

# Task 2: Foreground layer + auto-peek.
# front: true spawns the piece into a dedicated front container that sits ABOVE
# gameplay (crates/stones/props).  peek: true makes the piece tween to 0.65 alpha
# when any stone or crate occupies its world rect, restoring to 1.0 when clear.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

const EPSILON_SLACK := 3.0


func _base_d(extra: Dictionary = {}) -> Dictionary:
	var d := {"format": 1, "title": "t", "crates": [], "shots": 3}
	d.merge(extra, true)
	return d


func _tiny_b64(w: int = 4, h: int = 4, fill: Color = Color.WHITE) -> String:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


# Returns a LevelLayout with one overlay using the given b64 and extra dict keys.
func _overlay_layout(b64: String, extra: Dictionary = {}, px: float = 200.0, py: float = 300.0) -> LevelLayout:
	var raw := Marshalls.base64_to_raw(b64)
	var key := LevelJson.image_key(raw)
	var l := LevelLayout.new()
	l.title = "front_test"
	l.images[key] = b64
	var entry: Dictionary = {"image": key, "x": px, "y": py}
	entry.merge(extra, true)
	l.overlays.append(entry)
	return l


# ---------------------------------------------------------------------------
# Format validation tests
# ---------------------------------------------------------------------------

func test_front_validates_as_strict_bool() -> void:
	# non-bool string → named validation error
	var ov_str := {"image": "abcd1234", "x": 0, "y": 0, "front": "yes"}
	var err := LevelJson.validate(_base_d({"overlays": [ov_str]}))
	assert_eq(err, "overlay 0: front must be true/false",
		"string 'yes' must be rejected with the exact named error")

	# integer 1 → also rejected
	var ov_int := {"image": "abcd1234", "x": 0, "y": 0, "front": 1}
	var err2 := LevelJson.validate(_base_d({"overlays": [ov_int]}))
	assert_eq(err2, "overlay 0: front must be true/false",
		"integer 1 must also be rejected")

	# boolean true → valid
	var ov_ok := {"image": "abcd1234", "x": 0, "y": 0, "front": true}
	assert_eq(LevelJson.validate(_base_d({"overlays": [ov_ok]})), "",
		"front: true should pass validation")

	# boolean false → valid
	var ov_false := {"image": "abcd1234", "x": 0, "y": 0, "front": false}
	assert_eq(LevelJson.validate(_base_d({"overlays": [ov_false]})), "",
		"front: false should pass validation")

	# absent front → also valid (optional key)
	var ov_absent := {"image": "abcd1234", "x": 0, "y": 0}
	assert_eq(LevelJson.validate(_base_d({"overlays": [ov_absent]})), "",
		"absent front key should pass validation")


func test_peek_validates_as_strict_bool() -> void:
	# non-bool string → named validation error
	var ov_str := {"image": "abcd1234", "x": 0, "y": 0, "front": true, "peek": "yes"}
	var err := LevelJson.validate(_base_d({"overlays": [ov_str]}))
	assert_eq(err, "overlay 0: peek must be true/false",
		"string 'yes' for peek must be rejected")

	# integer 1 → also rejected
	var ov_int := {"image": "abcd1234", "x": 0, "y": 0, "front": true, "peek": 1}
	var err2 := LevelJson.validate(_base_d({"overlays": [ov_int]}))
	assert_eq(err2, "overlay 0: peek must be true/false",
		"integer 1 for peek must be rejected")

	# boolean true with front: true → valid
	var ov_ok := {"image": "abcd1234", "x": 0, "y": 0, "front": true, "peek": true}
	assert_eq(LevelJson.validate(_base_d({"overlays": [ov_ok]})), "",
		"peek: true with front: true should pass validation")

	# absent peek → valid
	var ov_absent := {"image": "abcd1234", "x": 0, "y": 0, "front": true}
	assert_eq(LevelJson.validate(_base_d({"overlays": [ov_absent]})), "",
		"absent peek key should pass validation")


func test_peek_requires_front() -> void:
	# peek: true without front: true → named validation error
	var ov_no_front := {"image": "abcd1234", "x": 0, "y": 0, "peek": true}
	var err := LevelJson.validate(_base_d({"overlays": [ov_no_front]}))
	assert_eq(err, "overlay 0: peek requires front",
		"peek without front must produce the exact named error")

	# peek: true with front: false → also fails (front must be true)
	var ov_front_false := {"image": "abcd1234", "x": 0, "y": 0, "front": false, "peek": true}
	var err2 := LevelJson.validate(_base_d({"overlays": [ov_front_false]}))
	assert_eq(err2, "overlay 0: peek requires front",
		"peek with front: false must also be rejected")

	# peek: false without front → valid (not a peek piece)
	var ov_peek_false := {"image": "abcd1234", "x": 0, "y": 0, "peek": false}
	assert_eq(LevelJson.validate(_base_d({"overlays": [ov_peek_false]})), "",
		"peek: false without front is valid")


# ---------------------------------------------------------------------------
# Round-trip and bake-survival tests
# ---------------------------------------------------------------------------

func test_front_and_peek_round_trip_and_survive_bake() -> void:
	var b64 := _tiny_b64()
	var raw := Marshalls.base64_to_raw(b64)
	var key := LevelJson.image_key(raw)

	# front: true + peek: true round-trips
	var l := LevelLayout.new()
	l.title = "rt"
	l.images[key] = b64
	l.overlays.append({"image": key, "x": 10.0, "y": 20.0, "front": true, "peek": true})

	var text := LevelJson.serialize(l)
	var parsed := LevelJson.parse(text)
	assert_not_null(parsed, "round-trip parse must succeed: %s" % LevelJson.last_error)
	assert_eq(parsed.overlays.size(), 1)
	assert_eq(parsed.overlays[0].get("front", false), true, "front key survives round-trip")
	assert_eq(parsed.overlays[0].get("peek", false), true, "peek key survives round-trip")

	# SceneryBake.bake leaves front and peek (not underscore keys)
	var l2 := LevelLayout.new()
	l2.title = "bake"
	l2.images[key] = b64
	l2.overlays.append({"image": key, "x": 0.0, "y": 0.0, "front": true, "peek": true, "_scale": 1.0})
	SceneryBake.bake(l2)
	assert_eq(l2.overlays[0].get("front", false), true, "bake must leave 'front' untouched")
	assert_eq(l2.overlays[0].get("peek", false), true, "bake must leave 'peek' untouched")
	assert_false(l2.overlays[0].has("_scale"), "bake must strip underscore keys")


# ---------------------------------------------------------------------------
# Spawn tests — front container parent
# ---------------------------------------------------------------------------

func test_front_piece_spawns_into_front_parent() -> void:
	var b64 := _tiny_b64()

	# back overlay: no front key
	var back_layout := _overlay_layout(b64, {}, 200.0, 300.0)
	# front overlay: front: true
	var raw := Marshalls.base64_to_raw(b64)
	var key := LevelJson.image_key(raw)
	var front_layout := LevelLayout.new()
	front_layout.title = "front"
	front_layout.images[key] = b64
	front_layout.overlays.append({"image": key, "x": 200.0, "y": 300.0, "front": true})

	var back_parent := Node2D.new()
	var front_parent := Node2D.new()
	add_child_autofree(back_parent)
	add_child_autofree(front_parent)

	# Back piece: no front_parent passed — all pieces go to back_parent
	var back_pieces := SceneryBuilder.spawn(back_parent, back_layout)
	assert_eq(back_pieces.size(), 1, "one back piece returned")
	assert_eq(back_pieces[0].get_parent(), back_parent, "back piece parent is back_parent")

	# Front piece: front_parent provided — front pieces go to front_parent
	var front_pieces := SceneryBuilder.spawn(front_parent, front_layout, front_parent)
	assert_eq(front_pieces.size(), 1, "one front piece returned")
	assert_eq(front_pieces[0].get_parent(), front_parent, "front piece parent is front_parent")


func test_back_and_front_pieces_split_between_parents() -> void:
	var b64 := _tiny_b64()
	var raw := Marshalls.base64_to_raw(b64)
	var key := LevelJson.image_key(raw)

	# Layout with one back and one front overlay
	var l := LevelLayout.new()
	l.title = "split"
	l.images[key] = b64
	l.overlays.append({"image": key, "x": 100.0, "y": 200.0})  # back
	l.overlays.append({"image": key, "x": 300.0, "y": 200.0, "front": true})  # front

	var back_parent := Node2D.new()
	var front_parent := Node2D.new()
	add_child_autofree(back_parent)
	add_child_autofree(front_parent)

	var pieces := SceneryBuilder.spawn(back_parent, l, front_parent)
	# Both pieces returned
	assert_eq(pieces.size(), 2, "two pieces returned total")

	# Back piece: parent is back_parent
	var found_back := false
	var found_front := false
	for p in pieces:
		if (p as NarfDecor).get_parent() == back_parent:
			found_back = true
		elif (p as NarfDecor).get_parent() == front_parent:
			found_front = true
	assert_true(found_back, "one piece must be parented to back_parent")
	assert_true(found_front, "one piece must be parented to front_parent")


# ---------------------------------------------------------------------------
# Peek watcher tests — requires physics timer tick simulation
# ---------------------------------------------------------------------------

# Builds a front+peek layout using a 100x100 opaque image centered at (400, 400).
# Default CENTER pivot: offset = -(50, 50), so the piece occupies world rect
# x: 350..450, y: 350..450.
func _peek_layout() -> LevelLayout:
	var img := Image.create(100, 100, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())
	return _overlay_layout(b64, {"front": true, "peek": true}, 400.0, 400.0)


# Fires one tick of the peek watcher logic by calling the public method on
# the Level node (the same _tick_peek logic the timer calls).
# Returns the front piece so tests can check its modulate.
func _spawn_with_peek(host_level: Node) -> NarfDecor:
	var pieces: Array[NarfDecor] = []
	for p in host_level.get_tree().get_nodes_in_group("scenery"):
		if (p as NarfDecor).get_meta("peek", false) == true:
			pieces.append(p)
	if pieces.is_empty():
		return null
	return pieces[0]


func test_peek_fade_when_stone_inside_rect() -> void:
	# Spawn a layout with a front+peek piece. Place a stone inside the rect.
	# Tick the peek watcher. Piece alpha should tween toward 0.65.
	var l := _peek_layout()
	Level.suppress_intro = true
	Level.next_layout = l
	var level: Node = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(level)
	await wait_physics_frames(2)

	# Find the front+peek piece (it's in group "scenery" with peek meta)
	var piece: NarfDecor = null
	for p in get_tree().get_nodes_in_group("scenery"):
		var nd := p as NarfDecor
		if nd != null and nd.get_meta("peek", false) == true:
			piece = nd
			break
	assert_not_null(piece, "front+peek piece must exist in group 'scenery'")
	# Confirm it starts at full alpha
	assert_almost_eq(piece.modulate.a, 1.0, 0.01, "piece starts at alpha 1.0")

	# Place a RigidBody2D stone inside the piece's world rect (center of the rect)
	# Piece occupies x: 350..450, y: 350..450 (400,400 center, 100x100, CENTER pivot)
	var stone_host := RigidBody2D.new()
	var stone_shape := CollisionShape2D.new()
	var stone_circle := CircleShape2D.new()
	stone_circle.radius = 8.0
	stone_shape.shape = stone_circle
	stone_host.add_child(stone_shape)
	stone_host.position = Vector2(400.0, 400.0)  # inside the piece rect
	stone_host.add_to_group("stones")
	level.add_child(stone_host)

	# Trigger the peek watcher tick
	(level as Level)._tick_peek()

	# Wait for tween to settle (0.2s tween + margin)
	var guard := 0
	while piece.modulate.a > 0.70 and guard < 60:
		await wait_physics_frames(2)
		guard += 2

	assert_lt(piece.modulate.a, 0.70, "piece alpha must tween toward 0.65 when stone is inside")


func test_peek_restore_when_stone_leaves() -> void:
	# After stone leaves the rect, another tick restores alpha to 1.0.
	var l := _peek_layout()
	Level.suppress_intro = true
	Level.next_layout = l
	var level: Node = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(level)
	await wait_physics_frames(2)

	var piece: NarfDecor = null
	for p in get_tree().get_nodes_in_group("scenery"):
		var nd := p as NarfDecor
		if nd != null and nd.get_meta("peek", false) == true:
			piece = nd
			break
	assert_not_null(piece, "piece must exist")

	# Stone inside the rect → fade
	var stone_host := RigidBody2D.new()
	var stone_shape := CollisionShape2D.new()
	var stone_circle := CircleShape2D.new()
	stone_circle.radius = 8.0
	stone_shape.shape = stone_circle
	stone_host.add_child(stone_shape)
	stone_host.position = Vector2(400.0, 400.0)
	stone_host.add_to_group("stones")
	level.add_child(stone_host)
	(level as Level)._tick_peek()
	# Wait for fade
	var guard := 0
	while piece.modulate.a > 0.70 and guard < 60:
		await wait_physics_frames(2)
		guard += 2
	assert_lt(piece.modulate.a, 0.70, "piece faded when stone was inside")

	# Move stone outside the rect
	stone_host.position = Vector2(1000.0, 400.0)  # far outside
	(level as Level)._tick_peek()
	# Wait for restore tween
	guard = 0
	while piece.modulate.a < 0.95 and guard < 60:
		await wait_physics_frames(2)
		guard += 2
	assert_gt(piece.modulate.a, 0.95, "piece alpha restored to 1.0 when stone left")


func test_peek_fades_for_crates_behind_it() -> void:
	# The fade is the passability affordance (owner: an opaque front frame
	# reads as a solid wall). A crate behind a front piece — resting or
	# moving — keeps it see-through so the player knows it can shoot there
	# and can see the targets.
	var l := _peek_layout()
	Level.suppress_intro = true
	Level.next_layout = l
	var level: Node = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(level)
	await wait_physics_frames(2)

	var piece: NarfDecor = null
	for p in get_tree().get_nodes_in_group("scenery"):
		var nd := p as NarfDecor
		if nd != null and nd.get_meta("peek", false) == true:
			piece = nd
			break
	assert_not_null(piece, "piece must exist")

	# A crate behind the front piece (even resting/frozen) fades it.
	var crate := RigidBody2D.new()
	crate.position = Vector2(400.0, 400.0)
	crate.freeze = true
	crate.add_to_group("crates")
	level.add_child(crate)
	var guard := 0
	while piece.modulate.a > 0.5 and guard < 80:
		(level as Level)._tick_peek()
		await wait_physics_frames(2)
		guard += 2
	assert_lt(piece.modulate.a, 0.5, "a crate behind the front piece fades it see-through (the affordance)")


func test_front_pieces_actually_render_above_crates() -> void:
	# Final-review Critical: parentage alone proved nothing — FrontScenery
	# at z_index 0 lost to later-tree-order crates and the whole feature
	# was visually inert in the game. Pin the RENDER ORDER: the front
	# container's z must beat a gameplay crate's effective z.
	var layout := LevelLayout.new()
	layout.title = "front_z"
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())
	var key := LevelJson.image_key(Marshalls.base64_to_raw(b64))
	layout.images[key] = b64
	layout.overlays.append({"image": key, "x": 832.0, "y": 380.0, "name": "roof", "front": true})
	layout.crates.append({"x": 832.0, "y": 443.0, "type": "crate-wood"})
	layout.shots = 3
	Level.next_layout = layout
	var lvl: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(lvl)
	await wait_frames(2)
	var front := lvl.get_node("FrontScenery") as Node2D
	var crate: Node2D = lvl.get_tree().get_nodes_in_group("crates")[0]
	assert_gt(front.z_index, crate.z_index,
		"front container z beats gameplay z — later tree order must not win")
