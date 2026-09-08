extends GutTest

# Tests for SceneryBake — audit 2026-09-08, findings 1 & 2.
# Uses SceneryBake statics directly with LevelLayout fixtures so the suite
# runs headlessly without an editor scene.


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Build a minimal LevelLayout with one image (flat-color flat PNG) and one
# overlay with the given edit-state keys.
func _layout_one(img: Image, overlay_extra: Dictionary = {}) -> Array:
	var layout := LevelLayout.new()
	layout.title = "T"
	var png_bytes := img.save_png_to_buffer()
	var b64 := Marshalls.raw_to_base64(png_bytes)
	var key := LevelJson.image_key(png_bytes)
	layout.images[key] = b64
	var o := {"image": key, "x": 0.0, "y": 0.0}
	o.merge(overlay_extra, true)  # overwrite=true so caller's x/y wins
	layout.overlays.append(o)
	return [layout, key]


# ---------------------------------------------------------------------------
# Finding 1: budget-gated rotation
# Audit case: 800×800 flat-color art rotated 45° → bake SKIPS because the
# rotated bounding box is ~1132×1132 (exceeds MAX_IMAGE_DIM=1024).
# The blob and underscore edit keys must be intact; skip counter must be +1.
# ---------------------------------------------------------------------------

func test_finding1_800x800_at_45deg_skips_dimension_budget() -> void:
	# Flat-color 800×800 — compresses very well (far under MAX_IMAGE_CHARS) but
	# once rotated 45° the bounding box becomes ceil(800*√2) ≈ 1132 > 1024.
	var img := Image.create(800, 800, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var result := _layout_one(img, {"_rot": PI / 4.0})
	var layout: LevelLayout = result[0]
	var old_key: String = result[1]
	var old_b64: String = layout.images[old_key]

	var skipped := SceneryBake.bake(layout)

	assert_eq(skipped, 1, "800×800 at 45° must be budget-skipped (skip counter +1)")
	# Original blob preserved.
	assert_true(layout.images.has(old_key), "original blob survives the skip")
	assert_eq(layout.images[old_key], old_b64, "original blob unchanged")
	# Edit key preserved (undo remains possible).
	var o: Dictionary = layout.overlays[0]
	assert_true(o.has("_rot"), "underscore edit key _rot survives the skip")
	assert_eq(float(o["_rot"]), PI / 4.0, "edit key value unchanged")
	# Image key unchanged.
	assert_eq(str(o["image"]), old_key, "overlay still points to original blob")


func test_finding1_exactly_1024x1024_no_rotation_bakes_fine() -> void:
	# A square at exactly the budget edge with no rotation must bake normally
	# (identity transform, no skip).
	var img := Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLUE)
	var result := _layout_one(img, {"_flip_h": false})
	var layout: LevelLayout = result[0]
	var old_key: String = result[1]

	var skipped := SceneryBake.bake(layout)

	assert_eq(skipped, 0, "identity bake at budget edge must not skip")
	# Edit key consumed (bake did run).
	assert_false(layout.overlays[0].has("_flip_h"), "edit key consumed by bake")
	# The image referenced by the overlay must be loadable (within budget).
	var new_key: String = layout.overlays[0]["image"]
	assert_true(layout.images.has(new_key), "baked blob stored")
	var decoded := LevelJson.decode_png_b64(layout.images[new_key])
	assert_not_null(decoded, "baked image is decodable")


