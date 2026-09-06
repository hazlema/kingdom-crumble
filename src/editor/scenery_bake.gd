# Save-time scenery baking + image processing. Moved verbatim from
# level_editor.gd (editor-split task 1) — pure functions of the layout,
# no editor state.
#
# NOTE: _bake_scenery had one implicit self reference: the live-piece
# visual reset block (piece.rotation = 0.0 etc.) called _piece_for_overlay,
# an instance method on LevelEditor. That block is NOT pure bake logic —
# it resets live editor nodes after bake. It has been left in the
# LevelEditor._bake_scenery() forwarder rather than moved here.
class_name SceneryBake
extends RefCounted


# Consume edit-state transforms into the raster, re-key the blob.
# Transform order: flip → scale → rotate.
# Returns the count of overlays skipped due to the image cap.
# This is the contract formerly held by LevelEditor._bake_scenery().
static func bake(layout: LevelLayout) -> int:
	var skipped := 0
	# Build reference counts for all image keys.
	var ref_count: Dictionary = {}
	for entry in layout.overlays:
		var k: String = (entry as Dictionary).get("image", "")
		if k != "":
			ref_count[k] = ref_count.get(k, 0) + 1

	for i in layout.overlays.size():
		var o: Dictionary = layout.overlays[i]
		var has_edits := false
		for k in o:
			if (k as String).begins_with("_"):
				has_edits = true
				break
		if not has_edits:
			continue

		var old_key: String = o.get("image", "")
		if old_key == "" or not layout.images.has(old_key):
			# Strip keys even on missing image to stay consistent.
			_strip_edit_keys(o)
			continue

		var img := LevelJson.decode_png_b64(layout.images[old_key])
		if img == null:
			_strip_edit_keys(o)
			continue

		# Apply flip (pixel-level, in place).
		if o.get("_flip_h", false):
			img.flip_x()
		if o.get("_flip_v", false):
			img.flip_y()

		# Apply scale via resize.
		var sc: float = o.get("_scale", 1.0)
		if not is_equal_approx(sc, 1.0):
			var nw := maxi(1, roundi(img.get_width() * sc))
			var nh := maxi(1, roundi(img.get_height() * sc))
			img.resize(nw, nh, Image.INTERPOLATE_LANCZOS)

		# Apply rotation via inverse-mapping into a rotated bounding box.
		var rot: float = o.get("_rot", 0.0)
		if not is_equal_approx(fmod(rot, TAU), 0.0):
			img = _rotate_image(img, rot)

		# Re-encode and cap.
		var cap_result := _cap_image_to_max(img)
		var png_bytes: PackedByteArray = cap_result[0]
		var new_b64: String = cap_result[1]
		var new_key := LevelJson.image_key(png_bytes)

		if new_key != old_key:
			# Would storing this new blob exceed the image cap?
			# Allow only if old_key is being orphaned (net count stays same).
			var old_still_needed: bool = ref_count.get(old_key, 0) > 1
			if not layout.images.has(new_key) and old_still_needed and layout.images.size() >= LevelJson.MAX_IMAGES:
				# Cap hit: skip bake for this overlay, keep its underscore edit-state.
				push_warning("SceneryBake: skipping overlay %d — image cap full" % i)
				skipped += 1
				continue
			# Store the new blob (dedup: might already exist under new_key).
			if not layout.images.has(new_key):
				layout.images[new_key] = new_b64
			# Update this overlay's key.
			o["image"] = new_key
			# Move the reference in the ledger: +new, -old. (Audit P1:
			# forgetting the increment let a later bake orphan-erase an
			# image this overlay still pointed at.)
			ref_count[new_key] = ref_count.get(new_key, 0) + 1
			ref_count[old_key] = ref_count.get(old_key, 1) - 1
			if ref_count.get(old_key, 0) <= 0:
				layout.images.erase(old_key)

		# Strip edit-state keys (always — identity bake still consumed them).
		_strip_edit_keys(o)

	return skipped


static func _strip_edit_keys(o: Dictionary) -> void:
	var to_remove: Array[String] = []
	for k in o:
		if (k as String).begins_with("_"):
			to_remove.append(k)
	for k in to_remove:
		o.erase(k)


