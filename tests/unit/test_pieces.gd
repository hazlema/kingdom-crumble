extends GutTest

# Wave-1 Pieces registry: PNG + JSON sidecar, clamped, warn-skip on junk.


func before_all() -> void:
	Pieces.scan()


func test_parse_sidecar_defaults_to_plain_crate() -> void:
	var meta := Pieces.parse_sidecar("crate-wood", {})
	assert_eq(meta["class"], "crate")
	assert_eq(meta["cells"], Vector2i(1, 1))
	assert_eq(meta["tilt"], 0)
	assert_eq(meta["bounce"], 1.5)
	assert_eq(meta["tip"], "crate-wood")


func test_parse_sidecar_clamps_and_curates() -> void:
	var meta := Pieces.parse_sidecar(
		"t", {"class": "trampoline", "cells": [9, 0], "tilt": 30, "bounce": 99.0, "tip": "x".repeat(500)}
	)
	assert_eq(meta["cells"], Vector2i(4, 1), "cells clamped 1-4")
	assert_eq(meta["tilt"], 0, "tilt outside curated set falls back to 0")
	assert_eq(meta["bounce"], 2.0, "bounce clamped to 2.0")
	assert_eq(meta["tip"].length(), 200, "tip capped")


func test_parse_sidecar_rejects_unknown_class() -> void:
	var meta := Pieces.parse_sidecar("t", {"class": "cannon"})
	assert_true(meta.is_empty(), "unknown class = skip signal (empty dict)")


func test_parse_sidecar_warns_malformed_cells() -> void:
	var meta := Pieces.parse_sidecar("t", {"cells": ["a", "b"]})
	assert_eq(meta["cells"], Vector2i(1, 1), "malformed cells fall back to 1x1")


func test_scan_finds_obstacles_with_metadata() -> void:
	var tramp := Pieces.entry("tramp-left")
	assert_eq(tramp["class"], "trampoline")
	assert_eq(tramp["cells"], Vector2i(2, 1))
	assert_eq(tramp["tilt"], -45)
	assert_not_null(tramp["texture"])
	var block := Pieces.entry("block-stone")
	assert_eq(block["class"], "static")
	assert_eq(block["cells"], Vector2i(1, 1))


func test_unknown_id_is_empty_and_null() -> void:
	assert_true(Pieces.entry("no-such-piece").is_empty())
	assert_null(Pieces.texture_for("no-such-piece"))


func test_all_crate_ids_resolve_through_pieces() -> void:
	# Migration pin: every shipped crate face must be served by Pieces.
	for id in ["crate-wood", "crate-blue", "crate-gold", "crate-green", "crate-ghost", "skull"]:
		var e := Pieces.entry(id)
		assert_false(e.is_empty(), "%s registered" % id)
		assert_eq(e["class"], "crate", "%s is a crate" % id)
		assert_not_null(e["texture"], "%s has art" % id)


func test_crate_tooltips_survived_txt_to_sidecar() -> void:
	assert_ne(Pieces.entry("crate-gold")["tip"], "crate-gold", "gold kept its .txt tooltip text")


func _props_doc(props: Variant) -> Dictionary:
	return {"title": "p", "background": "meadow", "crates": [], "props": props, "format": 1}


func test_props_validation_matrix() -> void:
	assert_eq(LevelJson.validate(_props_doc([])), "")
	assert_eq(LevelJson.validate(_props_doc([{"id": "tramp-left", "x": 1024, "y": 569}])), "")
	assert_eq(
		LevelJson.validate(_props_doc([{"id": "thanksgiving:turkey", "x": 0, "y": 0}])),
		"",
		"namespaced ids are legal"
	)
	assert_eq(LevelJson.validate(_props_doc("nope")), "props must be a list")
	assert_eq(LevelJson.validate(_props_doc([{"id": "BAD CAPS", "x": 0, "y": 0}])), "prop 0: bad id")
	assert_eq(LevelJson.validate(_props_doc([{"id": "ok", "x": "left", "y": 0}])), "prop 0: bad coords")
	assert_eq(LevelJson.validate(_props_doc([{"x": 0, "y": 0}])), "prop 0: bad id")
	var many := []
	for i in 65:
		many.append({"id": "block-stone", "x": i, "y": 0})
	assert_eq(LevelJson.validate(_props_doc(many)), "too many props")


