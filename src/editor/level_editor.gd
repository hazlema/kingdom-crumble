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
var save_path := ""  # last saved path, "" = unsaved
var _spawned: Array[Crate] = []
var _spawned_props: Array[Node2D] = []
var _scenery_pieces: Array[NarfDecor] = []
var _last_mouse := Vector2.ZERO
# RMB context menu state (shared between crate and scenery modes)
var _rmb_press_pos := Vector2.ZERO  # screen pos when RMB was pressed
var _rmb_down := false              # RMB was pressed this frame
const _CONTEXT_MENU_MOTION_THRESHOLD := 6.0  # px; below this RMB release opens menu
const _HIDDEN_GHOST_ALPHA := 0.4  # editor-only alpha for hidden overlay pieces

var _grid_tool: GridTool
var _scenery_tool: SceneryTool
var _tool: EditorTool  # the active tool


# Derived property — tests and _unhandled_input read this; it stays as the
# single authoritative mode indicator, driven by which tool is active.
var mode: Mode:
	get: return Mode.SCENERY if _tool == _scenery_tool else Mode.CRATES


# Forwarders — tests access these as editor properties/methods:
var carrying: String:
	get: return _grid_tool.carrying
	set(v): _grid_tool.carrying = v

var _crate_info: AcceptDialog:
	get: return _grid_tool._crate_info

var _info_key: String:
	get: return _grid_tool._info_key

# Scenery forwarder — tests write/read selected_overlay via the editor.
var selected_overlay: int:
	get: return _scenery_tool.selected_overlay
	set(v): _scenery_tool.selected_overlay = v

@onready var overlay: GridOverlay = $GridOverlay
@onready var palette: EditorPalette = $Ui/Palette
@onready var _gizmo: SceneryGizmo = $SceneryGizmo
@onready var menu: EditorMenu = $Ui/EditorMenu


func inspector() -> PieceInspector:
	return %PieceInspector


func gizmo() -> SceneryGizmo:
	return _gizmo


func camera() -> Camera2D:
	return $Camera


# Shared by all tools: true exactly when this frame is an RMB release
# without significant motion (a moving RMB is a camera pan).
func rmb_menu_release(mouse: Vector2, over_ui: bool) -> bool:
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if rmb and not _rmb_down:
		_rmb_press_pos = mouse
		_rmb_down = true
	elif not rmb and _rmb_down:
		_rmb_down = false
		return not over_ui and mouse.distance_to(_rmb_press_pos) < _CONTEXT_MENU_MOTION_THRESHOLD
	return false


func switch_tool(next: EditorTool) -> void:
	_tool.exit()
	_tool = next
	_tool.enter()


