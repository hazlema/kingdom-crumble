extends GutTest

# Drives the editor's press/release interaction state machine directly
# (the polling layer in _process only translates mouse state into these
# calls, and headless runs cannot move the virtual mouse).

var ed: LevelEditor


func before_each() -> void:
	ed = load("res://scenes/editor.tscn").instantiate()
	add_child_autofree(ed)


func test_press_places_carried_asset() -> void:
	ed.carrying = "crate-wood"
	ed._press(Vector2i(2, 0))
	assert_true(ed.occupancy.has(Vector2i(2, 0)))
	assert_eq(ed.carrying, "")
	assert_eq(ed.current.crates.size(), 1)


func test_release_places_carried_asset_after_palette_drag() -> void:
	ed.carrying = "crate-wood"
	ed._release(Vector2i(3, 1), false)
	assert_true(ed.occupancy.has(Vector2i(3, 1)))
	assert_eq(ed.carrying, "")


func test_release_over_ui_keeps_carrying() -> void:
	ed.carrying = "crate-wood"
	ed._release(Vector2i(3, 1), true)
	assert_false(ed.occupancy.has(Vector2i(3, 1)))
	assert_eq(ed.carrying, "crate-wood")


func test_press_out_of_zone_does_not_place() -> void:
	ed.carrying = "crate-wood"
	ed._press(Vector2i(-5, 0))
	assert_eq(ed.current.crates.size(), 0)
	assert_eq(ed.carrying, "crate-wood")


func test_press_on_crate_selects_it() -> void:
	ed.carrying = "crate-wood"
	ed._press(Vector2i(2, 0))
	ed._press(Vector2i(2, 0))
	assert_eq(ed.overlay.selected_cell, Vector2i(2, 0))


func test_drag_moves_crate_to_empty_cell() -> void:
	ed.carrying = "crate-wood"
	ed._press(Vector2i(2, 0))
	ed._press(Vector2i(2, 0))
	ed._release(Vector2i(4, 0), false)
	assert_false(ed.occupancy.has(Vector2i(2, 0)))
	assert_true(ed.occupancy.has(Vector2i(4, 0)))
	assert_eq(ed.current.crates.size(), 1)


func test_release_on_same_cell_keeps_selection_and_position() -> void:
	ed.carrying = "crate-wood"
	ed._press(Vector2i(2, 0))
	ed._press(Vector2i(2, 0))
	ed._release(Vector2i(2, 0), false)
	assert_true(ed.occupancy.has(Vector2i(2, 0)))
	assert_eq(ed.overlay.selected_cell, Vector2i(2, 0))


func test_drag_onto_occupied_cell_does_not_move() -> void:
	ed.carrying = "crate-wood"
	ed._press(Vector2i(2, 0))
	ed.carrying = "crate-gold"
	ed._press(Vector2i(4, 0))
	ed._press(Vector2i(2, 0))
	ed._release(Vector2i(4, 0), false)
	assert_true(ed.occupancy.has(Vector2i(2, 0)))
	assert_true(ed.occupancy.has(Vector2i(4, 0)))


func test_no_dialog_open_by_default() -> void:
	assert_false(ed.menu.any_dialog_open())


func test_menu_chrome_covers_its_button_but_not_the_field() -> void:
	var btn: Control = ed.menu.get_node("MenuBtn")
	assert_true(ed.menu.covers_point(btn.get_global_rect().get_center()))
	assert_false(ed.menu.covers_point(Vector2(-999.0, -999.0)))


func test_field_point_is_not_over_ui() -> void:
	var palette_center: Vector2 = ed.palette.get_global_rect().get_center()
	assert_true(ed._mouse_over_ui(palette_center))
	assert_false(ed._mouse_over_ui(Vector2(-999.0, -999.0)))


func test_ctrl_s_unsaved_opens_save_as() -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.ctrl_pressed = true
	ev.keycode = KEY_S
	ed._unhandled_input(ev)
	await wait_frames(1)
	assert_true(
		ed.menu.get_node("%SaveAsDialog").visible, "ctrl+S with no save path should open Save As"
	)
	ed.menu.get_node("%SaveAsDialog").hide()


func test_load_list_item_activation_emits_load() -> void:
	var list: ItemList = ed.menu.get_node("%LevelList")
	list.clear()
	var idx := list.add_item("Test Level")
	list.set_item_metadata(idx, "user://levels/test_level.json")
	watch_signals(ed.menu)
	list.item_activated.emit(idx)
	assert_signal_emitted_with_parameters(
		ed.menu, "load_requested", ["user://levels/test_level.json"]
	)


func test_delete_removes_selected_crate() -> void:
	ed.carrying = "crate-wood"
	ed._press(Vector2i(2, 0))
	ed._press(Vector2i(2, 0))
	ed._delete_selected()
	assert_false(ed.occupancy.has(Vector2i(2, 0)))
	assert_eq(ed.current.crates.size(), 0)
	assert_eq(ed.overlay.selected_cell, Vector2i(-1, -1))


func test_clear_is_a_new_document() -> void:
	ed.carrying = "crate-wood"
	ed._press(Vector2i(2, 0))
	ed.current.title = "aim"
	ed.current.thumb = "aGVsbG8="
	ed.save_path = "user://levels/aim.json"
	ed._on_clear()
	assert_eq(ed.current.crates.size(), 0)
	assert_eq(ed.current.title, "Untitled", "next Save As names the level itself")
	assert_eq(ed.current.thumb, "", "old portrait does not haunt the new level")
	assert_eq(ed.save_path, "", "Ctrl+S cannot overwrite the previous level")


