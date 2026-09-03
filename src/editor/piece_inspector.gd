class_name PieceInspector
extends PanelContainer

# Floating inspector shown while a scenery piece is selected.
# Exposes: behavior OptionButton (None/Spin/Sway/Bob), a 3x3 pivot grid
# (radio-style toggle buttons), speed HSlider (0-2), movement HSlider (0-60, overlay key "amplitude").
#
# open(overlay, piece) populates all controls from the dict and stores
# references.  Setter methods are the single path through which both UI
# signals AND tests mutate state — no signal-callback divergence.
#
# Live preview note: while in the editor, _rebuild_scenery() forces all
# pieces to behavior=NONE so they stay static during editing.  set_behavior_by_name
# writes the dict (source of truth) and pokes piece.behavior for the live
# piece — but _rebuild_scenery will re-zero it on the next rebuild.
# Speed, movement, and pivot ARE applied live because they are purely
# visual without motion.  Live behavior preview is deliberately off in the
# editor; the tests confirm dict correctness, not animation playback.

var _overlay: Dictionary = {}
var _piece: NarfDecor = null

# Guard to suppress re-entrant setter calls during UI population.
var _updating := false

# Node references — populated in _ready()
var _behavior_option: OptionButton
var _pivot_buttons: Array[Button] = []
var _speed_slider: HSlider
var _amplitude_slider: HSlider
var _axis_h: Button
var _axis_v: Button
var _travel_slider: HSlider
var _tilt_slider: HSlider

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

	# Populate behavior OptionButton labels.
	for bname in BEHAVIOR_NAMES:
		_behavior_option.add_item(bname)

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

	visible = false


# Open the inspector for the given overlay dict and live piece.
# Reads current values from the dict and pre-populates all controls.
func open(overlay: Dictionary, piece: NarfDecor) -> void:
	_overlay = overlay
	_piece = piece

	_updating = true

	# --- Pre-populate behavior ---
	var b_name: String = overlay.get("behavior", "NONE")
	var b_idx := BEHAVIOR_NAMES.find(b_name)
	if b_idx < 0:
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

func set_behavior_by_name(name: String) -> void:
	if _overlay.is_empty():
		return
	_overlay["behavior"] = name
	# Apply to the live piece.
	# NOTE: the editor's _rebuild_scenery will re-zero behavior to NONE on
	# the next rebuild (static editor preview is intentional).  We poke it
	# here so tests can verify the write went through immediately.
	if is_instance_valid(_piece):
		var behavior_keys := NarfDecor.Behavior.keys()
		var idx := behavior_keys.find(name)
		if idx >= 0:
			_piece.behavior = idx as NarfDecor.Behavior
	# Sync the UI without triggering the signal callback.
	var b_idx := BEHAVIOR_NAMES.find(name)
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


func set_axis_by_name(name: String) -> void:
	if _overlay.is_empty():
		return
	if not name in AXIS_NAMES:
		return
	_overlay["axis"] = name
	if is_instance_valid(_piece):
		_piece.axis = AXIS_NAMES.find(name) as NarfDecor.DriftAxis
	_press_axis(name)


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


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Radio-press the axis pair. Saves and restores the _updating guard so that
# callers mid-block (e.g. open()) do not drop the guard early.
func _press_axis(name: String) -> void:
	var was := _updating
	_updating = true
	_axis_v.button_pressed = name == "VERTICAL"
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
