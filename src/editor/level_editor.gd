class_name LevelEditor
extends Node2D

# Editing UX only — world visuals and crate spawning are the game's own
# scenes via LevelBuilder (spec §3 hard rule).
#
# Mouse interaction is polled in _process rather than event-driven: a
# drag that starts on a palette Button never delivers its motion or
# release events to _unhandled_input (the Control captures them), so
# drag-out-of-palette and drag-to-move only work reliably by reading
# Input state directly each frame.

static var resume_layout: LevelLayout = null

var current := LevelLayout.new()
var occupancy := {}  # Vector2i -> Crate
var carrying := ""  # asset id while placing, "" = none
var save_path := ""  # last saved path, "" = unsaved
var _spawned: Array[Crate] = []
var _drag_from := Vector2i(-1, -1)  # cell a drag-move started on
var _lmb_down := false
var _last_mouse := Vector2.ZERO

@onready var overlay: GridOverlay = $GridOverlay
@onready var palette: EditorPalette = $Ui/Palette
@onready var menu: EditorMenu = $Ui/EditorMenu


func _ready() -> void:
	EditorAssets.scan()
	palette.asset_picked.connect(
		func(id: String) -> void:
			carrying = id
			_drag_from = Vector2i(-1, -1)
			overlay.selected_cell = Vector2i(-1, -1)
	)
	menu.save_requested.connect(_on_save)
	menu.save_as_requested.connect(_on_save_as)
	menu.load_requested.connect(_on_load)
	menu.clear_requested.connect(_on_clear)
	menu.exit_requested.connect(_on_exit)
	menu.test_requested.connect(_on_test)
	menu.background_picked.connect(_on_background_picked)
	if resume_layout != null:
		current = resume_layout
		resume_layout = null
	_rebuild()


func _process(_delta: float) -> void:
	var mouse := get_viewport().get_mouse_position()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		$Camera.position -= mouse - _last_mouse
		_clamp_camera()
	_last_mouse = mouse

	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	# Geometry, not gui_get_hovered_control(): during a drag that began
	# on a palette Button the Control keeps mouse capture, so the hover
	# API still reports UI at release and would veto the drop.
	var over_ui := menu.any_dialog_open() or _mouse_over_ui(mouse)
	if lmb and not _lmb_down and not over_ui:
		_press(_mouse_cell())
	elif not lmb and _lmb_down:
		_release(_mouse_cell(), over_ui)
	_lmb_down = lmb
	_update_ghost()


func _press(cell: Vector2i) -> void:
	if carrying != "":
		_try_place(cell)
		return
	if occupancy.has(cell):
		overlay.selected_cell = cell
		_drag_from = cell
	else:
		overlay.selected_cell = Vector2i(-1, -1)
		_drag_from = Vector2i(-1, -1)
	overlay.refresh()


func _release(cell: Vector2i, over_ui: bool) -> void:
	if carrying != "" and not over_ui:
		_try_place(cell)
	elif (
		_drag_from.x >= 0
		and not over_ui
		and cell != _drag_from
		and EditorGrid.in_zone(cell)
		and not occupancy.has(cell)
	):
		_move(_drag_from, cell)
	_drag_from = Vector2i(-1, -1)


func _try_place(cell: Vector2i) -> void:
	if EditorGrid.in_zone(cell) and not occupancy.has(cell):
		_place(carrying, cell)
		carrying = ""


func _on_save() -> void:
	if save_path == "":
		menu.open_save_as()
		return
	var stem := save_path.get_file().get_basename()
	await _capture_thumb()
	LevelStore.save_user(current, stem)


# Save As IS the naming act — the dialog stem is the editor's only title
# field, so forking a level under a new name retitles it too (only-when-
# Untitled left forks wearing the original's title).
func _on_save_as(stem: String) -> void:
	current.title = stem
	await _capture_thumb()
	save_path = LevelStore.save_user(current, stem)


# A failed camera (headless, render hiccup) never wipes a good portrait.
func _capture_thumb() -> void:
	var shot: String = await ThumbCapture.grab(self)
	if shot != "":
		current.thumb = shot
		%Polaroid.show_b64(shot, current.title)


func _on_load(path: String) -> void:
	var loaded := LevelStore.load_level(path)
	if loaded == null:
		menu.show_load_error()
		return
	current = loaded
	save_path = path
	_rebuild()


