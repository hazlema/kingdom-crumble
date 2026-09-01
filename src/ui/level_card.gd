class_name LevelCard
extends Button

# One level in the jump grid (pretty-pass spec §4). Thumb preference order:
# 1. embedded base64 PNG stored in LevelLayout.thumb (written by the editor
#    capture pipeline, spec §4); 2. sibling <stem>.png on disk (owner's
#    two-file convention); 3. NO IMAGE placeholder.

signal picked(path: String)

# Compiled once for the class; validates base64 alphabet before decoding.
# Marshalls.base64_to_raw emits an engine error on bad chars — untrusted data
# must degrade silently (spec §4), so we pre-screen rather than let it through.
static var _b64_rx := RegEx.create_from_string("^[A-Za-z0-9+/]*={0,2}$")

var _path := ""


func _ready() -> void:
	pressed.connect(func() -> void: picked.emit(_path))


func setup(entry: Dictionary, cleared: bool, unlocked: bool, is_now: bool) -> void:
	_path = entry["path"]
	%Title.text = entry["title"]
	# Owner icon art auto-preferred when present (art/assets/ui/
	# state_cleared.png / state_locked.png); glyph fallback otherwise.
	# The icon column is always reserved so titles align across cards.
	var state_img := ""
	if cleared:
		state_img = "res://art/assets/ui/state_cleared.png"
	elif not unlocked:
		state_img = "res://art/assets/ui/state_locked.png"
	if state_img != "" and ResourceLoader.exists(state_img):
		%StateTex.texture = load(state_img)
		%StateTex.visible = true
		%StateIcon.visible = false
	else:
		%StateTex.visible = false
		%StateIcon.visible = true
		%StateIcon.text = "✓" if cleared else ("🔒" if not unlocked else "")
	if cleared:
		%StateIcon.add_theme_color_override("font_color", Color(0.1804, 0.4902, 0.1961, 1))
	else:
		%StateIcon.remove_theme_color_override("font_color")
	disabled = not unlocked
	%NowBadge.visible = is_now
	var tex := _embedded_thumb(entry.get("thumb", ""))
	if tex == null:
		tex = _sibling_thumb(entry["path"])
	%Thumb.visible = tex != null
	%NoImage.visible = tex == null
	if tex != null:
		%Thumb.texture = tex
	%ThumbBox.modulate = Color(1, 1, 1) if unlocked else Color(0.55, 0.55, 0.55)
	if is_now:
		var ring := _now_ring()
		add_theme_stylebox_override("normal", ring)
		add_theme_stylebox_override("hover", ring)
		add_theme_stylebox_override("pressed", ring)
	else:
		remove_theme_stylebox_override("normal")
		remove_theme_stylebox_override("hover")
		remove_theme_stylebox_override("pressed")


func _sibling_thumb(level_path: String) -> Texture2D:
	var png := level_path.get_basename() + ".png"
	if png.begins_with("res://"):
		return load(png) if ResourceLoader.exists(png) else null
	if FileAccess.file_exists(png):
		var img := Image.load_from_file(png)
		if img != null:
			return ImageTexture.create_from_image(img)
	return null


# Hostile or corrupt blobs degrade silently to the sibling/NO IMAGE
# fallbacks — a bad thumb can disappoint, never crash (spec §4).
func _embedded_thumb(b64: String) -> Texture2D:
	if b64 == "":
		return null
	# base64 encodes 3 bytes per 4 chars (with padding); any other length is
	# invalid and Marshalls.base64_to_raw behavior is undefined — reject early.
	if b64.length() % 4 != 0:
		return null
	# Alphabet check: Marshalls.base64_to_raw emits an engine error on bad
	# chars which GUT counts as a test failure; untrusted data must not reach it.
	if _b64_rx.search(b64) == null:
		return null
	var buf := Marshalls.base64_to_raw(b64)
	if buf.is_empty():
		return null
	# load_png_from_buffer emits engine errors on non-PNG bytes (confirmed by
	# test — 4 errors per call, GUT treats those as failures). Guard with the
	# 8-byte PNG magic signature before calling into the driver. Residual: a
	# correct magic prefix on a corrupt body still reaches the driver and logs
	# its errors — the != OK guard keeps the degrade correct, so hostile files
	# can spam the log but never crash or mis-render.
	const PNG_MAGIC := [137, 80, 78, 71, 13, 10, 26, 10]
	if buf.size() < PNG_MAGIC.size():
		return null
	for i in PNG_MAGIC.size():
		if buf[i] != PNG_MAGIC[i]:
			return null
	var img := Image.new()
	if img.load_png_from_buffer(buf) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _now_ring() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.9804, 0.9412, 1)
	sb.set_border_width_all(4)
	sb.border_color = Color(0.7098, 0.2667, 0.1804, 1)
	sb.set_corner_radius_all(8)
	return sb
