class_name SceneryTool
extends EditorTool

# Owns all scenery-mode input state: LMB edge detection, drag/handle
# tracking, the RMB context menu, and the gizmo pointer each frame.
# The editor owns the document (current, overlays, _scenery_pieces,
# _gizmo) and shared services; this tool owns nothing except what is
# listed below.

var selected_overlay := -1
var _scenery_dragging := false        # true while LMB drags a selected piece
var _scenery_drag_start_world := Vector2.ZERO   # world pos when drag began
var _scenery_drag_piece_origin := Vector2.ZERO  # piece.position when drag began
var _scenery_handle := -1             # -1 = body, 0-3 = corner, 4 = rotate
var _scenery_drag_press_scale := 1.0  # piece._scale at the moment of press
var _scenery_context: PopupMenu = null
var _lmb_down := false


func enter() -> void:
	# Drop any in-flight carry so a held crate doesn't ghost in scenery mode.
	ed._grid_tool.carrying = ""
	# Stale-input hygiene: clear drag/lmb state on the grid tool.
	ed._grid_tool._drag_from = Vector2i(-1, -1)
	ed._grid_tool._drag_prop = null
	ed._grid_tool._lmb_down = false
	_lmb_down = false
	ed._rmb_down = false  # a held right-click must not menu on re-entry
	ed.inspector().close()
	ed.palette.visible = false
	ed.get_node("%SceneryPanel").visible = true
	ed.overlay.visible = false
	ed._rebuild_scenery()  # dims crates + pauses behaviors (mode is SCENERY)
	ed._refresh_pieces()
	ed.gizmo().visible = true


func exit() -> void:
	_lmb_down = false
	ed._rmb_down = false  # a held right-click must not menu on mode return
	selected_overlay = -1
	ed.gizmo().piece = null
	ed.gizmo().queue_redraw()
	ed.inspector().close()
	ed.get_node("%SceneryPanel").visible = false
	ed.palette.visible = true
	ed.overlay.visible = true
	for c in ed._spawned:
		c.modulate.a = 1.0
	# Respawn scenery in CRATES mode: behaviors come back to life (the
	# pause above was editor-session-only; the dict never forgot them).
	ed._rebuild_scenery()


# Called every frame while SCENERY mode is active.
func process(mouse: Vector2, _over_ui: bool) -> void:
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var over_ui := ed.menu.any_dialog_open() or ed._mouse_over_ui(mouse)
	var world := ed.get_global_mouse_position()
	ed.gizmo().cam_zoom = ed.camera().zoom

	if lmb and not _lmb_down and not over_ui:
		_scenery_press(world)
	elif not lmb and _lmb_down:
		_scenery_release()
	elif lmb and _lmb_down and _scenery_dragging:
		_scenery_drag(world)

	_lmb_down = lmb

	# RMB context menu: open only on release without significant motion.
	if ed.rmb_menu_release(mouse, over_ui):
		var rmb_world := ed.get_global_mouse_position()
		var idx := _pick_piece(rmb_world)
		if idx >= 0:
			selected_overlay = idx
			_show_scenery_context(mouse)

	# Keep gizmo pointed at the selected piece.
	var _selected_piece := _piece_for_overlay(selected_overlay) if selected_overlay >= 0 else null
	if _selected_piece != null:
		ed.gizmo().piece = _selected_piece
		ed.gizmo().queue_redraw()
	else:
		ed.gizmo().piece = null
		ed.gizmo().queue_redraw()


func _scenery_press(world: Vector2) -> void:
	var zoom := ed.camera().zoom.x

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
			var po: Dictionary = ed.current.overlays[selected_overlay]
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
		var po: Dictionary = ed.current.overlays[selected_overlay]
		_scenery_drag_press_scale = po.get("_scale", 1.0)
		ed.inspector().open(po, piece)
	else:
		# Deselect.
		selected_overlay = -1
		_scenery_dragging = false
		ed.inspector().close()


func _scenery_release() -> void:
	if _scenery_dragging and selected_overlay >= 0 and selected_overlay < ed.current.overlays.size():
		var piece := _piece_for_overlay(selected_overlay)
		if piece != null:
			var o: Dictionary = ed.current.overlays[selected_overlay]
			o["x"] = piece.position.x
			o["y"] = piece.position.y
	_scenery_dragging = false
	_scenery_handle = -1


func _scenery_drag(world: Vector2) -> void:
	if selected_overlay < 0 or selected_overlay >= ed.current.overlays.size():
		return
	var piece := _piece_for_overlay(selected_overlay)
	if piece == null:
		return
	var o: Dictionary = ed.current.overlays[selected_overlay]
	var delta := world - _scenery_drag_start_world

	if _scenery_handle == -1:
		# Body drag — move piece, and keep overlay dict in sync for mid-drag saves.
		piece.position = _scenery_drag_piece_origin + delta
		piece.rehome()  # else a live verb snaps it back to where it was born
		o["x"] = piece.position.x
		o["y"] = piece.position.y
	elif _scenery_handle == 4:
		# Rotate handle — angle from piece center to mouse.
		var center := _scenery_drag_piece_origin
		var angle := (world - center).angle() + PI / 2.0
		piece.rotation = angle
		piece.rehome()  # SPIN/SWAY anchor to home rotation the same way
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
	for p in ed._scenery_pieces:
		if is_instance_valid(p) and p.has_meta("overlay_index") and p.get_meta("overlay_index") == overlay_idx:
			return p
	return null