# Pure-GDScript inverse-mapping rotation.
# Computes the rotated bounding box size, then for each destination pixel
# inverse-rotates back to source space and samples with bilinear interpolation.
# Transparent pixels outside the source rect become Color(0,0,0,0).
static func _rotate_image(src: Image, rot: float) -> Image:
	var sw := src.get_width()
	var sh := src.get_height()
	src.convert(Image.FORMAT_RGBA8)

	# Rotated bounding box: for a rectangle rotated by `rot`, the enclosing
	# axis-aligned box has dimensions:
	#   w' = |w·cos(r)| + |h·sin(r)|
	#   h' = |w·sin(r)| + |h·cos(r)|
	var abs_cos := absf(cos(rot))
	var abs_sin := absf(sin(rot))
	# ceili guards the half-pixel clip at odd angles; the tiny epsilon
	# guards ceili against cos(PI/2)'s 6e-17 dust inflating exact
	# 90-degree boxes by a whole pixel.
	var dw := maxi(1, ceili(sw * abs_cos + sh * abs_sin - 0.001))
	var dh := maxi(1, ceili(sw * abs_sin + sh * abs_cos - 0.001))

	var dst := Image.create(dw, dh, false, Image.FORMAT_RGBA8)
	dst.fill(Color(0, 0, 0, 0))

	# Centers.
	var cx_src := (sw - 1) * 0.5
	var cy_src := (sh - 1) * 0.5
	var cx_dst := (dw - 1) * 0.5
	var cy_dst := (dh - 1) * 0.5

	var cos_r := cos(-rot)  # inverse rotation
	var sin_r := sin(-rot)

	for dy in dh:
		for dx in dw:
			# Vector from dst center.
			var fx := dx - cx_dst
			var fy := dy - cy_dst
			# Inverse-rotate.
			var sx := fx * cos_r - fy * sin_r + cx_src
			var sy := fx * sin_r + fy * cos_r + cy_src
			# Bilinear sample.
			var color := _bilinear_sample(src, sx, sy, sw, sh)
			dst.set_pixel(dx, dy, color)

	return dst


static func _bilinear_sample(
	src: Image, sx: float, sy: float, sw: int, sh: int
) -> Color:
	# Clamp to avoid out-of-bounds — transparent outside source.
	if sx < -0.5 or sy < -0.5 or sx > sw - 0.5 or sy > sh - 0.5:
		return Color(0, 0, 0, 0)

	# Compute unclamped floor first so tx/ty are always in [0,1).
	var x0f := floorf(sx)
	var y0f := floorf(sy)
	var tx: float = sx - x0f
	var ty: float = sy - y0f
	var x0 := clampi(int(x0f), 0, sw - 1)
	var y0 := clampi(int(y0f), 0, sh - 1)
	var x1 := clampi(int(x0f) + 1, 0, sw - 1)
	var y1 := clampi(int(y0f) + 1, 0, sh - 1)

	var c00 := src.get_pixel(x0, y0)
	var c10 := src.get_pixel(x1, y0)
	var c01 := src.get_pixel(x0, y1)
	var c11 := src.get_pixel(x1, y1)

	# Premultiplied-alpha bilinear: lerp premultiplied channels, then unpremultiply.
	# Prevents transparent-black fringing at alpha boundaries.
	var a00 := c00.a
	var a10 := c10.a
	var a01 := c01.a
	var a11 := c11.a
	var r := c00.r * a00 * (1 - tx) * (1 - ty) + c10.r * a10 * tx * (1 - ty) + c01.r * a01 * (1 - tx) * ty + c11.r * a11 * tx * ty
	var g := c00.g * a00 * (1 - tx) * (1 - ty) + c10.g * a10 * tx * (1 - ty) + c01.g * a01 * (1 - tx) * ty + c11.g * a11 * tx * ty
	var b := c00.b * a00 * (1 - tx) * (1 - ty) + c10.b * a10 * tx * (1 - ty) + c01.b * a01 * (1 - tx) * ty + c11.b * a11 * tx * ty
	var a := a00 * (1 - tx) * (1 - ty) + a10 * tx * (1 - ty) + a01 * (1 - tx) * ty + a11 * tx * ty
	if a < 0.00001:
		return Color(0, 0, 0, 0)
	return Color(r / a, g / a, b / a, a)


