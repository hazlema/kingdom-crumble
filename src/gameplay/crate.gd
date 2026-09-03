class_name Crate
extends RigidBody2D

signal knocked_out(crate: Crate)

const STANDING_MAX_DEG := 45.0

# Post-impact settle feel: higher = crates calm down faster after a
# hit, lower = they slosh and rock longer. Bounce stays the per-tier
# gameplay dial (resources/difficulty/*.tres).
const LINEAR_DAMP := 0.7
# const ANGULAR_DAMP := 6.0
const ANGULAR_DAMP := 2.0
# Restitution is speed-gated: below MIN a touch is inert (a slow
# boulder kissing the tower must not detonate it), above MAX the full
# per-tier bounce applies. Linear ramp in between.
const BOUNCE_MIN_SPEED := 60.0
const BOUNCE_MAX_SPEED := 240.0
# A crate also counts as knocked out when shoved this far off its spawn
# spot — bottom-row crates slide upright along the ground and can never
# tip past 45 degrees.
const KNOCKED_OUT_DISTANCE := 48.0
# The hop (owner: a floor-level crate has "no clearance to build
# momentum when you hit it"): a solid stone hit adds a small upward
# kick so the crate gets airborne — then the tumble and the ground's
# bounce material can actually perform. Slow kisses don't hop. Scaled
# by the crate's own mass so the hop height is consistent.
const POP_MIN_STONE_SPEED := 150.0
const POP_VELOCITY := 170.0

# Owner's tennis-ball foley (phone + tennis ball, 2026-09-03): two takes,
# dealt at random with a little pitch wobble so a collapsing tower does
# not machine-gun the identical sample.
const IMPACT_SOUNDS: Array[AudioStream] = [
	preload("res://assets/sfx/impact-1.ogg"),
	preload("res://assets/sfx/impact-2.ogg"),
]
# The raw takes ring too high (owner's ear, 2026-09-03) — play them an
# octave down. 0.5 = one octave; raise toward 1.0 if the thunk gets
# too muddy. The +/-10% wobble rides on top of this.
const IMPACT_PITCH := 0.5

var type_id := "crate-wood"
var home := Vector2.ZERO  # spawn position, captured in _ready

var _knock_reported := false

var _full_bounce := 0.5
var _mat := PhysicsMaterial.new()


func _ready() -> void:
	home = global_position
	_full_bounce = Settings.preset.crate_natural_bounce if Settings.preset else 0.5
	_mat.bounce = 0.0
	physics_material_override = _mat
	var p := Settings.preset
	linear_damp = p.crate_linear_damp if p and p.crate_linear_damp >= 0.0 else LINEAR_DAMP
	angular_damp = p.crate_angular_damp if p and p.crate_angular_damp >= 0.0 else ANGULAR_DAMP
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body is Stone and body.linear_velocity.length() > POP_MIN_STONE_SPEED:
		apply_central_impulse(Vector2.UP * POP_VELOCITY * mass)
		_play_impact()


# Rides the same speed gate as the hop: slow kisses stay silent,
# real hits speak. One-shot player, freed when the take ends.
func _play_impact() -> void:
	var player := AudioStreamPlayer.new()
	player.stream = IMPACT_SOUNDS[randi() % IMPACT_SOUNDS.size()]
	player.bus = "Sfx" if AudioServer.get_bus_index("Sfx") != -1 else "Master"
	player.pitch_scale = IMPACT_PITCH * randf_range(0.9, 1.1)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _physics_process(_delta: float) -> void:
	if not _knock_reported and not freeze and not is_standing():
		_knock_reported = true
		knocked_out.emit(self)
	if sleeping:
		return
	var ramp := clampf(
		(linear_velocity.length() - BOUNCE_MIN_SPEED) / (BOUNCE_MAX_SPEED - BOUNCE_MIN_SPEED),
		0.0,
		1.0
	)
	_mat.bounce = _full_bounce * ramp


# One-way door (owner: "dead stays dead"): once a crate has been
# knocked out it never counts as standing again, even if physics later
# parks it back upright on its own grave — resurrection corrupted the
# score.
func is_standing() -> bool:
	if _knock_reported:
		return false
	return (
		is_standing_rotation(rotation) and global_position.distance_to(home) < KNOCKED_OUT_DISTANCE
	)


static func is_standing_rotation(rotation_rad: float) -> bool:
	var tilt := absf(rad_to_deg(wrapf(rotation_rad, -PI, PI)))
	return tilt < STANDING_MAX_DEG


func apply_type(id: String, tex: Texture2D) -> void:
	type_id = id
	if tex == null:
		return
	if has_node("Skin"):
		$Skin.visible = true
		$Skin.texture = tex
	if has_node("AnimatedSprite2D"):
		$AnimatedSprite2D.visible = false
