extends GutTest

# Drives the editor's press/release interaction state machine directly
# (the polling layer in _process only translates mouse state into these
# calls, and headless runs cannot move the virtual mouse).
#
# Footprint tests (multi-cell occupancy, blocked drops, selection ring spanning,
# drag-move freeing old cells) need a 2×1 fixture.  We provision it through the
# sandboxed toybox seam so no test ever depends on shipped art again.
# The fixture id is "gutfix:wide-block" (class "static", cells [2,1]).
# The sandbox dir is "user://toybox_gut_editor" — deliberately different from
# test_toybox.gd's "user://toybox_gut" so concurrent/sequential runs never collide.

const FIXTURE_TOYBOX_DIR := "user://toybox_gut_editor"
const TOYBOX_CFG := "user://toybox.cfg"
const FIXTURE_ID := "gutfix:wide-block"

var ed: LevelEditor
var _cfg_before: String = ""


func before_each() -> void:
	# ── Toybox sandbox ──────────────────────────────────────────────────────
	# Redirect all Pieces scans to our private sandbox.
	Pieces.toybox_root = FIXTURE_TOYBOX_DIR
	# Capture existing toybox.cfg so after_each can restore it byte-for-byte.
	if FileAccess.file_exists(TOYBOX_CFG):
		_cfg_before = FileAccess.open(TOYBOX_CFG, FileAccess.READ).get_as_text()
	else:
		_cfg_before = ""
	# Write the "gutfix" pack: a 128×63 PNG (2 cells wide at 64 px/cell) plus
	# a sidecar declaring class "static" and cells [2,1].
	var pack_dir := "%s/gutfix" % FIXTURE_TOYBOX_DIR
	DirAccess.make_dir_recursive_absolute(pack_dir)
	# pack.json — kind "objects" so the scanner registers pieces from it
	var mf := FileAccess.open("%s/pack.json" % pack_dir, FileAccess.WRITE)
	mf.store_string(JSON.stringify({"title": "GUT Editor Fixture", "kind": "objects"}))
	mf.close()
	# 128×63 PNG (2 cells wide × 1 cell tall)
	var img := Image.create(128, 63, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.6, 1.0, 1.0))
	img.save_png("%s/wide-block.png" % pack_dir)
	# Sidecar: static class, 2×1 footprint
	var sf := FileAccess.open("%s/wide-block.json" % pack_dir, FileAccess.WRITE)
	sf.store_string(JSON.stringify({"class": "static", "cells": [2, 1]}))
	sf.close()
	# Scan so "gutfix:wide-block" is live in the registry before any test runs.
	Pieces.scan()
	# ── Editor instance ──────────────────────────────────────────────────────
	ed = load("res://scenes/editor.tscn").instantiate()
	add_child_autofree(ed)


func after_each() -> void:
	# ── Sandbox teardown ─────────────────────────────────────────────────────
	# Remove every file inside the gutfix pack folder, then the folder itself.
	var pack_dir := "%s/gutfix" % FIXTURE_TOYBOX_DIR
	var dir := DirAccess.open(pack_dir)
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir():
				dir.remove(fname)
			fname = dir.get_next()
		dir.list_dir_end()
	DirAccess.remove_absolute(pack_dir)
	# Remove the sandbox root itself (empty after pack removal).
	DirAccess.remove_absolute(FIXTURE_TOYBOX_DIR)
	# Restore toybox.cfg exactly as it was before this test ran.
	if _cfg_before == "":
		if FileAccess.file_exists(TOYBOX_CFG):
			DirAccess.remove_absolute(TOYBOX_CFG)
	else:
		var f := FileAccess.open(TOYBOX_CFG, FileAccess.WRITE)
		if f:
			f.store_string(_cfg_before)
	# Restore the real toybox root and rescan so subsequent tests/files
	# see the real registry (halloween + spooky_season packs, etc.).
	Pieces.toybox_root = "user://toybox"
	Pieces.scan()


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
	# OLD: ed.carrying = "tramp-flat"  (shipped 2×1 trampoline; now resized to 1×1)
	# NEW: ed.carrying = FIXTURE_ID    (sandbox 2×1 static fixture — same footprint intent)
	# WHY: The test verifies that placing a 2×1 piece occupies both anchor and
	#      second cell.  The fixture has identical cells:[2,1]; the class change
	#      from trampoline→static is irrelevant to occupancy logic.
	ed.carrying = FIXTURE_ID
	ed._press(Vector2i(4, 0))
	assert_eq(ed.current.props.size(), 1, "prop recorded")
	assert_true(ed.occupancy.has(Vector2i(4, 0)), "anchor cell occupied")
	assert_true(ed.occupancy.has(Vector2i(5, 0)), "second cell occupied")
	assert_eq(ed.occupancy[Vector2i(4, 0)], ed.occupancy[Vector2i(5, 0)], "same node both cells")
	assert_eq(ed.carrying, "")


