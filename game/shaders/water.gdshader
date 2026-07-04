shader_type spatial;
render_mode cull_disabled;
// Painterly water that reads as WATER, tinted the pool's pink: the bed
// shows through and fades out with depth, ripples drift with the
// current, grazing angles catch the sky, low roughness gives real sun
// glints. The old identity survives as tint (color_a deep / color_b
// shallow) and the wading trace still stirs and brightens the surface.

uniform vec3 color_a : source_color = vec3(0.93, 0.55, 0.60); // deep tint
uniform vec3 color_b : source_color = vec3(0.99, 0.76, 0.77); // shallow tint
// Downstream drift, world XZ. Zero for still pools; rivers set their
// flow so ripples carry along the current.
uniform vec2 flow = vec2(0.0);
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
global uniform sampler2D trace_map;
global uniform vec2 trace_center;
global uniform float trace_size;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Three drifting sine sheets: paint, not physics.
float ripple(vec2 p, float t) {
	return sin(p.x * 1.7 + t * 1.1) * 0.5
			+ sin((p.x + p.y) * 0.9 - t * 0.7) * 0.3
			+ sin(p.y * 2.3 + t * 1.7) * 0.2;
}

void fragment() {
	// Water column under this pixel: opaque scene depth minus ours.
	float d_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 vpos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d_raw, 1.0);
	float scene_dist = -(vpos.z / vpos.w);
	float water_depth = max(scene_dist + VERTEX.z, 0.0);

	// Wading disturbs the ripples and brightens the water.
	float t = 0.0;
	vec2 trace_uv = (wpos.xz - trace_center) / trace_size + 0.5;
	if (all(greaterThan(trace_uv, vec2(0.0))) && all(lessThan(trace_uv, vec2(1.0)))) {
		t = texture(trace_map, trace_uv).r;
	}

	// Ripples drift downstream; a perturbed normal catches the sun.
	vec2 fp = wpos.xz - flow * TIME * 1.5;
	float wiggle = t * sin(TIME * 6.0) * 1.5;
	float r0 = ripple(fp * 0.8, TIME) + wiggle;
	float e = 0.35;
	float rx = ripple((fp + vec2(e, 0.0)) * 0.8, TIME) + wiggle - r0;
	float rz = ripple((fp + vec2(0.0, e)) * 0.8, TIME) + wiggle - r0;
	vec3 n_ws = normalize(vec3(-rx * (0.35 + t * 0.5), 1.0, -rz * (0.35 + t * 0.5)));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_ws, 0.0)).xyz);

	// Deep runs toward the deep pink, the shallows lighten, the last
	// hand-width to shore goes bright — a painted shoreline, not foam.
	float shallow = exp(-water_depth * 1.3);
	vec3 col = mix(color_a * 0.82, color_b, shallow);
	// The old drifting two-tone stripes, kept faint: the pool's identity.
	float band = sin(fp.x * 0.75 + sin(fp.y * 0.3 + TIME * 0.35) * 1.6 + TIME * 0.2);
	col = mix(col, color_b, smoothstep(-0.25, 0.25, band) * 0.14);
	col = mix(col, color_b * 1.06, smoothstep(0.35, 0.0, water_depth) * 0.55);
	// Grazing angles catch the sky's tint.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, color_b * 1.05, fresnel * 0.5);
	col = mix(col, color_b, t * 0.4);

	ALBEDO = col;
	ALPHA = clamp(0.38 + 0.5 * (1.0 - shallow) + fresnel * 0.22 + t * 0.2, 0.0, 0.92);
	ROUGHNESS = 0.12;
	SPECULAR = 0.5;
}