func _ready() -> void:
	_grid_tool = GridTool.new(self)
	_scenery_tool = SceneryTool.new(self)
	_tool = _grid_tool  # start in CRATES mode
	Pieces.scan()
	palette.asset_picked.connect(
		func(id: String) -> void:
			_grid_tool.carrying = id
			_grid_tool._drag_from = Vector2i(-1, -1)
			_grid_tool._drag_prop = null
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
	menu.download_requested.connect(_on_download)
	menu.upload_requested.connect(_on_upload)
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
		# Geometry, not gui_get_hovered_control(): during a drag that began
		# on a palette Button the Control keeps mouse capture, so the hover
		# API still reports UI at release and would veto the drop.
		var over_ui := (
			menu.any_dialog_open()
			or _mouse_over_ui(mouse)
			or (_grid_tool._crate_info != null and _grid_tool._crate_info.visible)
		)
		_tool.process(mouse, over_ui)
	else:
		_tool.process(mouse, false)


# ---------------------------------------------------------------------------
# Forwarders — GridTool owns these; editor exposes them so tests and
# _unhandled_input can call them on the editor directly.
# ---------------------------------------------------------------------------

func _press(cell: Vector2i) -> void:
	_grid_tool._press(cell)


func _release(cell: Vector2i, over_ui: bool) -> void:
	_grid_tool._release(cell, over_ui)


func _delete_selected() -> void:
	_grid_tool._delete_selected()


func _show_crate_info(cell: Vector2i) -> void:
	_grid_tool._show_crate_info(cell)


# ---------------------------------------------------------------------------
# Forwarders — SceneryTool owns these; editor exposes them so tests can
# call them on the editor directly.
# ---------------------------------------------------------------------------

func _delete_selected_piece() -> void:
	_scenery_tool._delete_selected_piece()


func _drop_background() -> void:
	_scenery_tool._drop_background()


func _pick_piece(world_pos: Vector2) -> int:
	return _scenery_tool._pick_piece(world_pos)


# Pure iteration logic — shared by editor and tool to avoid duplication.
# Arguments: pieces array and index to search for.
static func _piece_for_overlay_from_array(pieces: Array, overlay_idx: int) -> NarfDecor:
	for p in pieces:
		if is_instance_valid(p) and p.has_meta("overlay_index") and p.get_meta("overlay_index") == overlay_idx:
			return p
	return null


# Instance wrapper for test contract — tests call ed._piece_for_overlay(idx).
func _piece_for_overlay(overlay_idx: int) -> NarfDecor:
	return LevelEditor._piece_for_overlay_from_array(_scenery_pieces, overlay_idx)


func _on_save() -> void:
	if save_path == "":
		menu.open_save_as()
		return
	var stem := save_path.get_file().get_basename()
	await _bake_and_capture()
	if LevelStore.save_user(current, stem) == "":
		menu.show_save_error(LevelJson.last_error)


# Save As IS the naming act — the dialog stem is the editor's only title
# field, so forking a level under a new name retitles it too (only-when-
# Untitled left forks wearing the original's title).
func _on_save_as(stem: String) -> void:
	current.title = stem
	await _bake_and_capture()
	save_path = LevelStore.save_user(current, stem)
	if save_path == "":
		menu.show_save_error(LevelJson.last_error)
	else:
		menu.suggested_stem = stem


# Bake pending scenery edits, refresh the live scene to match, then
# capture the thumb over a CLEAN view (gizmo hidden, crates undimmed) —
# shared by Save and Save As.
func _bake_and_capture() -> void:
	var skipped := _bake_scenery()
	if skipped > 0:
		# Honest failure (audit: the cap-skip used to vanish silently at
		# save while the editor preview kept showing the edit).
		menu.show_save_error(
			"%d scenery change(s) hit the image limit and will NOT be saved" % skipped
		)
	_rebuild_scenery()
	_refresh_pieces()
	_scenery_tool._reopen_inspector()
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
		menu.show_load_error(LevelJson.last_error)
		return
	current = loaded
	save_path = path
	menu.suggested_stem = path.get_file().get_basename()
	_rebuild()


# --- Browser level sharing (audit #6): the one-file story, web edition ---

var _upload_cb: JavaScriptObject  # held so it isn't garbage-collected


# Hand the current level to the browser as a JSON download. Bakes and
# validates through the same gate as Save -- never share what the
# loader would refuse.
func _on_download() -> void:
	await _bake_and_capture()
	var text := LevelJson.serialize(current)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or LevelJson.validate(parsed) != "":
		menu.show_save_error(LevelJson.last_error)
		return
	var stem := LevelStore.sanitize_stem(current.title)
	if stem == "":
		stem = "level"
	var b64 := Marshalls.utf8_to_base64(text)
	JavaScriptBridge.eval(
		(
			"(function(){var a=document.createElement('a');"
			+ "a.href='data:application/json;base64,%s';" % b64
			+ "a.download='%s.json';" % stem
			+ "a.click();})();"
		),
		true
	)


# Take a friend's level file in. Same trust posture as any load:
# parse+validate or a spoken refusal, never a crash.
func _on_upload() -> void:
	_upload_cb = JavaScriptBridge.create_callback(_on_upload_text)
	var window := JavaScriptBridge.get_interface("window")
	window.kcLevelUploadCallback = _upload_cb
	JavaScriptBridge.eval(
		(
			"(function(){var inp=document.createElement('input');"
			+ "inp.type='file';inp.accept='.json';"
			+ "inp.onchange=function(e){var f=e.target.files[0];if(!f)return;"
			+ "var r=new FileReader();"
			+ "r.onload=function(){window.kcLevelUploadCallback(f.name,r.result);};"
			+ "r.readAsText(f);};inp.click();})();"
		),
		true
	)


func _on_upload_text(args: Array) -> void:
	if args.size() < 2:
		return
	var loaded := LevelJson.parse(str(args[1]))
	if loaded == null:
		menu.show_load_error(LevelJson.last_error)
		return
	current = loaded
	save_path = ""  # imported document: Save prompts for a name
	menu.suggested_stem = LevelStore.sanitize_stem(loaded.title)
	_rebuild()


# Clear = new document. Wiping only the crates once left the old title,
# thumb, and save_path alive — the next Save As inherited the previous
# level's title, and Ctrl+S would overwrite the previous level's file.
func _on_clear() -> void:
	current = LevelLayout.new()
	save_path = ""
	menu.suggested_stem = ""
	_rebuild()


func _on_exit() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_test() -> void:
	# Bake pending scenery transforms first so TEST shows exactly what
	# save would (owner's F3 call: no untransformed ghosts in playtests).
	var skipped := _bake_scenery()
	if skipped > 0:
		menu.show_save_error(
			"%d scenery change(s) hit the image limit and won't appear in TEST" % skipped
		)
	Level.next_layout = current
	Level.return_to_editor = true
	get_tree().change_scene_to_file("res://scenes/level.tscn")


func _on_background_picked(id: String) -> void:
	current.background = id


# Thin forwarders — kept for test-contract and signal wiring.
func _enter_scenery() -> void:
	switch_tool(_scenery_tool)


func _exit_scenery() -> void:
	# Always run the full exit cleanup, even if already in CRATES mode,
	# to preserve test-contract behavior (some tests call _exit_scenery
	# without a preceding _enter_scenery to clean up inspector state).
	if _tool != _grid_tool:
		switch_tool(_grid_tool)
	else:
		_scenery_tool.exit()


func _rebuild() -> void:
	%PieceInspector.close()
	for s in _scenery_pieces:
		if is_instance_valid(s):
			s.queue_free()
	_scenery_pieces.clear()
	for c in _spawned:
		if is_instance_valid(c):
			c.queue_free()
	_spawned.clear()
	for p in _spawned_props:
		if is_instance_valid(p):
			p.queue_free()
	_spawned_props.clear()
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
	_spawned = LevelBuilder.spawn_crates(self, current, true, Pieces.texture_for)
	for crate in _spawned:
		occupancy[EditorGrid.world_to_cell(crate.position)] = crate
	var kept_props: Array[Dictionary] = []
	for p in current.props:
		var anchor := EditorGrid.world_to_cell(Vector2(p["x"], p["y"]))
		var e := Pieces.entry(str(p["id"]))
		if e.is_empty() or e["class"] == "crate":
			push_warning("editor: dropping unknown prop '%s'" % p.get("id"))
			continue
		var blocked := false
		for c in LevelEditor.footprint(anchor, e["cells"]):
			if not EditorGrid.in_zone(c) or occupancy.has(c):
				blocked = true
				break
		if blocked:
			push_warning("editor: dropping overlapping prop '%s'" % p["id"])
			continue
		var snapped := EditorGrid.cell_to_world(anchor)
		var kept := (p as Dictionary).duplicate()
		kept["id"] = str(p["id"])
		kept["x"] = snapped.x
		kept["y"] = snapped.y
		kept_props.append(kept)
		var body := PropBuilder.spawn_one(self, kept)
		_spawned_props.append(body)
		for c in LevelEditor.footprint(anchor, e["cells"]):
			occupancy[c] = body
	current.props = kept_props
	# One spawn path for scenery: _rebuild_scenery owns z-order, pending
	# edit-state, hidden-piece ghosting, and rehome (load used to spawn
	# inline and skipped the ghost pass — hidden pieces were invisible
	# until the first EDIT SCENERY visit).
	_rebuild_scenery()
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
		# Hidden pieces (linked-trigger reveals) spawn invisible in the
		# game; the editor ghosts them instead so they stay editable.
		if o.get("hidden", false) == true:
			s.visible = true
			s.modulate.a = _HIDDEN_GHOST_ALPHA
	# Pieces keep their live verbs while editing (owner: adding a second
	# image used to freeze the first one's animation). rehome() re-anchors
	# each piece to its just-applied transform so nothing snaps.
	for s2 in _scenery_pieces:
		if is_instance_valid(s2):
			s2.rehome()
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
		var factor := 512.0 / float(long_edge)
		var new_w := maxi(1, int(w * factor))
		var new_h := maxi(1, int(h * factor))
		img.resize(new_w, new_h, Image.INTERPOLATE_LANCZOS)

	# Encode to PNG and check size cap, halving if needed.
	var cap_result := SceneryBake._cap_image_to_max(img)
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


# The overlay cap, enforced at the door (audit P1: adding a REUSED
# image dodged the distinct-image cap, minting levels the loader
# refuses to open).
func can_add_overlay() -> bool:
	return current.overlays.size() < LevelJson.MAX_OVERLAYS


# Wired to SceneryPanel.image_chosen signal.
func _on_image_chosen(path: String) -> void:
	if not can_add_overlay():
		push_warning("SceneryPanel: overlay cap reached (%d)" % LevelJson.MAX_OVERLAYS)
		return
	var img := Image.load_from_file(path)
	if img == null:
		return
	var key := import_scenery_image(img)
	if key == "":
		return
	# Place the new overlay centered on the current camera view.
	var cam_pos: Vector2 = ($Camera as Camera2D).position
	current.overlays.append({"image": key, "x": cam_pos.x, "y": cam_pos.y})
	_scenery_tool.selected_overlay = current.overlays.size() - 1
	_rebuild_scenery()
	_refresh_pieces()
	_scenery_tool._reopen_inspector()


# ---------------------------------------------------------------------------
# Bake: consume edit-state transforms into the raster, re-key the blob.
# Transform order: flip → scale → rotate (flip is pixel-level, then the
# scaled+flipped image is rotated into its bounding box).
# 90°/180°/270° rotations stay pixel-exact via the epsilon-guarded ceil
# bbox (swallows cos(PI/2)'s 1e-17 dust) + unclamped-floor bilinear
# (epsilon-negative coords land full-weight on the correct clamped pixel).
# Unedited overlays (no underscore keys) are left unchanged — no re-encode churn.
# ---------------------------------------------------------------------------

# Test-contract forwarder: delegates pure bake to SceneryBake, then
# resets the live piece transforms so the editor view matches the
# freshly-baked images. The live-piece reset is editor-side state
# (calls _piece_for_overlay which iterates _scenery_pieces); it was
# NOT moved to SceneryBake because it is not a pure function of the layout.
func _bake_scenery() -> int:
	var skipped := SceneryBake.bake(current)
	# Reset the live piece transform so the visual matches the baked image.
	# Only reset pieces whose bake succeeded (no pending underscore edit keys).
	for i in current.overlays.size():
		var live_piece := LevelEditor._piece_for_overlay_from_array(_scenery_pieces, i)
		if live_piece != null:
			# Guard: only reset if the bake consumed the edit keys.
			var still_pending := false
			for k in (current.overlays[i] as Dictionary).keys():
				if String(k).begins_with("_"):
					still_pending = true
					break
			if still_pending:
				continue
			var piece := live_piece
			piece.rotation = 0.0
			piece.scale = Vector2.ONE
			piece.flip_h = false
			piece.flip_v = false
	return skipped


# ---------------------------------------------------------------------------
# Static helpers (also used by GridTool via LevelEditor.footprint etc.)
# ---------------------------------------------------------------------------

static func footprint(anchor: Vector2i, cells: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in cells.x:
		for j in cells.y:
			out.append(Vector2i(anchor.x + i, anchor.y + j))
	return out


# The trigger event key this cell's crate answers to (matches what save
# writes: cell_to_world coords as bare ints — see linked-triggers spec).
static func crate_trigger_key(cell: Vector2i) -> String:
	var w := EditorGrid.cell_to_world(cell)
	return "hit:%d,%d" % [int(w.x), int(w.y)]
