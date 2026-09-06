class_name GridTool
extends EditorTool

# Owns all crate + prop input state: LMB edge detection, press/release,
# ghost preview, and the RMB Info menu. The editor owns the document
# (current, occupancy, overlay) and shared services; this tool owns
# nothing except what is listed below.

var carrying := ""  # asset id while placing, "" = none
var _drag_from := Vector2i(-1, -1)  # cell a drag-move started on
var _drag_prop: Node2D = null  # prop being drag-moved, null = none/crate
var _lmb_down := false
var _crate_context: PopupMenu = null
var _crate_info: AcceptDialog = null
var _info_cell := Vector2i(-1, -1)  # cell the crate menu opened on
var _info_key := ""  # trigger key shown in the open Info dialog


# Called every frame while CRATES mode is active.
func process(mouse: Vector2, over_ui: bool) -> void:
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if lmb and not _lmb_down and not over_ui:
		_press(ed._mouse_cell())
	elif not lmb and _lmb_down:
		_release(ed._mouse_cell(), over_ui)
	_lmb_down = lmb
	_update_ghost()

	# RMB Info menu: open only on release without significant motion
	# (a moving RMB is a camera pan — same rule as scenery mode).
	if ed.rmb_menu_release(mouse, over_ui):
		var cell := ed._mouse_cell()
		if ed.occupancy.has(cell) and ed.occupancy.get(cell) is Crate:
			var crate_node: Node2D = ed.occupancy.get(cell) as Node2D
			ed.select_cell(cell, Vector2i(1, 1), crate_node)
			_show_crate_context(mouse, cell)


func _press(cell: Vector2i) -> void:
	if carrying != "":
		_try_place(cell)
		return
	if ed.occupancy.has(cell):
		var node: Node2D = ed.occupancy[cell]
		if node is Crate:
			_drag_from = cell
			_drag_prop = null
			ed.select_cell(cell, Vector2i(1, 1), node)
		else:
			var e := Pieces.entry(str(node.get_meta("prop_id")))
			var anchor: Vector2i = node.get_meta("anchor_cell")
			var cells: Vector2i = e["cells"] if not e.is_empty() else Vector2i(1, 1)
			_drag_from = cell
			_drag_prop = node
			ed.select_cell(anchor, cells, node)
	else:
		_drag_from = Vector2i(-1, -1)
		_drag_prop = null
		ed.deselect()


func _release(cell: Vector2i, over_ui: bool) -> void:
	if carrying != "" and not over_ui:
		_try_place(cell)
	elif _drag_prop != null and _drag_from.x >= 0 and not over_ui and cell != _drag_from:
		_move_prop(_drag_prop, cell - _drag_from)
	elif (
		_drag_from.x >= 0
		and not over_ui
		and cell != _drag_from
		and EditorGrid.in_zone(cell)
		and not ed.occupancy.has(cell)
	):
		_move(_drag_from, cell)
	_drag_from = Vector2i(-1, -1)
	_drag_prop = null


func _try_place(cell: Vector2i) -> void:
	var e := Pieces.entry(carrying)
	if e.is_empty():
		return
	if e["class"] == "crate":
		if EditorGrid.in_zone(cell) and not ed.occupancy.has(cell):
			_place(carrying, cell)
			carrying = ""
		return
	var cells: Vector2i = e["cells"]
	for c in LevelEditor.footprint(cell, cells):
		if not EditorGrid.in_zone(c) or ed.occupancy.has(c):
			return  # whole footprint or nothing; keep carrying
	var w := EditorGrid.cell_to_world(cell)
	var prop := {"id": carrying, "x": w.x, "y": w.y}
	ed.current.props.append(prop)
	var body := PropBuilder.spawn_one(ed, prop)
	ed._spawned_props.append(body)
	for c in LevelEditor.footprint(cell, cells):
		ed.occupancy[c] = body
	carrying = ""
	ed.overlay.refresh()


func _place(id: String, cell: Vector2i) -> void:
	var w := EditorGrid.cell_to_world(cell)
	ed.current.crates.append({"x": w.x, "y": w.y, "type": id})
	ed._rebuild()


