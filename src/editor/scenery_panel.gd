class_name SceneryPanel
extends PanelContainer

signal background_picked(id: String)
signal image_chosen(path: String)
signal done

const BACKGROUNDS: Array[String] = ["meadow"]

var _file_dialog: FileDialog


func _ready() -> void:
	for bg in BACKGROUNDS:
		%BackgroundList.add_item(bg)
	%BackgroundList.item_selected.connect(
		func(i: int) -> void: background_picked.emit(%BackgroundList.get_item_text(i))
	)
	%AddImageBtn.pressed.connect(_open_file_dialog)
	%DoneBtn.pressed.connect(func() -> void: done.emit())

	_file_dialog = FileDialog.new()
	_file_dialog.use_native_dialog = false
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Images"])
	_file_dialog.file_selected.connect(func(path: String) -> void: image_chosen.emit(path))
	add_child(_file_dialog)


func _open_file_dialog() -> void:
	_file_dialog.popup_centered_ratio(0.7)
