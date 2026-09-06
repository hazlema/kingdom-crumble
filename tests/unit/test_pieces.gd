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
