class_name Auras
extends RefCounted

# Ambient cosmetic particles on any piece — crate or prop.
# IDs are curated and baked here; no scripting from content.
# Each id maps to a configuration Dictionary consumed by attach().
# The configurations are intentionally lightweight (CPUParticles2D, amount ≤ 12)
# so a tower of aura-bearing crates does not tank perf.

const KNOWN: Dictionary = {
	"embers": {
		"color": Color(1.0, 0.45, 0.05, 0.6),
		"color_ramp_end": Color(1.0, 0.1, 0.0, 0.0),
		"spread": 25.0,
		"gravity": Vector2(0.0, -30.0),
		"initial_velocity_min": 15.0,
		"initial_velocity_max": 35.0,
		"scale_amount": 2.0,
		"lifetime": 5,
		"amount": 8,
	},
	"mist": {
		"color": Color(0.85, 0.92, 1.0, 0.55),
		"color_ramp_end": Color(0.85, 0.92, 1.0, 0.0),
		"spread": 40.0,
		"gravity": Vector2(0.0, -8.0),
		"initial_velocity_min": 4.0,
		"initial_velocity_max": 12.0,
		"scale_amount": 3.5,
		"lifetime": 3.0,
		"amount": 10,
	},
	"smog": {
		"color": Color(0.18, 0.2, 0.15, 0.6),
		"color_ramp_end": Color(0.18, 0.2, 0.15, 0.0),
		"spread": 20.0,
		"gravity": Vector2(0.0, -6.0),
		"initial_velocity_min": 26.0,
		"initial_velocity_max": 46.0,
		"damping": 8.0,
		"scale_amount": 5.0,
		"lifetime": 4.5,
		"amount": 16,
	},
	"sparkle": {
		"color": Color(1.0, 0.95, 0.4, 0.6),
		"color_ramp_end": Color(1.0, 0.95, 0.4, 0.0),
		"spread": 50.0,
		"gravity": Vector2(0.0, 10.0),
		"initial_velocity_min": 20.0,
		"initial_velocity_max": 50.0,
		"scale_amount": 1.5,
		"lifetime": 1.2,
		"amount": 8,
	},
}


const _HEX_CHARS := "0123456789abcdefABCDEF"

# Shared soft-circle puff texture (radial white -> transparent), built once.
# CPUParticles2D without a texture draws 1px quads — the original auras
# were 4px specks, invisible in play (owner field report: "doesn't work").
static var _puff_tex: Texture2D = null


static func _puff() -> Texture2D:
	if _puff_tex == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(0.5, 0.0)
		gt.width = 32
		gt.height = 32
		_puff_tex = gt
	return _puff_tex


## True for a strict "#RRGGBB" string — the only color form sidecars may use.
## Per-character check: is_valid_hex_number accepts a leading minus sign,
## which would reach Color.html() as an engine error (re-review catch).
static func is_valid_color(s: String) -> bool:
	if not s.begins_with("#") or s.length() != 7:
		return false
	for i in range(1, 7):
		if not _HEX_CHARS.contains(s[i]):
			return false
	return true


## Attach a configured CPUParticles2D child to host.
## Empty id → silent no-op (every plain piece calls this).
## Unknown id → push_warning + skip (no child added).
## Known id → one CPUParticles2D with emitting = true, local_coords = false.
## color_override ("#RRGGBB") retints the verb; alpha ALWAYS comes from the
## verb table entry (through the 0.6 cap) — content can recolor, never opacify.
static func attach(host: Node2D, id: String, color_override: String = "") -> void:
	if id == "":
		return
	if id not in KNOWN:
		push_warning("Auras: unknown aura id '%s' — skipping" % id)
		return
	var cfg: Dictionary = KNOWN[id]
	var p := CPUParticles2D.new()
	p.texture = _puff()
	p.emitting = true
	# Global-space simulation: trails linger when the piece tumbles.
	# (CPUParticles2D has no visibility_rect — that dial is GPU-only.)
	p.local_coords = false
	# Spread emission across the piece top, not a point jet
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(20, 6)
	# Plume anatomy: puffs launch UPWARD (the engine default direction is
	# (1,0) — unset, the smoke oozed sideways and pooled into one fuzzy
	# dot), decelerate via damping so they HANG, and grow as they rise.
	p.direction = Vector2(0, -1)
	p.damping_min = float(cfg.get("damping", 6.0))
	p.damping_max = p.damping_min * 1.5
	p.lifetime_randomness = 0.4
	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.35))
	growth.add_point(Vector2(0.6, 1.0))
	growth.add_point(Vector2(1.0, 1.2))
	p.scale_amount_curve = growth
	p.amount = int(cfg.get("amount", 8))
	p.lifetime = float(cfg.get("lifetime", 2.0))
	p.spread = float(cfg.get("spread", 30.0))
	p.gravity = cfg.get("gravity", Vector2(0.0, -20.0)) as Vector2
	p.initial_velocity_min = float(cfg.get("initial_velocity_min", 10.0))
	p.initial_velocity_max = float(cfg.get("initial_velocity_max", 30.0))
	# scale is relative to the 32px puff texture now (1.0 = 32px puff)
	var scale_val := float(cfg.get("scale_amount", 2.0)) * 0.25
	p.scale_amount_min = scale_val
	p.scale_amount_max = scale_val * 1.5
	# Color: start color directly, ramp end via gradient
	var start_color: Color = cfg.get("color", Color.WHITE) as Color
	start_color.a = minf(start_color.a, 0.75)  # cosmetic cap — auras never obscure play
	var end_color: Color = cfg.get("color_ramp_end", Color(start_color.r, start_color.g, start_color.b, 0.0)) as Color
	if color_override != "":
		if is_valid_color(color_override):
			var tint := Color.html(color_override)
			start_color = Color(tint.r, tint.g, tint.b, start_color.a)
			end_color = Color(tint.r, tint.g, tint.b, end_color.a)
		else:
			push_warning("Auras: bad aura_color '%s' — using the verb default" % color_override)
	# The ramp OWNS the tint; base color stays white. Setting both squared
	# the color (final = color * ramp) — every dark tint collapsed to the
	# same near-black sludge (owner field bug: three colors, one result).
	p.color = Color.WHITE
	var grad := Gradient.new()
	grad.set_color(0, start_color)
	grad.set_color(1, end_color)
	p.color_ramp = grad
	# In FRONT of the art (z above siblings): behind-the-art at z=-1 hid the
	# aura under neighboring canvas items in play; the 0.6 alpha cap keeps
	# the piece face readable through the smoke.
	p.z_index = 1
	host.add_child(p)
