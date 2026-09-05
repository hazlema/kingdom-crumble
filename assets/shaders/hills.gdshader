// Flat-vector rolling hills: a silhouette drawn from two summed sine
// waves, filled with a single flat color. Layer several with different
// colors, phases, and parallax speeds for the whole skyline.
// cycles are whole numbers so the shape tiles seamlessly when the
// ParallaxLayer mirrors at the rect width.
//
// Spice (owner ask): painterly tonal mottle + a sunlit rim under the
// silhouette edge. Noise cells wrap at rect_w_px so texture tiles too.
shader_type canvas_item;

uniform vec4 fill: source_color = vec4(0.31, 0.66, 0.37, 1.0);
uniform float base_frac = 0.35;   // hilltop midline, fraction of rect height
uniform float amp1_px = 70.0;
uniform float cycles1 = 3.0;
uniform float phase1 = 0.0;
uniform float amp2_px = 24.0;
uniform float cycles2 = 7.0;
uniform float phase2 = 1.7;
uniform float rect_h_px = 900.0;
uniform float rect_w_px = 4096.0;   // must match the mirror width
uniform float mottle = 0.11;        // tonal wobble, 0 = the old flat look
uniform float rim_px = 30.0;        // sunlit band height under the edge
uniform float rim_boost = 0.13;     // how much the band brightens

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Value noise whose cells wrap horizontally every `period` cells, so
// the mottle repeats exactly with the parallax mirror. Vertical never
// wraps (hills don't tile vertically).
float vnoise(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(vec2(mod(i.x, period), i.y));
	float b = hash2(vec2(mod(i.x + 1.0, period), i.y));
	float c = hash2(vec2(mod(i.x, period), i.y + 1.0));
	float d = hash2(vec2(mod(i.x + 1.0, period), i.y + 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float y = UV.y * rect_h_px;
	float surf = base_frac * rect_h_px
		+ amp1_px * sin(TAU * UV.x * cycles1 + phase1)
		+ amp2_px * sin(TAU * UV.x * cycles2 + phase2);
	if (y > surf) {
		vec2 px = vec2(UV.x * rect_w_px, y);
		// Two octaves: broad patches + finer grain. 256 and 64 both
		// divide 4096, so both wrap clean at the mirror seam.
		float n = vnoise(px / 256.0, rect_w_px / 256.0)
			+ 0.5 * vnoise(px / 64.0, rect_w_px / 64.0);
		n /= 1.5;
		// Painter's mottle: bright patches drift warm (sun on grass),
		// dark patches drift cool -- hue does what brightness can't.
		float d = (n - 0.5) * 2.0 * mottle;
		vec3 col = fill.rgb * (vec3(1.0) + d * vec3(1.35, 1.0, 0.45));
		float rim = 1.0 - smoothstep(0.0, rim_px, y - surf);
		col *= 1.0 + rim_boost * rim;
		COLOR = vec4(col, fill.a);
	} else {
		COLOR = vec4(0.0);
	}
}
