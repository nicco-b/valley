shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
// Rain curtain (the Elements phase C): a tall translucent wall hung
// under a rain band's leading edge — the approaching storm has a
// BODY you can see across the sea. Painterly: soft vertical streaks
// scrolling down, posterized alpha, no photoreal sheeting.
// PLACEHOLDER look: her painted rain texture can replace the
// procedural streaks in the same slot.

uniform float intensity : hint_range(0.0, 1.0) = 0.6;
uniform vec3 tint : source_color = vec3(0.52, 0.5, 0.55);

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	// Vertical streak bands: a few coarse columns, each falling at its
	// own speed, posterized to read gouache instead of mist.
	float col_id = floor(v_uv.x * 90.0);
	float speed = 0.25 + 0.35 * hash(col_id);
	float phase = fract(v_uv.y * 3.0 + TIME * speed + hash(col_id * 1.7));
	float streak = step(0.35, phase) * (0.55 + 0.45 * hash(col_id * 2.3));
	// Fade: top into the cloud, bottom to the ground, ends of the wall.
	float vert = smoothstep(0.0, 0.25, v_uv.y) * (1.0 - smoothstep(0.75, 1.0, v_uv.y));
	float ends = smoothstep(0.0, 0.08, v_uv.x) * (1.0 - smoothstep(0.92, 1.0, v_uv.x));
	float a = intensity * vert * ends * (0.10 + 0.16 * streak);
	ALBEDO = tint;
	ALPHA = floor(a * 6.0) / 6.0; // posterize — gouache, not vapor
}
