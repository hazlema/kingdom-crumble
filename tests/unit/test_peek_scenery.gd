extends GutTest

# Peek is a standalone object PROPERTY (owner design, 2026-09-10): a scenery
# piece with peek: true fades to 0.35 when a SHOT comes near (rect grown by
# Level.PEEK_MARGIN), restoring to 1.0 when clear.  The fade is pure human
# feedback — "this thing isn't solid".  Draw order is fixed by decree:
# background -> peek -> crates -> stones -> hud.  The old "front" concept is
# dead vocabulary: ignored on load, never written, goals never obscured.

func _tiny_b64(w: int = 4, h: int = 4, fill: Color = Color.WHITE) -> String:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


func _overlay_layout(b64: String, extra: Dictionary = {}, px: float = 200.0, py: float = 300.0) -> LevelLayout:
	var raw := Marshalls.base64_to_raw(b64)
	var key := LevelJson.image_key(raw)
	var l := LevelLayout.new()
	l.title = "peek_test"
	l.images[key] = b64
	var entry: Dictionary = {"image": key, "x": px, "y": py}
	entry.merge(extra, true)
	l.overlays.append(entry)
	return l


func _peek_level(extra_overlay: Dictionary = {"peek": true, "name": "veil"}) -> Level:
	var b64 := _tiny_b64(64, 64)
	var l := _overlay_layout(b64, extra_overlay, 368.0, 368.0)
	l.crates.append({"x": 832.0, "y": 443.0, "type": "crate-wood"})
	l.shots = 3
	Level.suppress_intro = true
	Level.next_layout = l
	var lvl: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(lvl)
	return lvl


# ---------------------------------------------------------------------------
# Format
# ---------------------------------------------------------------------------

func test_peek_validates_as_standalone_strict_bool() -> void:
	var b64 := _tiny_b64()
	var raw := Marshalls.base64_to_raw(b64)
	var key := LevelJson.image_key(raw)
	var bad := {"format": 1, "title": "t", "crates": [], "shots": 3,
		"images": {key: b64},
		"overlays": [{"image": key, "x": 1.0, "y": 2.0, "peek": "yes"}]}
	assert_string_contains(LevelJson.validate(bad), "peek must be true/false")
	# peek WITHOUT front is legal now — it's a standalone property.
	var good := {"format": 1, "title": "t", "crates": [], "shots": 3,
		"images": {key: b64},
		"overlays": [{"image": key, "x": 1.0, "y": 2.0, "peek": true}]}
	assert_eq(LevelJson.validate(good), "", "peek stands alone — no front required")


func test_legacy_front_key_is_ignored() -> void:
	# Old files carry front: true (or garbage) — dead vocabulary, ignored.
	var b64 := _tiny_b64()
	var raw := Marshalls.base64_to_raw(b64)
	var key := LevelJson.image_key(raw)
	var legacy := {"format": 1, "title": "t", "crates": [], "shots": 3,
		"images": {key: b64},
		"overlays": [{"image": key, "x": 1.0, "y": 2.0, "front": true, "peek": true}]}
	assert_eq(LevelJson.validate(legacy), "", "legacy front key never blocks a load")


func test_peek_round_trips_and_survives_bake() -> void:
	var b64 := _tiny_b64()
	var l := _overlay_layout(b64, {"peek": true, "name": "veil"})
	var text := LevelJson.serialize(l)
	var back := LevelJson.parse(text)
	assert_eq(back.overlays[0].get("peek"), true, "peek survives serialize/parse")
	SceneryBake.bake(back)  # mutates in place, returns bake count
	assert_eq(back.overlays[0].get("peek"), true, "bake leaves peek")


# ---------------------------------------------------------------------------
# Draw order: background -> peek -> crates -> stones -> hud
# ---------------------------------------------------------------------------

func test_peek_pieces_draw_above_backdrops_below_crates() -> void:
	var lvl := _peek_level()
	await wait_frames(2)
	var piece: NarfDecor = null
	for p in lvl.get_tree().get_nodes_in_group("scenery"):
		if (p as NarfDecor) != null and p.get_meta("peek", false):
			piece = p
	assert_not_null(piece, "peek piece spawned")
	assert_eq(piece.z_index, 0, "no z hacks — tree order does the layering")
	var crate: Node2D = lvl.get_tree().get_nodes_in_group("crates")[0]
	# Same parent chain: the crate must come LATER in tree order than the
	# peek piece so the goal draws over it and is never obscured.
	assert_true(crate.is_greater_than(piece),
		"crates draw above peek pieces — the goal is never obscured")


