class_name Wormhole
extends Area2D

# Paired portal (spec 2026-09-06-wormholes-design.md): a Stone entering
# teleports to `partner` with velocity untouched. Pairing = same prop_id
# placed exactly twice; odd counts stay inert (partner == null).
# Arrival immunity: a teleported-in stone is ignored by this portal
# until it fully leaves once — no timers, framerate-proof.
#
# Implementation note: body_entered fires inside PhysicsServer2D::flush_queries(),
# after the physics server has run body integration for this frame. Any position
# change via Node2D.global_position does NOT reliably update the physics server
# for the current step. The fix: call PhysicsServer2D.body_set_state() directly
# on the RigidBody's RID, which atomically sets the body transform in the server,
# combined with the deferred node sync via global_position for rendering.

const SPIN_RAD_PER_SEC := 0.6
const FX_STREAKS := 12
const FX_LIFETIME := 0.35
const PULSE_TIME := 0.2

var partner: Wormhole = null
var _arrivals := {}  # body -> true while it must exit before re-trigger
var _sprite: Sprite2D = null
var _tint_cache := Color.WHITE
var _tint_ready := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	for c in get_children():
		if c is Sprite2D:
			_sprite = c
			break


func _process(delta: float) -> void:
	if _sprite != null:
		_sprite.rotation += SPIN_RAD_PER_SEC * delta


func _on_body_entered(body: Node) -> void:
	if partner == null or not body is Stone:
		return
	if _arrivals.has(body):
		return
	partner.expect_arrival(body)
	_teleport.call_deferred(body)


# Takes any RigidBody2D on purpose — the future crate-transit flag
# reuses this path unchanged (spec: crate door open).
func _teleport(body: Node) -> void:
	if not is_instance_valid(body) or partner == null or not is_instance_valid(partner):
		return
	# PhysicsServer2D.body_set_state is used directly here rather than
	# Node2D.global_position = ... because body_entered (and its call_deferred
	# chain) fires after the physics integration step has completed. The Node2D
	# property setter routes through body_set_state internally, but the physics
	# server may discard the new transform when it writes the just-integrated
	# position back to the node. Calling body_set_state directly on the RID
	# updates the server's canonical body record, which is then picked up in
	# the next integration step.
	var rb := body as RigidBody2D
	if rb == null:
		return
	PhysicsServer2D.body_set_state(
		rb.get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM,
		Transform2D(rb.global_rotation, partner.global_position)
	)
	(body as Node2D).global_position = partner.global_position
	body.reset_physics_interpolation()
	partner.play_arrival_fx(rb.linear_velocity)


func expect_arrival(body: Node) -> void:
	_arrivals[body] = true


func _on_body_exited(body: Node) -> void:
	_arrivals.erase(body)


# Arrival juice: the stone keeps its velocity (spec), so the whoosh
# sells the violence of arrival — streaks biased along the exit
# vector + a quick "gulp" pulse on the portal sprite.
func play_arrival_fx(exit_velocity: Vector2) -> void:
	var burst := CPUParticles2D.new()
	burst.one_shot = true
	burst.emitting = true
	burst.amount = FX_STREAKS
	burst.lifetime = FX_LIFETIME
	burst.explosiveness = 1.0
	burst.direction = exit_velocity.normalized() if exit_velocity.length() > 1.0 else Vector2.UP
	burst.spread = 55.0
	burst.initial_velocity_min = 180.0
	burst.initial_velocity_max = 320.0
	burst.gravity = Vector2.ZERO
	burst.scale_amount_min = 2.0
	burst.scale_amount_max = 4.0
	burst.color = _fx_tint()
	burst.finished.connect(burst.queue_free)
	add_child(burst)
	if _sprite != null:
		var tw := create_tween()
		tw.tween_property(_sprite, "scale", Vector2(1.3, 1.3), PULSE_TIME * 0.5)
		tw.tween_property(_sprite, "scale", Vector2.ONE, PULSE_TIME * 0.5)


# Average the portal art once so any color portal (future packs) gets
# a matching whoosh with zero config.
func _fx_tint() -> Color:
	if _tint_ready:
		return _tint_cache
	_tint_ready = true
	if _sprite != null and _sprite.texture != null:
		var img := _sprite.texture.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			img.resize(8, 8)
			var sum := Vector3.ZERO
			var n := 0
			for y in 8:
				for x in 8:
					var c := img.get_pixel(x, y)
					if c.a > 0.5:
						sum += Vector3(c.r, c.g, c.b)
						n += 1
			if n > 0:
				_tint_cache = Color(sum.x / n, sum.y / n, sum.z / n)
	return _tint_cache


# Wire portals after spawn: ids placed exactly twice link; anything
# else warns and stays inert — the level always plays (inert doctrine).
static func link_pairs(nodes: Array) -> void:
	var by_id := {}
	for n in nodes:
		if n is Wormhole:
			var pid: String = n.get_meta("prop_id", "")
			if not by_id.has(pid):
				by_id[pid] = []
			by_id[pid].append(n)
	for pid in by_id:
		var group: Array = by_id[pid]
		if group.size() == 2:
			group[0].partner = group[1]
			group[1].partner = group[0]
		else:
			push_warning("wormhole '%s': needs exactly 2, found %d — inert" % [pid, group.size()])
