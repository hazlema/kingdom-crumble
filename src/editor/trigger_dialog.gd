class_name TriggerDialog
extends AcceptDialog

# Programmatic dialog for authoring crate-hit triggers in the editor.
#
# Construction: TriggerDialog.new(ed), then ed.add_child + ed.register_popup.
# Opened via open(trigger_key, layout) — call from GridTool's context menu.
#
# The dialog writes directly into layout.triggers[trigger_key].
# It emits flash_requested(overlay_idx) when an overlay row is selected,
# so LevelEditor.flash_overlay can pulse the piece as a visual preview.
#
# Design: fully programmatic (no .tscn), matching PieceInspector/PauseMenu idiom.

signal flash_requested(overlay_idx: int)

# ---------------------------------------------------------------------------
# Catalog — data-driven so future parameterized effects add one entry here.
# ---------------------------------------------------------------------------

const ACTIONS: Array[Dictionary] = [
	{"id": "show",     "label": "Show",     "param": "overlay"},
	{"id": "hide",     "label": "Hide",     "param": "overlay"},
	{"id": "confetti", "label": "Confetti", "param": "none"},
	{"id": "sound",    "label": "Sound",    "param": "stem"},
	{"id": "display",  "label": "Display message", "param": "text"},
]

const ACTION_CAP := 16

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var _ed: LevelEditor
var _trigger_key := ""
var _layout: LevelLayout = null

# Main layout containers
var _vbox: VBoxContainer
var _action_list_box: VBoxContainer  # rows of existing actions (each: Label + ✕)
var _action_option: OptionButton     # the "new action" picker
var _param_container: VBoxContainer  # rebuilt per selected action
var _overlay_list: ItemList          # overlay param: ItemList of named overlays
var _stem_option: OptionButton       # stem param: OptionButton
var _text_edit: LineEdit             # text param: LineEdit (display message)
var _footer_label: Label             # unnamed-overlay count when > 0
var _warning_label: Label            # cap/validation warning
var _add_button: Button

# Mapping from ItemList row → layout.overlays index (named overlays only).
# Unnamed overlays are excluded from the list but skew the index.
var _overlay_row_to_index: Array[int] = []


func _init(editor: LevelEditor) -> void:
	_ed = editor


func _ready() -> void:
	title = "Add / Edit Triggers"
	size = Vector2i(420, 480)
	min_size = Vector2i(320, 320)
	# AcceptDialog, not bare Window: the kingdom theme styles dialog panels,
	# not raw window chrome (a themed Window still rendered engine-grey —
	# owner field report). Matches the crate Info dialog.
	exclusive = false
	ok_button_text = "Done"
	theme = load("res://resources/ui/kingdom_theme.tres")

	_vbox = VBoxContainer.new()
	_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vbox.add_theme_constant_override("separation", 8)
	var margin := MarginContainer.new()
	# no anchors preset — AcceptDialog manages its content rect
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 10)
	margin.add_child(_vbox)
	add_child(margin)

	# --- Key label ---
	var key_label := Label.new()
	key_label.name = "KeyLabel"
	_vbox.add_child(key_label)

	# --- Current actions list ---
	var act_header := Label.new()
	act_header.text = "Actions:"
	_vbox.add_child(act_header)

	_action_list_box = VBoxContainer.new()
	_action_list_box.name = "ActionListBox"
	_vbox.add_child(_action_list_box)

	# --- Warning label (cap / validation) ---
	_warning_label = Label.new()
	_warning_label.name = "WarningLabel"
	_warning_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	_warning_label.visible = false
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(_warning_label)

	# --- "Add action" row ---
	var add_header := Label.new()
	add_header.text = "Add action:"
	_vbox.add_child(add_header)

	_action_option = OptionButton.new()
	_action_option.name = "ActionOption"
	for entry in ACTIONS:
		_action_option.add_item(entry["label"])
	_action_option.item_selected.connect(_on_action_selected)
	_vbox.add_child(_action_option)

	# --- Param area (rebuilt per selection) ---
	_param_container = VBoxContainer.new()
	_param_container.name = "ParamContainer"
	_vbox.add_child(_param_container)

	# Overlay ItemList — permanent child of param_container, shown/hidden per action
	_overlay_list = ItemList.new()
	_overlay_list.name = "OverlayList"
	_overlay_list.custom_minimum_size = Vector2(0, 100)
	_overlay_list.visible = false
	_overlay_list.item_selected.connect(_on_overlay_row_selected)
	_param_container.add_child(_overlay_list)

	# Stem OptionButton — permanent child of param_container, shown/hidden per action
	_stem_option = OptionButton.new()
	_stem_option.name = "StemOption"
	_stem_option.visible = false
	for stem in _get_stems():
		_stem_option.add_item(stem)
	_param_container.add_child(_stem_option)

	# Text LineEdit — permanent child of param_container, shown/hidden per action
	_text_edit = LineEdit.new()
	_text_edit.name = "TextEdit"
	_text_edit.visible = false
	_text_edit.max_length = Effects.DISPLAY_CAP
	_text_edit.placeholder_text = "Message shown on screen (max %d chars)" % Effects.DISPLAY_CAP
	_param_container.add_child(_text_edit)

	# --- Footer: unnamed overlay count ---
	_footer_label = Label.new()
	_footer_label.name = "FooterLabel"
	_footer_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_footer_label.visible = false
	_vbox.add_child(_footer_label)

	# --- Add button ---
	_add_button = Button.new()
	_add_button.text = "Add"
	_add_button.pressed.connect(add_action)
	_vbox.add_child(_add_button)

	# Populate the param area for the default selection
	_rebuild_param_area()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# Opens the dialog for the given trigger key and layout.