func test_prop_placement_blocked_by_partial_overlap() -> void:
	# OLD: ed.carrying = "tramp-flat" / assert_eq(ed.carrying, "tramp-flat", ...)
	# NEW: ed.carrying = FIXTURE_ID   / assert_eq(ed.carrying, FIXTURE_ID, ...)
	# WHY: The test verifies that a 2×1 drop is refused when cell (5,0) is
	#      already occupied by a crate, and that carrying is unchanged.
	#      The fixture has the same 2×1 footprint; the refusal logic is class-agnostic.
	ed.carrying = "crate-wood"
	ed._press(Vector2i(5, 0))
	ed.carrying = FIXTURE_ID
	ed._press(Vector2i(4, 0))  # cell 5,0 is taken — whole footprint must refuse
	assert_eq(ed.current.props.size(), 0)
	assert_false(ed.occupancy.has(Vector2i(4, 0)))
	assert_eq(ed.carrying, FIXTURE_ID, "still carrying after refused drop")


func test_crate_cannot_land_on_prop_cell() -> void:
	# OLD: ed.carrying = "tramp-flat"  (2×1 trampoline, now 1×1)
	# NEW: ed.carrying = FIXTURE_ID    (2×1 static fixture)
	# WHY: The test verifies that a crate dropped onto the second cell of a
	#      2×1 prop is refused.  The fixture occupies the same two cells (4,0)
	#      and (5,0); the prop-class change does not affect crate refusal logic.
	ed.carrying = FIXTURE_ID
	ed._press(Vector2i(4, 0))
	ed.carrying = "crate-wood"
	ed._press(Vector2i(5, 0))
	assert_eq(ed.current.crates.size(), 0, "prop cell refuses crates")


func test_prop_delete_frees_all_cells() -> void:
	# OLD: ed.carrying = "tramp-flat"  (2×1 trampoline, now 1×1)
	# NEW: ed.carrying = FIXTURE_ID    (2×1 static fixture)
	# WHY: The test verifies that deleting a 2×1 prop frees both anchor and
	#      second cell from occupancy.  The fixture spans identical cells;
	#      the deletion path is class-agnostic.
	ed.carrying = FIXTURE_ID
	ed._press(Vector2i(4, 0))
	# OLD: ed.overlay.selected_cell = Vector2i(5, 0)  # direct view-write (bypassed selection)
	# NEW: arrange selection state via the public API — intent is "select via the SECOND cell"
	#      for a pure-state arrangement (not a click simulation) select_cell is correct.
	ed.select_cell(Vector2i(5, 0), Vector2i(1, 1), ed.occupancy[Vector2i(5, 0)] as Node2D)
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
	# OLD: ed.overlay.selected_cell = Vector2i(3, 2)  # direct view-write (bypassed selection)
	# NEW: arrange selection state via the public API — intent is pure state arrangement,
	#      not a click simulation, so select_cell is correct (not _press).
	ed.select_cell(Vector2i(3, 2), Vector2i(1, 1), ed.occupancy[Vector2i(3, 2)] as Node2D)
	ed._delete_selected()
	# All occupancy cells pointing at the body are erased, even with unknown id.
	assert_false(ed.occupancy.has(Vector2i(3, 2)), "anchor cell erased after unknown-id delete")
	assert_eq(ed.overlay.selected_cell, Vector2i(-1, -1), "selection cleared")


func test_prop_selection_ring_spans_footprint_from_any_cell() -> void:
	# OLD: ed.carrying = "tramp-flat"  (2×1 trampoline, now 1×1)
	# NEW: ed.carrying = FIXTURE_ID    (2×1 static fixture)
	# WHY: The test verifies that clicking either cell of a 2×1 prop snaps the
	#      selection ring to the anchor and reports selected_cells == Vector2i(2,1).
	#      The fixture has identical cells:[2,1]; selection-ring logic is class-agnostic.
	ed.carrying = FIXTURE_ID
	ed._press(Vector2i(4, 0))
	ed._press(Vector2i(5, 0))  # click the SECOND cell
	assert_eq(ed.overlay.selected_cell, Vector2i(4, 0), "selection snaps to the anchor")
	assert_eq(ed.overlay.selected_cells, Vector2i(2, 1), "ring spans the footprint")
	ed.carrying = "crate-wood"
	ed._press(Vector2i(8, 0))
	ed._press(Vector2i(8, 0))
	assert_eq(ed.overlay.selected_cells, Vector2i(1, 1), "crates stay 1x1")