func test_props_round_trip() -> void:
	var l := LevelLayout.new()
	l.title = "rt"
	l.props.append({"id": "tramp-right", "x": 1024.0, "y": 569.0})
	var back := LevelJson.parse(LevelJson.serialize(l))
	assert_not_null(back)
	assert_eq(back.props.size(), 1)
	assert_eq(back.props[0]["id"], "tramp-right")
	assert_eq(float(back.props[0]["x"]), 1024.0)


func test_level_without_props_still_parses() -> void:
	var l := LevelLayout.new()
	l.title = "legacy"
	var back := LevelJson.parse(LevelJson.serialize(l))
	assert_not_null(back, "props key optional — old levels unaffected")
	assert_eq(back.props.size(), 0)

	# Backward-compat: parse doc with NO "props" key (pre-props levels)
	var legacy := LevelJson.parse('{"format":1,"title":"legacy","background":"meadow","crates":[]}')
	assert_not_null(legacy, "doc with no props key parses")
	assert_eq(legacy.props.size(), 0)


func test_spawn_props_builds_static_geometry() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := LevelLayout.new()
	l.title = "geo"
	var anchor := EditorGrid.cell_to_world(Vector2i(3, 0))
	l.props.append({"id": "block-stone", "x": anchor.x, "y": anchor.y})
	l.props.append({"id": "tramp-left", "x": anchor.x + 128.0, "y": anchor.y})
	var spawned := PropBuilder.spawn_props(host, l)
	assert_eq(spawned.size(), 2)
	assert_true(spawned[0] is StaticBody2D)
	assert_true(spawned[0].is_in_group("props"))
	assert_false(spawned[0].is_in_group("crates"), "props are unscored")
	assert_eq(spawned[1].get_meta("prop_id"), "tramp-left")
	assert_eq(spawned[1].physics_material_override.bounce, 1.5, "sidecar bounce applied")
	# 2x1 footprint: body centered half a cell right of the anchor
	assert_almost_eq(spawned[1].position.x, anchor.x + 128.0 + 32.0, 0.01)


func test_spawn_props_skips_unknown_id_with_warning() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := LevelLayout.new()
	l.title = "orphan"
	l.props.append({"id": "thanksgiving:turkey", "x": 700.0, "y": 569.0})
	var spawned := PropBuilder.spawn_props(host, l)  # warns (missing pack) — GUT-safe
	assert_eq(spawned.size(), 0, "unknown id warn-skips, never crashes")


func test_spawn_props_tramp_right_has_collision_and_bounce() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := LevelLayout.new()
	l.title = "tramp_right_test"
	var anchor := EditorGrid.cell_to_world(Vector2i(0, 0))
	l.props.append({"id": "tramp-right", "x": anchor.x, "y": anchor.y})
	var spawned := PropBuilder.spawn_props(host, l)
	assert_eq(spawned.size(), 1)
	assert_true(spawned[0].get_child(0) is CollisionPolygon2D, "tramp-right has CollisionPolygon2D child")
	assert_eq(spawned[0].physics_material_override.bounce, 1.5, "tramp-right bounce is 1.5")


func test_footprint_center_multi_row_offset() -> void:
	var center := PropBuilder.footprint_center(Vector2(100, 500), Vector2i(2, 2))
	assert_eq(center, Vector2(132.0, 468.5), "2x2 footprint y-offset correct")


