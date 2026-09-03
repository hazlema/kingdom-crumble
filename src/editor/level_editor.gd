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
var _scenery_pieces: Array[NarfDecor] = []
var _drag_from := Vector2i(-1, -1)  # cell a drag-move started on
var _lmb_down := false
var _last_mouse := Vector2.ZERO
# Scenery drag state
var _scenery_dragging := false  # true while LMB drags a selected piece
var _scenery_drag_start_world := Vector2.ZERO  # world pos when drag began
var _scenery_drag_piece_origin := Vector2.ZERO  # piece.position when drag began
var _scenery_handle := -1  # -1 = body, 0-3 = corner, 4 = rotate
var _scenery_drag_press_scale := 1.0  # piece._scale at the moment of press
# Right-click context menu for scenery pieces
var _scenery_context: PopupMenu = null
# RMB context menu state (scenery mode)
var _rmb_press_pos := Vector2.ZERO  # screen pos when RMB was pressed (scenery mode)
var _rmb_down := false              # RMB was pressed this frame in scenery mode
const _CONTEXT_MENU_MOTION_THRESHOLD := 6.0  # px; below this RMB release opens menu

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
	await _bake_and_capture()
	LevelStore.save_user(current, stem)


# Save As IS the naming act — the dialog stem is the editor's only title
# field, so forking a level under a new name retitles it too (only-when-
# Untitled left forks wearing the original's title).
func _on_save_as(stem: String) -> void:
	current.title = stem
	await _bake_and_capture()
	save_path = LevelStore.save_user(current, stem)


# Bake pending scenery edits, refresh the live scene to match, then
# capture the thumb over a CLEAN view (gizmo hidden, crates undimmed) —
# shared by Save and Save As.
func _bake_and_capture() -> void:
	_bake_scenery()
	_rebuild_scenery()
	_refresh_pieces()
	_reopen_inspector()
	if mode == Mode.SCENERY:
		for c in _spawned:
			c.modulate.a = 1.0
	_gizmo.visible = false
	await _capture_thumb()
	_gizmo.visible = mode == Mode.SCENERY
	if mode == Mode.SCENERY:
		for c in _spawned:
			c.modulate.a = 0.8


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
	_rmb_down = false  # a held right-click must not menu on re-entry
	mode = Mode.SCENERY
	palette.visible = false
	%SceneryPanel.visible = true
	overlay.visible = false
	_rebuild_scenery()  # dims crates + pauses behaviors (mode is SCENERY)
	_refresh_pieces()
	_gizmo.visible = true


func _exit_scenery() -> void:
	selected_overlay = -1
	_gizmo.piece = null
	_gizmo.visible = false
	%PieceInspector.close()
	mode = Mode.CRATES
	%SceneryPanel.visible = false
	palette.visible = true
	overlay.visible = true
	for c in _spawned:
		c.modulate.a = 1.0
	# Respawn scenery in CRATES mode: behaviors come back to life (the
	# pause above was editor-session-only; the dict never forgot them).
	_rebuild_scenery()