func test_finding1_small_art_oblique_rotation_bakes_fine() -> void:
	# A 200×100 image at PI/3 — rotated bbox ~= ceil(200*0.5+100*0.866,
	# 200*0.866+100*0.5) = ceil(186, 223) — both well under 1024.
	var img := Image.create(200, 100, false, Image.FORMAT_RGBA8)
	img.fill(Color.GREEN)
	var result := _layout_one(img, {"_rot": PI / 3.0})
	var layout: LevelLayout = result[0]

	var skipped := SceneryBake.bake(layout)

	assert_eq(skipped, 0, "small art at oblique rotation must bake fine")
	var new_key: String = layout.overlays[0]["image"]
	var decoded := LevelJson.decode_png_b64(layout.images[new_key])
	assert_not_null(decoded, "baked image is decodable")
	assert_lte(decoded.get_width(), LevelJson.MAX_IMAGE_DIM)
	assert_lte(decoded.get_height(), LevelJson.MAX_IMAGE_DIM)
	assert_lte(decoded.get_width() * decoded.get_height(), LevelJson.MAX_IMAGE_PIXELS)


func test_finding1_level_still_parses_after_skip() -> void:
	# After a budget-skip the layout must still serialise and parse cleanly.
	# The old blob in images[] must keep the piece visible (decode succeeds).
	var img := Image.create(800, 800, false, Image.FORMAT_RGBA8)
	img.fill(Color.CYAN)
	var result := _layout_one(img, {"_rot": PI / 4.0})
	var layout: LevelLayout = result[0]
	var old_key: String = result[1]

	SceneryBake.bake(layout)

	# Serialize (strip edit keys) and parse.
	var serialised := LevelJson.serialize(layout)
	var parsed := LevelJson.parse(serialised)
	assert_not_null(parsed, "level still parses after skip: " + LevelJson.last_error)
	# Blob present and decodable from the parsed layout.
	assert_true(parsed.images.has(old_key), "blob round-trips through serialization")
	var decoded := LevelJson.decode_png_b64(parsed.images[old_key])
	assert_not_null(decoded, "old blob decodable — piece remains visible")


# ---------------------------------------------------------------------------
# Finding 2: pivot-true placement after bake
# Audit case: 64×64 image at (1000,400), LOWER_CENTER pivot, 90° rotation →
# post-bake world center must be (1032,400), NOT (1000,368).
# ---------------------------------------------------------------------------

func test_finding2_lower_center_90deg_placement() -> void:
	# Canonical audit reproduction.
	# LOWER_CENTER pivot = index 7: fx = 7%3 = 1 → 0.5;  fy = 7/3 = 2 → 1.0
	# NarfDecor: offset = -Vector2(w*fx, h*fy); centered=false
	#   → image_center = position + Vector2(w*(0.5-fx), h*(0.5-fy))
	# For LOWER_CENTER: image_center = position + Vector2(0, -h*0.5)
	#
	# Unrotated: position=(1000,400), 64×64
	#   image_center = (1000+0, 400-32) = (1000, 368)
	# Rotate 90° around pivot=(1000,400):
	#   delta = (0,-32); Rot(90°): new_delta=(32,0)
	#   new_center = (1032, 400)   ← the audit target
	# Required stored position so image_center = (1032,400):
	#   (1032,400) = pos + (0,-32) → pos = (1032, 432)
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.YELLOW)
	var result := _layout_one(
		img,
		{"x": 1000.0, "y": 400.0, "pivot": "LOWER_CENTER", "_rot": PI / 2.0}
	)
	var layout: LevelLayout = result[0]

	SceneryBake.bake(layout)

	var o: Dictionary = layout.overlays[0]
	var baked_key: String = o["image"]
	var baked := LevelJson.decode_png_b64(layout.images[baked_key])
	assert_not_null(baked, "baked image decodable")

	# Verify world center using the NarfDecor formula:
	# image_center = position + Vector2(bw*(0.5-fx), bh*(0.5-fy))
	# LOWER_CENTER: fx=0.5, fy=1.0 → image_center = (px+0, py-bh*0.5)
	var bw := float(baked.get_width())
	var bh := float(baked.get_height())
	var px: float = float(o["x"])
	var py: float = float(o["y"])
	var world_cx := px + bw * (0.5 - 0.5)   # = px
	var world_cy := py + bh * (0.5 - 1.0)   # = py - bh*0.5

	assert_almost_eq(world_cx, 1032.0, 1.0, "baked world center X must be 1032 (audit target)")
	assert_almost_eq(world_cy, 400.0, 1.0, "baked world center Y must be 400 (audit target)")


