class_name LevelCard
extends Button

# One level in the jump grid (pretty-pass spec §4). Thumb comes from
# the level's sibling <stem>.png when it exists — the owner's two-file
# convention; a future capture pipeline needs no changes here.

signal picked(path: String)

var _path := ""


func _ready() -> void:
	pressed.connect(func() -> void: picked.emit(_path))


func setup(entry: Dictionary, cleared: bool, unlocked: bool, is_now: bool) -> void:
	_path = entry["path"]
	%Title.text = entry["title"]
	%StateIcon.text = "✓" if cleared else ("🔒" if not unlocked else "")
	%StateIcon.visible = %StateIcon.text != ""
	if cleared:
		%StateIcon.add_theme_color_override("font_color", Color(0.1804, 0.4902, 0.1961, 1))
	else:
		%StateIcon.remove_theme_color_override("font_color")
	disabled = not unlocked
	%NowBadge.visible = is_now
	var tex := _sibling_thumb(entry["path"])
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


func _now_ring() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.9804, 0.9412, 1)
	sb.set_border_width_all(4)
	sb.border_color = Color(0.7098, 0.2667, 0.1804, 1)
	sb.set_corner_radius_all(8)
	return sb
