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
