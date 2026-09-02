class_name NarfDecor
extends Sprite2D

# NarfKit: living scenery. Any texture + a behavior verb = animated
# decor. Composite over a static backdrop wherever a windmill should
# turn, a tree should sway, or a boat should bob.
#
# Kit rules: zero host-game dependencies — dials are exported, host
# supplies the art.

enum Behavior { NONE, SPIN, SWAY, BOB }

## What the piece does with its time.
@export var behavior := Behavior.NONE
## SPIN: rotations per second. SWAY/BOB: oscillations per second.
@export_range(0.0, 10.0, 0.01) var speed := 0.25
## SWAY: peak tilt in degrees. BOB: peak travel in pixels.
@export_range(0.0, 180.0, 0.5) var amplitude := 6.0

var _t := 0.0
var _home_rotation := 0.0
var _home_y := 0.0


func _ready() -> void:
	_home_rotation = rotation
	_home_y = position.y


func _process(delta: float) -> void:
	if behavior == Behavior.NONE:
		return
	_t += delta
	match behavior:
		Behavior.SPIN:
			rotation = _home_rotation + _t * speed * TAU
		Behavior.SWAY:
			rotation = _home_rotation + deg_to_rad(amplitude) * sin(_t * speed * TAU)
		Behavior.BOB:
			position.y = _home_y + amplitude * sin(_t * speed * TAU)
