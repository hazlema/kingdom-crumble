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


func test_rebuild_twice_leaves_exactly_one_prop_body() -> void:
	# Regression: prop StaticBody2D nodes were not freed by _rebuild, so
	# calling _rebuild twice left a phantom body from the first pass.
	ed.carrying = "block-stone"
	ed._press(Vector2i(2, 1))
	assert_eq(ed.current.props.size(), 1, "prop recorded before first rebuild")
	ed._rebuild()
	ed._rebuild()
	# _spawned_props tracks the live prop bodies (queue_free defers removal
	# from the scene tree, so we check the tracking array, not get_children).
	assert_eq(ed._spawned_props.size(), 1, "exactly one prop body tracked after two rebuilds — no phantom leak")


func test_clear_removes_all_prop_bodies() -> void:
	# Regression: CLEAR left phantom prop StaticBody2D nodes on screen.
	ed.carrying = "block-stone"
	ed._press(Vector2i(2, 1))
	# Simulate clear: replace layout and rebuild (same as _on_clear).
	ed.current = LevelLayout.new()
	ed._rebuild()
	# _spawned_props must be empty after clearing the layout.
	assert_eq(ed._spawned_props.size(), 0, "no prop bodies tracked after clear")
	# Occupancy must also be empty (no prop cells).
	for k in ed.occupancy:
		assert_false(ed.occupancy[k] is StaticBody2D, "occupancy has no prop entries after clear")


func test_delete_prop_with_unknown_registry_id_does_not_crash() -> void:
	# Regression: _delete_prop crashed if prop_id vanished from Pieces registry.
	# After fix: registry-free sweep erases all occupancy cells pointing at the body.
	ed.carrying = "block-stone"
	ed._press(Vector2i(3, 2))
	var body: Node2D = ed.occupancy[Vector2i(3, 2)]
	body.set_meta("prop_id", "gone:piece")
	ed.overlay.selected_cell = Vector2i(3, 2)
	ed._delete_selected()
	# All occupancy cells pointing at the body are erased, even with unknown id.
	assert_false(ed.occupancy.has(Vector2i(3, 2)), "anchor cell erased after unknown-id delete")
	assert_eq(ed.overlay.selected_cell, Vector2i(-1, -1), "selection cleared")


func test_prop_selection_ring_spans_footprint_from_any_cell() -> void:
	ed.carrying = "tramp-flat"
	ed._press(Vector2i(4, 0))
	ed._press(Vector2i(5, 0))  # click the SECOND cell
	assert_eq(ed.overlay.selected_cell, Vector2i(4, 0), "selection snaps to the anchor")
	assert_eq(ed.overlay.selected_cells, Vector2i(2, 1), "ring spans the footprint")
	ed.carrying = "crate-wood"
	ed._press(Vector2i(8, 0))
	ed._press(Vector2i(8, 0))
	assert_eq(ed.overlay.selected_cells, Vector2i(1, 1), "crates stay 1x1")


func test_prop_drag_moves_whole_footprint() -> void:
	ed.carrying = "tramp-flat"
	ed._press(Vector2i(4, 0))
	ed._press(Vector2i(5, 0))          # grab by the second cell
	ed._release(Vector2i(9, 0), false)  # drag +4 columns
	assert_true(ed.occupancy.has(Vector2i(8, 0)), "new anchor occupied")
	assert_true(ed.occupancy.has(Vector2i(9, 0)), "new second cell occupied")
	assert_false(ed.occupancy.has(Vector2i(4, 0)), "old cells freed")
	assert_false(ed.occupancy.has(Vector2i(5, 0)))
	var w := EditorGrid.cell_to_world(Vector2i(8, 0))
	assert_eq(float(ed.current.props[0]["x"]), w.x, "data moved with the node")
	assert_eq(ed.occupancy[Vector2i(8, 0)].get_meta("anchor_cell"), Vector2i(8, 0), "meta updated")


