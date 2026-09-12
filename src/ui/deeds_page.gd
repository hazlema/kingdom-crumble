class_name DeedsPage
extends Control

# Deeds of the Kingdom — the parchment page.
#
# Full-screen Control displaying all manifest entries as a scrollable
# medallion grid (4 per row). Unlocked slots show solid art + plain name;
# locked slots show ghost art (hand-drawn ghost png preferred, else
# auto-desaturated via ghost_of()) + name with "?" suffix; secret locked
# slots show "???" for the name.
#
# Clicking/tapping a slot updates the plaque label: unlocked shows the deed
# text; locked shows "Not yet discovered…". ESC returns to the main menu.
#
# Live refresh: listens to Deeds.deed_unlocked while open; disconnects
# on tree_exiting so the autoload outliving the scene doesn't leak.

const ART_DIR := "res://achievements/"
const COLS := 4
const PANEL_W := 1560.0
const PANEL_H := 869.0

# Cache of auto-generated ghost textures (keyed by source texture object id).
var _ghost_cache: Dictionary = {}

# References to per-slot nodes for live refresh.
var _slot_nodes: Array[Control] = []

# Plaque label that shows deed text on click.
var _plaque: Label

# Callable ref so we can disconnect on exit.
var _deed_unlocked_cb: Callable


func _ready() -> void:
	_build_ui()
	_deed_unlocked_cb = _on_deed_unlocked
	Deeds.deed_unlocked.connect(_deed_unlocked_cb)
	tree_exiting.connect(_on_tree_exiting)


func _on_tree_exiting() -> void:
	if Deeds.deed_unlocked.is_connected(_deed_unlocked_cb):
		Deeds.deed_unlocked.disconnect(_deed_unlocked_cb)


func _on_deed_unlocked(_id: String) -> void:
	# Refresh the whole grid when any deed is unlocked while this page is open.
	_refresh_slots()


# ---------------------------------------------------------------------------
# Pure helper — unit-testable
# ---------------------------------------------------------------------------

## Return a greyscale+lightened copy of `tex` as a new ImageTexture.
## Result average saturation is < 0.05 (tested by test_deeds_page.gd).
static func ghost_of(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return null
	img = img.duplicate() as Image
	# Convert to RGBA8 for reliable pixel access
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	# Desaturate: for each pixel, map RGB to its luminance, then lighten.
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var c: Color = img.get_pixel(x, y)
			# Luminance (perceptual weights)
			var lum: float = c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			# Lighten: blend toward white by 40%
			var l2: float = lum + (1.0 - lum) * 0.4
			img.set_pixel(x, y, Color(l2, l2, l2, c.a))
	var out := ImageTexture.create_from_image(img)
	return out


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Apply kingdom_theme at the root Control level
	var theme_res = load("res://resources/ui/kingdom_theme.tres")
	if theme_res != null:
		theme = theme_res

	# Popup overlay: the menu keeps living behind a dimmer; the panel is
	# the PAINTED framed parchment (deeds-frame.png — header baked in).
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dimmer"
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var panel := TextureRect.new()
	panel.name = "Panel"
	panel.texture = _load_tex("deeds-frame.png")
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	panel.offset_left = -PANEL_W / 2.0
	panel.offset_top = -PANEL_H / 2.0
	panel.offset_right = PANEL_W / 2.0
	panel.offset_bottom = PANEL_H / 2.0
	panel.stretch_mode = TextureRect.STRETCH_SCALE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	# Interior: the parchment area inside the frame, below the baked header.
	var interior := Control.new()
	interior.name = "Interior"
	interior.set_anchors_preset(Control.PRESET_FULL_RECT)
	interior.offset_left = PANEL_W * 0.055
	interior.offset_top = PANEL_H * 0.215
	interior.offset_right = -PANEL_W * 0.055
	interior.offset_bottom = -PANEL_H * 0.145
	panel.add_child(interior)

	var scroll := ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	interior.add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 26)
	center.add_child(grid)

	# Populate slots
	_slot_nodes = []
	for entry in Deeds.entries():
		var slot := _make_slot(entry)
		grid.add_child(slot)
		_slot_nodes.append(slot)

	# Plaque strip in the parchment's lower margin (inside the frame).
	_plaque = Label.new()
	_plaque.name = "Plaque"
	_plaque.text = ""
	_plaque.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plaque.add_theme_font_size_override("font_size", 20)
	_plaque.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plaque.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_plaque.offset_left = PANEL_W * 0.08
	_plaque.offset_right = -PANEL_W * 0.08
	_plaque.offset_top = -PANEL_H * 0.135
	_plaque.offset_bottom = -PANEL_H * 0.055
	panel.add_child(_plaque)

	# Close ✕ on the frame's top-right corner.
	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 30)
	close_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_btn.offset_left = -PANEL_W * 0.065
	close_btn.offset_top = PANEL_H * 0.025
	close_btn.offset_right = -PANEL_W * 0.022
	close_btn.offset_bottom = PANEL_H * 0.085
	close_btn.pressed.connect(_go_back)
	panel.add_child(close_btn)


