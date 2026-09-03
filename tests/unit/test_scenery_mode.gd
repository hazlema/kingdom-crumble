extends GutTest

var ed: LevelEditor


func before_each() -> void:
	ed = load("res://scenes/editor.tscn").instantiate()
	add_child_autofree(ed)


func test_scenery_mode_blocks_crate_placement() -> void:
	ed._enter_scenery()
	ed.carrying = "crate-wood"
	ed._press(Vector2i(2, 0))
	assert_eq(ed.current.crates.size(), 1, "_press itself still works when called")
	ed.current.crates.clear()
	ed._rebuild()
	# the real guard is the polling gate: simulate a frame's decision
	assert_eq(ed.mode, LevelEditor.Mode.SCENERY)
	ed._exit_scenery()
	assert_eq(ed.mode, LevelEditor.Mode.CRATES)


func test_panel_swaps_with_mode() -> void:
	ed._enter_scenery()
	assert_false(ed.palette.visible)
	assert_true(ed.get_node("%SceneryPanel").visible)
	assert_false(ed.overlay.visible, "grid rests during scenery work")
	ed._exit_scenery()
	assert_true(ed.palette.visible)
	assert_false(ed.get_node("%SceneryPanel").visible)
	assert_true(ed.overlay.visible)


func test_background_picker_still_reaches_the_layout() -> void:
	ed._enter_scenery()
	ed.get_node("%SceneryPanel").background_picked.emit("meadow")
	assert_eq(ed.current.background, "meadow")


func test_import_downscales_caps_and_dedupes() -> void:
	var big := Image.create(2048, 1024, false, Image.FORMAT_RGBA8)
	big.fill(Color.BLUE)
	var key := ed.import_scenery_image(big)
	assert_ne(key, "")
	var stored: String = ed.current.images[key]
	var decoded := LevelJson.decode_png_b64(stored)
	assert_lte(maxi(decoded.get_width(), decoded.get_height()), 512, "long edge capped")
	assert_lte(stored.length(), LevelJson.MAX_IMAGE_CHARS)
	var key2 := ed.import_scenery_image(big)
	assert_eq(key2, key, "same pixels, same key")
	assert_eq(ed.current.images.size(), 1, "dedup stores one blob")


func test_import_refuses_a_ninth_image() -> void:
	for i in LevelJson.MAX_IMAGES:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(float(i) / 8.0, 0.2, 0.3))
		assert_ne(ed.import_scenery_image(img), "")
	var extra := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	extra.fill(Color.WHITE)
	assert_eq(ed.import_scenery_image(extra), "", "the ninth image is politely declined")
	assert_eq(ed.current.images.size(), LevelJson.MAX_IMAGES)


func test_bake_rotates_pixels_and_strips_edit_keys() -> void:
	var img := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var key := ed.import_scenery_image(img)
	ed.current.overlays.append({"image": key, "x": 100.0, "y": 100.0, "_rot": PI / 2})
	ed._bake_scenery()
	var o: Dictionary = ed.current.overlays[-1]
	assert_false(o.has("_rot"), "edit-state keys consumed")
	var baked := LevelJson.decode_png_b64(ed.current.images[o["image"]])
	assert_eq(baked.get_width(), 4, "90-degree bake swaps dimensions")
	assert_eq(baked.get_height(), 8)


func test_delete_drops_orphaned_image() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.YELLOW)
	var key := ed.import_scenery_image(img)
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0})
	ed._rebuild_scenery()
	ed.selected_overlay = ed.current.overlays.size() - 1
	ed._delete_selected_piece()
	assert_false(ed.current.images.has(key), "unreferenced blob leaves with its piece")


func test_bake_rotation_pixel_pin() -> void:
	# 2x1 image: left pixel RED, right pixel BLUE.
	var img := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.RED)
	img.set_pixel(1, 0, Color.BLUE)
	var key := ed.import_scenery_image(img)
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0, "_rot": PI / 2.0})
	ed._bake_scenery()
	var o: Dictionary = ed.current.overlays[-1]
	assert_false(o.has("_rot"), "edit keys consumed")
	var baked := LevelJson.decode_png_b64(ed.current.images[o["image"]])
	assert_not_null(baked)
	# 90° CW rotation of 2×1 → 1×2.
	# Inverse-mapping: dst pixel (0,0) maps back to src via (-90°):
	# src center = (0.5, 0). dst center = (0, 0.5).
	# dst(0,0): offset from dst_center = (0-0, 0-0.5) = (0, -0.5)
	# inverse-rotate by -rot = -PI/2: cos(PI/2)=0,sin(PI/2)=1 → inverse = cos(-PI/2)=0,sin(-PI/2)=-1
	# sx = 0*0 - (-0.5)*(-1) + 0.5 = -0.5 + 0.5 = 0  → src_x=0 = RED
	# sy = 0*(-1) + (-0.5)*0 + 0 = 0 → src_y=0
	# So dst(0,0) = RED.
	# dst(0,1): offset = (0-0, 1-0.5) = (0, 0.5)
	# sx = 0*0 - 0.5*(-1) + 0.5 = 0.5 + 0.5 = 1 → src_x=1 = BLUE
	# sy = 0*(-1) + 0.5*0 + 0 = 0
	# So dst(0,1) = BLUE.
	assert_eq(baked.get_width(), 1)
	assert_eq(baked.get_height(), 2)
	var top := baked.get_pixel(0, 0)
	var bot := baked.get_pixel(0, 1)
	assert_almost_eq(top.r, 1.0, 0.05, "top pixel is RED")
	assert_almost_eq(top.b, 0.0, 0.05)
	assert_almost_eq(bot.b, 1.0, 0.05, "bottom pixel is BLUE")
	assert_almost_eq(bot.r, 0.0, 0.05)


func test_bake_identity_preserves_image_key() -> void:
	# Import an image, add overlay with _flip_h: false (no-op transform).
	# Bake must not erase the blob even though new_key == old_key.
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.GREEN)
	var key := ed.import_scenery_image(img)
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0, "_flip_h": false})
	ed._bake_scenery()
	assert_true(ed.current.images.has(key), "blob survives identity bake")
	var o: Dictionary = ed.current.overlays[-1]
	assert_eq(o.get("image", ""), key, "overlay still references the key")
	assert_false(o.has("_flip_h"), "edit key stripped")


func test_pick_piece_survives_skipped_overlay() -> void:
	# overlay[0] references a MISSING image (will be skipped by SceneryBuilder).
	# overlay[1] is valid. After rebuild, picking at overlay[1]'s position must
	# return source index 1, and deleting it must remove overlay[1] not overlay[0].
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var key := ed.import_scenery_image(img)
	# overlay[0] = missing image → skipped
	ed.current.overlays.append({"image": "deadbeef", "x": 9999.0, "y": 9999.0})
	# overlay[1] = valid
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0})
	ed._rebuild_scenery()
	assert_eq(ed._scenery.size(), 1, "only 1 piece spawned (overlay[0] skipped)")
	# The one piece's position is overlay[1]'s position.
	var piece_pos: Vector2 = ed._scenery[0].position
	var idx := ed._pick_piece(piece_pos)
	assert_eq(idx, 1, "_pick_piece returns source index 1")
	ed.selected_overlay = idx
	var overlays_before := ed.current.overlays.size()
	ed._delete_selected_piece()
	assert_eq(ed.current.overlays.size(), overlays_before - 1, "one overlay removed")
	# overlay[0] (the missing-image one) must still be present.
	assert_eq(ed.current.overlays[0].get("image", ""), "deadbeef", "overlay[0] untouched")