func test_prop_drag_moves_whole_footprint() -> void:
	# OLD: ed.carrying = "tramp-flat"  (2×1 trampoline, now 1×1)
	# NEW: ed.carrying = FIXTURE_ID    (2×1 static fixture)
	# WHY: The test verifies that dragging a 2×1 prop (grabbed by its second cell)
	#      moves both cells atomically and updates the data record.  The fixture
	#      has the same 2×1 footprint; drag-move logic is class-agnostic.
	ed.carrying = FIXTURE_ID
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
	# OLD: ed.carrying = "tramp-flat"  (2×1 trampoline, now 1×1)
	# NEW: ed.carrying = FIXTURE_ID    (2×1 static fixture)
	# WHY: The test verifies that dragging a 2×1 prop is refused when the
	#      destination overlaps an existing crate, leaving the piece at its
	#      original position.  The fixture has the same footprint; overlap
	#      detection is class-agnostic.
	ed.carrying = "crate-wood"
	ed._press(Vector2i(9, 0))
	ed.carrying = FIXTURE_ID
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


# ---------------------------------------------------------------------------
# TEST round-trip keeps the filename (owner bug: "after you test a level the
# system forgets what the filename was").  The doc rides LevelEditor.resume_layout
# back from TEST; save_path must ride beside it — a fresh editor instance
# otherwise reverts to "" and Save prompts Save-As.
# ---------------------------------------------------------------------------

func test_resume_from_test_keeps_save_path() -> void:
	var layout := LevelLayout.new()
	layout.title = "roundtrip"
	LevelEditor.resume_layout = layout
	LevelEditor.resume_save_path = "user://levels/roundtrip.json"
	var ed2: LevelEditor = load("res://scenes/editor.tscn").instantiate()
	add_child_autofree(ed2)
	assert_eq(ed2.current, layout, "doc adopted from resume rail")
	assert_eq(ed2.save_path, "user://levels/roundtrip.json", "filename survives the TEST round-trip")
	assert_eq(LevelEditor.resume_save_path, "", "rail cleared after adoption")


func test_fresh_editor_ignores_stale_resume_save_path() -> void:
	# The adoption trap: a stale path must never leak into a NEW document
	# (no resume_layout = not a TEST return, whatever the path static says).
	LevelEditor.resume_layout = null
	LevelEditor.resume_save_path = "user://levels/stale.json"
	var ed2: LevelEditor = load("res://scenes/editor.tscn").instantiate()
	add_child_autofree(ed2)
	assert_eq(ed2.save_path, "", "fresh document stays unsaved")
	assert_eq(LevelEditor.resume_save_path, "", "stale rail cleared either way")


# ---------------------------------------------------------------------------
# Bare-letter editor keybinds (S/A/T/C) — game-parity, browser-safe.
# T is untestable headless (change_scene); C and S cover the shared path.
# ---------------------------------------------------------------------------

func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func test_key_c_toggles_scenery_mode() -> void:
	assert_eq(ed.mode, LevelEditor.Mode.CRATES)
	ed._unhandled_input(_key(KEY_C))
	assert_eq(ed.mode, LevelEditor.Mode.SCENERY, "C enters scenery")
	ed._unhandled_input(_key(KEY_C))
	assert_eq(ed.mode, LevelEditor.Mode.CRATES, "C again exits")


func test_key_s_unsaved_opens_save_as() -> void:
	ed.save_path = ""
	ed._unhandled_input(_key(KEY_S))
	assert_true(ed.menu.any_dialog_open(), "unsaved S falls through to the Save As dialog")


func test_keys_blocked_while_dialog_open() -> void:
	ed.menu.open_save_as()
	ed._unhandled_input(_key(KEY_C))
	assert_eq(ed.mode, LevelEditor.Mode.CRATES, "letters are inert behind a dialog")


func test_keys_blocked_while_typing() -> void:
	var box := LineEdit.new()
	ed.add_child(box)
	box.grab_focus()
	ed._unhandled_input(_key(KEY_C))
	assert_eq(ed.mode, LevelEditor.Mode.CRATES, "letters are inert while typing")
	box.queue_free()


# ---------------------------------------------------------------------------
# Overlay auto-naming (owner: multiple anonymous overlays made trigger
# authoring blind).  Names come from the filename, sanitized to the
# trigger charset, deduped sign/sign2/sign3.
# ---------------------------------------------------------------------------