func _make_slot(entry: Dictionary) -> Control:
	var unlocked: bool = Deeds.is_unlocked(entry["id"])
	var secret: bool = bool(entry.get("secret", false))

	var slot := Button.new()
	slot.name = "Slot_" + entry["id"]
	slot.custom_minimum_size = Vector2(190, 182)
	slot.focus_mode = Control.FOCUS_CLICK
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Use flat style so our VBox layout shows through
	slot.flat = true

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(vbox)

	# Medallion image
	var img_rect := TextureRect.new()
	img_rect.name = "Medallion"
	img_rect.custom_minimum_size = Vector2(124, 124)
	img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	img_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_medallion_texture(img_rect, entry, unlocked)
	vbox.add_child(img_rect)

	# Name ribbon: the painted ribbon rides INSIDE the label (behind the
	# text), so the tree stays VBox -> Medallion, NameLabel for tests.
	var lbl := Label.new()
	lbl.name = "NameLabel"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.custom_minimum_size = Vector2(176, 46)
	lbl.clip_text = false
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.29, 0.23, 0.16, 1.0))  # theme ink
	var ribbon := TextureRect.new()
	ribbon.name = "Ribbon"
	ribbon.texture = _load_tex("deeds-ribbon.png")
	ribbon.set_anchors_preset(Control.PRESET_FULL_RECT)
	ribbon.stretch_mode = TextureRect.STRETCH_SCALE
	# CRITICAL: without this the TextureRect demands its natural 360px as
	# minimum size, blowing every grid cell out (owner screenshot catch —
	# overlapping giant ribbons).
	ribbon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ribbon.show_behind_parent = true
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_child(ribbon)
	_style_name_label(lbl, entry, unlocked, secret)
	vbox.add_child(lbl)

	# Wire click to plaque update
	var entry_copy := entry.duplicate()
	slot.pressed.connect(func() -> void: _on_slot_clicked(entry_copy))

	return slot


static func _style_name_label(lbl: Label, entry: Dictionary, unlocked: bool, secret: bool) -> void:
	if unlocked:
		lbl.text = str(entry.get("name", ""))
		lbl.modulate = Color.WHITE
	elif secret:
		lbl.text = "???"
		lbl.modulate = Color(1, 1, 1, 0.55)
	else:
		lbl.text = str(entry.get("name", "")) + " ?"
		lbl.modulate = Color(1, 1, 1, 0.7)


func _apply_medallion_texture(img_rect: TextureRect, entry: Dictionary, unlocked: bool) -> void:
	var tex: Texture2D = null
	if unlocked:
		tex = _load_tex(str(entry.get("solid", "")))
	else:
		# Prefer hand-drawn ghost png if present
		var ghost_file: String = str(entry.get("ghost", ""))
		if ghost_file != "":
			tex = _load_tex(ghost_file)
		if tex == null:
			# Fall back: auto-desaturate solid
			var solid_tex := _load_tex(str(entry.get("solid", "")))
			if solid_tex != null:
				var cache_key := solid_tex.get_instance_id()
				if _ghost_cache.has(cache_key):
					tex = _ghost_cache[cache_key]
				else:
					tex = ghost_of(solid_tex)
					_ghost_cache[cache_key] = tex
	img_rect.texture = tex


func _load_tex(filename: String) -> Texture2D:
	if filename == "":
		return null
	var path := ART_DIR + filename
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "Texture2D") as Texture2D


func _on_slot_clicked(entry: Dictionary) -> void:
	if Deeds.is_unlocked(entry["id"]):
		_plaque.text = str(entry.get("text", ""))
	else:
		_plaque.text = "Not yet discovered…"


func _refresh_slots() -> void:
	var entries := Deeds.entries()
	for i in _slot_nodes.size():
		if i >= entries.size():
			break
		var entry := entries[i]
		var slot := _slot_nodes[i]
		var unlocked := Deeds.is_unlocked(entry["id"])
		var secret := bool(entry.get("secret", false))

		# Update medallion texture
		var img_rect := slot.get_node_or_null("VBoxContainer/Medallion") as TextureRect
		if img_rect == null:
			# Fallback: find by name in children recursively
			for child in slot.get_children():
				if child is VBoxContainer:
					for grandchild in child.get_children():
						if grandchild.name == "Medallion":
							img_rect = grandchild as TextureRect
		if img_rect != null:
			_apply_medallion_texture(img_rect, entry, unlocked)

		# Update name label
		var lbl: Label = null
		for child in slot.get_children():
			if child is VBoxContainer:
				for grandchild in child.get_children():
					if grandchild.name == "NameLabel":
						lbl = grandchild as Label
		if lbl != null:
			_style_name_label(lbl, entry, unlocked, secret)


# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _go_back() -> void:
	# As a popup over the menu we just vanish; as a standalone scene
	# (tests, direct loads) fall back to the menu swap.
	if get_tree().current_scene != self:
		queue_free()
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_go_back()
