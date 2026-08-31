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

func _boom_visual() -> void:
	var p := CPUParticles2D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = 120
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector2(0, 300)
	p.initial_velocity_min = 250.0
	p.initial_velocity_max = 700.0
	p.scale_amount_min = 6.0
	p.scale_amount_max = 13.0
	p.color = Color(1.0, 0.6, 0.15)
	get_parent().add_child(p)
	p.global_position = global_position
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)
