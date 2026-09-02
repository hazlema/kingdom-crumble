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

enum Mode { CRATES, SCENERY }

static var resume_layout: LevelLayout = null

var current := LevelLayout.new()
var occupancy := {}  # Vector2i -> Crate
var carrying := ""  # asset id while placing, "" = none
var save_path := ""  # last saved path, "" = unsaved
var mode := Mode.CRATES
var selected_overlay := -1
var _spawned: Array[Crate] = []
var _scenery: Array[NarfDecor] = []
var _drag_from := Vector2i(-1, -1)  # cell a drag-move started on
var _lmb_down := false
var _last_mouse := Vector2.ZERO
# Scenery drag state
var _scenery_dragging := false  # true while LMB drags a selected piece
var _scenery_drag_start_world := Vector2.ZERO  # world pos when drag began
var _scenery_drag_piece_origin := Vector2.ZERO  # piece.position when drag began
var _scenery_handle := -1  # -1 = body, 0-3 = corner, 4 = rotate
# Right-click context menu for scenery pieces
var _scenery_context: PopupMenu = null

@onready var overlay: GridOverlay = $GridOverlay
@onready var palette: EditorPalette = $Ui/Palette
@onready var _gizmo: SceneryGizmo = $SceneryGizmo
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
	menu.intro_edited.connect(func(t: String) -> void: current.intro = t)
	menu.open_intro_requested.connect(func() -> void: menu.open_intro(current.intro))
	menu.scenery_requested.connect(_enter_scenery)
	%SceneryPanel.background_picked.connect(_on_background_picked)
	%SceneryPanel.image_chosen.connect(_on_image_chosen)
	%SceneryPanel.done.connect(_exit_scenery)
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

	if mode == Mode.CRATES:
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
	else:
		_scenery_process(mouse)


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
	_bake_scenery()
	await _capture_thumb()
	LevelStore.save_user(current, stem)


# Save As IS the naming act — the dialog stem is the editor's only title
# field, so forking a level under a new name retitles it too (only-when-
# Untitled left forks wearing the original's title).
func _on_save_as(stem: String) -> void:
	current.title = stem
	_bake_scenery()
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


func _enter_scenery() -> void:
	# Drop any in-flight carry so a held crate doesn't ghost in scenery mode.
	carrying = ""
	# Stale-input hygiene: clear drag/lmb state so a leftover press can't
	# fire a spurious release as a crate move once we return to CRATES mode.
	_drag_from = Vector2i(-1, -1)
	_lmb_down = false
	mode = Mode.SCENERY
	palette.visible = false
	%SceneryPanel.visible = true
	overlay.visible = false
	for c in _spawned:
		c.modulate.a = 0.8
	_refresh_pieces()
	_gizmo.visible = true


func _exit_scenery() -> void:
	selected_overlay = -1
	_gizmo.piece = null
	_gizmo.visible = false
	mode = Mode.CRATES
	%SceneryPanel.visible = false
	palette.visible = true
	overlay.visible = true
	for c in _spawned:
		c.modulate.a = 1.0


func _rebuild() -> void:
	for s in _scenery:
		if is_instance_valid(s):
			s.queue_free()
	_scenery.clear()
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
	_scenery = SceneryBuilder.spawn(self, current)
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
		if mode == Mode.SCENERY:
			_delete_selected_piece()
		else:
			_delete_selected()
	elif event.is_action_pressed("menu"):
		if mode == Mode.SCENERY:
			_exit_scenery()
		elif carrying != "":
			carrying = ""


func _mouse_cell() -> Vector2i:
	return EditorGrid.world_to_cell(get_global_mouse_position())


func _mouse_over_ui(p: Vector2) -> bool:
	var sp: Node = %SceneryPanel
	return (
		palette.get_global_rect().has_point(p)
		or menu.covers_point(p)
		or (sp.visible and (sp as Control).get_global_rect().has_point(p))
	)


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