func test_spawner_orders_peek_after_plain_scenery() -> void:
	var b64a := _tiny_b64(8, 8, Color.RED)
	var b64b := _tiny_b64(8, 8, Color.BLUE)
	var rawa := Marshalls.base64_to_raw(b64a)
	var rawb := Marshalls.base64_to_raw(b64b)
	var ka := LevelJson.image_key(rawa)
	var kb := LevelJson.image_key(rawb)
	var l := LevelLayout.new()
	l.title = "order"
	l.images[ka] = b64a
	l.images[kb] = b64b
	l.overlays.append({"image": ka, "x": 100.0, "y": 100.0, "peek": true, "name": "veil"})
	l.overlays.append({"image": kb, "x": 100.0, "y": 100.0, "name": "backdrop"})
	var host := Node2D.new()
	add_child_autofree(host)
	var pieces := SceneryBuilder.spawn(host, l)
	assert_eq(pieces.size(), 2)
	var veil: NarfDecor = pieces[0]
	var backdrop: NarfDecor = pieces[1]
	assert_true(veil.get_index() > backdrop.get_index(),
		"peek piece sits after plain scenery even when authored first")


# ---------------------------------------------------------------------------
# Proximity fade: "fade out when a shot comes near"
# ---------------------------------------------------------------------------

func test_peek_fades_when_stone_near_and_restores_when_gone() -> void:
	var lvl := _peek_level()
	await wait_frames(2)
	var piece: NarfDecor = null
	for p in lvl.get_tree().get_nodes_in_group("scenery"):
		if (p as NarfDecor) != null and p.get_meta("peek", false):
			piece = p
	assert_not_null(piece)
	assert_almost_eq(piece.modulate.a, 1.0, 0.01, "opaque before any shot")

	# A "stone" near the piece (inside rect + margin, not inside the rect).
	var stone := RigidBody2D.new()
	stone.freeze = true  # park it — we test proximity, not ballistics
	stone.add_to_group("stones")
	lvl.add_child(stone)
	stone.global_position = Vector2(368.0 + 64.0 + Level.PEEK_MARGIN * 0.5, 400.0)
	var guard := 0
	while piece.modulate.a > 0.4 and guard < 80:
		lvl._tick_peek()
		await wait_physics_frames(2)
		guard += 2
	assert_lt(piece.modulate.a, 0.4, "shot near -> fades (feedback: not solid)")

	# Move the stone far away -> restores.
	stone.global_position = Vector2(2500.0, 400.0)
	guard = 0
	while piece.modulate.a < 0.95 and guard < 80:
		lvl._tick_peek()
		await wait_physics_frames(2)
		guard += 2
	assert_gt(piece.modulate.a, 0.95, "shot gone -> restores to opaque")


func test_resting_crates_do_not_fade_peek() -> void:
	# Crates draw OVER peek pieces (goal never obscured), so a crate behind
	# the depot must not hold the veil faded — only shots trigger it.
	var lvl := _peek_level()
	await wait_frames(2)
	var piece: NarfDecor = null
	for p in lvl.get_tree().get_nodes_in_group("scenery"):
		if (p as NarfDecor) != null and p.get_meta("peek", false):
			piece = p
	var crate := RigidBody2D.new()
	crate.freeze = true
	crate.add_to_group("crates")
	lvl.add_child(crate)
	crate.global_position = Vector2(400.0, 400.0)  # inside the piece rect
	lvl._tick_peek()
	await wait_physics_frames(4)
	assert_almost_eq(piece.modulate.a, 1.0, 0.02, "crates never trip the fade")


func test_hidden_peek_piece_does_not_fade() -> void:
	var lvl := _peek_level({"peek": true, "name": "veil", "hidden": true})
	await wait_frames(2)
	var piece: NarfDecor = null
	for p in lvl.get_tree().get_nodes_in_group("scenery"):
		if (p as NarfDecor) != null and p.get_meta("peek", false):
			piece = p
	var stone := RigidBody2D.new()
	stone.freeze = true
	stone.add_to_group("stones")
	lvl.add_child(stone)
	stone.global_position = Vector2(400.0, 400.0)
	lvl._tick_peek()
	await wait_physics_frames(4)
	assert_false(piece.visible, "hidden piece stays hidden — no surprise pre-fade")
