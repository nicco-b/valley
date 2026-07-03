shader_type spatial;
render_mode specular_disabled;
// Painterly character surface: takes a flat base color (per glTF material,
// set from the model's albedo) and adds gouache depth the .glb can't carry
// — a soft value-noise wash, fine paper grain, and darkened edges. Stays
// matte and lit by the world's own sun/ambient so characters sit in the
// same light as everything else (no "pasted-on" 3D look).

uniform vec4 base_color : source_color = vec4(0.9, 0.85, 0.57, 1.0);
uniform float mottle_strength = 0.16;   // large-scale wash depth
uniform float mottle_scale = 7.0;
uniform float grain_strength = 0.05;    // fine paper tooth
uniform float grain_scale = 55.0;
uniform float edge_darken = 0.34;       // gouache rim
uniform vec3 edge_tint : source_color = vec3(0.05, 0.02, 0.04);

varying vec3 lpos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

void vertex() {
	lpos = VERTEX;  // model-local (post-skin) — stable enough for a subtle wash
}

void fragment() {
	vec3 col = base_color.rgb;

	// Soft-light wash: two octaves of value noise around the base value.
	float m = vnoise(lpos * mottle_scale) * 0.7
			+ vnoise(lpos * mottle_scale * 2.3) * 0.3;
	col *= 1.0 + (m - 0.5) * mottle_strength * 2.0;

	// Paper grain.
	float g = vnoise(lpos * grain_scale);
	col *= 1.0 + (g - 0.5) * grain_strength;

	// Gouache edge-darkening (view-facing ratio).
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.5);
	col = mix(col, edge_tint, rim * edge_darken);

	ALBEDO = col;
	ROUGHNESS = 1.0;
}
