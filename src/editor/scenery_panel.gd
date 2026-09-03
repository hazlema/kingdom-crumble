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
	if OS.has_feature("web"):
		# The browser guards the real disk — summon ITS picker instead.
		# The chosen file is copied into the WASM sandbox and the path
		# handed back, where the normal import pipeline can eat it.
		DisplayServer.file_dialog_show(
			"Add Image",
			"",
			"",
			false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
			PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Images"]),
			_on_web_file_picked
		)
		return
	_file_dialog.popup_centered(Vector2i(940, 640))  # a polite window, not a cinema screen (owner)


func _on_web_file_picked(status: bool, selected: PackedStringArray, _filter: int) -> void:
	if status and selected.size() > 0:
		image_chosen.emit(selected[0])
