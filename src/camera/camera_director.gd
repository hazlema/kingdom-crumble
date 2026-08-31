class_name CameraDirector
extends Camera2D

enum Mode { AIM, FOLLOW, SCOUT }

const SCOUT_SPEED := 900.0
# Keep the aim focus at least this far inside the viewport edge.
const AIM_EDGE_MARGIN := 160.0

var mode := Mode.AIM
var follow_target: Node2D
var home_position := Vector2.ZERO
# While charging a shot: the world point (arrow end) that must stay in
# frame. Vector2.INF = no focus, sit at home.
var aim_focus := Vector2.INF

func _init() -> void:
	# BEFORE entering the tree: physics interpolation forces cameras to
	# physics ticks and logs an override notice if we're late about it
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS

func _ready() -> void:
	home_position = global_position
	position_smoothing_enabled = true
	position_smoothing_speed = 6.0

func set_mode(m: Mode) -> void:
	mode = m
	if m == Mode.AIM:
		follow_target = null

# Hold the right mouse button and drag to scout the level by hand.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion \
			and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		if mode == Mode.AIM:
			set_mode(next_mode(mode, "scout_input"))
		if mode == Mode.SCOUT:
			global_position -= event.relative / zoom
			_clamp_to_limits()

func _physics_process(delta: float) -> void:
	match mode:
		Mode.AIM:
			global_position = _aim_position()
		Mode.FOLLOW:
			if is_instance_valid(follow_target):
				global_position = follow_target.global_position
		Mode.SCOUT:
			var dir := Input.get_axis("scout_left", "scout_right")
			global_position.x += dir * SCOUT_SPEED * delta
			_clamp_to_limits()

# Free-pan must clamp POSITION, not just the display: past the level
# bounds the display pins while position keeps travelling, and panning
# back drags through invisible overshoot — "scrolling stopped working".
func _clamp_to_limits() -> void:
	var half := get_viewport_rect().size * 0.5 / zoom
	global_position.x = clampf(global_position.x,
		limit_left + half.x, limit_right - half.x)
	global_position.y = clampf(global_position.y,
		limit_top + half.y, limit_bottom - half.y)

# Split the view between the catapult and the arrow's end, but never
# let the end leave the frame — the tip wins over the midpoint.
func _aim_position() -> Vector2:
	if not aim_focus.is_finite():
		return home_position
	var half := get_viewport_rect().size * 0.5 / zoom
	var target := (home_position + aim_focus) * 0.5
	target.x = clampf(target.x,
		aim_focus.x - (half.x - AIM_EDGE_MARGIN),
		aim_focus.x + (half.x - AIM_EDGE_MARGIN))
	target.y = clampf(target.y,
		aim_focus.y - (half.y - AIM_EDGE_MARGIN),
		aim_focus.y + (half.y - AIM_EDGE_MARGIN))
	return target

static func next_mode(current: Mode, event: String) -> Mode:
	match event:
		"fired":
			return Mode.FOLLOW
		"settled":
			return Mode.AIM if current == Mode.FOLLOW else current
		"scout_input":
			return Mode.SCOUT if current == Mode.AIM else current
		"aim_input":
			return Mode.AIM if current == Mode.SCOUT else current
	return current
