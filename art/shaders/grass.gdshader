// Procedural side-view grass: a fringe of swaying blades along the top
// edge, mottled gradient body below. Fully generated — no texture.
shader_type canvas_item;

uniform vec3 blade_color: source_color = vec3(0.36, 0.55, 0.25);
uniform vec3 tip_color: source_color = vec3(0.55, 0.72, 0.33);
uniform vec3 body_top_color: source_color = vec3(0.42, 0.56, 0.30);
uniform vec3 body_bottom_color: source_color = vec3(0.24, 0.36, 0.18);
uniform float rect_width_px = 6000.0;
uniform float rect_height_px = 600.0;
uniform float blade_height_px = 26.0;
uniform float blade_width_px = 6.0;
uniform float sway_px = 5.0;
uniform float sway_speed = 1.4;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i.x + i.y * 57.0);
	float b = hash(i.x + 1.0 + i.y * 57.0);
	float c = hash(i.x + (i.y + 1.0) * 57.0);
	float d = hash(i.x + 1.0 + (i.y + 1.0) * 57.0);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float x_px = UV.x * rect_width_px;
	float y_px = UV.y * rect_height_px; // 0 at the grass line (rect top)

	if (y_px < blade_height_px) {
		// Blade fringe. Sway grows toward the tips; each column is a blade.
		float depth = y_px / blade_height_px;            // 0 tip .. 1 root
		float gust = noise2(vec2(x_px * 0.002, TIME * 0.25)) - 0.5;
		float sway = (sin(TIME * sway_speed + x_px * 0.045) * 0.6 + gust * 2.0)
			* sway_px * (1.0 - depth);
		float col = floor((x_px + sway) / blade_width_px);
		float h = blade_height_px * (0.35 + 0.65 * hash(col));
		float blade_top = blade_height_px - h;
		if (y_px < blade_top) {
			COLOR = vec4(0.0);
		} else {
			float t = clamp((y_px - blade_top) / max(h, 0.001), 0.0, 1.0);
			vec3 c = mix(tip_color, blade_color, t);
			c *= 0.92 + 0.16 * hash(col + 31.0); // per-blade variety
			COLOR = vec4(c, 1.0);
		}
	} else {
		// Ground body: vertical gradient with soft mottling.
		float t = clamp((y_px - blade_height_px) / (rect_height_px - blade_height_px), 0.0, 1.0);
		vec3 c = mix(body_top_color, body_bottom_color, t);
		float m = noise2(vec2(x_px * 0.012, y_px * 0.012));
		c *= 0.94 + m * 0.12;
		COLOR = vec4(c, 1.0);
	}
}