func open(trigger_key: String, layout: LevelLayout) -> void:
	_trigger_key = trigger_key
	_layout = layout
	# Re-scan stems each open — a fresh ogg dropped mid-session appears
	# without recreating the dialog (matches the overlay-list refresh).
	_stem_option.clear()
	for stem in _get_stems():
		_stem_option.add_item(stem)

	# Update key label
	var key_label: Label = _vbox.get_node("KeyLabel")
	key_label.text = "Trigger: %s" % trigger_key

	_warning_label.visible = false

	_rebuild_action_list()
	_rebuild_overlay_list()
	_rebuild_param_area()

	popup_centered()


# Set the active action by id — used by tests to drive the dialog.
func set_action_by_id(action_id: String) -> void:
	for i in ACTIONS.size():
		if ACTIONS[i]["id"] == action_id:
			_action_option.selected = i
			_rebuild_param_area()
			return


# Add the currently-configured action to the trigger list.
# Called by the Add button and by tests.
func add_action() -> void:
	if _layout == null:
		return

	var action_str := _compose_action()
	if action_str == "":
		return

	# Validate: a validate message means we refuse
	var validate_msg := _validate_action(action_str)
	if validate_msg != "":
		_show_warning(validate_msg)
		return

	# Fetch or create the array
	var trig: Array
	if _layout.triggers.has(_trigger_key):
		trig = _layout.triggers[_trigger_key] as Array
	else:
		trig = []
		_layout.triggers[_trigger_key] = trig

	# Dedup
	if trig.has(action_str):
		_show_warning("Action already in list (no duplicates).")
		return

	# Cap
	if trig.size() >= ACTION_CAP:
		_show_warning("Trigger action cap (%d) reached." % ACTION_CAP)
		return

	trig.append(action_str)
	_warning_label.visible = false
	_rebuild_action_list()


# Remove the action at the given index from the trigger list.
func remove_action(index: int) -> void:
	if _layout == null or not _layout.triggers.has(_trigger_key):
		return
	var trig: Array = _layout.triggers[_trigger_key] as Array
	if index < 0 or index >= trig.size():
		return
	trig.remove_at(index)
	# Remove key if array is now empty
	if trig.is_empty():
		_layout.triggers.erase(_trigger_key)
	_rebuild_action_list()


# ---------------------------------------------------------------------------
# Accessors for tests
# ---------------------------------------------------------------------------

func get_overlay_list() -> ItemList:
	return _overlay_list


func get_text_edit() -> LineEdit:
	return _text_edit


func get_stem_option() -> OptionButton:
	return _stem_option


func get_footer_label() -> Label:
	return _footer_label


func get_warning_label() -> Label:
	return _warning_label


func get_all_stems() -> Array[String]:
	return _get_stems()


# ---------------------------------------------------------------------------
# Signal handler: row selected in overlay list → emit flash_requested
# ---------------------------------------------------------------------------

func _on_overlay_row_selected(row: int) -> void:
	if row < 0 or row >= _overlay_row_to_index.size():
		return
	var overlay_idx: int = _overlay_row_to_index[row]
	flash_requested.emit(overlay_idx)


