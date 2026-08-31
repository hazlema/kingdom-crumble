class_name EditorMenu
extends CanvasLayer

signal save_requested
signal save_as_requested(stem: String)
signal load_requested(path: String)
signal clear_requested
signal exit_requested
signal test_requested
signal background_picked(id: String)

const BACKGROUNDS: Array[String] = ["meadow"]

func _ready() -> void:
	%MenuBtn.pressed.connect(func() -> void: %Panel.visible = not %Panel.visible)
	%TestBtn.pressed.connect(func() -> void: _pick(test_requested))
	%SaveBtn.pressed.connect(func() -> void: _pick(save_requested))
	%SaveAsBtn.pressed.connect(func() -> void:
		%Panel.visible = false
		%SaveAsDialog.popup_centered())
	%LoadBtn.pressed.connect(_open_load)
	%ClearBtn.pressed.connect(func() -> void:
		%Panel.visible = false
		%ClearConfirm.popup_centered())
	%FolderBtn.pressed.connect(func() -> void:
		DirAccess.make_dir_recursive_absolute(LevelStore.USER_DIR)
		OS.shell_open(ProjectSettings.globalize_path(LevelStore.USER_DIR)))
	%ExitBtn.pressed.connect(func() -> void: _pick(exit_requested))
	for bg in BACKGROUNDS:
		%BackgroundList.add_item(bg)
	%BackgroundList.item_selected.connect(func(i: int) -> void:
		background_picked.emit(%BackgroundList.get_item_text(i)))
	%SaveAsDialog.confirmed.connect(func() -> void:
		if %StemEdit.text.strip_edges() != "":
			save_as_requested.emit(%StemEdit.text.strip_edges()))
	%LoadDialog.confirmed.connect(func() -> void:
		var sel: PackedInt32Array = %LevelList.get_selected_items()
		if sel.size() > 0:
			load_requested.emit(%LevelList.get_item_metadata(sel[0])))
	%ClearConfirm.confirmed.connect(func() -> void: clear_requested.emit())

func _pick(sig: Signal) -> void:
	%Panel.visible = false
	sig.emit()

func open_save_as() -> void:
	%SaveAsDialog.popup_centered()

func show_load_error() -> void:
	%LoadError.popup_centered()

func _open_load() -> void:
	%Panel.visible = false
	%LevelList.clear()
	for path in LevelStore.list_user():
		var l := LevelStore.load_level(path)
		var idx: int = %LevelList.add_item(l.title if l else path.get_file())
		%LevelList.set_item_metadata(idx, path)
	%LoadDialog.popup_centered()