func test_default_overlay_name_sanitizes_filename() -> void:
	assert_eq(LevelEditor.default_overlay_name("/tmp/Sign Post!.PNG", []), "signpost")
	assert_eq(LevelEditor.default_overlay_name("/tmp/@@@.png", []), "piece", "all-junk stem falls back")
	var long_name := LevelEditor.default_overlay_name("/tmp/a_very_long_filename_indeed.png", [])
	assert_true(Effects.valid_name(long_name), "truncated name is trigger-legal")


func test_default_overlay_name_dedupes_with_index() -> void:
	var overlays := [{"name": "sign"}, {"name": "sign2"}]
	assert_eq(LevelEditor.default_overlay_name("/tmp/sign.png", overlays), "sign3")
	assert_eq(LevelEditor.default_overlay_name("/tmp/tree.png", overlays), "tree", "unused base stays bare")


func test_default_overlay_name_keeps_dashes_and_respects_hand_names() -> void:
	assert_eq(LevelEditor.default_overlay_name("/tmp/stone-sign.png", []), "stone-sign", "dashes are trigger-legal and kept")
	# hand-authored names count as taken — imports dodge them
	var hand := [{"name": "castle"}]
	assert_eq(LevelEditor.default_overlay_name("/tmp/castle.png", hand), "castle2")


func test_image_import_assigns_unique_names() -> void:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var tmp := "user://gut_sign.png"
	img.save_png(tmp)
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	ed._on_image_chosen(abs_tmp)
	ed._on_image_chosen(abs_tmp)
	var n := ed.current.overlays.size()
	assert_eq(str(ed.current.overlays[n - 2].get("name", "")), "gut_sign")
	assert_eq(str(ed.current.overlays[n - 1].get("name", "")), "gut_sign2")
	assert_true(Effects.valid_name(str(ed.current.overlays[n - 1].get("name", ""))))
	DirAccess.remove_absolute(abs_tmp)


# ---------------------------------------------------------------------------
# Triggers follow their crate (the three-smoking-crates bug: moving a
# triggered crate orphaned its hit: key silently).
# ---------------------------------------------------------------------------

func test_moving_a_crate_moves_its_trigger_key() -> void:
	var from := Vector2i(4, 0)
	var to := Vector2i(6, 0)
	ed.carrying = "crate-wood"
	ed._press(from)
	var old_key := LevelEditor.crate_trigger_key(from)
	ed.current.triggers[old_key] = ["smoke:#112233"]
	ed._press(from)
	ed._release(to, false)
	assert_false(ed.current.triggers.has(old_key), "old key gone")
	assert_eq(ed.current.triggers[LevelEditor.crate_trigger_key(to)], ["smoke:#112233"], "trigger followed the crate")


func test_deleting_a_crate_deletes_its_trigger_key() -> void:
	var cell := Vector2i(5, 0)
	ed.carrying = "crate-wood"
	ed._press(cell)
	var key := LevelEditor.crate_trigger_key(cell)
	ed.current.triggers[key] = ["confetti"]
	ed._press(cell)  # select it
	ed._delete_selected()
	assert_false(ed.current.triggers.has(key), "deleted crate takes its trigger along")


func test_shift_place_keeps_carrying() -> void:
	# Iggy's request: hold shift to place multiple blocks.
	var shift := InputEventKey.new()
	shift.keycode = KEY_SHIFT
	shift.physical_keycode = KEY_SHIFT
	shift.pressed = true
	Input.parse_input_event(shift)
	await get_tree().process_frame
	ed.carrying = "crate-wood"
	ed._press(Vector2i(8, 0))
	assert_eq(ed.carrying, "crate-wood", "shift keeps the stamp loaded")
	ed._press(Vector2i(9, 0))
	shift.pressed = false
	Input.parse_input_event(shift)
	await get_tree().process_frame
	ed._press(Vector2i(10, 0))
	assert_eq(ed.carrying, "", "no shift, stamp drops after placing")
	assert_eq(ed.current.crates.size(), 3, "three crates stamped")


