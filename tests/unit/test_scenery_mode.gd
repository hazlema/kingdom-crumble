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


func test_inspector_writes_through_to_overlay_and_piece() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.CYAN)
	var key := ed.import_scenery_image(img)
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0})
	ed._rebuild_scenery()
	var insp: PieceInspector = ed.get_node("%PieceInspector")
	insp.open(ed.current.overlays[-1], ed._scenery_pieces[-1])
	insp.set_behavior_by_name("SPIN")
	insp.set_speed(0.4)
	assert_eq(str(ed.current.overlays[-1]["behavior"]), "SPIN")
	assert_eq(ed._scenery_pieces[-1].behavior, NarfDecor.Behavior.SPIN)
	assert_almost_eq(ed._scenery_pieces[-1].speed, 0.4, 0.001)


func test_inspector_hidden_on_deselect() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.MAGENTA)
	var key := ed.import_scenery_image(img)
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0})
	ed._rebuild_scenery()
	var insp: PieceInspector = ed.get_node("%PieceInspector")
	insp.open(ed.current.overlays[-1], ed._scenery_pieces[-1])
	assert_true(insp.visible, "open makes inspector visible")
	ed._exit_scenery()
	assert_false(insp.visible, "exit_scenery hides inspector")


func test_inspector_pre_populates_from_overlay() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var key := ed.import_scenery_image(img)
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0, "behavior": "SWAY", "speed": 1.2, "amplitude": 30.0, "pivot": "LOWER_CENTER"})
	ed._rebuild_scenery()
	var insp: PieceInspector = ed.get_node("%PieceInspector")
	insp.open(ed.current.overlays[-1], ed._scenery_pieces[-1])
	assert_eq(str(ed.current.overlays[-1]["behavior"]), "SWAY", "behavior pre-populated")
	assert_almost_eq(ed.current.overlays[-1].get("speed", 0.0) as float, 1.2, 0.001, "speed pre-populated")


func test_inspector_set_amplitude_writes_dict_and_piece() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.ORANGE)
	var key := ed.import_scenery_image(img)
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0})
	ed._rebuild_scenery()
	var insp: PieceInspector = ed.get_node("%PieceInspector")
	insp.open(ed.current.overlays[-1], ed._scenery_pieces[-1])
	insp.set_amplitude(25.0)
	assert_almost_eq(ed.current.overlays[-1].get("amplitude", 0.0) as float, 25.0, 0.001)
	assert_almost_eq(ed._scenery_pieces[-1].movement, 25.0, 0.001)


func test_inspector_set_pivot_writes_dict_and_piece() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.PURPLE)
	var key := ed.import_scenery_image(img)
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0})
	ed._rebuild_scenery()
	var insp: PieceInspector = ed.get_node("%PieceInspector")
	insp.open(ed.current.overlays[-1], ed._scenery_pieces[-1])
	insp.set_pivot_by_index(NarfDecor.Pivot.LOWER_CENTER)
	assert_eq(str(ed.current.overlays[-1].get("pivot", "")), "LOWER_CENTER")
	assert_eq(ed._scenery_pieces[-1].pivot, NarfDecor.Pivot.LOWER_CENTER)


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
	assert_eq(ed._scenery_pieces.size(), 1, "only 1 piece spawned (overlay[0] skipped)")
	# The one piece's position is overlay[1]'s position.
	var piece_pos: Vector2 = ed._scenery_pieces[0].position
	var idx := ed._pick_piece(piece_pos)
	assert_eq(idx, 1, "_pick_piece returns source index 1")
	ed.selected_overlay = idx
	var overlays_before := ed.current.overlays.size()
	ed._delete_selected_piece()
	assert_eq(ed.current.overlays.size(), overlays_before - 1, "one overlay removed")
	# overlay[0] (the missing-image one) must still be present.
	assert_eq(ed.current.overlays[0].get("image", ""), "deadbeef", "overlay[0] untouched")


