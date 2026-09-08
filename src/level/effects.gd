class_name Effects
extends RefCounted

# Curated effect library for level triggers (spec §8). Effects are data
# ids, never code — the whole reason shared levels are safe.

const SFX_DIR := "res://assets/sfx"

# Overlay-name charset shared with LevelJson (single direction:
# level_json calls Effects, never the reverse — no circular statics).
const DISPLAY_CAP := 80  # display: payload cap — one toast line
const DISPLAY_SECS := [3, 10, 20, 30]  # curated durations (dialog dropdown)


## The message part of a display: action (duration prefix stripped).
static func display_message(id: String) -> String:
	var payload := id.trim_prefix("display:")
	var head := payload.split(":", true, 1)
	if head.size() == 2 and int(head[0]) in DISPLAY_SECS and head[0] == str(int(head[0])):
		return head[1]
	return payload


## The duration of a display: action in seconds (default 3.0).
static func display_secs(id: String) -> float:
	var payload := id.trim_prefix("display:")
	var head := payload.split(":", true, 1)
	if head.size() == 2 and int(head[0]) in DISPLAY_SECS and head[0] == str(int(head[0])):
		return float(int(head[0]))
	return 3.0

static var _name_rx := RegEx.create_from_string("^[a-z0-9_-]{1,16}$")


static func valid_name(n: String) -> bool:
	return _name_rx.search(n) != null


static func is_known(id: String) -> bool:
	if id == "confetti":
		return true
	if id.begins_with("sound:"):
		var stem := id.trim_prefix("sound:")
		if stem.contains("/") or stem.contains("\\") or stem.contains(".."):
			return false
		return true
	# Linked-trigger actions (spec 2026-09-05): scenery show/hide by
	# overlay name. Whether the name EXISTS is runtime's warn-skip;
	# here we only vouch for the shape.
	if id.begins_with("show:") or id.begins_with("hide:"):
		return valid_name(id.split(":", true, 1)[1])
	# display:<message> or display:<secs>:<message> — inert text on the
	# HUD toast (tutorial beats). Durations are CURATED (3/10/20/30);
	# any other leading token is just message text. Length policed only.
	# smoke / smoke:#RRGGBB — the hit crate starts smoldering (ignites a
	# smog aura on the SOURCE crate; color optional, strict hex).
	if id == "smoke":
		return true
	if id.begins_with("smoke:"):
		return Auras.is_valid_color(id.trim_prefix("smoke:"))
	if id.begins_with("display:"):
		var msg := display_message(id)
		return msg.length() >= 1 and msg.length() <= DISPLAY_CAP
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