# Frees and respawns ONLY the _scenery array — crates untouched.
# Used in the import path so entering/being in scenery mode doesn't
# accidentally un-dim the crates (a full _rebuild would reset modulate).
func _rebuild_scenery() -> void:
	for s in _scenery:
		if is_instance_valid(s):
			s.queue_free()
	_scenery.clear()
	_scenery = SceneryBuilder.spawn(self, current)
	# Re-apply dim: crates are already dimmed when we're in scenery mode.
	if mode == Mode.SCENERY:
		for c in _spawned:
			c.modulate.a = 0.8


# Repopulates the %Pieces ItemList: one entry per overlay, thumbnail only.
func _refresh_pieces() -> void:
	var pieces: ItemList = %SceneryPanel.get_node("%Pieces")
	pieces.clear()
	for entry in current.overlays:
		var img_key: String = entry.get("image", "")
		var b64: String = current.images.get(img_key, "")
		var img := LevelJson.decode_png_b64(b64)
		if img == null:
			pieces.add_item("")
			continue
		var tex := ImageTexture.create_from_image(img)
		pieces.add_item("", tex)


# Pure import pipeline — separated so unit tests can call it directly
# without any dialog/filesystem interaction.
# Returns the content-hash key on success, "" on refusal (cap reached).
func import_scenery_image(img: Image) -> String:
	# Downscale so the long edge is at most 512 px, keeping aspect ratio.
	var w := img.get_width()
	var h := img.get_height()
	var long_edge := maxi(w, h)
	if long_edge > 512:
		var scale := 512.0 / float(long_edge)
		var new_w := maxi(1, int(w * scale))
		var new_h := maxi(1, int(h * scale))
		img.resize(new_w, new_h, Image.INTERPOLATE_LANCZOS)

	# Encode to PNG and check size cap, halving if needed.
	var png_bytes := img.save_png_to_buffer()
	var b64 := Marshalls.raw_to_base64(png_bytes)
	while b64.length() > LevelJson.MAX_IMAGE_CHARS:
		var cw := img.get_width()
		var ch := img.get_height()
		if cw <= 1 and ch <= 1:
			break
		img.resize(maxi(1, cw / 2), maxi(1, ch / 2), Image.INTERPOLATE_LANCZOS)
		png_bytes = img.save_png_to_buffer()
		b64 = Marshalls.raw_to_base64(png_bytes)

	var key := LevelJson.image_key(png_bytes)

	# Dedup: if this exact image is already stored, return the existing key.
	if current.images.has(key):
		return key

	# Refuse if we've hit the image cap.
	if current.images.size() >= LevelJson.MAX_IMAGES:
		return ""

	current.images[key] = b64
	return key


