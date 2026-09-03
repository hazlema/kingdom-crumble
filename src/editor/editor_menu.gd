class_name EditorMenu
extends CanvasLayer

signal save_requested
signal save_as_requested(stem: String)
signal load_requested(path: String)
signal clear_requested
signal exit_requested
signal test_requested
signal intro_edited(text: String)
signal open_intro_requested
signal scenery_requested


func _ready() -> void:
	%MenuBtn.pressed.connect(func() -> void: %Panel.visible = not %Panel.visible)
	%TestBtn.pressed.connect(func() -> void: _pick(test_requested))
	%SaveBtn.pressed.connect(func() -> void: _pick(save_requested))
	%SaveAsBtn.pressed.connect(
		func() -> void:
			%Panel.visible = false
			%SaveAsDialog.popup_centered()
	)
	%LoadBtn.pressed.connect(_open_load)
	%IntroBtn.pressed.connect(
		func() -> void:
			%Panel.visible = false
			open_intro_requested.emit()
	)
	%ClearBtn.pressed.connect(
		func() -> void:
			%Panel.visible = false
			%ClearConfirm.popup_centered()
	)
	%FolderBtn.pressed.connect(
		func() -> void:
			DirAccess.make_dir_recursive_absolute(LevelStore.USER_DIR)
			OS.shell_open(ProjectSettings.globalize_path(LevelStore.USER_DIR))
	)
	%ExitBtn.pressed.connect(func() -> void: _pick(exit_requested))
	%SceneryBtn.pressed.connect(func() -> void: _pick(scenery_requested))
	%SaveAsDialog.confirmed.connect(
		func() -> void:
			if %StemEdit.text.strip_edges() != "":
				save_as_requested.emit(%StemEdit.text.strip_edges())
	)
	%LoadDialog.confirmed.connect(
		func() -> void:
			var sel: PackedInt32Array = %LevelList.get_selected_items()
			if sel.size() > 0:
				load_requested.emit(%LevelList.get_item_metadata(sel[0]))
	)
	%ClearConfirm.confirmed.connect(func() -> void: clear_requested.emit())
	%IntroDialog.confirmed.connect(
		func() -> void:
			var text: String = %IntroEdit.text.strip_edges()
			if text.length() > LevelJson.MAX_INTRO_CHARS:
				text = text.substr(0, LevelJson.MAX_INTRO_CHARS)
			intro_edited.emit(text)
	)
	# The CLEAR button inside the IntroDialog emits "" and closes the dialog.
	%IntroClearBtn.pressed.connect(
		func() -> void:
			intro_edited.emit("")
			%IntroDialog.hide()
	)
	%IntroDialog.about_to_popup.connect(
		func() -> void:
			%IntroEdit.call_deferred("grab_focus")
	)
	# Enter in the name field submits the dialog; Esc cancels for free
	# (dialogs close on escape by default). Field grabs focus on open.
	%SaveAsDialog.register_text_enter(%StemEdit)
	%SaveAsDialog.about_to_popup.connect(
		func() -> void:
			%StemEdit.call_deferred("grab_focus")
			%StemEdit.call_deferred("select_all")
	)
	# Enter or double-click on a list entry loads it immediately.
	%LevelList.item_activated.connect(
		func(i: int) -> void:
			load_requested.emit(%LevelList.get_item_metadata(i))
			%LoadDialog.hide()
	)


func _pick(sig: Signal) -> void:
	%Panel.visible = false
	sig.emit()


# True while any modal dialog is up — the editor pauses field
# interaction so clicks aimed at a dialog can't edit the level.
func any_dialog_open() -> bool:
	return (
		%SaveAsDialog.visible
		or %LoadDialog.visible
		or %ClearConfirm.visible
		or %LoadError.visible
		or %IntroDialog.visible
	)


# Geometry test for the polled interaction layer: is this viewport
# point over the menu's visible chrome?
func covers_point(p: Vector2) -> bool:
	if %MenuBtn.get_global_rect().has_point(p):
		return true
	return %Panel.visible and %Panel.get_global_rect().has_point(p)


func open_save_as() -> void:
	%SaveAsDialog.popup_centered()


func open_intro(current_text: String) -> void:
	%IntroEdit.text = current_text
	%IntroDialog.popup_centered()


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
