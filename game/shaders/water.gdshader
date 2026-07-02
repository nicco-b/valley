shader_type spatial;
render_mode specular_disabled;
// Painterly pool: two-tone drifting stripes, after the pink pool in the
// style reference. No transparency, no reflections — paint, not physics.

uniform vec3 color_a : source_color = vec3(0.93, 0.55, 0.60);
uniform vec3 color_b : source_color = vec3(0.99, 0.76, 0.77);
global uniform sampler2D trace_map;
global uniform vec2 trace_center;
global uniform float trace_size;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Wading disturbs the stripes and brightens the water.
	float t = 0.0;
	vec2 trace_uv = (wpos.xz - trace_center) / trace_size + 0.5;
	if (all(greaterThan(trace_uv, vec2(0.0))) && all(lessThan(trace_uv, vec2(1.0)))) {
		t = texture(trace_map, trace_uv).r;
	}
	float band = sin(wpos.x * 0.75
			+ sin(wpos.z * 0.3 + TIME * 0.35) * 1.6
			+ TIME * 0.2
			+ t * sin(TIME * 6.0) * 2.2);
	vec3 col = mix(color_a, color_b, smoothstep(-0.25, 0.25, band));
	ALBEDO = mix(col, color_b, t * 0.45);
	ROUGHNESS = 0.3;
}
