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

func test_delete_removes_selected_crate() -> void:
	ed.carrying = "crate-wood"
	ed._press(Vector2i(2, 0))
	ed._press(Vector2i(2, 0))
	ed._delete_selected()
	assert_false(ed.occupancy.has(Vector2i(2, 0)))
	assert_eq(ed.current.crates.size(), 0)
	assert_eq(ed.overlay.selected_cell, Vector2i(-1, -1))