# Shared size-cap: halve the image until its base64 fits MAX_IMAGE_CHARS.
# Returns [png_bytes: PackedByteArray, b64: String]. Used by import AND bake
# so a baked blob can never bypass the cap the import path enforces.
static func _cap_image_to_max(img: Image) -> Array:
	var png_bytes := img.save_png_to_buffer()
	var b64 := Marshalls.raw_to_base64(png_bytes)
	while b64.length() > LevelJson.MAX_IMAGE_CHARS:
		var cw := img.get_width()
		var ch := img.get_height()
		if cw <= 1 and ch <= 1:
			break
		img.resize(maxi(1, cw / 2), maxi(1, ch / 2), Image.INTERPOLATE_LANCZOS)
		png_bytes = img.save_png_to_buffer()
		b64 = Marshalls.raw_to_base64(png_bytes)
	return [png_bytes, b64]


# The darkroom, in-engine (owner: "drop background"): flat AI-image
# backdrops (the classic black/white card) become transparency. The
# four corners vote on the background color; if they disagree there is
# no uniform background and the op declines. Destructive by design —
# recovery is delete + re-import (the source file never left the disk).
static func _strip_background(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	if w < 4 or h < 4:
		return null
	var corners: Array[Color] = [
		img.get_pixel(1, 1),
		img.get_pixel(w - 2, 1),
		img.get_pixel(1, h - 2),
		img.get_pixel(w - 2, h - 2),
	]
	var bg := Color(0, 0, 0, 0)
	for c in corners:
		bg += c
	bg *= 0.25
	for c in corners:
		if Vector3(c.r - bg.r, c.g - bg.g, c.b - bg.b).length() > 0.15:
			return null
	# Flood-fill from the border: only background CONNECTED to the frame
	# is keyed — a king's black pupils on a black card stay landlocked
	# and untouched (the global-distance version blinded the poor frog).
	var dist := PackedFloat32Array()
	dist.resize(w * h)
	for y in h:
		for x in w:
			var px := img.get_pixel(x, y)
			dist[y * w + x] = Vector3(px.r - bg.r, px.g - bg.g, px.b - bg.b).length()
	var keyed := PackedByteArray()
	keyed.resize(w * h)
	var queue: Array[int] = []
	for x in w:
		for y: int in [0, h - 1]:
			var i := y * w + x
			if dist[i] < 0.35 and keyed[i] == 0:
				keyed[i] = 1
				queue.append(i)
	for y in h:
		for x: int in [0, w - 1]:
			var i := y * w + x
			if dist[i] < 0.35 and keyed[i] == 0:
				keyed[i] = 1
				queue.append(i)
	while not queue.is_empty():
		var i: int = queue.pop_back()
		var ix := i % w
		var iy := i / w
		for n in [[ix + 1, iy], [ix - 1, iy], [ix, iy + 1], [ix, iy - 1]]:
			var nx: int = n[0]
			var ny: int = n[1]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var ni := ny * w + nx
			if keyed[ni] == 0 and dist[ni] < 0.35:
				keyed[ni] = 1
				queue.append(ni)
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var i := y * w + x
			var px := img.get_pixel(x, y)
			if keyed[i] == 0:
				out.set_pixel(x, y, px)
				continue
			var a := clampf((dist[i] - 0.10) / 0.25, 0.0, 1.0) * px.a
			if a <= 0.001:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				# Unmix the background's contribution from edge blends.
				var r := clampf((px.r - (1.0 - a) * bg.r) / a, 0.0, 1.0)
				var g := clampf((px.g - (1.0 - a) * bg.g) / a, 0.0, 1.0)
				var b := clampf((px.b - (1.0 - a) * bg.b) / a, 0.0, 1.0)
				out.set_pixel(x, y, Color(r, g, b, a))
	return out
