@tool
class_name NarfDecor
extends Sprite2D

# NarfKit: living scenery. Any texture + a behavior verb = animated
# decor. Composite over a static backdrop wherever a windmill should
# turn, a tree should sway, a boat should bob, a cloud should drift,
# or a butterfly should wander.
#
# Kit rules: zero host-game dependencies -- dials are exported, host
# supplies the art. No raw numbers where a name will do: the pivot is
# a 9-point anchor, because a rotor spins around CENTER but a tree
# hinges at LOWER_CENTER -- the enum is the documentation.

enum Behavior { NONE, SPIN, SWAY, BOB, DRIFT, WANDER }
enum DriftAxis { HORIZONTAL, VERTICAL }
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
## How much it moves. SWAY: peak tilt in degrees. BOB: peak travel in pixels.
@export_range(0.0, 180.0, 0.5) var movement := 6.0
## DRIFT: which way the piece slides.
@export var axis := DriftAxis.HORIZONTAL
## DRIFT: max distance either side of placement. WANDER: roam radius. Pixels.
@export_range(0.0, 2000.0, 1.0) var travel := 120.0
## WANDER: peak banking angle while flying, in degrees. Level at rest.
@export_range(0.0, 45.0, 0.5) var tilt := 8.0

var _t := 0.0
var _home_rotation := 0.0
var _home_pos := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
# WANDER hop state -- glide from _hop_start to _hop_target as _hop_p runs 0..1.
var _hop_start := Vector2.ZERO
var _hop_target := Vector2.ZERO
var _hop_p := 0.0
var _hop_active := false


func _ready() -> void:
	_apply_pivot()
	rehome()


## Re-anchor the motion home to the current transform. Position-driven
## verbs animate AROUND home, so a host that moves a live piece (an
## editor drag, a cutscene) must call this or the next frame snaps the
## piece back to wherever it was born.
func rehome() -> void:
	_home_rotation = rotation
	_home_pos = position
	_hop_active = false


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
			position.y = _home_pos.y + movement * sin(_t * speed * TAU)
		Behavior.DRIFT:
			var axis_vec := Vector2.RIGHT if axis == DriftAxis.HORIZONTAL else Vector2.DOWN
			position = _home_pos + axis_vec * travel * sin(_t * speed * TAU)
		Behavior.WANDER:
			_wander(delta)


# Butterfly logic: pick a uniform random point inside the roam circle,
# smoothstep-glide to it over 1/speed seconds, repeat. Flips to fly
# nose-first (art assumed to face right -- flip the PNG if it doesn't)
# and banks into the turn, always level at each endpoint.
func _wander(delta: float) -> void:
	if not _hop_active:
		_hop_start = position
		var r := travel * sqrt(_rng.randf())
		_hop_target = _home_pos + Vector2.from_angle(_rng.randf() * TAU) * r
		_hop_p = 0.0
		_hop_active = true
		flip_h = _hop_target.x < _hop_start.x
	_hop_p = minf(_hop_p + delta * maxf(speed, 0.01), 1.0)
	var q := _hop_p * _hop_p * (3.0 - 2.0 * _hop_p)
	position = _hop_start.lerp(_hop_target, q)
	var hsign := -1.0 if flip_h else 1.0
	rotation = _home_rotation + hsign * deg_to_rad(tilt) * sin(_hop_p * PI)
	if _hop_p >= 1.0:
		_hop_active = false


func _apply_pivot() -> void:
	if texture == null:
		return
	centered = false
	var fx := (pivot % 3) * 0.5  # column: left / center / right
	var fy := (pivot / 3) * 0.5  # row: top / center / lower
	offset = -Vector2(texture.get_size().x * fx, texture.get_size().y * fy)