func _rebuild() -> void:
	for s in _scenery_pieces:
		if is_instance_valid(s):
			s.queue_free()
	_scenery_pieces.clear()
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
	_scenery_pieces = SceneryBuilder.spawn(self, current)
	# Behind the whole stage in the editor preview too (below trebuchet).
	for _zi in _scenery_pieces.size():
		move_child(_scenery_pieces[_zi], 1 + _zi)
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
	var insp: Node = %PieceInspector
	return (
		palette.get_global_rect().has_point(p)
		or menu.covers_point(p)
		or (sp.visible and (sp as Control).get_global_rect().has_point(p))
		or (insp.visible and (insp as Control).get_global_rect().has_point(p))
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


# Frees and respawns ONLY the _scenery_pieces array — crates untouched.
# Used in the import path so entering/being in scenery mode doesn't
# accidentally un-dim the crates (a full _rebuild would reset modulate).
func _rebuild_scenery() -> void:
	for s in _scenery_pieces:
		if is_instance_valid(s):
			s.queue_free()
	_scenery_pieces.clear()
	_scenery_pieces = SceneryBuilder.spawn(self, current)
	# Behind the whole stage in the editor preview too (below trebuchet).
	for _zi in _scenery_pieces.size():
		move_child(_scenery_pieces[_zi], 1 + _zi)
	# Pieces re-emerge wearing any PENDING (unbaked) edit-state — a
	# rebuild must never visually revert edits the dict still carries
	# (import/delete/cap-skip all rebuild mid-session).
	for s in _scenery_pieces:
		if not is_instance_valid(s):
			continue
		var oi: int = s.get_meta("overlay_index", -1)
		if oi < 0 or oi >= current.overlays.size():
			continue
		var o: Dictionary = current.overlays[oi]
		s.rotation = o.get("_rot", 0.0)
		var sc: float = o.get("_scale", 1.0)
		s.scale = Vector2(sc, sc)
		s.flip_h = o.get("_flip_h", false)
		s.flip_v = o.get("_flip_v", false)
	# Re-apply dim and behavior pause while in scenery mode (editor
	# previews are static while editing; the dict keeps the real verb).
	if mode == Mode.SCENERY:
		for c in _spawned:
			c.modulate.a = 0.8
		for s in _scenery_pieces:
			if is_instance_valid(s):
				s.behavior = NarfDecor.Behavior.NONE


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


# Shared size-cap: halve the image until its base64 fits MAX_IMAGE_CHARS.
# Returns [png_bytes: PackedByteArray, b64: String]. Used by import AND bake
# so a baked blob can never bypass the cap the import path enforces.
static func _cap_image_to_max(img: Image) -> Array:
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
	return [png_bytes, b64]


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
	var cap_result := _cap_image_to_max(img)
	var png_bytes: PackedByteArray = cap_result[0]
	var b64: String = cap_result[1]

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
	_reopen_inspector()


# Rebuilds free every live piece — any open inspector must be re-pointed
# at the FRESH piece for the current selection (or closed if none), else
# it displays one overlay while selection means another.
func _reopen_inspector() -> void:
	if selected_overlay >= 0 and selected_overlay < current.overlays.size():
		var piece := _piece_for_overlay(selected_overlay)
		%PieceInspector.open(current.overlays[selected_overlay], piece)
	else:
		%PieceInspector.close()


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

	# RMB context menu: open only on release without significant motion.
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if rmb and not _rmb_down:
		_rmb_press_pos = mouse
		_rmb_down = true
	elif not rmb and _rmb_down:
		_rmb_down = false
		if not menu.any_dialog_open() and not _mouse_over_ui(mouse):
			var travel := mouse.distance_to(_rmb_press_pos)
			if travel < _CONTEXT_MENU_MOTION_THRESHOLD:
				var rmb_world := get_global_mouse_position()
				var idx := _pick_piece(rmb_world)
				if idx >= 0:
					selected_overlay = idx
					_show_scenery_context(mouse)

	# Keep gizmo pointed at the selected piece.
	var _selected_piece := _piece_for_overlay(selected_overlay) if selected_overlay >= 0 else null
	if _selected_piece != null:
		_gizmo.piece = _selected_piece
		_gizmo.queue_redraw()
	else:
		_gizmo.piece = null
		_gizmo.queue_redraw()


func _scenery_press(world: Vector2) -> void:
	var cam: Camera2D = $Camera
	var zoom := cam.zoom.x

	# Check handles on current selection first.
	if selected_overlay >= 0:
		var h := _hit_handle(world, zoom)
		if h >= 0:
			var piece := _piece_for_overlay(selected_overlay)
			if piece == null:
				return
			_scenery_handle = h
			_scenery_dragging = true
			_scenery_drag_start_world = world
			_scenery_drag_piece_origin = piece.position
			var po: Dictionary = current.overlays[selected_overlay]
			_scenery_drag_press_scale = po.get("_scale", 1.0)
			return

	# Pick a new piece.
	var idx := _pick_piece(world)
	if idx >= 0:
		var piece := _piece_for_overlay(idx)
		if piece == null:
			return
		selected_overlay = idx
		_scenery_handle = -1  # body drag
		_scenery_dragging = true
		_scenery_drag_start_world = world
		_scenery_drag_piece_origin = piece.position
		var po: Dictionary = current.overlays[selected_overlay]
		_scenery_drag_press_scale = po.get("_scale", 1.0)
		%PieceInspector.open(po, piece)
	else:
		# Deselect.
		selected_overlay = -1
		_scenery_dragging = false
		%PieceInspector.close()


func _scenery_release() -> void:
	if _scenery_dragging and selected_overlay >= 0 and selected_overlay < current.overlays.size():
		var piece := _piece_for_overlay(selected_overlay)
		if piece != null:
			var o: Dictionary = current.overlays[selected_overlay]
			o["x"] = piece.position.x
			o["y"] = piece.position.y
	_scenery_dragging = false
	_scenery_handle = -1


func _scenery_drag(world: Vector2) -> void:
	if selected_overlay < 0 or selected_overlay >= current.overlays.size():
		return
	var piece := _piece_for_overlay(selected_overlay)
	if piece == null:
		return
	var o: Dictionary = current.overlays[selected_overlay]
	var delta := world - _scenery_drag_start_world

	if _scenery_handle == -1:
		# Body drag — move piece, and keep overlay dict in sync for mid-drag saves.
		piece.position = _scenery_drag_piece_origin + delta
		o["x"] = piece.position.x
		o["y"] = piece.position.y
	elif _scenery_handle == 4:
		# Rotate handle — angle from piece center to mouse.
		var center := _scenery_drag_piece_origin
		var angle := (world - center).angle() + PI / 2.0
		piece.rotation = angle
		o["_rot"] = angle
	else:
		# Corner resize — aspect-locked scale.
		# Uses the scale captured at PRESS time so each frame computes from the
		# original, preventing per-frame compounding.
		var center := _scenery_drag_piece_origin
		var dist_now := (world - center).length()
		var dist_start := (_scenery_drag_start_world - center).length()
		if dist_start > 0.01:
			# Clamp: the baked long edge must not exceed 1024 px.
			var tex := piece.texture
			var max_scale := 20.0
			if tex != null:
				var long_edge := maxi(tex.get_width(), tex.get_height())
				if long_edge > 0:
					max_scale = minf(20.0, 1024.0 / float(long_edge))
			var new_scale := clampf(_scenery_drag_press_scale * (dist_now / dist_start), 0.05, max_scale)
			piece.scale = Vector2(new_scale, new_scale)
			o["_scale"] = new_scale


# Returns the NarfDecor piece for the given overlay source index, or null.
func _piece_for_overlay(overlay_idx: int) -> NarfDecor:
	for p in _scenery_pieces:
		if is_instance_valid(p) and p.has_meta("overlay_index") and p.get_meta("overlay_index") == overlay_idx:
			return p
	return null


# Returns the index of the topmost piece whose world-space rect contains `world_pos`,
# or -1 if none. Exposed so unit tests can call it directly.
func _pick_piece(world_pos: Vector2) -> int:
	# Iterate in reverse (top-most drawn last).
	for i in range(_scenery_pieces.size() - 1, -1, -1):
		var piece := _scenery_pieces[i]
		if not is_instance_valid(piece):
			continue
		var rect := piece.get_rect()
		# to_local() already accounts for the piece's position, rotation, and scale;
		# the rect from get_rect() is in un-scaled local space — no further division needed.
		var local := piece.to_local(world_pos)
		if rect.has_point(local):
			return piece.get_meta("overlay_index", i) as int
	return -1


# Returns which handle (0-3 corners, 4 rotate) is within hit radius at world_pos,
# or -1 if none. Requires a selected piece.
func _hit_handle(world_pos: Vector2, zoom: float) -> int:
	if selected_overlay < 0:
		return -1
	var piece := _piece_for_overlay(selected_overlay)
	if piece == null or piece.texture == null:
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
	%PieceInspector.close()
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

# RMB context menu is handled via release-based polling in _scenery_process.


func _show_scenery_context(screen_pos: Vector2) -> void:
	if _scenery_context == null:
		_scenery_context = PopupMenu.new()
		_scenery_context.id_pressed.connect(_on_scenery_context_item)
		add_child(_scenery_context)
	_scenery_context.clear()
	_scenery_context.add_item("Flip H", 0)
	_scenery_context.add_item("Flip V", 1)
	_scenery_context.add_item("Drop Background", 3)
	_scenery_context.add_separator()
	_scenery_context.add_item("Delete", 2)
	_scenery_context.position = Vector2i(int(screen_pos.x), int(screen_pos.y))
	_scenery_context.popup()


func _on_scenery_context_item(id: int) -> void:
	if selected_overlay < 0 or selected_overlay >= current.overlays.size():
		return
	var piece := _piece_for_overlay(selected_overlay)
	if piece == null and id != 2:
		return
	var o: Dictionary = current.overlays[selected_overlay]
	match id:
		0:  # Flip H
			if piece != null:
				piece.flip_h = not piece.flip_h
				o["_flip_h"] = piece.flip_h
		1:  # Flip V
			if piece != null:
				piece.flip_v = not piece.flip_v
				o["_flip_v"] = piece.flip_v
		2:  # Delete
			_delete_selected_piece()
		3:  # Drop Background
			_drop_background()


# The darkroom, in-engine (owner: "drop background"): flat AI-image
# backdrops (the classic black/white card) become transparency. The
# four corners vote on the background color; if they disagree there is
# no uniform background and the op declines. Destructive by design —
# recovery is delete + re-import (the source file never left the disk).
static func _strip_background(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	if w < 4 or h < 4:
		return null
	var corners: Array[Color] = [
		img.get_pixel(1, 1),
		img.get_pixel(w - 2, 1),
		img.get_pixel(1, h - 2),
		img.get_pixel(w - 2, h - 2),
	]
	var bg := Color(0, 0, 0, 0)
	for c in corners:
		bg += c
	bg *= 0.25
	for c in corners:
		if Vector3(c.r - bg.r, c.g - bg.g, c.b - bg.b).length() > 0.15:
			return null
	# Flood-fill from the border: only background CONNECTED to the frame
	# is keyed — a king's black pupils on a black card stay landlocked
	# and untouched (the global-distance version blinded the poor frog).
	var dist := PackedFloat32Array()
	dist.resize(w * h)
	for y in h:
		for x in w:
			var px := img.get_pixel(x, y)
			dist[y * w + x] = Vector3(px.r - bg.r, px.g - bg.g, px.b - bg.b).length()
	var keyed := PackedByteArray()
	keyed.resize(w * h)
	var queue: Array[int] = []
	for x in w:
		for y: int in [0, h - 1]:
			var i := y * w + x
			if dist[i] < 0.35 and keyed[i] == 0:
				keyed[i] = 1
				queue.append(i)
	for y in h:
		for x: int in [0, w - 1]:
			var i := y * w + x
			if dist[i] < 0.35 and keyed[i] == 0:
				keyed[i] = 1
				queue.append(i)
	while not queue.is_empty():
		var i: int = queue.pop_back()
		var ix := i % w
		var iy := i / w
		for n in [[ix + 1, iy], [ix - 1, iy], [ix, iy + 1], [ix, iy - 1]]:
			var nx: int = n[0]
			var ny: int = n[1]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var ni := ny * w + nx
			if keyed[ni] == 0 and dist[ni] < 0.35:
				keyed[ni] = 1
				queue.append(ni)
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var i := y * w + x
			var px := img.get_pixel(x, y)
			if keyed[i] == 0:
				out.set_pixel(x, y, px)
				continue
			var a := clampf((dist[i] - 0.10) / 0.25, 0.0, 1.0) * px.a
			if a <= 0.001:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				# Unmix the background's contribution from edge blends.
				var r := clampf((px.r - (1.0 - a) * bg.r) / a, 0.0, 1.0)
				var g := clampf((px.g - (1.0 - a) * bg.g) / a, 0.0, 1.0)
				var b := clampf((px.b - (1.0 - a) * bg.b) / a, 0.0, 1.0)
				out.set_pixel(x, y, Color(r, g, b, a))
	return out


func _drop_background() -> void:
	if selected_overlay < 0 or selected_overlay >= current.overlays.size():
		return
	var o: Dictionary = current.overlays[selected_overlay]
	var old_key := str(o.get("image", ""))
	var img := LevelJson.decode_png_b64(str(current.images.get(old_key, "")))
	if img == null:
		return
	var stripped := _strip_background(img)
	if stripped == null:
		push_warning("Drop Background: corners disagree — no uniform backdrop found")
		return
	var cap_result := _cap_image_to_max(stripped)
	var png_bytes: PackedByteArray = cap_result[0]
	var new_b64: String = cap_result[1]
	var new_key := LevelJson.image_key(png_bytes)
	if new_key != old_key:
		var refs := 0
		for entry in current.overlays:
			if str(entry.get("image", "")) == old_key:
				refs += 1
		if (
			not current.images.has(new_key)
			and refs > 1
			and current.images.size() >= LevelJson.MAX_IMAGES
		):
			push_warning("Drop Background: image cap full")
			return
		if not current.images.has(new_key):
			current.images[new_key] = new_b64
		o["image"] = new_key
		if refs <= 1:
			current.images.erase(old_key)
	_rebuild_scenery()
	_refresh_pieces()
	_reopen_inspector()


# ---------------------------------------------------------------------------
# Bake: consume edit-state transforms into the raster, re-key the blob.
# Transform order: flip → scale → rotate (flip is pixel-level, then the
# scaled+flipped image is rotated into its bounding box).
# 90°/180°/270° rotations stay pixel-exact via the epsilon-guarded ceil
# bbox (swallows cos(PI/2)'s 1e-17 dust) + unclamped-floor bilinear
# (epsilon-negative coords land full-weight on the correct clamped pixel).
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

		# Re-encode and cap.
		var cap_result := _cap_image_to_max(img)
		var png_bytes: PackedByteArray = cap_result[0]
		var new_b64: String = cap_result[1]
		var new_key := LevelJson.image_key(png_bytes)

		if new_key != old_key:
			# Would storing this new blob exceed the image cap?
			# Allow only if old_key is being orphaned (net count stays same).
			var old_still_needed: bool = ref_count.get(old_key, 0) > 1
			if not current.images.has(new_key) and old_still_needed and current.images.size() >= LevelJson.MAX_IMAGES:
				# Cap hit: skip bake for this overlay, keep its underscore edit-state.
				push_warning("SceneryBake: skipping overlay %d — image cap full" % i)
				continue
			# Store the new blob (dedup: might already exist under new_key).
			if not current.images.has(new_key):
				current.images[new_key] = new_b64
			# Update this overlay's key.
			o["image"] = new_key
			# Decrement refcount on old key; erase if orphaned.
			ref_count[old_key] = ref_count.get(old_key, 1) - 1
			if ref_count.get(old_key, 0) <= 0:
				current.images.erase(old_key)

		# Strip edit-state keys (always — identity bake still consumed them).
		_strip_edit_keys(o)

		# Reset the live piece transform so the visual matches the baked image.
		var live_piece := _piece_for_overlay(i)
		if live_piece != null:
			var piece := live_piece
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
	# ceili guards the half-pixel clip at odd angles; the tiny epsilon
	# guards ceili against cos(PI/2)'s 6e-17 dust inflating exact
	# 90-degree boxes by a whole pixel.
	var dw := maxi(1, ceili(sw * abs_cos + sh * abs_sin - 0.001))
	var dh := maxi(1, ceili(sw * abs_sin + sh * abs_cos - 0.001))

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

	# Compute unclamped floor first so tx/ty are always in [0,1).
	var x0f := floorf(sx)
	var y0f := floorf(sy)
	var tx: float = sx - x0f
	var ty: float = sy - y0f
	var x0 := clampi(int(x0f), 0, sw - 1)
	var y0 := clampi(int(y0f), 0, sh - 1)
	var x1 := clampi(int(x0f) + 1, 0, sw - 1)
	var y1 := clampi(int(y0f) + 1, 0, sh - 1)

	var c00 := src.get_pixel(x0, y0)
	var c10 := src.get_pixel(x1, y0)
	var c01 := src.get_pixel(x0, y1)
	var c11 := src.get_pixel(x1, y1)

	# Premultiplied-alpha bilinear: lerp premultiplied channels, then unpremultiply.
	# Prevents transparent-black fringing at alpha boundaries.
	var a00 := c00.a
	var a10 := c10.a
	var a01 := c01.a
	var a11 := c11.a
	var r := c00.r * a00 * (1 - tx) * (1 - ty) + c10.r * a10 * tx * (1 - ty) + c01.r * a01 * (1 - tx) * ty + c11.r * a11 * tx * ty
	var g := c00.g * a00 * (1 - tx) * (1 - ty) + c10.g * a10 * tx * (1 - ty) + c01.g * a01 * (1 - tx) * ty + c11.g * a11 * tx * ty
	var b := c00.b * a00 * (1 - tx) * (1 - ty) + c10.b * a10 * tx * (1 - ty) + c01.b * a01 * (1 - tx) * ty + c11.b * a11 * tx * ty
	var a := a00 * (1 - tx) * (1 - ty) + a10 * tx * (1 - ty) + a01 * (1 - tx) * ty + a11 * tx * ty
	if a < 0.00001:
		return Color(0, 0, 0, 0)
	return Color(r / a, g / a, b / a, a)