# Wired to SceneryPanel.image_chosen signal.
func _on_image_chosen(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null:
		return
	var key := import_scenery_image(img)
	if key == "":
		return
	# Place the new overlay centered on the current camera view.
	var cam_pos: Vector2 = ($Camera as Camera2D).position
	current.overlays.append({"image": key, "x": cam_pos.x, "y": cam_pos.y})
	selected_overlay = current.overlays.size() - 1
	_rebuild_scenery()
	_refresh_pieces()


# ---------------------------------------------------------------------------
# Scenery mode: pointer / handle polling (mirrors CRATES block structure)
# ---------------------------------------------------------------------------

func _scenery_process(mouse: Vector2) -> void:
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var over_ui := menu.any_dialog_open() or _mouse_over_ui(mouse)
	var world := get_global_mouse_position()
	var cam: Camera2D = $Camera
	_gizmo.cam_zoom = cam.zoom

	if lmb and not _lmb_down and not over_ui:
		_scenery_press(world)
	elif not lmb and _lmb_down:
		_scenery_release()
	elif lmb and _lmb_down and _scenery_dragging:
		_scenery_drag(world)

	_lmb_down = lmb

	# Keep gizmo pointed at the selected piece.
	if selected_overlay >= 0 and selected_overlay < _scenery.size():
		var p := _scenery[selected_overlay]
		if is_instance_valid(p):
			_gizmo.piece = p
			_gizmo.queue_redraw()
		else:
			_gizmo.piece = null
			_gizmo.queue_redraw()
	else:
		_gizmo.piece = null
		_gizmo.queue_redraw()


func _scenery_press(world: Vector2) -> void:
	var cam: Camera2D = $Camera
	var zoom := cam.zoom.x

	# Check handles on current selection first.
	if selected_overlay >= 0 and selected_overlay < _scenery.size():
		var h := _hit_handle(world, zoom)
		if h >= 0:
			_scenery_handle = h
			_scenery_dragging = true
			_scenery_drag_start_world = world
			var piece := _scenery[selected_overlay]
			_scenery_drag_piece_origin = piece.position
			return

	# Pick a new piece.
	var idx := _pick_piece(world)
	if idx >= 0:
		selected_overlay = idx
		_scenery_handle = -1  # body drag
		_scenery_dragging = true
		_scenery_drag_start_world = world
		var piece := _scenery[selected_overlay]
		_scenery_drag_piece_origin = piece.position
	else:
		# Deselect.
		selected_overlay = -1
		_scenery_dragging = false


func _scenery_release() -> void:
	if _scenery_dragging and selected_overlay >= 0 and selected_overlay < _scenery.size():
		# Commit position back to overlay dict.
		var piece := _scenery[selected_overlay]
		var o: Dictionary = current.overlays[selected_overlay]
		o["x"] = piece.position.x
		o["y"] = piece.position.y
	_scenery_dragging = false
	_scenery_handle = -1


func _scenery_drag(world: Vector2) -> void:
	if selected_overlay < 0 or selected_overlay >= _scenery.size():
		return
	var piece := _scenery[selected_overlay]
	var o: Dictionary = current.overlays[selected_overlay]
	var delta := world - _scenery_drag_start_world

	if _scenery_handle == -1:
		# Body drag — move piece.
		piece.position = _scenery_drag_piece_origin + delta
	elif _scenery_handle == 4:
		# Rotate handle — angle from piece center to mouse.
		var center := _scenery_drag_piece_origin
		var angle := (world - center).angle() + PI / 2.0
		piece.rotation = angle
		o["_rot"] = angle
	else:
		# Corner resize — aspect-locked scale.
		var center := _scenery_drag_piece_origin
		var dist_now := (world - center).length()
		var dist_start := (_scenery_drag_start_world - center).length()
		if dist_start > 0.01:
			var orig_scale: float = o.get("_scale", 1.0)
			var new_scale := clampf(orig_scale * (dist_now / dist_start), 0.05, 20.0)
			piece.scale = Vector2(new_scale, new_scale)
			o["_scale"] = new_scale


# Returns the index of the topmost piece whose world-space rect contains `world_pos`,
# or -1 if none. Exposed so unit tests can call it directly.
func _pick_piece(world_pos: Vector2) -> int:
	# Iterate in reverse (top-most drawn last).
	for i in range(_scenery.size() - 1, -1, -1):
		var piece := _scenery[i]
		if not is_instance_valid(piece):
			continue
		var rect := piece.get_rect()
		# Transform world_pos into piece's local space to test against un-rotated rect.
		var local := piece.to_local(world_pos)
		# Un-apply scale (piece.scale is set by _scale).
		if piece.scale.x > 0.0 and piece.scale.y > 0.0:
			local /= piece.scale
		# The rect is in local-space after offset; check containment.
		if rect.has_point(local):
			return i
	return -1


# Returns which handle (0-3 corners, 4 rotate) is within hit radius at world_pos,
# or -1 if none. Requires a selected piece.
func _hit_handle(world_pos: Vector2, zoom: float) -> int:
	if selected_overlay < 0 or selected_overlay >= _scenery.size():
		return -1
	var piece := _scenery[selected_overlay]
	if not is_instance_valid(piece) or piece.texture == null:
		return -1
	var radius := SceneryGizmo.HANDLE_RADIUS / zoom
	var corners := SceneryGizmo._rect_corners(
		piece.get_rect(), piece.position, piece.rotation, piece.scale
	)
	for i in 4:
		if world_pos.distance_to(corners[i]) <= radius:
			return i
	# Rotate lollipop.
	var top_mid := (corners[0] + corners[1]) * 0.5
	var up_dir := Vector2(-sin(piece.rotation), -cos(piece.rotation))
	var lollipop := top_mid + up_dir * (SceneryGizmo.ROTATE_LOLLIPOP_DIST / zoom)
	if world_pos.distance_to(lollipop) <= radius:
		return 4
	return -1


# ---------------------------------------------------------------------------
# Delete selected scenery piece + orphan-cleanup
# ---------------------------------------------------------------------------

func _delete_selected_piece() -> void:
	if selected_overlay < 0 or selected_overlay >= current.overlays.size():
		return
	var o: Dictionary = current.overlays[selected_overlay]
	var old_key: String = o.get("image", "")
	current.overlays.remove_at(selected_overlay)
	selected_overlay = -1
	_gizmo.piece = null
	_gizmo.queue_redraw()
	# Drop the image blob if no remaining overlay references it.
	if old_key != "":
		var still_used := false
		for entry in current.overlays:
			if (entry as Dictionary).get("image", "") == old_key:
				still_used = true
				break
		if not still_used:
			current.images.erase(old_key)
	_rebuild_scenery()
	_refresh_pieces()


# ---------------------------------------------------------------------------
# Right-click context menu for scenery pieces
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if mode != Mode.SCENERY:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			var world := get_global_mouse_position()
			var idx := _pick_piece(world)
			if idx >= 0:
				selected_overlay = idx
				_show_scenery_context(mb.global_position)
				get_viewport().set_input_as_handled()


func _show_scenery_context(screen_pos: Vector2) -> void:
	if _scenery_context == null:
		_scenery_context = PopupMenu.new()
		_scenery_context.id_pressed.connect(_on_scenery_context_item)
		add_child(_scenery_context)
	_scenery_context.clear()
	_scenery_context.add_item("Flip H", 0)
	_scenery_context.add_item("Flip V", 1)
	_scenery_context.add_separator()
	_scenery_context.add_item("Delete", 2)
	_scenery_context.position = Vector2i(int(screen_pos.x), int(screen_pos.y))
	_scenery_context.popup()


func _on_scenery_context_item(id: int) -> void:
	if selected_overlay < 0 or selected_overlay >= _scenery.size():
		return
	var piece := _scenery[selected_overlay]
	var o: Dictionary = current.overlays[selected_overlay]
	match id:
		0:  # Flip H
			piece.flip_h = not piece.flip_h
			o["_flip_h"] = piece.flip_h
		1:  # Flip V
			piece.flip_v = not piece.flip_v
			o["_flip_v"] = piece.flip_v
		2:  # Delete
			_delete_selected_piece()


# ---------------------------------------------------------------------------
# Bake: consume edit-state transforms into the raster, re-key the blob.
# Transform order: flip → scale → rotate (flip is pixel-level, then the
# scaled+flipped image is rotated into its bounding box).
# 90°/180°/270° rotations stay pixel-exact because inverse-mapping with
# round() lands on exact source pixels for those multiples.
# Unedited overlays (no underscore keys) are left unchanged — no re-encode churn.
# ---------------------------------------------------------------------------

func _bake_scenery() -> void:
	# Build reference counts for all image keys.
	var ref_count: Dictionary = {}
	for entry in current.overlays:
		var k: String = (entry as Dictionary).get("image", "")
		if k != "":
			ref_count[k] = ref_count.get(k, 0) + 1

	for i in current.overlays.size():
		var o: Dictionary = current.overlays[i]
		var has_edits := false
		for k in o:
			if (k as String).begins_with("_"):
				has_edits = true
				break
		if not has_edits:
			continue

		var old_key: String = o.get("image", "")
		if old_key == "" or not current.images.has(old_key):
			# Strip keys even on missing image to stay consistent.
			_strip_edit_keys(o)
			continue

		var img := LevelJson.decode_png_b64(current.images[old_key])
		if img == null:
			_strip_edit_keys(o)
			continue

		# Apply flip (pixel-level, in place).
		if o.get("_flip_h", false):
			img.flip_x()
		if o.get("_flip_v", false):
			img.flip_y()

		# Apply scale via resize.
		var sc: float = o.get("_scale", 1.0)
		if not is_equal_approx(sc, 1.0):
			var nw := maxi(1, roundi(img.get_width() * sc))
			var nh := maxi(1, roundi(img.get_height() * sc))
			img.resize(nw, nh, Image.INTERPOLATE_LANCZOS)

		# Apply rotation via inverse-mapping into a rotated bounding box.
		var rot: float = o.get("_rot", 0.0)
		if not is_equal_approx(fmod(rot, TAU), 0.0):
			img = _rotate_image(img, rot)

		# Re-encode and re-key.
		var png_bytes := img.save_png_to_buffer()
		var new_key := LevelJson.image_key(png_bytes)
		var new_b64 := Marshalls.raw_to_base64(png_bytes)

		# Store the new blob (dedup: might already exist).
		if not current.images.has(new_key):
			current.images[new_key] = new_b64

		# Update this overlay's key.
		o["image"] = new_key

		# Decrement refcount on old key; erase if orphaned.
		ref_count[old_key] = ref_count.get(old_key, 1) - 1
		if ref_count.get(old_key, 0) <= 0:
			current.images.erase(old_key)

		# Strip edit-state keys.
		_strip_edit_keys(o)

		# Reset the live piece transform so the visual matches the baked image.
		if i < _scenery.size() and is_instance_valid(_scenery[i]):
			var piece := _scenery[i]
			piece.rotation = 0.0
			piece.scale = Vector2.ONE
			piece.flip_h = false
			piece.flip_v = false


static func _strip_edit_keys(o: Dictionary) -> void:
	var to_remove: Array[String] = []
	for k in o:
		if (k as String).begins_with("_"):
			to_remove.append(k)
	for k in to_remove:
		o.erase(k)


# Pure-GDScript inverse-mapping rotation.
# Computes the rotated bounding box size, then for each destination pixel
# inverse-rotates back to source space and samples with bilinear interpolation.
# Transparent pixels outside the source rect become Color(0,0,0,0).
static func _rotate_image(src: Image, rot: float) -> Image:
	var sw := src.get_width()
	var sh := src.get_height()
	src.convert(Image.FORMAT_RGBA8)

	# Rotated bounding box: for a rectangle rotated by `rot`, the enclosing
	# axis-aligned box has dimensions:
	#   w' = |w·cos(r)| + |h·sin(r)|
	#   h' = |w·sin(r)| + |h·cos(r)|
	var abs_cos := absf(cos(rot))
	var abs_sin := absf(sin(rot))
	var dw := roundi(sw * abs_cos + sh * abs_sin)
	var dh := roundi(sw * abs_sin + sh * abs_cos)

	var dst := Image.create(dw, dh, false, Image.FORMAT_RGBA8)
	dst.fill(Color(0, 0, 0, 0))

	# Centers.
	var cx_src := (sw - 1) * 0.5
	var cy_src := (sh - 1) * 0.5
	var cx_dst := (dw - 1) * 0.5
	var cy_dst := (dh - 1) * 0.5

	var cos_r := cos(-rot)  # inverse rotation
	var sin_r := sin(-rot)

	for dy in dh:
		for dx in dw:
			# Vector from dst center.
			var fx := dx - cx_dst
			var fy := dy - cy_dst
			# Inverse-rotate.
			var sx := fx * cos_r - fy * sin_r + cx_src
			var sy := fx * sin_r + fy * cos_r + cy_src
			# Bilinear sample.
			var color := _bilinear_sample(src, sx, sy, sw, sh)
			dst.set_pixel(dx, dy, color)

	return dst


static func _bilinear_sample(
	src: Image, sx: float, sy: float, sw: int, sh: int
) -> Color:
	# Clamp to avoid out-of-bounds — transparent outside source.
	if sx < -0.5 or sy < -0.5 or sx > sw - 0.5 or sy > sh - 0.5:
		return Color(0, 0, 0, 0)

	var x0 := clampi(int(floor(sx)), 0, sw - 1)
	var y0 := clampi(int(floor(sy)), 0, sh - 1)
	var x1 := clampi(x0 + 1, 0, sw - 1)
	var y1 := clampi(y0 + 1, 0, sh - 1)

	var tx: float = sx - floor(sx)
	var ty: float = sy - floor(sy)

	var c00 := src.get_pixel(x0, y0)
	var c10 := src.get_pixel(x1, y0)
	var c01 := src.get_pixel(x0, y1)
	var c11 := src.get_pixel(x1, y1)

	return c00.lerp(c10, tx).lerp(c01.lerp(c11, tx), ty)
