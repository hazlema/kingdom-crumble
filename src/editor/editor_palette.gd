class_name EditorPalette
extends PanelContainer

signal asset_picked(id: String)

var _drag := false
var _drag_off := Vector2.ZERO


func _ready() -> void:
	for entry in Pieces.by_class("crate"):
		%Grid.add_child(_piece_button(entry))
	var box := %Grid.get_parent()
	var header := Label.new()
	header.text = "OBSTACLES"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(header)
	var ob_grid := GridContainer.new()
	ob_grid.columns = (%Grid as GridContainer).columns
	box.add_child(ob_grid)
	for cls in ["static", "trampoline", "wormhole"]:
		for entry in Pieces.by_class(cls):
			ob_grid.add_child(_piece_button(entry))
	%TitleBar.gui_input.connect(_on_title_input)


func _piece_button(entry: Dictionary) -> Button:
	var b := Button.new()
	b.icon = entry["texture"]
	b.expand_icon = true
	b.custom_minimum_size = Vector2(72, 72)
	b.tooltip_text = entry["tip"]
	b.focus_mode = Control.FOCUS_NONE
	var id: String = entry["id"]
	b.button_down.connect(func() -> void: asset_picked.emit(id))
	return b


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
		_drag_off = get_global_mouse_position() - global_position
	elif event is InputEventMouseMotion and _drag:
		global_position = get_global_mouse_position() - _drag_off
