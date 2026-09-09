class_name PieceInspector
extends PanelContainer

# Floating inspector shown while a scenery piece is selected.
# Exposes: behavior OptionButton (None/Spin/Sway/Bob), a 3x3 pivot grid
# (radio-style toggle buttons), speed HSlider (0-2), movement HSlider (0-60, overlay key "amplitude").
# Full mode only: Solid / Front / Peek CheckBoxes.
#
# open(overlay, piece) populates all controls from the dict and stores
# references.  Setter methods are the single path through which both UI
# signals AND tests mutate state — no signal-callback divergence.
#
# Live preview note: verbs stay LIVE in the editor (since 8c02d4e).
# set_behavior_by_name writes the dict (source of truth) AND applies the
# verb to the live piece, which keeps animating; _rebuild_scenery()
# re-applies pending edit-state and rehome()s every piece, so rebuilds
# never silence or revert a verb.  Speed, movement, and pivot are applied
# live the same way.  The tests confirm dict correctness, not animation
# playback.
#
# _updating guard discipline: ALWAYS hoist _updating = true BEFORE any
# programmatic set on a control that emits a signal; restore with was/false
# after.  Never let the guard drop mid-block (use the was=_updating pattern
# for nested helpers, see _press_axis / _press_pivot_button).

var _overlay: Dictionary = {}
var _piece: NarfDecor = null

# Guard to suppress re-entrant setter calls during UI population.
var _updating := false

# True when open() was called in reduced (prop) mode.
var _reduced := false

# Node references — populated in _ready()
var _behavior_option: OptionButton
var _pivot_buttons: Array[Button] = []
var _speed_slider: HSlider
var _amplitude_slider: HSlider
var _axis_h: Button
var _axis_v: Button
var _travel_slider: HSlider
var _tilt_slider: HSlider
# Solid / Front / Peek checkboxes (full mode only).
var _solid_check: CheckBox
var _front_check: CheckBox
var _peek_check: CheckBox
# Separator above the scenery-flag row (hidden in reduced mode).
var _sep_scenery: HSeparator
# Nodes toggled by reduced mode (not all have unique_name_in_owner).
var _pivot_label: Label
var _axis_label: Label
var _axis_row: HBoxContainer
var _travel_label: Label
var _tilt_label: Label

# Behavior name ordering must match NarfDecor.Behavior ordinals exactly — indices 0-5.
const BEHAVIOR_NAMES := ["NONE", "SPIN", "SWAY", "BOB", "DRIFT", "WANDER"]
# Axis name ordering must match NarfDecor.DriftAxis indices 0-1.
const AXIS_NAMES := ["HORIZONTAL", "VERTICAL"]