func _move(from: Vector2i, to: Vector2i) -> void:
	if not ed.occupancy.get(from) is Crate:
		return
	var fw := EditorGrid.cell_to_world(from)
	var tw := EditorGrid.cell_to_world(to)
	for c in ed.current.crates:
		if is_equal_approx(c["x"], fw.x) and is_equal_approx(c["y"], fw.y):
			c["x"] = tw.x
			c["y"] = tw.y
			break
	# Set selection to destination cell before rebuild so _sync_views can re-resolve.
	ed.selection = {"kind": "cell", "cell": to, "cells": Vector2i(1, 1), "node": null}
	ed._rebuild()


func _delete_selected() -> void:
	# Read selection cell from the selection dict (or fall back to overlay for compat).
	var cell: Vector2i
	if ed.selection.get("kind") == "cell":
		cell = ed.selection["cell"]
	else:
		cell = ed.overlay.selected_cell
	if cell.x < 0:
		return
	var node: Variant = ed.occupancy.get(cell)
	if node != null and not node is Crate:
		_delete_prop(node)
		return
	var w := EditorGrid.cell_to_world(cell)
	for i in ed.current.crates.size():
		var c: Dictionary = ed.current.crates[i]
		if is_equal_approx(c["x"], w.x) and is_equal_approx(c["y"], w.y):
			ed.current.crates.remove_at(i)
			break
	_drag_from = Vector2i(-1, -1)
	ed.deselect()
	ed._rebuild()


# Delta-based footprint move: data, occupancy, node, and meta in lockstep.
# A blocked target (out of zone / any foreign occupant) is a no-op.
func _move_prop(body: Node2D, delta: Vector2i) -> void:
	var pid := str(body.get_meta("prop_id"))
	var e := Pieces.entry(pid)
	if e.is_empty():
		return
	var old_anchor: Vector2i = body.get_meta("anchor_cell")
	var new_anchor := old_anchor + delta
	var cells: Vector2i = e["cells"]
	for c in LevelEditor.footprint(new_anchor, cells):
		if not EditorGrid.in_zone(c):
			return
		var occ: Variant = ed.occupancy.get(c)
		if occ != null and occ != body:
			return
	var old_w := EditorGrid.cell_to_world(old_anchor)
	var new_w := EditorGrid.cell_to_world(new_anchor)
	for i in ed.current.props.size():
		var p: Dictionary = ed.current.props[i]
		if (
			p["id"] == pid
			and is_equal_approx(float(p["x"]), old_w.x)
			and is_equal_approx(float(p["y"]), old_w.y)
		):
			var moved := (ed.current.props[i] as Dictionary).duplicate()
			moved["x"] = new_w.x
			moved["y"] = new_w.y
			ed.current.props[i] = moved
			break
	for c in LevelEditor.footprint(old_anchor, cells):
		ed.occupancy.erase(c)
	for c in LevelEditor.footprint(new_anchor, cells):
		ed.occupancy[c] = body
	body.position = PropBuilder.footprint_center(new_w, cells)
	body.set_meta("anchor_cell", new_anchor)
	# Route through select_cell: re-resolves inspector to the fresh anchor.
	ed.select_cell(new_anchor, cells, body)


func _prop_entry_for(body: Node2D) -> Dictionary:
	var pid := str(body.get_meta("prop_id"))
	var w := EditorGrid.cell_to_world(body.get_meta("anchor_cell"))
	for p in ed.current.props:
		if p["id"] == pid and is_equal_approx(float(p["x"]), w.x) and is_equal_approx(float(p["y"]), w.y):
			return p
	return {}


func _delete_prop(body: Node2D) -> void:
	var anchor: Vector2i = body.get_meta("anchor_cell")
	var pid: String = body.get_meta("prop_id")
	for i in ed.current.props.size():
		var pw := EditorGrid.world_to_cell(Vector2(ed.current.props[i]["x"], ed.current.props[i]["y"]))
		if ed.current.props[i]["id"] == pid and pw == anchor:
			ed.current.props.remove_at(i)
			break
	# Erase every occupancy cell whose value points at this body.
	# Works whether the registry id is known or not — no footprint lookup needed.
	var to_erase: Array[Vector2i] = []
	for k in ed.occupancy:
		if ed.occupancy[k] == body:
			to_erase.append(k)
	for k in to_erase:
		ed.occupancy.erase(k)
	ed._spawned_props.erase(body)
	body.queue_free()
	_drag_prop = null
	ed.deselect()