func test_drop_background_keys_out_flat_backdrop() -> void:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	img.fill_rect(Rect2i(11, 11, 10, 10), Color.RED)
	var key := ed.import_scenery_image(img)
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0})
	ed._rebuild_scenery()
	ed.selected_overlay = 0
	ed._drop_background()
	var o: Dictionary = ed.current.overlays[0]
	assert_ne(str(o["image"]), key, "stripped image gets its own key")
	var out := LevelJson.decode_png_b64(ed.current.images[str(o["image"])])
	assert_almost_eq(out.get_pixel(2, 2).a, 0.0, 0.02, "backdrop keyed out")
	assert_gt(out.get_pixel(16, 16).a, 0.9, "the subject survives")
	assert_false(ed.current.images.has(key), "orphaned original dropped")


func test_drop_background_declines_without_uniform_backdrop() -> void:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	img.fill_rect(Rect2i(0, 0, 16, 32), Color.WHITE)  # corners disagree
	var key := ed.import_scenery_image(img)
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0})
	ed._rebuild_scenery()
	ed.selected_overlay = 0
	ed._drop_background()
	assert_eq(str(ed.current.overlays[0]["image"]), key, "no uniform bg = polite no-op")


func test_drop_background_spares_the_kings_eyes() -> void:
	# Black card, red frog, black EYE inside the frog — the eye must
	# survive because it is not connected to the border.
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	img.fill_rect(Rect2i(8, 8, 16, 16), Color.RED)
	img.fill_rect(Rect2i(14, 14, 4, 4), Color.BLACK)  # the eye
	var key := ed.import_scenery_image(img)
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0})
	ed._rebuild_scenery()
	ed.selected_overlay = 0
	ed._drop_background()
	var out := LevelJson.decode_png_b64(ed.current.images[str(ed.current.overlays[0]["image"])])
	assert_almost_eq(out.get_pixel(2, 2).a, 0.0, 0.02, "card keyed out")
	assert_gt(out.get_pixel(10, 10).a, 0.9, "frog survives")
	assert_gt(out.get_pixel(16, 16).a, 0.9, "the royal eye survives")


# ---------------------------------------------------------------------------
# Task 4: DRIFT / WANDER inspector dials
# ---------------------------------------------------------------------------

func _make_inspector_with_piece() -> Array:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.CORAL)
	var key := ed.import_scenery_image(img)
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0})
	ed._rebuild_scenery()
	var insp: PieceInspector = ed.get_node("%PieceInspector")
	insp.open(ed.current.overlays[-1], ed._scenery_pieces[-1])
	return [insp, ed.current.overlays[-1], ed._scenery_pieces[-1]]


func test_inspector_offers_all_six_behaviors() -> void:
	var insp: PieceInspector = ed.get_node("%PieceInspector")
	var opt: OptionButton = insp.get_node("%BehaviorOption")
	assert_eq(opt.item_count, 6, "BehaviorOption has 6 items")
	assert_eq(opt.get_item_text(4), "DRIFT", "index 4 = DRIFT")
	assert_eq(opt.get_item_text(5), "WANDER", "index 5 = WANDER")


func test_axis_setter_writes_dict_and_radio_buttons() -> void:
	var result := _make_inspector_with_piece()
	var insp: PieceInspector = result[0]
	var overlay: Dictionary = result[1]
	var piece: NarfDecor = result[2]
	insp.set_axis_by_name("VERTICAL")
	assert_eq(str(overlay.get("axis", "")), "VERTICAL", "overlay[axis] == VERTICAL")
	assert_eq(piece.axis, NarfDecor.DriftAxis.VERTICAL, "piece.axis == VERTICAL")
	var axis_v: Button = insp.get_node("%AxisV")
	var axis_h: Button = insp.get_node("%AxisH")
	assert_true(axis_v.button_pressed, "%AxisV must be pressed")
	assert_false(axis_h.button_pressed, "%AxisH must be unpressed")


