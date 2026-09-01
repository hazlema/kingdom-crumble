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
	assert_true(ed.menu.get_node("%SaveAsDialog").visible,
		"ctrl+S with no save path should open Save As")
	ed.menu.get_node("%SaveAsDialog").hide()

func test_load_list_item_activation_emits_load() -> void:
	var list: ItemList = ed.menu.get_node("%LevelList")
	list.clear()
	var idx := list.add_item("Test Level")
	list.set_item_metadata(idx, "user://levels/test_level.json")
	watch_signals(ed.menu)
	list.item_activated.emit(idx)
	assert_signal_emitted_with_parameters(ed.menu, "load_requested",
		["user://levels/test_level.json"])

func test_delete_removes_selected_crate() -> void:
	ed.carrying = "crate-wood"
	ed._press(Vector2i(2, 0))
	ed._press(Vector2i(2, 0))
	ed._delete_selected()
	assert_false(ed.occupancy.has(Vector2i(2, 0)))
	assert_eq(ed.current.crates.size(), 0)
	assert_eq(ed.overlay.selected_cell, Vector2i(-1, -1))