func _ready() -> void:
	_behavior_option = %BehaviorOption
	_speed_slider = %SpeedSlider
	_amplitude_slider = %AmplitudeSlider

	# Collect pivot buttons in grid order (children of the GridContainer).
	var grid: GridContainer = %PivotGrid
	for child in grid.get_children():
		if child is Button:
			_pivot_buttons.append(child as Button)
			(child as Button).toggle_mode = true

	# Populate behavior OptionButton labels (full set; reduced open() re-fills to 4).
	_rebuild_behavior_options(true)

	# Connect UI signals → setters (guarded by _updating).
	_behavior_option.item_selected.connect(func(idx: int) -> void:
		if not _updating:
			set_behavior_by_name(BEHAVIOR_NAMES[idx])
	)
	_speed_slider.value_changed.connect(func(v: float) -> void:
		if not _updating:
			set_speed(v)
	)
	_amplitude_slider.value_changed.connect(func(v: float) -> void:
		if not _updating:
			set_amplitude(v)
	)
	_axis_h = %AxisH
	_axis_v = %AxisV
	_travel_slider = %TravelSlider
	_tilt_slider = %TiltSlider
	_pivot_label = $Box/PivotLabel
	_axis_label = $Box/AxisLabel
	_axis_row = $Box/AxisRow
	_travel_label = $Box/TravelLabel
	_tilt_label = $Box/TiltLabel
	_axis_h.toggled.connect(func(pressed: bool) -> void:
		if pressed and not _updating:
			set_axis_by_name("HORIZONTAL")
	)
	_axis_v.toggled.connect(func(pressed: bool) -> void:
		if pressed and not _updating:
			set_axis_by_name("VERTICAL")
	)
	_travel_slider.value_changed.connect(func(v: float) -> void:
		if not _updating:
			set_travel(v)
	)
	_tilt_slider.value_changed.connect(func(v: float) -> void:
		if not _updating:
			set_tilt(v)
	)
	for i in _pivot_buttons.size():
		var btn := _pivot_buttons[i]
		var captured_i := i
		btn.toggled.connect(func(pressed: bool) -> void:
			if pressed and not _updating:
				set_pivot_by_index(captured_i)
		)

	# Solid / Front / Peek checkboxes (full-mode scenery flags).
	_solid_check = %SolidCheck
	_front_check = %FrontCheck
	_peek_check = %PeekCheck
	_sep_scenery = $Box/Separator7
	_solid_check.toggled.connect(func(pressed: bool) -> void:
		if not _updating:
			set_solid(pressed)
	)
	_front_check.toggled.connect(func(pressed: bool) -> void:
		if not _updating:
			set_front(pressed)
	)
	_peek_check.toggled.connect(func(pressed: bool) -> void:
		if not _updating:
			set_peek(pressed)
	)

	visible = false


# Open the inspector for the given overlay dict and live piece.
# Reads current values from the dict and pre-populates all controls.
# Pass reduced=true for animatable props (hides pivot/axis/travel/tilt,
# restricts verbs to NONE/SPIN/SWAY/BOB, caps amplitude to 12).
func open(overlay: Dictionary, piece: NarfDecor, reduced := false) -> void:
	_overlay = overlay
	_piece = piece
	_reduced = reduced
	var full := not reduced

	_updating = true

	# Apply mode — hide/show advanced controls and rebuild verb list.
	# Nodes are direct children of Box (VBoxContainer), addressed by stored refs.
	_pivot_label.visible = full
	%PivotGrid.visible = full
	_axis_label.visible = full
	_axis_row.visible = full
	_travel_label.visible = full
	_travel_slider.visible = full
	_tilt_label.visible = full
	_tilt_slider.visible = full
	# Scenery-only flags: hidden in reduced (prop) mode.
	_sep_scenery.visible = full
	_solid_check.visible = full
	_front_check.visible = full
	_peek_check.visible = full
	_amplitude_slider.max_value = 60.0 if full else 12.0
	_rebuild_behavior_options(full)

	# --- Pre-populate behavior ---
	var b_name: String = overlay.get("behavior", "NONE")
	var b_idx := BEHAVIOR_NAMES.find(b_name)
	if b_idx < 0:
		b_idx = 0
	# In reduced mode only 4 items exist (NONE/SPIN/SWAY/BOB); cap the index.
	if reduced and b_idx >= 4:
		b_idx = 0
	_behavior_option.selected = b_idx

	# --- Pre-populate speed ---
	_speed_slider.value = float(overlay.get("speed", 0.25))

	# --- Pre-populate movement (overlay key "amplitude") ---
	_amplitude_slider.value = float(overlay.get("amplitude", 6.0))

	# --- Pre-populate pivot ---
	var pivot_keys := NarfDecor.Pivot.keys()
	var p_name: String = overlay.get("pivot", "CENTER")
	var p_idx := pivot_keys.find(p_name)
	if p_idx < 0:
		p_idx = NarfDecor.Pivot.CENTER
	_press_pivot_button(p_idx)

	# --- Pre-populate drift dials ---
	_press_axis(String(overlay.get("axis", "HORIZONTAL")))
	_travel_slider.value = float(overlay.get("travel", 120.0))
	_tilt_slider.value = float(overlay.get("tilt", 8.0))

	# --- Pre-populate Solid / Front / Peek (full mode only) ---
	if full:
		var is_solid: bool = overlay.get("solid", false) == true
		var is_front: bool = overlay.get("front", false) == true
		var is_peek: bool = overlay.get("peek", false) == true
		_solid_check.button_pressed = is_solid
		_front_check.button_pressed = is_front
		_peek_check.button_pressed = is_peek
		_peek_check.disabled = not is_front
		# Reflect travel-verb disabled state from current solid flag.
		_set_travel_verbs_disabled(is_solid)

	_updating = false

	visible = true