func test_tramp_left_polygon_deflects_stones_left() -> void:
	# Pin the exact triangle for tramp-left (tilt < 0).
	# tramp-left has cells=Vector2i(2,1), so size=(128,63), hw=64, hh=31.5.
	# "/" ramp: high edge on the RIGHT (at x=+hw).
	# Hypotenuse goes from (-hw, hh) to (hw, -hh).
	# Direction vector: (2hw, -2hh). Right-hand normal: (-2hh, -2hw) → up-left. ✓
	# Stones landing on this surface are deflected to the LEFT, matching the tooltip.
	var host := Node2D.new()
	add_child_autofree(host)
	var l := LevelLayout.new()
	l.title = "ramp_dir"
	var anchor := EditorGrid.cell_to_world(Vector2i(0, 0))
	l.props.append({"id": "tramp-left", "x": anchor.x, "y": anchor.y})
	var spawned := PropBuilder.spawn_props(host, l)
	assert_eq(spawned.size(), 1)
	var poly_node: CollisionPolygon2D = spawned[0].get_child(0) as CollisionPolygon2D
	assert_not_null(poly_node, "tramp-left has CollisionPolygon2D")
	var hw := 64.0  # cells.x=2, CELL_W=64 → size.x=128 → hw=64
	var hh := 31.5  # cells.y=1, CELL_H=63 → size.y=63  → hh=31.5
	var expected := PackedVector2Array([Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
	assert_eq(poly_node.polygon, expected, "tramp-left is '/' ramp — normal points up-left, stones launch left")


func test_wormhole_sidecars_register() -> void:
	var blue := Pieces.entry("wormhole-blue")
	assert_eq(blue["class"], "wormhole")
	assert_eq(blue["cells"], Vector2i(1, 2))
	assert_not_null(blue["texture"])
	assert_eq(Pieces.entry("wormhole-orange")["class"], "wormhole")


func test_link_pairs_wires_exactly_two() -> void:
	var a := Wormhole.new()
	var b := Wormhole.new()
	a.set_meta("prop_id", "wormhole-blue")
	b.set_meta("prop_id", "wormhole-blue")
	autofree(a)
	autofree(b)
	Wormhole.link_pairs([a, b])
	assert_eq(a.partner, b)
	assert_eq(b.partner, a)


func test_link_pairs_odd_counts_stay_inert() -> void:
	var lone := Wormhole.new()
	lone.set_meta("prop_id", "wormhole-orange")
	autofree(lone)
	Wormhole.link_pairs([lone])  # warns (GUT-safe)
	assert_null(lone.partner, "1 portal = inert")
	var t1 := Wormhole.new()
	var t2 := Wormhole.new()
	var t3 := Wormhole.new()
	for t in [t1, t2, t3]:
		t.set_meta("prop_id", "wormhole-blue")
		autofree(t)
	Wormhole.link_pairs([t1, t2, t3])  # warns (GUT-safe)
	assert_null(t1.partner, "3 portals = all inert")
	assert_null(t2.partner)
	assert_null(t3.partner)


func test_spawn_props_builds_linked_wormholes() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := LevelLayout.new()
	l.title = "warp-spawn"
	var a := EditorGrid.cell_to_world(Vector2i(2, 0))
	var b := EditorGrid.cell_to_world(Vector2i(20, 0))
	l.props.append({"id": "wormhole-blue", "x": a.x, "y": a.y})
	l.props.append({"id": "wormhole-blue", "x": b.x, "y": b.y})
	var spawned := PropBuilder.spawn_props(host, l)
	assert_eq(spawned.size(), 2)
	assert_true(spawned[0] is Wormhole)
	assert_true(spawned[0].is_in_group("props"))
	assert_eq(spawned[0].get_meta("prop_id"), "wormhole-blue")
	assert_eq((spawned[0] as Wormhole).partner, spawned[1], "pair auto-linked")
	assert_eq((spawned[1] as Wormhole).partner, spawned[0])


func test_spawn_props_lone_wormhole_spawns_inert() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := LevelLayout.new()
	l.title = "lone"
	var a := EditorGrid.cell_to_world(Vector2i(4, 0))
	l.props.append({"id": "wormhole-orange", "x": a.x, "y": a.y})
	var spawned := PropBuilder.spawn_props(host, l)  # warns (GUT-safe)
	assert_eq(spawned.size(), 1, "spawns as scenery")
	assert_null((spawned[0] as Wormhole).partner, "but inert")


func test_teleport_guards_freed_partner() -> void:
	# Pin the use-after-free fix: partner freed between deferred call queue and execute.
	var a := Wormhole.new()
	var b := Wormhole.new()
	a.set_meta("prop_id", "wormhole-blue")
	b.set_meta("prop_id", "wormhole-blue")
	add_child_autofree(a)
	add_child_autofree(b)
	Wormhole.link_pairs([a, b])

	# Place portals far apart so teleport would be obvious.
	a.global_position = Vector2(100, 100)
	b.global_position = Vector2(500, 500)

	# Instantiate a real Stone, add to tree.
	var stone := load("res://scenes/stone.tscn").instantiate() as Stone
	add_child_autofree(stone)
	stone.global_position = a.global_position
	var stone_x_before := stone.global_position.x

	# Queue _teleport(stone) to b; then free b immediately (not queue_free).
	a._on_body_entered(stone)
	b.free()

	# Let deferred calls run; the freed partner guard should prevent crash.
	await wait_process_frames(2)

	# Assert stone did NOT teleport (x should stay near original, not jump to b's x=500).
	assert_lt(abs(stone.global_position.x - stone_x_before), 50.0, "stone x near original after freed-partner teleport")


func _warp_pair(host: Node2D) -> Array:
	var l := LevelLayout.new()
	l.title = "e2e"
	var a := EditorGrid.cell_to_world(Vector2i(2, 0))
	var b := EditorGrid.cell_to_world(Vector2i(24, 0))
	l.props.append({"id": "wormhole-blue", "x": a.x, "y": a.y})
	l.props.append({"id": "wormhole-blue", "x": b.x, "y": b.y})
	return [PropBuilder.spawn_props(host, l), a, b]


func test_stone_warps_with_velocity_preserved() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var parts := _warp_pair(host)
	var a: Vector2 = parts[1]
	var b: Vector2 = parts[2]
	var stone: Stone = load("res://scenes/stone.tscn").instantiate()
	stone.gravity_scale = 0.0
	# test control: isolate the warp from world air drag (game stones keep it)
	stone.linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	stone.global_position = a + Vector2(-150, 0)
	stone.linear_velocity = Vector2(600, 0)
	host.add_child(stone)
	autofree(stone)
	await wait_physics_frames(40)
	assert_gt(stone.global_position.x, b.x, "stone crossed the map via the warp")
	assert_almost_eq(stone.linear_velocity.x, 600.0, 30.0, "speed preserved (minor damp tolerated)")
	assert_almost_eq(stone.linear_velocity.y, 0.0, 5.0, "direction preserved")


func test_arrival_immunity_blocks_instant_return() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var parts := _warp_pair(host)
	var spawned: Array = parts[0]
	var exit_hole: Wormhole = spawned[1]
	var stone: Stone = load("res://scenes/stone.tscn").instantiate()
	stone.gravity_scale = 0.0
	host.add_child(stone)
	autofree(stone)
	exit_hole.expect_arrival(stone)
	stone.global_position = exit_hole.global_position
	stone.linear_velocity = Vector2.ZERO
	await wait_physics_frames(20)
	assert_almost_eq(
		stone.global_position.x, exit_hole.global_position.x, 2.0,
		"arrived stone parks in the exit portal — no ping-pong back"
	)


func test_crates_do_not_warp() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var parts := _warp_pair(host)
	var a: Vector2 = parts[1]
	var crate := RigidBody2D.new()  # any non-Stone body
	var cshape := CollisionShape2D.new()
	var crect := RectangleShape2D.new()
	crect.size = Vector2(40, 40)
	cshape.shape = crect
	crate.add_child(cshape)
	crate.gravity_scale = 0.0
	crate.global_position = a
	host.add_child(crate)
	autofree(crate)
	await wait_physics_frames(15)
	assert_almost_eq(crate.global_position.x, a.x, 5.0, "non-stones stay put")


func test_arrival_fx_spawns_tinted_oneshot_burst() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := LevelLayout.new()
	l.title = "fx"
	var a := EditorGrid.cell_to_world(Vector2i(2, 0))
	l.props.append({"id": "wormhole-blue", "x": a.x, "y": a.y})
	var spawned := PropBuilder.spawn_props(host, l)  # lone → warns (GUT-safe)
	var hole: Wormhole = spawned[0]
	await wait_process_frames(1)  # _ready ran, _sprite found
	hole.play_arrival_fx(Vector2(600, 0))
	var burst: CPUParticles2D = null
	for c in hole.get_children():
		if c is CPUParticles2D:
			burst = c
	assert_not_null(burst, "whoosh burst spawned")
	assert_true(burst.one_shot and burst.emitting)
	assert_gt(burst.color.b, burst.color.r, "tint sampled from the blue portal art (NOTE: art-coupled — re-check if pieces/wormhole-blue.png is repainted warmer)")


func test_warp_arrival_fires_partner_whoosh() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var parts := _warp_pair(host)
	var spawned: Array = parts[0]
	var stone: Stone = load("res://scenes/stone.tscn").instantiate()
	stone.gravity_scale = 0.0
	stone.global_position = (parts[1] as Vector2) + Vector2(-150, 0)
	stone.linear_velocity = Vector2(600, 0)
	host.add_child(stone)
	autofree(stone)
	await wait_physics_frames(30)
	var exit_hole: Wormhole = spawned[1]
	var found := false
	for c in exit_hole.get_children():
		if c is CPUParticles2D:
			found = true
	assert_true(found, "arrival whoosh at the exit portal")


func test_parse_sidecar_powerup_curated_set() -> void:
	assert_eq(Pieces.parse_sidecar("t", {"powerup": "multishot"})["powerup"], "multishot")
	assert_eq(Pieces.parse_sidecar("t", {})["powerup"], "", "absent = plain crate")
	assert_eq(
		Pieces.parse_sidecar("t", {"powerup": "laser_eyes"})["powerup"],
		"",
		"unknown power warns and downgrades to plain"
	)  # warns (GUT-safe)


func test_shipped_crates_route_identically_through_registry() -> void:
	var no_roll := func() -> float: return 0.99
	assert_eq(PowerupRules.route("crate-gold", true, no_roll)["kind"], "refund")
	assert_eq(PowerupRules.route("skull", true, no_roll)["buff"], &"exploding")
	assert_eq(PowerupRules.route("crate-blue", true, no_roll)["buff"], &"multishot")
	assert_eq(PowerupRules.route("crate-green", true, no_roll)["buff"], &"super_bounce")
	assert_eq(PowerupRules.route("crate-wood", true, no_roll)["kind"], "none")
	assert_eq(PowerupRules.route("no-such-crate", true, no_roll)["kind"], "none")
	# ghost mystery: skunk roll preserved (roll below chance, skunk locked)
	var low_roll := func() -> float: return 0.01
	assert_eq(PowerupRules.route("crate-ghost", false, low_roll)["kind"], "skunk")
	# ghost mystery: pool pick when skunk unlocked
	var r := PowerupRules.route("crate-ghost", true, no_roll)
	assert_true(r["kind"] in ["refund", "buff"], "mystery rolls the pool")


func test_parse_sidecar_animatable_strict_bool() -> void:
	assert_false(Pieces.parse_sidecar("t", {})["animatable"], "default off")
	assert_true(Pieces.parse_sidecar("t", {"animatable": true})["animatable"])
	assert_false(Pieces.parse_sidecar("t", {"animatable": 1})["animatable"], "non-bool warns + off")  # warns


func test_props_animation_key_validation() -> void:
	var good := _props_doc([{"id": "wormhole-blue", "x": 0, "y": 0, "behavior": "SPIN", "speed": 0.6}])
	assert_eq(LevelJson.validate(good), "")
	var travel := _props_doc([{"id": "wormhole-blue", "x": 0, "y": 0, "behavior": "WANDER"}])
	assert_eq(LevelJson.validate(travel), "prop 0: bad behavior", "travel verbs rejected for props")
	var junk := _props_doc([{"id": "wormhole-blue", "x": 0, "y": 0, "behavior": 7}])
	assert_eq(LevelJson.validate(junk), "prop 0: bad behavior")
	var dial := _props_doc([{"id": "wormhole-blue", "x": 0, "y": 0, "amplitude": "big"}])
	assert_eq(LevelJson.validate(dial), "prop 0: bad dial")


func test_props_animation_keys_round_trip() -> void:
	var l := LevelLayout.new()
	l.title = "anim-rt"
	l.props.append({"id": "wormhole-blue", "x": 100.0, "y": 500.0, "behavior": "SWAY", "speed": 1.0, "amplitude": 8.0})
	var back := LevelJson.parse(LevelJson.serialize(l))
	assert_not_null(back)
	assert_eq(back.props[0].get("behavior"), "SWAY")
	assert_eq(float(back.props[0].get("amplitude")), 8.0)
	l.props.append({"id": "block-stone", "x": 200.0, "y": 500.0})
	var back2 := LevelJson.parse(LevelJson.serialize(l))
	assert_false(back2.props[1].has("behavior"), "keyless entries stay keyless")
