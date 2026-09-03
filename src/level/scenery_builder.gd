class_name SceneryBuilder
extends RefCounted

# The ONE place overlays become living NarfDecor pieces — used by both
# the game level and the editor preview (spec §3: editor owns zero
# gameplay code; sharing this builder is how).
#
# Caller adds the returned pieces BEFORE crates so tree order draws
# scenery behind gameplay nodes — no z_index tricks needed.


static func spawn(parent: Node, layout: LevelLayout) -> Array[NarfDecor]:
	var out: Array[NarfDecor] = []
	if layout.overlays.is_empty():
		return out

	# Decode each distinct image once.
	var tex_cache: Dictionary = {}
	for key in layout.images:
		var img := LevelJson.decode_png_b64(layout.images[key])
		if img == null:
			continue
		var tex := ImageTexture.create_from_image(img)
		tex_cache[key] = tex

	var behavior_keys := NarfDecor.Behavior.keys()
	var pivot_keys := NarfDecor.Pivot.keys()

	for i in layout.overlays.size():
		var entry: Dictionary = layout.overlays[i]
		var img_key: String = entry.get("image", "")
		if not tex_cache.has(img_key):
			# missing or broken image — skip silently
			continue

		# Map behavior name; unknown verb → warning and skip entry.
		var behavior_name: String = entry.get("behavior", "NONE")
		var behavior_idx: int = behavior_keys.find(behavior_name)
		if behavior_idx == -1:
			push_warning("SceneryBuilder: unknown behavior '%s' — skipping overlay" % behavior_name)
			continue

		# Map pivot name; unknown name → warning and skip entry.
		var pivot_name: String = entry.get("pivot", "CENTER")
		var pivot_idx: int = pivot_keys.find(pivot_name)
		if pivot_idx == -1:
			push_warning("SceneryBuilder: unknown pivot '%s' — skipping overlay" % pivot_name)
			continue

		var piece := NarfDecor.new()
		# Set texture first so _apply_pivot can compute offset correctly.
		piece.texture = tex_cache[img_key]
		piece.behavior = behavior_idx as NarfDecor.Behavior
		piece.pivot = pivot_idx as NarfDecor.Pivot
		piece.speed = clampf(float(entry.get("speed", 0.25)), 0.0, 10.0)
		# JSON field keeps the old name "amplitude" for save compat.
		piece.movement = clampf(float(entry.get("amplitude", 6.0)), 0.0, 180.0)
		piece.position = Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)))
		piece.add_to_group("scenery")
		piece.set_meta("overlay_index", i)  # source index; used by editor for index alignment
		parent.add_child(piece)
		out.append(piece)

	return out
