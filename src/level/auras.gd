class_name Auras
extends RefCounted

# Ambient cosmetic particles on any piece — crate or prop.
# IDs are curated and baked here; no scripting from content.
# Each id maps to a configuration Dictionary consumed by attach().
# The configurations are intentionally lightweight (CPUParticles2D, amount ≤ 12)
# so a tower of aura-bearing crates does not tank perf.

const KNOWN: Dictionary = {
	"embers": {
		"color": Color(1.0, 0.45, 0.05, 0.85),
		"color_ramp_end": Color(1.0, 0.1, 0.0, 0.0),
		"spread": 25.0,
		"gravity": Vector2(0.0, -30.0),
		"initial_velocity_min": 15.0,
		"initial_velocity_max": 35.0,
		"scale_amount": 2.0,
		"lifetime": 1.8,
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
	"smog-green": {
		"color": Color(0.3, 0.85, 0.2, 0.65),
		"color_ramp_end": Color(0.3, 0.85, 0.2, 0.0),
		"spread": 35.0,
		"gravity": Vector2(0.0, -12.0),
		"initial_velocity_min": 6.0,
		"initial_velocity_max": 20.0,
		"scale_amount": 4.0,
		"lifetime": 2.5,
		"amount": 12,
	},
	"sparkle": {
		"color": Color(1.0, 0.95, 0.4, 1.0),
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


## Attach a configured CPUParticles2D child to host.
## Empty id → silent no-op (every plain piece calls this).
## Unknown id → push_warning + skip (no child added).
## Known id → one CPUParticles2D with emitting = true, local_coords = false.
static func attach(host: Node2D, id: String) -> void:
	if id == "":
		return
	if id not in KNOWN:
		push_warning("Auras: unknown aura id '%s' — skipping" % id)
		return
	var cfg: Dictionary = KNOWN[id]
	var p := CPUParticles2D.new()
	p.emitting = true
	p.local_coords = false
	p.amount = int(cfg.get("amount", 8))
	p.lifetime = float(cfg.get("lifetime", 2.0))
	p.spread = float(cfg.get("spread", 30.0))
	p.gravity = cfg.get("gravity", Vector2(0.0, -20.0)) as Vector2
	p.initial_velocity_min = float(cfg.get("initial_velocity_min", 10.0))
	p.initial_velocity_max = float(cfg.get("initial_velocity_max", 30.0))
	var scale_val := float(cfg.get("scale_amount", 2.0))
	p.scale_amount_min = scale_val
	p.scale_amount_max = scale_val * 1.5
	# Color: start color directly, ramp end via gradient
	var start_color: Color = cfg.get("color", Color.WHITE) as Color
	var end_color: Color = cfg.get("color_ramp_end", Color(start_color.r, start_color.g, start_color.b, 0.0)) as Color
	p.color = start_color
	var grad := Gradient.new()
	grad.set_color(0, start_color)
	grad.set_color(1, end_color)
	p.color_ramp = grad
	# z-index: behind the sprite (sprite is added after, so this is already behind
	# in child order — also set z_index to ensure visual stacking)
	p.z_index = -1
	host.add_child(p)