# Clear = new document. Wiping only the crates once left the old title,
# thumb, and save_path alive — the next Save As inherited the previous
# level's title, and Ctrl+S would overwrite the previous level's file.
func _on_clear() -> void:
	current = LevelLayout.new()
	save_path = ""
	_rebuild()


func _on_exit() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_test() -> void:
	Level.next_layout = current
	Level.return_to_editor = true
	get_tree().change_scene_to_file("res://scenes/level.tscn")


func _on_background_picked(id: String) -> void:
	current.background = id


func _rebuild() -> void:
	for c in _spawned:
		if is_instance_valid(c):
			c.queue_free()
	_spawned.clear()
	occupancy.clear()
	# Snap all coords to cell centres and drop duplicates.
	var seen_cells: Array[Vector2i] = []
	var snapped_crates: Array[Dictionary] = []
	for c in current.crates:
		var cell := EditorGrid.world_to_cell(Vector2(c["x"], c["y"]))
		var snapped_pos := EditorGrid.cell_to_world(cell)
		if seen_cells.has(cell):
			continue
		seen_cells.append(cell)
		snapped_crates.append({"x": snapped_pos.x, "y": snapped_pos.y, "type": c["type"]})
	current.crates = snapped_crates
	_spawned = LevelBuilder.spawn_crates(self, current, true, EditorAssets.texture_for)
	for crate in _spawned:
		occupancy[EditorGrid.world_to_cell(crate.position)] = crate
	overlay.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.ctrl_pressed:
		match event.keycode:
			KEY_T:
				_on_test()
			KEY_S:
				_on_save()  # falls through to Save As when unsaved
	elif event is InputEventKey and event.pressed and event.keycode == KEY_DELETE:
		_delete_selected()
	elif event.is_action_pressed("menu") and carrying != "":
		carrying = ""


func _mouse_cell() -> Vector2i:
	return EditorGrid.world_to_cell(get_global_mouse_position())


func _mouse_over_ui(p: Vector2) -> bool:
	return palette.get_global_rect().has_point(p) or menu.covers_point(p)


# Clamp pan POSITION to the camera limits — past the bounds the display
# pins while position drifts on, and panning back drags through the
# invisible overshoot ("scrolling stopped working").
func _clamp_camera() -> void:
	var cam: Camera2D = $Camera
	var half := get_viewport_rect().size * 0.5 / cam.zoom
	cam.position.x = clampf(cam.position.x, cam.limit_left + half.x, cam.limit_right - half.x)
	cam.position.y = clampf(cam.position.y, cam.limit_top + half.y, cam.limit_bottom - half.y)


func _update_ghost() -> void:
	var id := carrying
	if id == "" and _drag_from.x >= 0 and _lmb_down:
		var held: Crate = occupancy.get(_drag_from)
		if held != null:
			id = held.type_id
	if id == "":
		if overlay.ghost_cell != Vector2i(-1, -1):
			overlay.ghost_cell = Vector2i(-1, -1)
			overlay.refresh()
		return
	var cell := _mouse_cell()
	var ok := EditorGrid.in_zone(cell) and (not occupancy.has(cell) or cell == _drag_from)
	if cell == overlay.ghost_cell and ok == overlay.ghost_ok:
		return
	overlay.ghost_cell = cell
	overlay.ghost_tex = EditorAssets.texture_for(id)
	overlay.ghost_ok = ok
	overlay.refresh()


func _place(id: String, cell: Vector2i) -> void:
	var w := EditorGrid.cell_to_world(cell)
	current.crates.append({"x": w.x, "y": w.y, "type": id})
	_rebuild()


func _move(from: Vector2i, to: Vector2i) -> void:
	var fw := EditorGrid.cell_to_world(from)
	var tw := EditorGrid.cell_to_world(to)
	for c in current.crates:
		if is_equal_approx(c["x"], fw.x) and is_equal_approx(c["y"], fw.y):
			c["x"] = tw.x
			c["y"] = tw.y
			break
	overlay.selected_cell = to
	_rebuild()


func _delete_selected() -> void:
	var cell: Vector2i = overlay.selected_cell
	if cell.x < 0:
		return
	var w := EditorGrid.cell_to_world(cell)
	for i in current.crates.size():
		var c: Dictionary = current.crates[i]
		if is_equal_approx(c["x"], w.x) and is_equal_approx(c["y"], w.y):
			current.crates.remove_at(i)
			break
	overlay.selected_cell = Vector2i(-1, -1)
	_drag_from = Vector2i(-1, -1)
	_rebuild()
