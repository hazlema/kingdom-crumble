class_name GridOverlay
extends Node2D

# Faint build-zone grid + ghost/selection markers, all draw-only.

var ghost_cell := Vector2i(-1, -1)
var ghost_ok := false
var ghost_tex: Texture2D
var ghost_cells := Vector2i(1, 1)
var selected_cell := Vector2i(-1, -1)


func _draw() -> void:
	var col := Color(1, 1, 1, 0.14)
	for cx in range(EditorGrid.cols() + 1):
		var x := EditorGrid.MIN_X + cx * EditorGrid.CELL
		draw_line(
			Vector2(x, EditorGrid.FLOOR_Y),
			Vector2(x, EditorGrid.FLOOR_Y - EditorGrid.MAX_ROWS * EditorGrid.ROW_H),
			col,
			2
		)
	for ry in range(EditorGrid.MAX_ROWS + 1):
		var y := EditorGrid.FLOOR_Y - ry * EditorGrid.ROW_H
		draw_line(Vector2(EditorGrid.MIN_X, y), Vector2(EditorGrid.MAX_X, y), col, 2)
	if ghost_cell.x >= 0 and ghost_tex:
		var p := EditorGrid.cell_to_world(ghost_cell)
		var tint := Color(0.6, 1.0, 0.6, 0.6) if ghost_ok else Color(1.0, 0.4, 0.4, 0.6)
		var size := Vector2(ghost_cells.x * 64.0, ghost_cells.y * 63.0)
		var top_left := Vector2(p.x - 32.0, p.y - 31.5 - (ghost_cells.y - 1) * 63.0)
		draw_texture_rect(ghost_tex, Rect2(top_left, size), false, tint)
	if selected_cell.x >= 0:
		var s := EditorGrid.cell_to_world(selected_cell)
		draw_rect(
			Rect2(s - Vector2(34, 34), Vector2(68, 68)), Color(1.0, 0.83, 0.29, 0.95), false, 4.0
		)


func refresh() -> void:
	queue_redraw()
