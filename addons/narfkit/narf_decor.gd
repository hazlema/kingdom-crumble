@tool
class_name NarfDecor
extends Sprite2D

# NarfKit: living scenery. Any texture + a behavior verb = animated
# decor. Composite over a static backdrop wherever a windmill should
# turn, a tree should sway, or a boat should bob.
#
# Kit rules: zero host-game dependencies — dials are exported, host
# supplies the art. No raw numbers where a name will do: the pivot is
# a 9-point anchor, because a rotor spins around CENTER but a tree
# hinges at LOWER_CENTER — the enum is the documentation.

enum Behavior { NONE, SPIN, SWAY, BOB }
enum Pivot {
	TOP_LEFT,
	TOP_CENTER,
	TOP_RIGHT,
	CENTER_LEFT,
	CENTER,
	CENTER_RIGHT,
	LOWER_LEFT,
	LOWER_CENTER,
	LOWER_RIGHT,
}

## What the piece does with its time.
@export var behavior := Behavior.NONE
## The point the piece rotates/hangs from (node origin sits here).
@export var pivot := Pivot.CENTER:
	set(v):
		pivot = v
		_apply_pivot()
## SPIN: rotations per second. SWAY/BOB: oscillations per second.
@export_range(0.0, 10.0, 0.01) var speed := 0.25
## How much it moves — SWAY: peak tilt in degrees. BOB: peak travel in pixels.
@export_range(0.0, 180.0, 0.5) var movement := 6.0

var _t := 0.0
var _home_rotation := 0.0
var _home_y := 0.0


func _ready() -> void:
	_apply_pivot()
	_home_rotation = rotation
	_home_y = position.y


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or behavior == Behavior.NONE:
		return
	_t += delta
	match behavior:
		Behavior.SPIN:
			rotation = _home_rotation + _t * speed * TAU
		Behavior.SWAY:
			rotation = _home_rotation + deg_to_rad(movement) * sin(_t * speed * TAU)
		Behavior.BOB:
			position.y = _home_y + movement * sin(_t * speed * TAU)


func _apply_pivot() -> void:
	if texture == null:
		return
	centered = false
	var fx := (pivot % 3) * 0.5  # column: left / center / right
	var fy := (pivot / 3) * 0.5  # row: top / center / lower
	offset = -Vector2(texture.get_size().x * fx, texture.get_size().y * fy)
