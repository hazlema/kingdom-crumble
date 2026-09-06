class_name PauseMenu
extends CanvasLayer

# ESC pause menu. Owns the ESC key and the tree pause entirely: ESC
# opens it (pausing the game) and closes it (resuming). The level only
# listens for restart/quit. Runs in PROCESS_MODE_ALWAYS so it works
# while the tree is paused; music keeps playing (MusicDirector is
# ALWAYS too) so the volume slider gives live feedback.

signal restart_requested
signal quit_requested
signal back_to_editor_requested
signal jump_levels_requested

## Month names for the out-of-season label (index 0 = unused placeholder).
const MONTHS := ["", "January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"]

@onready var _resume: Button = %Resume
@onready var _restart: Button = %RestartLevel
@onready var _quit: Button = %QuitToTitle
@onready var _music_slider: HSlider = %MusicSlider
@onready var _items: VBoxContainer = $"Center/Panel/Margin/Items"

## Programmatic container for the Toybox section (appended to _items).
var _toybox_section: VBoxContainer


func _ready() -> void:
	visible = false
	_resume.pressed.connect(close)
	_restart.pressed.connect(
		func() -> void:
			close()
			restart_requested.emit()
	)
	_quit.pressed.connect(
		func() -> void:
			close()
			quit_requested.emit()
	)
	_music_slider.value = Music.get_volume_linear()
	_music_slider.value_changed.connect(Music.set_volume_linear)
	%SfxSlider.value = Music.get_sfx_volume_linear()
	%SfxSlider.value_changed.connect(Music.set_sfx_volume_linear)
	%BackToEditor.visible = false
	%BackToEditor.pressed.connect(
		func():
			close()
			back_to_editor_requested.emit()
	)
	%JumpLevels.pressed.connect(
		func():
			close()
			jump_levels_requested.emit()
	)
	# Create the Toybox section container once; populate on open()
	_toybox_section = VBoxContainer.new()
	_toybox_section.name = "ToyboxSection"
	_toybox_section.visible = false
	_items.add_child(_toybox_section)


func set_editor_mode(on: bool) -> void:
	%BackToEditor.visible = on
	%JumpLevels.visible = not on  # no chain inside the editor sandbox


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		close() if visible else open()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	get_tree().paused = true
	# a press with no release survives the pause and sticks forever
	Input.action_release("fire")
	_rebuild_toybox()
	_resume.grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = false


## Rebuild the Toybox section from Pieces.packs() every open().
## Clears all children first so reopening never duplicates widgets.
func _rebuild_toybox() -> void:
	for child in _toybox_section.get_children():
		child.free()

	var all_packs := Pieces.packs()
	if all_packs.is_empty():
		_toybox_section.visible = false
		return

	_toybox_section.visible = true

	# Section header
	var header := Label.new()
	header.text = "TOYBOX"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toybox_section.add_child(header)

	# Object pack checkboxes
	var object_packs := all_packs.filter(func(p: Dictionary) -> bool: return p["kind"] == "objects")
	for pack: Dictionary in object_packs:
		var cb := CheckBox.new()
		var in_season: bool = pack["in_season"]
		if in_season:
			cb.text = pack["title"]
			cb.disabled = false
		else:
			# Mirror theme dropdown treatment: disabled + "returns in <Month>"
			var months: Array = pack.get("months", [])
			var month_name := ""
			if months.size() > 0:
				var m := int(months[0])
				if m >= 1 and m <= 12:
					month_name = MONTHS[m]
			cb.text = "%s (returns in %s)" % [pack["title"], month_name]
			cb.disabled = true
		cb.button_pressed = pack["enabled"]
		var folder: String = pack["folder"]
		cb.toggled.connect(func(on: bool) -> void:
			Pieces.set_pack_enabled(folder, on)
		)
		_toybox_section.add_child(cb)

	# Theme OptionButton (only if there are theme packs)
	var theme_packs := all_packs.filter(func(p: Dictionary) -> bool: return p["kind"] == "theme")
	if not theme_packs.is_empty():
		var theme_row := HBoxContainer.new()
		var theme_label := Label.new()
		theme_label.text = "Theme"
		theme_row.add_child(theme_label)

		var ob := OptionButton.new()
		ob.add_item("Default")  # index 0 = ""

		var active := Pieces.active_theme()
		var selected_idx := 0

		for i: int in theme_packs.size():
			var pack: Dictionary = theme_packs[i]
			var item_idx: int = i + 1  # offset by 1 for Default
			var folder: String = pack["folder"]
			var title: String = pack["title"]
			var in_season: bool = pack["in_season"]

			if in_season:
				ob.add_item(title)
			else:
				# Show first month in the months array (multi-month packs show first month only)
				var months: Array = pack.get("months", [])
				var month_name := ""
				if months.size() > 0:
					var m := int(months[0])
					if m >= 1 and m <= 12:
						month_name = MONTHS[m]
				ob.add_item("%s (returns in %s)" % [title, month_name])
				ob.set_item_disabled(item_idx, true)

			if folder == active:
				selected_idx = item_idx

		ob.selected = selected_idx
		ob.item_selected.connect(func(idx: int) -> void:
			if idx == 0:
				Pieces.set_active_theme("")
			else:
				var theme_idx := idx - 1
				if theme_idx < theme_packs.size():
					Pieces.set_active_theme(theme_packs[theme_idx]["folder"])
		)
		theme_row.add_child(ob)
		_toybox_section.add_child(theme_row)

	# Note label
	var note := Label.new()
	note.text = "Changes apply on next level load"
	_toybox_section.add_child(note)
