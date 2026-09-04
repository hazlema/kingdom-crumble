class_name NarfConfetti
extends CPUParticles2D

# NarfKit: party in a node. A one-shot confetti burst of real particles,
# so nothing clips it -- pieces launch from the node and flutter as far
# as gravity takes them, across the whole screen if the screen is there.
#
# Two ways to celebrate:
#   scene: add a NarfConfetti node, call pop() whenever the mood strikes
#   code:  NarfConfetti.burst(host, at) -- fire-and-forget, self-cleaning

## How hard pieces launch before gravity wins.
@export_range(0.0, 2000.0, 10.0) var punch := 420.0
## Seconds a piece stays aloft -- 3s reaches the floor of a 1080 screen.
@export_range(0.5, 8.0, 0.1) var flutter_time := 3.0
## How many pieces per pop.
@export_range(1, 500) var pieces := 90


func _init() -> void:
	one_shot = true
	explosiveness = 1.0
	direction = Vector2.UP
	spread = 70.0
	emitting = false


func _ready() -> void:
	amount = pieces
	lifetime = flutter_time
	gravity = Vector2(0, 420)
	initial_velocity_min = punch * 0.45
	initial_velocity_max = punch
	angular_velocity_min = -540.0
	angular_velocity_max = 540.0
	# Air resistance: launch dies off and pieces settle into a drift.
	damping_min = 40.0
	damping_max = 120.0
	scale_amount_min = 3.0
	scale_amount_max = 6.0
	color_ramp = _festive()


func pop() -> void:
	restart()
	emitting = true


## Fire-and-forget: spawn a burst at `at` (host-local), free it after.
static func burst(host: Node, at: Vector2, pieces_n: int = 90) -> NarfConfetti:
	var c := NarfConfetti.new()
	c.position = at
	c.pieces = pieces_n
	host.add_child(c)
	c.pop()
	c.get_tree().create_timer(c.flutter_time + 1.0).timeout.connect(c.queue_free)
	return c


static func _festive() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.83, 0.29))
	g.add_point(0.33, Color(0.91, 0.28, 0.25))
	g.add_point(0.66, Color(0.31, 0.66, 0.9))
	g.set_color(1, Color(0.55, 0.79, 0.47))
	return g
