class_name Wormhole
extends Area2D

# Paired portal (spec 2026-09-06-wormholes-design.md): a Stone entering
# teleports to `partner` with velocity untouched. Pairing = same prop_id
# placed exactly twice; odd counts stay inert (partner == null).
# Arrival immunity: a teleported-in stone is ignored by this portal
# until it fully leaves once — no timers, framerate-proof.

const SPIN_RAD_PER_SEC := 0.6

var partner: Wormhole = null
var _arrivals := {}  # body -> true while it must exit before re-trigger
var _sprite: Sprite2D = null


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
	(body as Node2D).global_position = partner.global_position
	body.reset_physics_interpolation()


func expect_arrival(body: Node) -> void:
	_arrivals[body] = true


func _on_body_exited(body: Node) -> void:
	_arrivals.erase(body)


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