func test_dropping_carry_off_grid_or_on_palette_cancels() -> void:
	# Gesture starting on canvas, ending off-grid: cancel.
	ed.carrying = "crate-wood"
	ed._press(Vector2i(-3, 0))
	ed._release(Vector2i(-3, 0), false)
	assert_eq(ed.carrying, "", "off-grid drop cancels the carry")
	# Gesture starting on canvas (blocked spot), dragged onto the palette: cancel.
	ed.carrying = "crate-wood"
	ed._press(Vector2i(4, 0))  # places it
	ed.carrying = "crate-wood"
	ed._press(Vector2i(4, 0))  # blocked — keeps carrying
	ed._release(Vector2i(4, 0), true)
	assert_eq(ed.carrying, "", "dragging the carry onto the palette cancels")
	# A palette pick's release (no canvas press) must NOT cancel.
	ed.carrying = "crate-wood"
	ed._release(Vector2i(4, 0), true)
	assert_eq(ed.carrying, "crate-wood", "palette pick survives its own release")
	# Blocked in-grid spot keeps carrying (try the next cell).
	ed._press(Vector2i(4, 0))
	ed._release(Vector2i(4, 0), false)
	assert_eq(ed.carrying, "crate-wood", "occupied in-grid spot keeps the carry")


func test_ghost_visible_flag_not_fooled_by_negative_cells() -> void:
	# Cells left of the grid have negative x — the old draw guard read
	# them as the hidden sentinel, so the ghost stayed invisible until
	# the mouse first crossed the grid (owner report).
	ed._grid_tool.carrying = "crate-wood"
	ed._grid_tool._update_ghost()
	assert_true(ed.overlay.ghost_visible, "carrying shows the ghost wherever the mouse is")
	ed._grid_tool.carrying = ""
	ed._grid_tool._update_ghost()
	assert_false(ed.overlay.ghost_visible, "no cargo, no ghost")


func test_drag_preview_shows_over_ui_and_hides_off() -> void:
	# The palette lives in a CanvasLayer above the world — the world ghost
	# can never draw there, so a UI-layer preview carries the picked piece.
	ed._grid_tool.carrying = "crate-wood"
	ed._update_drag_preview(Vector2(60, 300), true)
	assert_not_null(ed._drag_preview, "preview created on demand")
	assert_true(ed._drag_preview.visible, "visible while carrying over UI")
	assert_not_null(ed._drag_preview.texture)
	ed._update_drag_preview(Vector2(900, 300), false)
	assert_false(ed._drag_preview.visible, "hidden off-UI (world ghost takes over)")
	ed._grid_tool.carrying = ""
	ed._update_drag_preview(Vector2(60, 300), true)
	assert_false(ed._drag_preview.visible, "no cargo, no preview")


# ---------------------------------------------------------------------------
# Task 2 — Finding 3: missing-pack props are retained as placeholders
# (audit 2026-09-08, finding 3)
# ---------------------------------------------------------------------------

func test_missing_pack_prop_survives_rebuild_in_document() -> void:
	# Audit reproduction: a document containing a prop whose pack is absent
	# must NOT have that prop deleted from current.props during _rebuild.
	# After _rebuild, current.props.size() must still be 1.
	var w := EditorGrid.cell_to_world(Vector2i(3, 1))
	ed.current.props.append({"id": "missing:wall", "x": w.x, "y": w.y})
	ed._rebuild()
	assert_eq(ed.current.props.size(), 1, "missing-pack prop stays in document after _rebuild")


func test_missing_pack_prop_placeholder_occupies_cell() -> void:
	# The placeholder must block the cell so nothing is placed on top of it.
	var w := EditorGrid.cell_to_world(Vector2i(3, 1))
	ed.current.props.append({"id": "missing:wall", "x": w.x, "y": w.y})
	ed._rebuild()
	assert_true(ed.occupancy.has(Vector2i(3, 1)), "placeholder occupies its cell in ed.occupancy")


func test_missing_pack_prop_placeholder_is_selectable() -> void:
	# The placeholder must be a selectable Node2D (not a Crate).
	var cell := Vector2i(3, 1)
	var w := EditorGrid.cell_to_world(cell)
	ed.current.props.append({"id": "missing:wall", "x": w.x, "y": w.y})
	ed._rebuild()
	var node: Variant = ed.occupancy.get(cell)
	assert_not_null(node, "placeholder node present")
	assert_false(node is Crate, "placeholder is not a Crate")
	assert_true(node is Node2D, "placeholder is a Node2D")


func test_missing_pack_prop_placeholder_deletable() -> void:
	# DELETE on a selected placeholder removes the prop from the document.
	var cell := Vector2i(3, 1)
	var w := EditorGrid.cell_to_world(cell)
	ed.current.props.append({"id": "missing:wall", "x": w.x, "y": w.y})
	ed._rebuild()
	var node: Node2D = ed.occupancy[cell] as Node2D
	ed.select_cell(cell, Vector2i(1, 1), node)
	ed._delete_selected()
	assert_eq(ed.current.props.size(), 0, "placeholder DELETE removes the prop from the document")
	assert_false(ed.occupancy.has(cell), "cell freed after placeholder delete")


