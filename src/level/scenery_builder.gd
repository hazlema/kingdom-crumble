class_name SceneryBuilder
extends RefCounted

# The ONE place overlays become living NarfDecor pieces — used by both
# the game level and the editor preview (spec §3: editor owns zero
# gameplay code; sharing this builder is how).
#
# Caller adds the returned pieces BEFORE crates so tree order draws
# scenery behind gameplay nodes — no z_index tricks needed.

# Epsilon values tried in order for opaque_to_polygons when the polygon
# point budget is exceeded.  2.0 is the spike value; escalation handles
# pathological checkerboard art.
const _SOLID_EPSILONS := [2.0, 4.0, 8.0]
# Maximum total polygon points across all polygons for one solid overlay.
# Generous: the spike measured a whole building at 7 points.
const _SOLID_POINT_BUDGET := 512


# Returns opaque-region polygons for the given image using BitMap alpha →
# opaque_to_polygons with epsilon escalation.  Returns [] when over budget
# even after escalation (push_warning is the CALLER's job — this function
# is pure so it can be unit-tested without side-effects).
static func solid_polygons(img: Image) -> Array[PackedVector2Array]:
	if img == null:
		return []
	var bm := BitMap.new()
	bm.create_from_image_alpha(img, 0.5)
	var rect := Rect2i(Vector2i.ZERO, img.get_size())
	for eps in _SOLID_EPSILONS:
		var raw: Array = bm.opaque_to_polygons(rect, eps)
		var total_pts := 0
		for poly in raw:
			total_pts += (poly as PackedVector2Array).size()
		if total_pts <= _SOLID_POINT_BUDGET:
			var out: Array[PackedVector2Array] = []
			for poly in raw:
				out.append(poly as PackedVector2Array)
			return out
	return []


static func spawn(parent: Node, layout: LevelLayout) -> Array[NarfDecor]:
	var out: Array[NarfDecor] = []
	if layout.overlays.is_empty():
		return out

	# Decode each REFERENCED image once (audit: decoding unused blobs
	# lets a hostile file spend memory on images nothing displays).
	var referenced: Dictionary = {}
	for entry in layout.overlays:
		var rk: String = (entry as Dictionary).get("image", "")
		if rk != "":
			referenced[rk] = true
	var tex_cache: Dictionary = {}
	var img_cache: Dictionary = {}  # key → Image, needed for solid collision
	for key in layout.images:
		if not referenced.has(key):
			continue
		var img := LevelJson.decode_png_b64(layout.images[key])
		if img == null:
			continue
		var tex := ImageTexture.create_from_image(img)
		tex_cache[key] = tex
		img_cache[key] = img

	var behavior_keys := NarfDecor.Behavior.keys()
	var pivot_keys := NarfDecor.Pivot.keys()
	var axis_keys := NarfDecor.DriftAxis.keys()

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

		# Map axis name; unknown name → warning and skip entry.
		var axis_name: String = entry.get("axis", "HORIZONTAL")
		var axis_idx: int = axis_keys.find(axis_name)
		if axis_idx == -1:
			push_warning("SceneryBuilder: unknown axis '%s' — skipping overlay" % axis_name)
			continue

		var piece := NarfDecor.new()
		# Set texture first so _apply_pivot can compute offset correctly.
		piece.texture = tex_cache[img_key]
		piece.behavior = behavior_idx as NarfDecor.Behavior
		piece.pivot = pivot_idx as NarfDecor.Pivot
		piece.speed = clampf(float(entry.get("speed", 0.25)), 0.0, 10.0)
		# JSON field keeps the old name "amplitude" for save compat.
		piece.movement = clampf(float(entry.get("amplitude", 6.0)), 0.0, 180.0)
		piece.axis = axis_idx as NarfDecor.DriftAxis
		piece.travel = clampf(float(entry.get("travel", 120.0)), 0.0, 2000.0)
		piece.tilt = clampf(float(entry.get("tilt", 8.0)), 0.0, 45.0)
		piece.position = Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)))
		# Linked triggers: hidden pieces wait for a show: action; named
		# pieces are addressable by triggers.
		var hidden_val = (entry as Dictionary).get("hidden", false)
		if hidden_val is bool and hidden_val == true:
			piece.visible = false
		var _nm: String = str((entry as Dictionary).get("name", ""))
		if _nm != "":
			piece.set_meta("overlay_name", _nm)
		piece.add_to_group("scenery")
		piece.set_meta("overlay_index", i)  # source index; used by editor for index alignment
		parent.add_child(piece)
		out.append(piece)

		# Solid overlay: spawn a sibling StaticBody2D whose collision polygon
		# matches the painted alpha shape exactly (the picture IS the physics).
		var is_solid: Variant = (entry as Dictionary).get("solid", false)
		if is_solid is bool and is_solid == true:
			_spawn_solid_body(parent, piece, img_cache[img_key], _nm, hidden_val)

	return out


# Builds a StaticBody2D sibling (same parent as piece) whose CollisionPolygon2D
# nodes map the image alpha into the exact world rect the sprite occupies.
#
# Why sibling, not child?
#   Solid overlays allow sprite-only verbs (SWAY/BOB/SPIN) that animate the
#   NarfDecor's transform.  A child body would inherit those transforms and
#   rotate/oscillate with the sprite — the collision would move.  A sibling
#   has its own static transform anchored to the image top-left, independent
#   of the sprite's animation.
#
# Coordinate mapping:
#   NarfDecor: centered=false, offset = -(w*fx, h*fy) (pivot-based).
#   Image top-left in world space = piece.position + piece.offset.
#   opaque_to_polygons returns top-left-origin image coords.
#   Body position = piece.position + piece.offset so body.global_transform * pt
#   maps image-local coords directly to world space.
static func _spawn_solid_body(
	parent: Node,
	piece: NarfDecor,
	img: Image,
	overlay_name: String,
	hidden_val: Variant
) -> void:
	var polys := solid_polygons(img)
	if polys.is_empty():
		push_warning(
			"SceneryBuilder: overlay '%s' — polygon budget exceeded; spawning visual-only" % overlay_name
		)
		return

	var body := StaticBody2D.new()
	# Anchor: image top-left world position = piece.position + piece.offset
	# (piece.offset was set by _apply_pivot using the texture size + pivot).
	body.position = piece.position + piece.offset
	body.add_to_group("scenery_solid")
	if overlay_name != "":
		body.set_meta("overlay_name", overlay_name)

	for poly in polys:
		var cp := CollisionPolygon2D.new()
		cp.polygon = poly
		body.add_child(cp)

	# Hidden solid overlay: disable physics so a hidden wall has no collision.
	# Re-enabled when _set_scenery_visible is called with on=true.
	# We use process_mode=DISABLED (StaticBody2D ignores physics when disabled).
	if hidden_val is bool and hidden_val == true:
		body.process_mode = Node.PROCESS_MODE_DISABLED

	parent.add_child(body)