# Called when inspector should close (deselect / exit scenery).
func close() -> void:
	_overlay = {}
	_piece = null
	visible = false


# ---------------------------------------------------------------------------
# Setter API — used by UI signals AND unit tests
# ---------------------------------------------------------------------------

func set_behavior_by_name(verb_name: String) -> void:
	if _overlay.is_empty():
		return
	var b_idx := BEHAVIOR_NAMES.find(verb_name)
	if _reduced and b_idx >= 4:
		return
	_overlay["behavior"] = verb_name
	# Apply to the live piece — verbs stay live in the editor (8c02d4e),
	# and _rebuild_scenery re-applies dict state rather than silencing it.
	if is_instance_valid(_piece):
		var behavior_keys := NarfDecor.Behavior.keys()
		var idx := behavior_keys.find(verb_name)
		if idx >= 0:
			# Re-anchor first: home was captured at spawn, and the piece may
			# have been dragged since -- without this the verb snaps it back.
			_piece.rehome()
			_piece.behavior = idx as NarfDecor.Behavior
	# Sync the UI without triggering the signal callback.
	if b_idx >= 0 and _behavior_option.selected != b_idx:
		_updating = true
		_behavior_option.selected = b_idx
		_updating = false


func set_speed(v: float) -> void:
	if _overlay.is_empty():
		return
	_overlay["speed"] = v
	if is_instance_valid(_piece):
		_piece.speed = v
	if not is_equal_approx(_speed_slider.value, v):
		_updating = true
		_speed_slider.value = v
		_updating = false


func set_amplitude(v: float) -> void:
	if _overlay.is_empty():
		return
	_overlay["amplitude"] = v
	if is_instance_valid(_piece):
		_piece.movement = v
	if not is_equal_approx(_amplitude_slider.value, v):
		_updating = true
		_amplitude_slider.value = v
		_updating = false


func set_pivot_by_index(i: int) -> void:
	if _overlay.is_empty():
		return
	var pivot_keys := NarfDecor.Pivot.keys()
	if i < 0 or i >= pivot_keys.size():
		return
	_overlay["pivot"] = pivot_keys[i]
	if is_instance_valid(_piece):
		_piece.pivot = i as NarfDecor.Pivot
	_press_pivot_button(i)


func set_axis_by_name(axis_name: String) -> void:
	if _overlay.is_empty():
		return
	if not axis_name in AXIS_NAMES:
		return
	_overlay["axis"] = axis_name
	if is_instance_valid(_piece):
		_piece.axis = AXIS_NAMES.find(axis_name) as NarfDecor.DriftAxis
	_press_axis(axis_name)


func set_travel(v: float) -> void:
	if _overlay.is_empty():
		return
	_overlay["travel"] = v
	if is_instance_valid(_piece):
		_piece.travel = v
	if not is_equal_approx(_travel_slider.value, v):
		_updating = true
		_travel_slider.value = v
		_updating = false


func set_tilt(v: float) -> void:
	if _overlay.is_empty():
		return
	_overlay["tilt"] = v
	if is_instance_valid(_piece):
		_piece.tilt = v
	if not is_equal_approx(_tilt_slider.value, v):
		_updating = true
		_tilt_slider.value = v
		_updating = false