func test_prop_move_blocked_by_overlap_stays_put() -> void:
	ed.carrying = "crate-wood"
	ed._press(Vector2i(9, 0))
	ed.carrying = "tramp-flat"
	ed._press(Vector2i(4, 0))
	ed._press(Vector2i(4, 0))
	ed._release(Vector2i(8, 0), false)  # footprint would hit the crate at (9,0)
	assert_true(ed.occupancy.has(Vector2i(4, 0)), "blocked move leaves the piece")
	assert_true(ed.occupancy.has(Vector2i(5, 0)))
	assert_false(ed.occupancy.has(Vector2i(8, 0)), "no half-move")
	var w := EditorGrid.cell_to_world(Vector2i(4, 0))
	assert_eq(float(ed.current.props[0]["x"]), w.x, "data untouched")


func test_selecting_animatable_prop_opens_reduced_inspector() -> void:
	ed.carrying = "wormhole-blue"
	ed._press(Vector2i(4, 0))
	ed._press(Vector2i(4, 0))  # select it
	var insp: Control = ed.get_node("%PieceInspector")
	assert_true(insp.visible, "inspector opens for animatable prop")
	insp.set_behavior_by_name("SPIN")
	insp.set_speed(1.2)
	assert_eq(ed.current.props[0].get("behavior"), "SPIN", "writes land in the level data")
	assert_eq(float(ed.current.props[0].get("speed")), 1.2)


func test_selecting_non_animatable_prop_keeps_inspector_closed() -> void:
	ed.carrying = "block-stone"
	ed._press(Vector2i(4, 0))
	ed._press(Vector2i(4, 0))
	var insp: Control = ed.get_node("%PieceInspector")
	assert_false(insp.visible, "statics are not animatable")


func test_move_prop_preserves_animation_keys() -> void:
	ed.carrying = "wormhole-blue"
	ed._press(Vector2i(4, 0))
	ed.current.props[0]["behavior"] = "SWAY"
	ed.current.props[0]["amplitude"] = 8.0
	ed._press(Vector2i(4, 0))
	ed._release(Vector2i(9, 0), false)
	assert_eq(ed.current.props[0].get("behavior"), "SWAY", "drag keeps the animation")
	assert_eq(float(ed.current.props[0].get("amplitude")), 8.0)
	var w := EditorGrid.cell_to_world(Vector2i(9, 0))
	assert_eq(float(ed.current.props[0]["x"]), w.x, "and still moved")


func test_rebuild_preserves_animation_keys() -> void:
	# Regression: _rebuild() discarded animation keys (behavior, speed, amplitude)
	# on every rebuild (any crate place/move/delete). After fix: all keys preserved.
	ed.carrying = "wormhole-blue"
	ed._press(Vector2i(4, 0))
	ed.current.props[0]["behavior"] = "SPIN"
	ed.current.props[0]["speed"] = 2.5
	ed.current.props[0]["amplitude"] = 12.0
	ed.carrying = "crate-wood"
	ed._press(Vector2i(2, 0))  # Placing a crate triggers _rebuild
	assert_eq(ed.current.props[0].get("behavior"), "SPIN", "behavior survives rebuild")
	assert_eq(float(ed.current.props[0].get("speed")), 2.5, "speed survives rebuild")
	assert_eq(float(ed.current.props[0].get("amplitude")), 12.0, "amplitude survives rebuild")


# ---------------------------------------------------------------------------
# Task 4 — ONE selection rule
# ---------------------------------------------------------------------------

func test_clear_path_resets_selection_and_hides_inspector() -> void:
	# (a) clear-path: select an animatable prop, then clear the level.
	# After the clear+rebuild, selection must be "none" and inspector hidden.
	ed.carrying = "wormhole-blue"
	ed._press(Vector2i(4, 0))
	ed._press(Vector2i(4, 0))  # select it — opens inspector
	var insp: Control = ed.get_node("%PieceInspector")
	assert_true(insp.visible, "inspector open after selecting animatable prop")
	# Simulate clear (same as _on_clear)
	ed.current = LevelLayout.new()
	ed._rebuild()
	assert_false(insp.visible, "inspector hidden after clear+rebuild")
	assert_eq(ed.selection.get("kind", ""), "none", "selection kind is none after clear")


