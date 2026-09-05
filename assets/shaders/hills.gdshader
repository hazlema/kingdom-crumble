// Flat-vector rolling hills: a silhouette drawn from two summed sine
// waves, filled with a single flat color. Layer several with different
// colors, phases, and parallax speeds for the whole skyline.
// cycles are whole numbers so the shape tiles seamlessly when the
// ParallaxLayer mirrors at the rect width.
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

void fragment() {
	float y = UV.y * rect_h_px;
	float surf = base_frac * rect_h_px
		+ amp1_px * sin(TAU * UV.x * cycles1 + phase1)
		+ amp2_px * sin(TAU * UV.x * cycles2 + phase2);
	COLOR = y > surf ? fill : vec4(0.0);
}
