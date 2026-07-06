shader_type spatial;
render_mode cull_disabled;
// The tier-2 dynamics field made visible: a grid patch near the player
// whose vertices ride the GPU water field (base terrain + live depth).
// Rain gathers into rivulets and puddles that drain when the storm
// passes. Same pink water language as the pond/river shader, shaded by
// the field itself: depth tints deeper, fast runs brighten.

uniform vec3 color_a : source_color = vec3(0.93, 0.55, 0.60); // deep tint (golden hour)
uniform vec3 color_b : source_color = vec3(0.99, 0.76, 0.77); // shallow tint (golden hour)
// Same hour-palettes as water.gdshader: pink is the low sun's gift;
// day runs teal, night slate (day_night.gd publishes the factors).
const vec3 DAY_A = vec3(0.20, 0.38, 0.47);
const vec3 DAY_B = vec3(0.42, 0.62, 0.66);
const vec3 NIGHT_A = vec3(0.14, 0.18, 0.28);
const vec3 NIGHT_B = vec3(0.28, 0.34, 0.46);
global uniform float water_gold;
global uniform float water_night;
uniform float patch_size = 96.0;
global uniform sampler2D water_field_map; // R depth m, G flow speed
global uniform sampler2D water_base_map; // terrain heights, meters
global uniform vec2 water_field_center;
global uniform float water_field_size;

varying vec3 wpos;
varying float w_depth;
varying float w_speed;
varying float edge_fade;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = (world.xz - water_field_center) / water_field_size + 0.5;
	vec2 field = textureLod(water_field_map, uv, 0.0).rg;
	float base = textureLod(water_base_map, uv, 0.0).r;
	w_depth = field.r;
	w_speed = field.g;
	world.y = base + w_depth + 0.015; // ride the live surface, just proud
	wpos = world;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	// Fade the patch border so the sheet never ends in a hard line.
	vec2 local = abs(VERTEX.xz) / (patch_size * 0.5);
	edge_fade = 1.0 - smoothstep(0.8, 1.0, max(local.x, local.y));
}

float ripple(vec2 p, float t) {
	return sin(p.x * 2.1 + t * 1.3) * 0.5
			+ sin((p.x + p.y) * 1.1 - t * 0.8) * 0.3
			+ sin(p.y * 2.7 + t * 1.9) * 0.2;
}

void fragment() {
	// Nothing to draw where the field holds less than a film of water.
	if (w_depth < 0.012) {
		discard;
	}
	float r0 = ripple(wpos.xz, TIME);
	float e = 0.3;
	float rx = ripple(wpos.xz + vec2(e, 0.0), TIME) - r0;
	float rz = ripple(wpos.xz + vec2(0.0, e), TIME) - r0;
	vec3 n_ws = normalize(vec3(-rx * 0.3, 1.0, -rz * 0.3));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_ws, 0.0)).xyz);
	vec3 pal_a = mix(mix(DAY_A, NIGHT_A, water_night), color_a, water_gold);
	vec3 pal_b = mix(mix(DAY_B, NIGHT_B, water_night), color_b, water_gold);
	float deep = clamp(w_depth * 4.0, 0.0, 1.0);
	vec3 col = mix(pal_b, pal_a, deep * 0.8);
	// A fast run reads bright — the painted stand-in for white water.
	col = mix(col, pal_b * 1.08, clamp(w_speed * 2.5, 0.0, 0.55));
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, pal_b * 1.05, fresnel * 0.4);
	ALBEDO = col;
	ALPHA = clamp(w_depth * 14.0, 0.0, 0.85) * edge_fade;
	ROUGHNESS = 0.14;
	SPECULAR = 0.5;
}