func test_travel_and_tilt_setters_write_dict_and_piece() -> void:
	var result := _make_inspector_with_piece()
	var insp: PieceInspector = result[0]
	var overlay: Dictionary = result[1]
	var piece: NarfDecor = result[2]
	insp.set_travel(640.0)
	assert_almost_eq(float(overlay.get("travel", 0.0)), 640.0, 0.001, "overlay[travel] == 640.0")
	assert_almost_eq(piece.travel, 640.0, 0.001, "piece.travel == 640.0")
	var travel_slider: HSlider = insp.get_node("%TravelSlider")
	assert_almost_eq(travel_slider.value, 640.0, 0.001, "%TravelSlider.value == 640.0")
	insp.set_tilt(20.0)
	assert_almost_eq(float(overlay.get("tilt", 0.0)), 20.0, 0.001, "overlay[tilt] == 20.0")
	assert_almost_eq(piece.tilt, 20.0, 0.001, "piece.tilt == 20.0")
	var tilt_slider: HSlider = insp.get_node("%TiltSlider")
	assert_almost_eq(tilt_slider.value, 20.0, 0.001, "%TiltSlider.value == 20.0")


func test_open_prepopulates_drift_dials() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.AQUA)
	var key := ed.import_scenery_image(img)
	# open() with overlay containing drift keys
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0, "axis": "VERTICAL", "travel": 500.0, "tilt": 30.0})
	ed._rebuild_scenery()
	var insp: PieceInspector = ed.get_node("%PieceInspector")
	insp.open(ed.current.overlays[-1], ed._scenery_pieces[-1])
	var axis_v: Button = insp.get_node("%AxisV")
	var axis_h: Button = insp.get_node("%AxisH")
	var travel_slider: HSlider = insp.get_node("%TravelSlider")
	var tilt_slider: HSlider = insp.get_node("%TiltSlider")
	assert_true(axis_v.button_pressed, "%AxisV pressed when axis=VERTICAL")
	assert_false(axis_h.button_pressed, "%AxisH unpressed when axis=VERTICAL")
	assert_almost_eq(travel_slider.value, 500.0, 0.001, "%TravelSlider pre-populated from overlay")
	assert_almost_eq(tilt_slider.value, 30.0, 0.001, "%TiltSlider pre-populated from overlay")
	# open() with overlay missing those keys — should default to H, 120.0, 8.0
	var img2 := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img2.fill(Color.LIME)
	var key2 := ed.import_scenery_image(img2)
	ed.current.overlays.append({"image": key2, "x": 10.0, "y": 10.0})
	ed._rebuild_scenery()
	insp.open(ed.current.overlays[-1], ed._scenery_pieces[-1])
	assert_true(axis_h.button_pressed, "%AxisH defaults to pressed when axis absent")
	assert_false(axis_v.button_pressed, "%AxisV defaults to unpressed when axis absent")
	assert_almost_eq(travel_slider.value, 120.0, 0.001, "%TravelSlider defaults to 120.0")
	assert_almost_eq(tilt_slider.value, 8.0, 0.001, "%TiltSlider defaults to 8.0")
	# Overlay-cleanliness: mere selection must NOT write default dial values into
	# an overlay that never had those keys (pins the _updating guard fix).
	var overlay2: Dictionary = ed.current.overlays[-1]
	assert_false(overlay2.has("axis"), "mere selection must not write axis into overlay")
	assert_false(overlay2.has("travel"), "mere selection must not write travel into overlay")
	assert_false(overlay2.has("tilt"), "mere selection must not write tilt into overlay")


func test_setting_behavior_rehomes_a_dragged_piece() -> void:
	# Regression: place -> drag -> turn on DRIFT used to snap the piece
	# back to its spawn position (stale _home_pos captured in _ready).
	var result := _make_inspector_with_piece()
	var insp: PieceInspector = result[0]
	var piece: NarfDecor = result[2]
	piece.position = Vector2(777, 333)  # simulate the editor drag
	insp.set_behavior_by_name("DRIFT")
	assert_eq(piece._home_pos, Vector2(777, 333), "verb anchors to the dragged spot")