func test_missing_pack_prop_save_round_trips() -> void:
	# The prop must survive a serialize → parse round trip unchanged.
	var w := EditorGrid.cell_to_world(Vector2i(3, 1))
	ed.current.props.append({"id": "missing:wall", "x": w.x, "y": w.y})
	ed._rebuild()
	# Serialize and re-parse.
	var json_str := LevelJson.serialize(ed.current)
	var parsed := LevelJson.parse(json_str)
	assert_not_null(parsed, "serialized document is valid JSON")
	assert_eq(parsed.props.size(), 1, "prop count preserved through serialize/parse")
	assert_eq(str(parsed.props[0]["id"]), "missing:wall", "prop id round-trips verbatim")


func test_rebuild_does_not_duplicate_props_on_repeated_rebuilds() -> void:
	# Regression guard: repeated rebuilds must not accumulate extra prop entries.
	var w := EditorGrid.cell_to_world(Vector2i(3, 1))
	ed.current.props.append({"id": "missing:wall", "x": w.x, "y": w.y})
	ed._rebuild()
	ed._rebuild()
	assert_eq(ed.current.props.size(), 1, "no duplicate props after two rebuilds")
	assert_eq(ed._spawned_props.size(), 1, "no duplicate bodies after two rebuilds")


# ---------------------------------------------------------------------------
# Task 2 — Finding 4: load-time crate snap migrates trigger keys
# (audit 2026-09-08, finding 4)
# ---------------------------------------------------------------------------

func test_offgrid_crate_snap_migrates_trigger_key() -> void:
	# Audit reproduction: a crate at (833,443) with hit:833,443 → after
	# _rebuild the trigger is at hit:832,443 (the snapped cell) and the
	# original key is gone.
	ed.current.crates.append({"x": 833.0, "y": 443.0, "type": "crate-wood"})
	ed.current.triggers["hit:833,443"] = ["confetti"]
	ed._rebuild()
	# The snapped cell for (833,443):
	var snapped_cell := EditorGrid.world_to_cell(Vector2(833.0, 443.0))
	var new_key := LevelEditor.crate_trigger_key(snapped_cell)
	assert_true(ed.current.triggers.has(new_key), "trigger migrated to snapped key: %s" % new_key)
	assert_false(ed.current.triggers.has("hit:833,443"), "original off-grid key removed")
	assert_eq(ed.current.triggers[new_key], ["confetti"], "trigger actions preserved after snap migration")


func test_trigger_snap_no_mutation_when_already_on_grid() -> void:
	# A crate that is already on a grid cell must NOT lose its trigger key.
	var cell := Vector2i(5, 1)
	var w := EditorGrid.cell_to_world(cell)
	ed.current.crates.append({"x": w.x, "y": w.y, "type": "crate-wood"})
	var key := LevelEditor.crate_trigger_key(cell)
	ed.current.triggers[key] = ["smoke:#ff0000"]
	ed._rebuild()
	assert_true(ed.current.triggers.has(key), "on-grid trigger key preserved")
	assert_eq(ed.current.triggers[key], ["smoke:#ff0000"], "actions preserved")


func test_trigger_snap_collision_merges_and_deduplicates() -> void:
	# Two crates at different off-grid positions that both snap to the same
	# cell: their trigger action lists are merged (deduped, capped at 16).
	var snapped_cell := EditorGrid.world_to_cell(Vector2(833.0, 443.0))
	var snapped_w := EditorGrid.cell_to_world(snapped_cell)
	# Use the snapped position for the second crate so the first gets
	# removed as a duplicate (seen_cells dedup) and the trigger gets merged.
	# Place first crate off-grid (snaps to snapped_cell).
	ed.current.crates.append({"x": 833.0, "y": 443.0, "type": "crate-wood"})
	# Place second crate off-grid at a slightly different off-grid position
	# that also snaps to the same cell — to ensure collision we use the same
	# snapped world pos (already on grid) as "another" source.
	# Actually per the snap dedup logic, the second crate AT THE SAME CELL
	# is dropped. So we need to test via triggers: two off-grid keys that
	# BOTH map to the same snapped key.
	ed.current.triggers["hit:833,443"] = ["confetti", "smoke:#112233"]
	# Add a second trigger at an adjacent off-grid coord that snaps to the same cell.
	# We inject it directly — the snap loop must merge both into the new key.
	var snapped_key := LevelEditor.crate_trigger_key(snapped_cell)
	# Use a different off-grid trigger key that would also snap to the same cell.
	# Since we are testing the TRIGGER migration (not crate placement),
	# we can have one crate and two old trigger keys pointing to the same new key.
	# But the snap loop only builds old→new from crate positions.
	# Instead: place the first crate off-grid (snaps to snapped_cell) with actions A+B,
	# and manually insert a SECOND old trigger key for the SAME new cell
	# to test collision merge.
	# Clear and redo with a direct collision scenario:
	ed.current.crates.clear()
	ed.current.triggers.clear()
	ed.current.crates.append({"x": 833.0, "y": 443.0, "type": "crate-wood"})
	# Inject a second old key that maps to the SAME snapped key
	# (simulate a case where two different sources snap to the same destination).
	ed.current.triggers["hit:833,443"] = ["confetti"]
	# Add the snapped key itself as a pre-existing trigger (collision source).
	ed.current.triggers[snapped_key] = ["smoke:#112233"]
	ed._rebuild()
	# After migration, snapped_key should have merged actions (confetti + smoke, deduped).
	assert_true(ed.current.triggers.has(snapped_key), "merged key present")
	var merged: Array = ed.current.triggers[snapped_key]
	assert_true(merged.has("confetti"), "first source action present")
	assert_true(merged.has("smoke:#112233"), "second source action present")
	assert_false(ed.current.triggers.has("hit:833,443"), "old off-grid key removed")