func _update_ghost() -> void:
	var id := carrying
	if id == "" and _drag_from.x >= 0 and _lmb_down:
		var held: Variant = ed.occupancy.get(_drag_from)
		if held != null and held is Crate:
			id = (held as Crate).type_id
		elif _drag_prop != null:
			id = str(_drag_prop.get_meta("prop_id"))
	if id == "":
		if ed.overlay.ghost_cell != Vector2i(-1, -1):
			ed.overlay.ghost_cell = Vector2i(-1, -1)
			ed.overlay.refresh()
		ed.overlay.ghost_cells = Vector2i(1, 1)
		return
	var cell := ed._mouse_cell()
	if _drag_prop != null and _lmb_down:
		cell += (_drag_prop.get_meta("anchor_cell") as Vector2i) - _drag_from
	var e := Pieces.entry(id)
	var ghost_cells := Vector2i(1, 1)
	var ok := false
	if not e.is_empty() and e["class"] != "crate":
		ghost_cells = e["cells"] as Vector2i
		ok = true
		for c in LevelEditor.footprint(cell, ghost_cells):
			var occ: Variant = ed.occupancy.get(c)
			if not EditorGrid.in_zone(c) or (occ != null and occ != _drag_prop):
				ok = false
				break
	else:
		ok = EditorGrid.in_zone(cell) and (not ed.occupancy.has(cell) or cell == _drag_from)
	ed.overlay.ghost_cells = ghost_cells
	if cell == ed.overlay.ghost_cell and ok == ed.overlay.ghost_ok and ed.overlay.ghost_tex == Pieces.texture_for(id):
		return
	ed.overlay.ghost_cell = cell
	ed.overlay.ghost_tex = Pieces.texture_for(id)
	ed.overlay.ghost_ok = ok
	ed.overlay.refresh()


func _show_crate_context(screen_pos: Vector2, cell: Vector2i) -> void:
	if _crate_context == null:
		_crate_context = PopupMenu.new()
		_crate_context.id_pressed.connect(_on_crate_context_item)
		ed.add_child(_crate_context)
		ed.register_popup(_crate_context)
	_info_cell = cell
	_crate_context.clear()
	_crate_context.add_item("Info", 0)
	_crate_context.position = Vector2i(int(screen_pos.x), int(screen_pos.y))
	_crate_context.popup()


func _on_crate_context_item(id: int) -> void:
	if id == 0:
		_show_crate_info(_info_cell)


func _show_crate_info(cell: Vector2i) -> void:
	if not ed.occupancy.has(cell):
		return
	var w := EditorGrid.cell_to_world(cell)
	var type_id := ""
	for c in ed.current.crates:
		if int(c["x"]) == int(w.x) and int(c["y"]) == int(w.y):
			type_id = String(c["type"])
			break
	_info_key = LevelEditor.crate_trigger_key(cell)
	if _crate_info == null:
		_crate_info = AcceptDialog.new()
		_crate_info.title = "Crate Info"
		_crate_info.theme = load("res://resources/ui/kingdom_theme.tres")
		_crate_info.add_button("Copy Key", true, "copy_key")
		_crate_info.custom_action.connect(_on_crate_info_action)
		ed.add_child(_crate_info)
		ed.register_popup(_crate_info)
	_crate_info.dialog_text = (
		"Type: %s\nTrigger key: %s\nGrid cell: (%d, %d)" % [type_id, _info_key, cell.x, cell.y]
	)
	_crate_info.popup_centered()


func _on_crate_info_action(action: StringName) -> void:
	if action == &"copy_key":
		DisplayServer.clipboard_set(_info_key)
		_crate_info.hide()