func test_finding2_center_pivot_rotation_is_unaffected() -> void:
	# CENTER pivot: pivot_world IS the image center — delta = (0,0) → no change.
	# CENTER: fx=0.5, fy=0.5 → image_center = position + Vector2(0,0) = position
	# After baking 90°: new_center = old_center (rotating (0,0) gives (0,0)).
	# Stored position must still equal the original (500, 300).
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.MAGENTA)
	var result := _layout_one(
		img,
		{"x": 500.0, "y": 300.0, "pivot": "CENTER", "_rot": PI / 2.0}
	)
	var layout: LevelLayout = result[0]

	SceneryBake.bake(layout)

	var o: Dictionary = layout.overlays[0]
	var baked_key: String = o["image"]
	var baked := LevelJson.decode_png_b64(layout.images[baked_key])
	assert_not_null(baked, "baked image decodable")

	# CENTER: fx=0.5, fy=0.5 → image_center = position + (0,0) = position
	var px: float = float(o["x"])
	var py: float = float(o["y"])
	var world_cx := px  # + bw*(0.5-0.5) = px + 0
	var world_cy := py  # + bh*(0.5-0.5) = py + 0

	# For CENTER pivot, rotation around the pivot (which IS the center) is a no-op.
	assert_almost_eq(world_cx, 500.0, 1.0, "CENTER pivot: world center X unchanged")
	assert_almost_eq(world_cy, 300.0, 1.0, "CENTER pivot: world center Y unchanged")


func test_finding2_top_left_pivot_180deg() -> void:
	# TOP_LEFT = 0 → fx=0, fy=0 → offset = (0,0) → image center = (x+w/2, y+h/2)
	# Position x=200, y=100, 80×60 image, 180° rotation.
	# old_center = (200+40, 100+30) = (240, 130)
	# pivot_world = (200, 100)
	# delta = (40, 30)
	# rotate 180°: new_delta = (-40, -30)
	# new_center = (160, 70)
	# new_position = new_center - (80*0, 60*0) = (160, 70)
	var img := Image.create(80, 60, false, Image.FORMAT_RGBA8)
	img.fill(Color.ORANGE)
	var result := _layout_one(
		img,
		{"x": 200.0, "y": 100.0, "pivot": "TOP_LEFT", "_rot": PI}
	)
	var layout: LevelLayout = result[0]

	SceneryBake.bake(layout)

	var o: Dictionary = layout.overlays[0]
	var baked_key: String = o["image"]
	var baked := LevelJson.decode_png_b64(layout.images[baked_key])
	assert_not_null(baked, "baked image decodable")

	var bw := float(baked.get_width())
	var bh := float(baked.get_height())
	var px: float = float(o["x"])
	var py: float = float(o["y"])
	# TOP_LEFT: fx=0, fy=0 → world center = (px + bw*0.5, py + bh*0.5)
	var world_cx := px + bw * 0.5
	var world_cy := py + bh * 0.5

	assert_almost_eq(world_cx, 160.0, 1.5, "TOP_LEFT pivot 180°: world center X = 160")
	assert_almost_eq(world_cy, 70.0, 1.5, "TOP_LEFT pivot 180°: world center Y = 70")


func test_finding2_no_rotation_no_position_change() -> void:
	# A flip without rotation should not change the stored x,y.
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var result := _layout_one(
		img,
		{"x": 100.0, "y": 200.0, "pivot": "LOWER_CENTER", "_flip_h": true}
	)
	var layout: LevelLayout = result[0]

	SceneryBake.bake(layout)

	var o: Dictionary = layout.overlays[0]
	assert_almost_eq(float(o["x"]), 100.0, 0.001, "flip does not change x")
	assert_almost_eq(float(o["y"]), 200.0, 0.001, "flip does not change y")