# ---------------------------------------------------------------------------
# Internal rebuild helpers
# ---------------------------------------------------------------------------

func _rebuild_action_list() -> void:
	# Clear existing rows
	for child in _action_list_box.get_children():
		child.free()

	if _layout == null or not _layout.triggers.has(_trigger_key):
		return

	var trig: Array = _layout.triggers[_trigger_key] as Array
	for i in trig.size():
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = str(trig[i])
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = "✕"
		var captured_i := i
		btn.pressed.connect(func() -> void: remove_action(captured_i))
		row.add_child(btn)
		_action_list_box.add_child(row)


func _rebuild_overlay_list() -> void:
	_overlay_list.clear()
	_overlay_row_to_index.clear()

	if _layout == null:
		return

	var unnamed_count := 0
	for i in _layout.overlays.size():
		var o: Dictionary = _layout.overlays[i]
		var name_val: String = str(o.get("name", ""))
		if name_val == "":
			unnamed_count += 1
			continue
		var label := name_val
		if o.get("hidden", false) == true:
			label += " (hidden)"
		_overlay_list.add_item(label)
		_overlay_row_to_index.append(i)

	# Footer
	if unnamed_count > 0:
		_footer_label.text = "%d overlay(s) have no name and won't appear here — name them for triggers." % unnamed_count
		_footer_label.visible = true
	else:
		_footer_label.visible = false


func _rebuild_param_area() -> void:
	if _action_option == null:
		return

	var idx := _action_option.selected
	if idx < 0 or idx >= ACTIONS.size():
		_overlay_list.visible = false
		_stem_option.visible = false
		_text_edit.visible = false
		return

	var param_type: String = ACTIONS[idx]["param"]
	_overlay_list.visible = (param_type == "overlay")
	_stem_option.visible = (param_type == "stem")
	_text_edit.visible = (param_type == "text")


func _on_action_selected(_idx: int) -> void:
	_rebuild_param_area()


func _compose_action() -> String:
	var idx := _action_option.selected
	if idx < 0 or idx >= ACTIONS.size():
		return ""

	var entry: Dictionary = ACTIONS[idx]
	var action_id: String = entry["id"]
	var param_type: String = entry["param"]

	match param_type:
		"none":
			return action_id
		"text":
			var msg := _text_edit.text.strip_edges()
			if msg == "":
				_show_warning("Type a message to display.")
				return ""
			return "%s:%s" % [action_id, msg]
		"overlay":
			var sel := _overlay_list.get_selected_items()
			if sel.is_empty():
				_show_warning("Select an overlay to target.")
				return ""
			var row: int = sel[0]
			if row >= _overlay_row_to_index.size():
				return ""
			var oi: int = _overlay_row_to_index[row]
			if oi < 0 or oi >= _layout.overlays.size():
				return ""
			var o: Dictionary = _layout.overlays[oi]
			var oname: String = str(o.get("name", ""))
			if oname == "":
				_show_warning("Selected overlay has no name.")
				return ""
			return "%s:%s" % [action_id, oname]
		"stem":
			if _stem_option.item_count == 0:
				_show_warning("No sound stems available.")
				return ""
			var stem_idx := _stem_option.selected
			if stem_idx < 0:
				stem_idx = 0
			var stem: String = _stem_option.get_item_text(stem_idx)
			return "sound:%s" % stem
	return ""


func _validate_action(action_str: String) -> String:
	# Only validate shape here — Effects.is_known handles the rest at runtime
	if action_str == "":
		return "Empty action."
	return ""


func _show_warning(msg: String) -> void:
	_warning_label.text = msg
	_warning_label.visible = true


# ---------------------------------------------------------------------------
# SFX stem list — scans res://assets/sfx/ for .ogg files
# ---------------------------------------------------------------------------

static func _get_stems() -> Array[String]:
	var stems: Array[String] = []
	var dir := DirAccess.open("res://assets/sfx")
	if dir == null:
		return stems
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		# Exported builds list disguised names (boom.ogg.remap / .import) —
		# strip before matching or the list is empty on web (MusicDirector lesson).
		var stripped := fname.trim_suffix(".remap").trim_suffix(".import")
		if not dir.current_is_dir() and stripped.ends_with(".ogg"):
			stems.append(stripped.get_basename())
		fname = dir.get_next()
	dir.list_dir_end()
	stems.sort()
	return stems