# Returns the index of the topmost piece whose world-space rect contains `world_pos`,
# or -1 if none. Exposed so unit tests can call it directly.
func _pick_piece(world_pos: Vector2) -> int:
	# Iterate in reverse (top-most drawn last).
	for i in range(ed._scenery_pieces.size() - 1, -1, -1):
		var piece := ed._scenery_pieces[i]
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
	if selected_overlay < 0 or selected_overlay >= ed.current.overlays.size():
		return
	var o: Dictionary = ed.current.overlays[selected_overlay]
	var old_key: String = o.get("image", "")
	ed.current.overlays.remove_at(selected_overlay)
	selected_overlay = -1
	ed.gizmo().piece = null
	ed.gizmo().queue_redraw()
	ed.inspector().close()
	# Drop the image blob if no remaining overlay references it.
	if old_key != "":
		var still_used := false
		for entry in ed.current.overlays:
			if (entry as Dictionary).get("image", "") == old_key:
				still_used = true
				break
		if not still_used:
			ed.current.images.erase(old_key)
	ed._rebuild_scenery()
	ed._refresh_pieces()


# ---------------------------------------------------------------------------
# Right-click context menu for scenery pieces
# ---------------------------------------------------------------------------

func _show_scenery_context(screen_pos: Vector2) -> void:
	if _scenery_context == null:
		_scenery_context = PopupMenu.new()
		_scenery_context.id_pressed.connect(_on_scenery_context_item)
		ed.add_child(_scenery_context)
	_scenery_context.clear()
	_scenery_context.add_item("Flip H", 0)
	_scenery_context.add_item("Flip V", 1)
	_scenery_context.add_item("Reset Transform", 4)
	_scenery_context.add_item("Drop Background", 3)
	_scenery_context.add_separator()
	_scenery_context.add_item("Delete", 2)
	_scenery_context.position = Vector2i(int(screen_pos.x), int(screen_pos.y))
	_scenery_context.popup()


func _on_scenery_context_item(id: int) -> void:
	if selected_overlay < 0 or selected_overlay >= ed.current.overlays.size():
		return
	var piece := _piece_for_overlay(selected_overlay)
	if piece == null and id != 2:
		return
	var o: Dictionary = ed.current.overlays[selected_overlay]
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
		4:  # Reset Transform (owner: a runaway rotate/mirror had no way home)
			for k in ["_rot", "_scale", "_flip_h", "_flip_v"]:
				o.erase(k)
			if piece != null:
				piece.rotation = 0.0
				piece.scale = Vector2.ONE
				piece.flip_h = false
				piece.flip_v = false
				piece.rehome()


func _drop_background() -> void:
	if selected_overlay < 0 or selected_overlay >= ed.current.overlays.size():
		return
	var o: Dictionary = ed.current.overlays[selected_overlay]
	var old_key := str(o.get("image", ""))
	var img := LevelJson.decode_png_b64(str(ed.current.images.get(old_key, "")))
	if img == null:
		return
	var stripped := SceneryBake._strip_background(img)
	if stripped == null:
		push_warning("Drop Background: corners disagree — no uniform backdrop found")
		return
	var cap_result := SceneryBake._cap_image_to_max(stripped)
	var png_bytes: PackedByteArray = cap_result[0]
	var new_b64: String = cap_result[1]
	var new_key := LevelJson.image_key(png_bytes)
	if new_key != old_key:
		var refs := 0
		for entry in ed.current.overlays:
			if str(entry.get("image", "")) == old_key:
				refs += 1
		if (
			not ed.current.images.has(new_key)
			and refs > 1
			and ed.current.images.size() >= LevelJson.MAX_IMAGES
		):
			push_warning("Drop Background: image cap full")
			return
		if not ed.current.images.has(new_key):
			ed.current.images[new_key] = new_b64
		o["image"] = new_key
		if refs <= 1:
			ed.current.images.erase(old_key)
	ed._rebuild_scenery()
	ed._refresh_pieces()
	_reopen_inspector()


# Rebuilds free every live piece — any open inspector must be re-pointed
# at the FRESH piece for the current selection (or closed if none), else
# it displays one overlay while selection means another.
func _reopen_inspector() -> void:
	if selected_overlay >= 0 and selected_overlay < ed.current.overlays.size():
		var piece := _piece_for_overlay(selected_overlay)
		ed.inspector().open(ed.current.overlays[selected_overlay], piece)
	else:
		ed.inspector().close()
