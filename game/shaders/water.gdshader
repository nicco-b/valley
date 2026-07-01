shader_type spatial;
render_mode specular_disabled;
// Painterly pool: two-tone drifting stripes, after the pink pool in the
// style reference. No transparency, no reflections — paint, not physics.

uniform vec3 color_a : source_color = vec3(0.93, 0.55, 0.60);
uniform vec3 color_b : source_color = vec3(0.99, 0.76, 0.77);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float band = sin(wpos.x * 0.75
			+ sin(wpos.z * 0.3 + TIME * 0.35) * 1.6
			+ TIME * 0.2);
	ALBEDO = mix(color_a, color_b, smoothstep(-0.25, 0.25, band));
	ROUGHNESS = 0.3;
}