func test_save_as_renames_a_fork() -> void:
	ed.current.title = "aim"
	await ed._on_save_as("gut_blowup")
	assert_eq(ed.current.title, "gut_blowup", "Save As names the level, always")
	DirAccess.remove_absolute("user://levels/gut_blowup.json")


func test_intro_edit_lands_in_the_layout() -> void:
	ed.menu.intro_edited.emit("Aim for the base of the tower!")
	assert_eq(ed.current.intro, "Aim for the base of the tower!")
	ed.menu.intro_edited.emit("")
	assert_eq(ed.current.intro, "", "clearing empties the field")


func test_crate_trigger_key_matches_runtime_json_coords() -> void:
	# The Info dialog's key must be the exact key the runtime fires on:
	# place a crate, spawn it through LevelBuilder, and compare against
	# the "hit:%d,%d" the level forms from json_coords meta.
	ed.carrying = "skull"
	ed._press(Vector2i(5, 1))
	var host := Node2D.new()
	add_child_autofree(host)
	var crates := LevelBuilder.spawn_crates(
		host, ed.current, true, func(_id: String) -> Texture2D: return null
	)
	var jc: Vector2i = crates[0].get_meta("json_coords")
	var runtime_key := "hit:%d,%d" % [jc.x, jc.y]
	assert_eq(LevelEditor.crate_trigger_key(Vector2i(5, 1)), runtime_key)


func test_crate_info_dialog_shows_type_and_key() -> void:
	ed.carrying = "skull"
	ed._press(Vector2i(5, 1))
	ed._show_crate_info(Vector2i(5, 1))
	assert_true(ed._crate_info.visible, "info dialog pops")
	assert_string_contains(ed._crate_info.dialog_text, "Type: skull")
	assert_string_contains(ed._crate_info.dialog_text, ed._info_key)
	assert_true(ed._info_key.begins_with("hit:"), "key ready for the clipboard")


func test_hidden_overlay_ghosts_in_editor_but_stays_hidden_in_data() -> void:
	# In the game a hidden piece spawns invisible; the editor must ghost
	# it (visible at reduced alpha) so the author can still see/edit it,
	# WITHOUT touching the data that save writes.
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())
	var key := LevelJson.image_key(Marshalls.base64_to_raw(b64))
	ed.current.images[key] = b64
	ed.current.overlays.append({"image": key, "x": 100, "y": 100, "name": "reward", "hidden": true})
	ed._rebuild_scenery()
	var piece: NarfDecor = ed._scenery_pieces[0]
	assert_true(piece.visible, "editor ghosts the hidden piece")
	assert_almost_eq(piece.modulate.a, 0.4, 0.001, "ghost alpha")
	assert_eq(ed.current.overlays[0].get("hidden"), true, "data untouched — save still writes hidden")


func test_load_path_ghosts_hidden_overlays_immediately() -> void:
	# Regression: _rebuild (the load/clear path) used to spawn scenery
	# inline, skipping the ghost pass — hidden pieces stayed invisible
	# until the first EDIT SCENERY visit.
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLUE)
	var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())
	var key := LevelJson.image_key(Marshalls.base64_to_raw(b64))
	ed.current.images[key] = b64
	ed.current.overlays.append({"image": key, "x": 100, "y": 100, "name": "sign2", "hidden": true})
	ed._rebuild()
	var piece: NarfDecor = ed._scenery_pieces[0]
	assert_true(piece.visible, "ghost visible straight from load")
	assert_almost_eq(piece.modulate.a, 0.4, 0.001, "ghost alpha on the load path")


func test_prop_placement_occupies_full_footprint() -> void:
	ed.carrying = "tramp-flat"
	ed._press(Vector2i(4, 0))
	assert_eq(ed.current.props.size(), 1, "prop recorded")
	assert_true(ed.occupancy.has(Vector2i(4, 0)), "anchor cell occupied")
	assert_true(ed.occupancy.has(Vector2i(5, 0)), "second cell occupied")
	assert_eq(ed.occupancy[Vector2i(4, 0)], ed.occupancy[Vector2i(5, 0)], "same node both cells")
	assert_eq(ed.carrying, "")


func test_prop_placement_blocked_by_partial_overlap() -> void:
	ed.carrying = "crate-wood"
	ed._press(Vector2i(5, 0))
	ed.carrying = "tramp-flat"
	ed._press(Vector2i(4, 0))  # cell 5,0 is taken — whole footprint must refuse
	assert_eq(ed.current.props.size(), 0)
	assert_false(ed.occupancy.has(Vector2i(4, 0)))
	assert_eq(ed.carrying, "tramp-flat", "still carrying after refused drop")


func test_crate_cannot_land_on_prop_cell() -> void:
	ed.carrying = "tramp-flat"
	ed._press(Vector2i(4, 0))
	ed.carrying = "crate-wood"
	ed._press(Vector2i(5, 0))
	assert_eq(ed.current.crates.size(), 0, "prop cell refuses crates")


func test_prop_delete_frees_all_cells() -> void:
	ed.carrying = "tramp-flat"
	ed._press(Vector2i(4, 0))
	ed.overlay.selected_cell = Vector2i(5, 0)  # select via the SECOND cell
	ed._delete_selected()
	assert_eq(ed.current.props.size(), 0)
	assert_false(ed.occupancy.has(Vector2i(4, 0)))
	assert_false(ed.occupancy.has(Vector2i(5, 0)))


func test_prop_round_trips_through_rebuild() -> void:
	ed.carrying = "block-stone"
	ed._press(Vector2i(2, 1))
	ed._rebuild()
	assert_true(ed.occupancy.has(Vector2i(2, 1)), "prop survives rebuild")
	assert_false(ed.occupancy[Vector2i(2, 1)] is Crate, "and is not a crate")