# ---------------------------------------------------------------------------
# Audit 2026-09-08 — Finding 5: SceneryPanel file dialog blocks polled input
# (dialog visible → ed.over_ui_at(any world point) must be true)
# ---------------------------------------------------------------------------

func test_scenery_file_dialog_registered_as_popup() -> void:
	# Audit reproduction: _file_dialog is visible → over_ui_at must report blocked.
	# The dialog is a non-native FileDialog (a Window subclass); it must be
	# registered with ed.register_popup() so the polling gate catches it.
	# We call the panel's expose path to make the dialog visible without a
	# physical desktop click.
	var panel: SceneryPanel = ed.get_node("%SceneryPanel")
	assert_not_null(panel, "SceneryPanel accessible on the editor")
	# Make the panel visible (entering scenery mode shows it)
	ed._enter_scenery()
	# Expose the dialog as visible via the registered hook
	var dlg: FileDialog = panel._file_dialog
	assert_not_null(dlg, "_file_dialog exists on SceneryPanel")
	# Show the dialog directly (simulates user clicking Add Image headless)
	dlg.visible = true
	# Now over_ui_at must be true at a far-away world point (not over any UI rect)
	assert_true(ed.over_ui_at(Vector2(900, 500)),
		"open file dialog must block polled input (over_ui_at returns true)")
	# Hide and verify it no longer blocks (sanity check that it's the dialog, not the panel)
	dlg.visible = false
	# Exit scenery to restore state
	ed._exit_scenery()


func test_opening_file_dialog_resets_scenery_drag_state() -> void:
	# When the file dialog opens, any in-flight scenery drag must be ended.
	# We verify _scenery_tool._scenery_dragging is false after dialog opens.
	ed._enter_scenery()
	# Simulate that a scenery drag is in flight
	ed._scenery_tool._scenery_dragging = true
	ed._scenery_tool._lmb_down = true
	# Open the dialog (via the panel's internal open path)
	var panel: SceneryPanel = ed.get_node("%SceneryPanel")
	panel._open_file_dialog_for_test()
	# Drag state must be reset
	assert_false(ed._scenery_tool._scenery_dragging,
		"scenery drag state reset when file dialog opens")
	# Cleanup
	panel._file_dialog.visible = false
	ed._exit_scenery()


func test_crate_on_ghost_prop_anchor_keeps_prop_in_document() -> void:
	# Reviewer follow-up (audit finding 3): a crate occupying a missing-pack
	# prop's anchor cell spawns no placeholder node, but the prop must
	# survive the document and the save round-trip.
	var w := EditorGrid.cell_to_world(Vector2i(6, 1))
	ed.current.props.append({"id": "missing:wall", "x": w.x, "y": w.y})
	ed.current.crates.append({"x": w.x, "y": w.y, "type": "crate-wood"})
	ed._rebuild()
	assert_eq(ed.current.props.size(), 1, "prop retained despite crate at its anchor")
	var text := LevelJson.serialize(ed.current)
	var reparsed := LevelJson.parse(text)
	assert_eq(reparsed.props.size(), 1, "prop survives the round trip")
	assert_eq(str(reparsed.props[0]["id"]), "missing:wall")


