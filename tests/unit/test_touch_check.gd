extends GutTest

# Long-press the battlefield = the H crate check. The script is exercised
# bare (no scene tree) -- these funcs touch only hold-state and Input.

var LevelScript := preload("res://src/level/level.gd")


func _mb(pressed: bool, pos: Vector2 = Vector2(500, 300)) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	return ev


func test_long_press_lights_check_and_release_clears_it() -> void:
	var l: Node = LevelScript.new()
	l._unhandled_input(_mb(true))
	l._tick_hold(CHECK_TIME(l) - 0.1)
	assert_false(Input.is_action_pressed("check"), "not yet -- still short of the hold time")
	l._tick_hold(0.2)
	assert_true(Input.is_action_pressed("check"), "held long enough: crates light up")
	l._unhandled_input(_mb(false))
	assert_false(Input.is_action_pressed("check"), "release clears it")
	l.free()


func test_drag_past_slop_cancels_the_press() -> void:
	var l: Node = LevelScript.new()
	l._unhandled_input(_mb(true))
	var move := InputEventMouseMotion.new()
	move.position = Vector2(600, 300)  # 100px away, well past the slop
	l._unhandled_input(move)
	l._tick_hold(1.0)
	assert_false(Input.is_action_pressed("check"), "a drag is not a press")
	l.free()


static func CHECK_TIME(l: Node) -> float:
	return l.CHECK_HOLD_SEC