# Writes or erases "solid" in the overlay dict.
# When solid is set: disables DRIFT/WANDER dropdown items; if the current
# behavior is a travel verb, resets it to NONE through the existing setter
# (live piece updates, dict stays canonical).
# When solid is cleared: re-enables DRIFT/WANDER items.
# Absent = unchecked; we erase rather than write false to keep files minimal.
func set_solid(v: bool) -> void:
	if _overlay.is_empty():
		return
	if v:
		_overlay["solid"] = true
		# If the current behavior is a travel verb, reset to NONE.
		var cur_behavior: String = _overlay.get("behavior", "NONE")
		if cur_behavior == "DRIFT" or cur_behavior == "WANDER":
			set_behavior_by_name("NONE")
	else:
		_overlay.erase("solid")
	# Sync checkbox without re-entering the signal.
	var was := _updating
	_updating = true
	_solid_check.button_pressed = v
	_updating = was
	# Update DRIFT/WANDER item enabled/disabled state.
	_set_travel_verbs_disabled(v)


# Writes or erases "front" in the overlay dict.
# Unchecking front also erases peek (validator rejects orphan peek).
func set_front(v: bool) -> void:
	if _overlay.is_empty():
		return
	if v:
		_overlay["front"] = true
	else:
		_overlay.erase("front")
		# Peek requires front — erase it too to keep the dict valid.
		_overlay.erase("peek")
		# Uncheck peek checkbox and disable it.
		var was := _updating
		_updating = true
		_peek_check.button_pressed = false
		_updating = was
	# Sync front checkbox.
	var was := _updating
	_updating = true
	_front_check.button_pressed = v
	_peek_check.disabled = not v
	_updating = was


# Writes or erases "peek" in the overlay dict.
# Only meaningful while front is checked; caller is responsible for only
# enabling the control when front is set (the _peek_check.disabled guard does this).
func set_peek(v: bool) -> void:
	if _overlay.is_empty():
		return
	if v:
		_overlay["peek"] = true
	else:
		_overlay.erase("peek")
	var was := _updating
	_updating = true
	_peek_check.button_pressed = v
	_updating = was


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Radio-press the axis pair. Saves and restores the _updating guard so that
# callers mid-block (e.g. open()) do not drop the guard early.
func _press_axis(axis_name: String) -> void:
	var was := _updating
	_updating = true
	_axis_v.button_pressed = axis_name == "VERTICAL"
	_axis_h.button_pressed = not _axis_v.button_pressed
	_updating = was


# Press the pivot button at index i, unpressing all others.
# Saves and restores the _updating guard so that callers mid-block (e.g.
# open()) do not drop the guard early.
func _press_pivot_button(i: int) -> void:
	var was := _updating
	_updating = true
	for j in _pivot_buttons.size():
		_pivot_buttons[j].button_pressed = (j == i)
	_updating = was


# Clears and re-fills the behavior OptionButton.
# full=true: all six BEHAVIOR_NAMES; full=false: first four (NONE/SPIN/SWAY/BOB).
func _rebuild_behavior_options(full: bool) -> void:
	_behavior_option.clear()
	var count := BEHAVIOR_NAMES.size() if full else 4
	for i in count:
		_behavior_option.add_item(BEHAVIOR_NAMES[i])


# Enables or disables DRIFT (index 4) and WANDER (index 5) in the behavior dropdown.
# Called when solid is toggled.  Only affects items that actually exist (full mode
# has 6 items; reduced mode only has 4 and travel verbs never appear there).
func _set_travel_verbs_disabled(disabled: bool) -> void:
	# Name-driven, not index-hardcoded — a BEHAVIOR_NAMES reorder must
	# never silently disable the wrong verbs (review catch). The travel
	# items only exist in full mode.
	for verb in ["DRIFT", "WANDER"]:
		var idx := BEHAVIOR_NAMES.find(verb)
		if idx >= 0 and _behavior_option.item_count > idx:
			_behavior_option.set_item_disabled(idx, disabled)