func test_inspector_survives_rebuild_after_selecting_animatable_prop() -> void:
	# (b) rebuild re-resolution: select an animatable prop, then place a
	# crate (triggers _rebuild). Inspector must STILL be open and writes must
	# land in the CURRENT (fresh) props entry.
	#
	# This test MUST FAIL against today's close-on-rebuild code; it will
	# pass only after _sync_views re-resolution is implemented.
	ed.carrying = "wormhole-blue"
	ed._press(Vector2i(4, 0))
	ed._press(Vector2i(4, 0))  # select wormhole → opens inspector (reduced mode)
	var insp: PieceInspector = ed.get_node("%PieceInspector")
	assert_true(insp.visible, "inspector open before rebuild")
	# Trigger a rebuild by placing a crate in a different cell.
	ed.carrying = "crate-wood"
	ed._press(Vector2i(2, 0))
	# After rebuild, inspector must still be open (re-resolved to fresh prop).
	assert_true(insp.visible, "inspector still open after rebuild (re-resolution)")
	# Writes after rebuild must land in the CURRENT props entry.
	insp.set_behavior_by_name("SPIN")
	insp.set_speed(1.5)
	assert_eq(ed.current.props[0].get("behavior"), "SPIN", "write lands in fresh props entry")
	assert_almost_eq(float(ed.current.props[0].get("speed", 0.0)), 1.5, 0.001, "speed write lands in fresh entry")


func test_document_swap_clears_selection_no_adoption() -> void:
	# Pin: select a crate at cell (3,0), then load a different document
	# that has a different crate at the same cell. The new crate must NOT
	# be auto-adopted by the stale selection — selection must clear first,
	# so the ring and inspector stay clean until an explicit re-click.
	ed.carrying = "crate-wood"
	ed._press(Vector2i(3, 0))
	ed._press(Vector2i(3, 0))  # select it
	var insp: Control = ed.get_node("%PieceInspector")
	assert_eq(ed.selection.get("kind"), "cell", "crate selected before load")

	# Create a different document with a different crate type at the same cell.
	var doc2 := LevelLayout.new()
	doc2.title = "other"
	var w := EditorGrid.cell_to_world(Vector2i(3, 0))
	doc2.crates.append({"x": w.x, "y": w.y, "type": "skull"})

	# Save doc2 to disk and load it through the real _on_load path.
	var path := LevelStore.save_user(doc2, "test_doc_swap_pin")
	assert_ne(path, "", "save succeeded")

	# Load doc2 (triggers clear + _rebuild).
	ed._on_load(path)

	# Verify: selection cleared, inspector hidden, but crate occupies the cell.
	assert_eq(ed.selection.get("kind"), "none", "selection cleared on document swap")
	assert_false(insp.visible, "inspector hidden after load")
	assert_true(ed.occupancy.has(Vector2i(3, 0)), "new crate occupies the cell")
	# Verify the new crate is skull, not the old wood.
	var c: Crate = ed.occupancy[Vector2i(3, 0)]
	assert_eq(c.type_id, "skull", "new document's crate adopted, not old selection")

	# Clean up.
	DirAccess.remove_absolute(path)


func test_exit_scenery_restores_crate_modulate_to_full() -> void:
	# Pin: crates must be dimmed (α=0.8) while in SCENERY mode and fully
	# restored (α=1.0) after leaving — the switch_tool ordering fix ensures
	# _rebuild_scenery() sees CRATES mode when called from exit().
	ed.carrying = "crate-wood"
	ed._press(Vector2i(2, 0))
	ed._enter_scenery()
	assert_almost_eq(ed._spawned[0].modulate.a, 0.8, 0.001, "crate dimmed in SCENERY mode")
	ed._exit_scenery()
	assert_almost_eq(ed._spawned[0].modulate.a, 1.0, 0.001, "crate restored after leaving SCENERY")
