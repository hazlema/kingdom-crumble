class_name Effects
extends RefCounted

# Curated effect library for level triggers (spec §8). Effects are data
# ids, never code — the whole reason shared levels are safe.

const SFX_DIR := "res://assets/sfx"


static func is_known(id: String) -> bool:
	if id == "confetti":
		return true
	if id.begins_with("sound:"):
		var stem := id.trim_prefix("sound:")
		if stem.contains("/") or stem.contains("\\") or stem.contains(".."):
			return false
		return true
	return false


static func fire_all(ids: Array, host: Node2D, at: Vector2) -> int:
	var fired := 0
	for id in ids:
		var s := String(id)
		if s == "confetti":
			_confetti(host, at)
			fired += 1
		elif s.begins_with("sound:"):
			if _sound(host, s.trim_prefix("sound:")):
				fired += 1
		else:
			push_warning("Unknown effect id: %s" % s)
	return fired


static func _confetti(host: Node2D, at: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.emitting = true
	p.one_shot = true
	p.amount = 120
	p.lifetime = 1.6
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector2(0, 700)
	p.initial_velocity_min = 300.0
	p.initial_velocity_max = 700.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	p.color_ramp = _confetti_colors()
	host.add_child(p)
	host.get_tree().create_timer(3.0).timeout.connect(p.queue_free)


static func _confetti_colors() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.83, 0.29))
	g.add_point(0.33, Color(0.91, 0.28, 0.25))
	g.add_point(0.66, Color(0.31, 0.66, 0.9))
	g.set_color(1, Color(0.55, 0.79, 0.47))
	return g


static func _sound(host: Node2D, stem: String) -> bool:
	if stem.contains("/") or stem.contains("\\") or stem.contains(".."):
		push_warning("Unsafe sound name rejected: %s" % stem)
		return false
	var path := "%s/%s.ogg" % [SFX_DIR, stem]
	if not ResourceLoader.exists(path):
		push_warning("No such sound effect: %s" % stem)
		return false
	var player := AudioStreamPlayer.new()
	player.bus = "Sfx" if AudioServer.get_bus_index("Sfx") != -1 else "Master"
	player.stream = load(path)
	host.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return true
