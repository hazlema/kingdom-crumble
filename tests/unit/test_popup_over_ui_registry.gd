extends GutTest

# Pin for the Task-5 leak closure: a registered editor popup (here the
# crate Info dialog) must count as over-UI in SCENERY mode too. Input is
# polled, so window routing alone never protected the field — before the
# popup registry, scenery-mode over_ui skipped the Info dialog and a
# click aimed at the dialog also landed on the field.

var ed: LevelEditor


func before_each() -> void:
	ed = load("res://scenes/editor.tscn").instantiate()
	add_child_autofree(ed)


func test_scenery_over_ui_true_while_registered_popup_visible() -> void:
	ed.carrying = "crate-wood"
	ed._press(Vector2i(2, 0))
	ed._enter_scenery()
	ed._show_crate_info(Vector2i(2, 0))
	assert_true(ed._crate_info.visible, "info dialog pops")
	var field_point := Vector2(-999.0, -999.0)
	assert_false(ed._mouse_over_ui(field_point), "panel geometry alone says field")
	assert_true(ed.any_popup_open(), "the dialog is a registered popup")
	assert_true(
		ed.over_ui_at(field_point),
		"the shared over_ui answer (consumed by SceneryTool.process) vetoes the field click"
	)