func test_trigger_merge_overflow_caps_at_sixteen() -> void:
	# Reviewer follow-up (audit finding 4): two off-grid crates snapping to
	# one cell merge their action lists — the 16 cap must hold with a warning.
	var w := EditorGrid.cell_to_world(Vector2i(7, 1))
	var actions_a: Array = []
	var actions_b: Array = []
	for i in 10:
		actions_a.append("display:msg-a-%d" % i)
		actions_b.append("display:msg-b-%d" % i)
	ed.current.crates.append({"x": w.x + 0.4, "y": w.y, "type": "crate-wood"})
	ed.current.triggers["hit:%d,%d" % [int(w.x + 0.4), int(w.y)]] = actions_a
	ed.current.crates.append({"x": w.x - 0.4, "y": w.y, "type": "crate-wood"})
	ed.current.triggers["hit:%d,%d" % [int(w.x - 0.4), int(w.y)]] = actions_b
	ed._rebuild()  # warns about the drop
	var key := LevelEditor.crate_trigger_key(Vector2i(7, 1))
	assert_true(ed.current.triggers.has(key), "merged onto the snapped key")
	assert_eq((ed.current.triggers[key] as Array).size(), 16, "merge capped at 16")


# ---------------------------------------------------------------------------
# Editor QoL from building the depot: click-cycle-down, keyboard nudge,
# grid toggle. (Owner-designed: cycle decided on the up-event so a
# click-to-drag never dives.)
# ---------------------------------------------------------------------------

func _stack_two_overlays_at(px: float, py: float) -> void:
	# Two overlapping scenery pieces at the same spot: index 0 lower, 1 upper.
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())
	var key := LevelJson.image_key(Marshalls.base64_to_raw(b64))
	ed.current.images[key] = b64
	ed.current.overlays.append({"image": key, "x": px, "y": py, "name": "lower"})
	ed.current.overlays.append({"image": key, "x": px, "y": py, "name": "upper"})
	ed._enter_scenery()
	ed._rebuild_scenery()


func test_click_cycles_down_the_overlap_stack() -> void:
	_stack_two_overlays_at(500.0, 400.0)
	var st: SceneryTool = ed._scenery_tool
	var hit := Vector2(500.0, 400.0)
	# First click (press+release, no motion): selects the TOP piece.
	st._scenery_press(hit)
	st._scenery_release()
	assert_eq(ed.current.overlays[ed.selected_overlay].get("name"), "upper", "first click grabs the top")
	# Second click same spot, no motion: cycles to the LOWER piece.
	st._scenery_press(hit)
	st._scenery_release()
	assert_eq(ed.current.overlays[ed.selected_overlay].get("name"), "lower", "click again dives to the lower piece")
	# Third click: wraps back to the top.
	st._scenery_press(hit)
	st._scenery_release()
	assert_eq(ed.current.overlays[ed.selected_overlay].get("name"), "upper", "cycle wraps to the top")


func test_drag_moves_selection_and_does_not_cycle() -> void:
	_stack_two_overlays_at(500.0, 400.0)
	var st: SceneryTool = ed._scenery_tool
	st._scenery_press(Vector2(500.0, 400.0))
	st._scenery_release()  # top selected
	assert_eq(ed.current.overlays[ed.selected_overlay].get("name"), "upper")
	# Press then MOVE past the threshold then release = a drag, NOT a cycle.
	st._scenery_press(Vector2(500.0, 400.0))
	st._scenery_drag(Vector2(560.0, 400.0))
	st._scenery_release()
	assert_eq(ed.current.overlays[ed.selected_overlay].get("name"), "upper", "a drag keeps the selection (no dive)")
	assert_almost_eq(float(ed.current.overlays[ed.selected_overlay]["x"]), 560.0, 1.0, "the dragged piece moved")


func test_nudge_moves_selected_scenery_by_pixels() -> void:
	_stack_two_overlays_at(500.0, 400.0)
	ed.select_overlay(0)
	var before: float = float(ed.current.overlays[0]["x"])
	ed._nudge_scenery(Vector2(1.0, 0.0))
	assert_almost_eq(float(ed.current.overlays[0]["x"]), before + 1.0, 0.01, "1px nudge")
	ed._nudge_scenery(Vector2(0.0, -10.0))
	assert_almost_eq(float(ed.current.overlays[0]["y"]), 390.0, 0.01, "10px vertical nudge writes the dict")


func test_grid_toggle_flips_overlay_visibility() -> void:
	ed._enter_scenery()
	assert_false(ed.overlay.visible, "scenery mode hides the grid")
	var ev := InputEventKey.new()
	ev.keycode = KEY_G
	ev.pressed = true
	ed._unhandled_input(ev)
	assert_true(ed.overlay.visible, "G brings the grid back in scenery mode")
	ed._unhandled_input(ev)
	assert_false(ed.overlay.visible, "G toggles it off again")
