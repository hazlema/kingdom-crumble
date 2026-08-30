@tool
class_name StatBar
extends Control

# Reusable boxless stat capsule (Risk-style): an icon overlapping a
# rounded track with a rounded fill. Drop an instance anywhere, set
# the icon and drive `value` — health, power, ammo, anything.

@export var icon: Texture2D:
	set(v):
		icon = v
		if _icon_rect:
			_icon_rect.texture = v

@export_range(0.0, 1.0) var value := 1.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		_update_fill()

@export var fill_color := Color(0.91, 0.28, 0.25, 1.0):
	set(v):
		fill_color = v
		if _fill_box:
			_fill_box.bg_color = v

const PAD := 7.0

var _icon_rect: TextureRect
var _fill: Panel
var _fill_box: StyleBoxFlat

func _ready() -> void:
	_icon_rect = get_node_or_null("%Icon")
	_fill = get_node_or_null("%Fill")
	if _icon_rect:
		_icon_rect.texture = icon
	if _fill:
		# unique stylebox per instance so fill colors don't bleed
		_fill_box = _fill.get_theme_stylebox("panel").duplicate()
		_fill_box.bg_color = fill_color
		_fill.add_theme_stylebox_override("panel", _fill_box)
	resized.connect(_update_fill)
	_update_fill()

func _update_fill() -> void:
	if not _fill:
		return
	var track: Control = _fill.get_parent()
	var inner: float = track.size.x - PAD * 2.0
	_fill.offset_right = PAD + maxf(inner * value, 0.0)
