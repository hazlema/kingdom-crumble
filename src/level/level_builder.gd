class_name LevelBuilder
extends RefCounted

# The ONE place layouts become crates — used by the game level and the
# editor preview alike (spec §3: editor owns zero gameplay code).

const CRATE_SCENE := preload("res://scenes/crate.tscn")

static func spawn_crates(parent: Node, layout: LevelLayout, frozen: bool,
		tex_lookup: Callable) -> Array[Crate]:
	var out: Array[Crate] = []
	for c in layout.crates:
		var crate: Crate = CRATE_SCENE.instantiate()
		crate.position = Vector2(c["x"], c["y"])
		crate.freeze = frozen
		crate.add_to_group("crates")
		parent.add_child(crate)
		var _tex: Texture2D = tex_lookup.call(c["type"])
		if _tex == null and c["type"] != "crate-wood":
			push_warning("Unknown crate type: %s" % c["type"])
		crate.apply_type(c["type"], _tex)
		out.append(crate)
	return out
