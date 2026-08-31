class_name LevelEditor
extends Node2D

# Editing UX only — world visuals and crate spawning are the game's own
# scenes via LevelBuilder (spec §3 hard rule).

static var resume_layout: LevelLayout = null

var current := LevelLayout.new()
var occupancy := {}           # Vector2i -> Crate
var carrying := ""            # asset id while placing, "" = none
var moving_from := Vector2i(-1, -1)
var save_path := ""           # last saved path, "" = unsaved
var _spawned: Array[Crate] = []

@onready var overlay: GridOverlay = $GridOverlay
@onready var palette: EditorPalette = $Ui/Palette
@onready var menu: EditorMenu = $Ui/EditorMenu

func _ready() -> void:
	EditorAssets.scan()
	palette.asset_picked.connect(func(id: String) -> void:
		carrying = id
		moving_from = Vector2i(-1, -1)
		overlay.selected_cell = Vector2i(-1, -1))
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

func _on_save() -> void:
	if save_path == "":
		menu.open_save_as()
	else:
		var stem := save_path.get_file().get_basename()
		LevelStore.save_user(current, stem)

func _on_save_as(stem: String) -> void:
	if current.title == "Untitled":
		current.title = stem
	save_path = LevelStore.save_user(current, stem)

func _on_load(path: String) -> void:
	var loaded := LevelStore.load_level(path)
	if loaded == null:
		menu.show_load_error()
		return
	current = loaded
	save_path = path
	_rebuild()

func _on_clear() -> void:
	current.crates.clear()
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
	var snapped: Array[Dictionary] = []
	for c in current.crates:
		var cell := EditorGrid.world_to_cell(Vector2(c["x"], c["y"]))
		var snapped_pos := EditorGrid.cell_to_world(cell)
		if seen_cells.has(cell):
			continue
		seen_cells.append(cell)
		snapped.append({"x": snapped_pos.x, "y": snapped_pos.y, "type": c["type"]})
	current.crates = snapped
	_spawned = LevelBuilder.spawn_crates(self, current, true, EditorAssets.texture_for)
	for crate in _spawned:
		occupancy[EditorGrid.world_to_cell(crate.position)] = crate
	overlay.refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion \
			and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		$Camera.global_position -= event.relative
	elif event is InputEventMouseMotion:
		_update_ghost()
	elif event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_click()
		elif carrying != "" and _mouse_cell().x >= 0:
			_on_click()  # drag-release placement
	elif event is InputEventKey and event.pressed \
			and event.keycode == KEY_DELETE:
		_delete_selected()
	elif event.is_action_pressed("menu") and carrying != "":
		carrying = ""
		_update_ghost()

func _mouse_cell() -> Vector2i:
	return EditorGrid.world_to_cell(get_global_mouse_position())

func _update_ghost() -> void:
	if carrying == "":
		overlay.ghost_cell = Vector2i(-1, -1)
	else:
		var cell := _mouse_cell()
		overlay.ghost_cell = cell
		overlay.ghost_tex = EditorAssets.texture_for(carrying)
		overlay.ghost_ok = EditorGrid.in_zone(cell) \
			and not occupancy.has(cell)
	overlay.refresh()

func _on_click() -> void:
	var cell := _mouse_cell()
	if carrying != "":
		if EditorGrid.in_zone(cell) and not occupancy.has(cell):
			_place(carrying, cell)
			carrying = ""
			_update_ghost()
		return
	if moving_from.x >= 0 and EditorGrid.in_zone(cell) \
			and not occupancy.has(cell):
		_move(moving_from, cell)
		moving_from = Vector2i(-1, -1)
		return
	if occupancy.has(cell):
		overlay.selected_cell = cell
		moving_from = cell
	else:
		overlay.selected_cell = Vector2i(-1, -1)
		moving_from = Vector2i(-1, -1)
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
	moving_from = Vector2i(-1, -1)
	_rebuild()
