class_name Stone
extends RigidBody2D

const VARIANTS: Array[Texture2D] = [
	preload("res://art/assets/stones_64/stone-1.png"),
	preload("res://art/assets/stones_64/stone-2.png"),
	preload("res://art/assets/stones_64/stone-3.png"),
	preload("res://art/assets/stones_64/stone-4.png"),
]

const BOUNCE := 0.75
const BOOM_RADIUS := 180.0
const BOOM_MIN_SPEED := 300.0

# Set BEFORE add_child — read once in _ready (spec §3).
var exploding := false
var super_bounce := false

var _boomed := false

func _ready() -> void:
	mass = 2.0 * (Settings.preset.impact_force if Settings.preset else 1.0)
	$Visual.texture = VARIANTS[randi() % VARIANTS.size()]
	if super_bounce:
		var mat := PhysicsMaterial.new()
		mat.bounce = BOUNCE
		physics_material_override = mat
	if exploding:
		contact_monitor = true
		max_contacts_reported = 8
		body_entered.connect(_on_contact)

func launch(from: Vector2, velocity: Vector2) -> void:
	global_position = from
	linear_velocity = velocity

func _on_contact(_body: Node) -> void:
	# Stones never detonate on other stones — prevents multishot+exploding
	# volleys from instantly self-detonating on sibling contact.
	if _body is Stone:
		return
	_boom()

func _boom() -> void:
	if _boomed and not super_bounce:
		return  # two contacts in one frame must not double the one boom
	_boomed = true
	var power := mass * maxf(linear_velocity.length(), BOOM_MIN_SPEED)
	for c in get_tree().get_nodes_in_group("crates"):
		if c.freeze:
			continue
		var d: float = c.global_position.distance_to(global_position)
		if d < BOOM_RADIUS:
			var dir: Vector2 = (c.global_position - global_position).normalized()
			c.apply_central_impulse(dir * power * (1.0 - d / BOOM_RADIUS))
	_boom_visual()
	if not super_bounce:
		queue_free()

# A real blast reads in three layers: a ballooning shockwave flash,
# hot fire that dies fast, and smoke that lingers — not confetti.
func _boom_visual() -> void:
	var parent := get_parent()
	var tree := get_tree()

	var wave := Sprite2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.97, 0.8, 0.95))
	grad.set_color(1, Color(1.0, 0.55, 0.15, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 256
	tex.height = 256
	wave.texture = tex
	wave.scale = Vector2(0.3, 0.3)
	parent.add_child(wave)
	wave.global_position = global_position
	var grow := BOOM_RADIUS * 2.2 / 256.0
	var wt := wave.create_tween().set_parallel(true)
	wt.tween_property(wave, "scale", Vector2(grow, grow), 0.22)
	wt.tween_property(wave, "modulate:a", 0.0, 0.3)
	tree.create_timer(0.5).timeout.connect(wave.queue_free)

	var fire := CPUParticles2D.new()
	fire.emitting = true
	fire.one_shot = true
	fire.amount = 120
	fire.lifetime = 0.55
	fire.explosiveness = 1.0
	fire.spread = 180.0
	fire.gravity = Vector2(0, 150)
	fire.initial_velocity_min = 350.0
	fire.initial_velocity_max = 900.0
	fire.damping_min = 400.0
	fire.damping_max = 700.0
	fire.scale_amount_min = 5.0
	fire.scale_amount_max = 11.0
	fire.color_ramp = _fire_colors()
	parent.add_child(fire)
	fire.global_position = global_position
	tree.create_timer(1.5).timeout.connect(fire.queue_free)

	var smoke := CPUParticles2D.new()
	smoke.emitting = true
	smoke.one_shot = true
	smoke.amount = 30
	smoke.lifetime = 1.1
	smoke.explosiveness = 0.9
	smoke.spread = 180.0
	smoke.gravity = Vector2(0, -120)
	smoke.initial_velocity_min = 60.0
	smoke.initial_velocity_max = 220.0
	smoke.scale_amount_min = 10.0
	smoke.scale_amount_max = 20.0
	smoke.color = Color(0.35, 0.32, 0.3, 0.55)
	parent.add_child(smoke)
	smoke.global_position = global_position
	tree.create_timer(2.5).timeout.connect(smoke.queue_free)

static func _fire_colors() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.6))
	g.add_point(0.35, Color(1.0, 0.55, 0.12))
	g.set_color(1, Color(0.45, 0.12, 0.05, 0.0))
	return g
