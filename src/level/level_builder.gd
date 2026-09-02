class_name LevelBuilder
extends RefCounted

# The ONE place layouts become crates — used by the game level and the
# editor preview alike (spec §3: editor owns zero gameplay code).

const CRATE_SCENE := preload("res://scenes/crate.tscn")


static func spawn_crates(
	parent: Node, layout: LevelLayout, frozen: bool, tex_lookup: Callable
) -> Array[Crate]:
	var out: Array[Crate] = []
	for c in layout.crates:
		var crate: Crate = CRATE_SCENE.instantiate()
		crate.position = Vector2(c["x"], c["y"])
		crate.freeze = frozen
		crate.add_to_group("crates")
		parent.add_child(crate)
		# Spawn at rest: with per-tier bounce (chill = 0.6) live stacks
		# trampoline against each other forever. Asleep they are statues
		# until the first real impact wakes them. The physics server
		# wakes fresh bodies on their first step, so tuck them back in
		# a couple of ticks later.
		if not frozen:
			crate.sleeping = true
			_sleep_when_registered(crate, parent.get_tree())
		var _tex: Texture2D = tex_lookup.call(c["type"])
		if _tex == null and c["type"] != "crate-wood":
			push_warning("Unknown crate type: %s" % c["type"])
		crate.apply_type(c["type"], _tex)
		out.append(crate)
	return out


static func _sleep_when_registered(crate: Crate, tree: SceneTree) -> void:
	# Count only UNPAUSED physics frames. The intro dialog pauses the
	# tree in the same stack as spawning, and physics_frame keeps firing
	# under pause while the space is NOT stepping — the tuck-in burned
	# away before the server's first real step ever woke the crate, so
	# floaters fell the moment the dialog closed.
	var steps := 0
	while steps < 2:
		await tree.physics_frame
		if not tree.paused:
			steps += 1
	if is_instance_valid(crate) and not crate.freeze:
		crate.sleeping = true
