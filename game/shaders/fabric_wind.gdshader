shader_type spatial;
render_mode cull_disabled, specular_disabled;
// World fabric in the one wind (PLAN_FABRIC F1, the Elements -> the Loom).
// Vertex-displaced cloth driven by the global wind truth — banners, tent
// walls, ground sheets, nets. Stateless in TIME + wind, exactly the
// flora_sway pattern: fabric never invents wind, it only echoes Weather.
//
// Pin weights are PAINTED into vertex color alpha (gen_meshes.py bakes
// them): a=1 rigid (pole, stakes, hoist edge), a->0 free cloth, so one
// shader serves flags, awnings, tent walls. freedom = 1 - COLOR.a is also
// the normalized distance from the pin, which makes `hang` meters real.
//
// Motion is a children's-book wind, not a cloth sim (Art Bible Law 5):
// a lean that eases hard at the top (storm is a different painting, not a
// louder one) plus TWO sine octaves max. `flap_posterize` quantizes the
// flap phase into N held poses per wave — the posterized-foam trick
// applied to motion; 0 = smooth. Tune it by eye at the fabric probe.

global uniform float wind_strength; // Weather publishes this (0..1)
global uniform vec2 wind_dir; // Weather: FROM->TO on xz; cloth streams TOWARD it

uniform float hang = 1.0; // meters of cloth at freedom 1 (card: wind_hang)
// Held poses per wave cycle; 0 = smooth sine. 4 shipped from the F1 probe
// A/B: the quantized phase also chunks the FOLD along the cloth, so the
// crease reads as a painted kink instead of a CG sine. Retune by eye.
uniform float flap_posterize = 4.0;
// The gouache treatment, same knobs as character_paint: matte paint,
// value-noise wash, paper grain, edge-darkening. Base color comes from
// the placeholder's painted vertex colors (or real art's, later).
uniform float mottle_strength = 0.16;
uniform float mottle_scale = 7.0;
uniform float grain_strength = 0.05;
uniform float grain_scale = 55.0;
uniform float edge_darken = 0.34;
uniform vec3 edge_tint : source_color = vec3(0.05, 0.02, 0.04);

varying vec3 lpos; // pre-displacement local pos: the paint must not swim

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
	lpos = VERTEX;
	float freedom = 1.0 - COLOR.a; // painted pin weight: a=1 stays put
	if (freedom > 0.003) {
		float w = clamp(wind_strength, 0.0, 1.0);
		vec3 wdir = normalize(vec3(wind_dir.x, 0.0, wind_dir.y));
		vec3 side = vec3(-wdir.z, 0.0, wdir.x);
		// Per-instance phase from world position (the flora trick), so a
		// camp of banners gusts together without ever syncing exactly.
		float iphase = MODEL_MATRIX[3].x * 0.71 + MODEL_MATRIX[3].z * 1.33;
		// Flap dies gracefully with distance; the LEAN survives — a far
		// banner still points with the wind (it's information: you can
		// read the weather across the valley), it just stops animating.
		float fade = 1.0 - smoothstep(120.0, 200.0,
				distance(MODEL_MATRIX[3].xyz, INV_VIEW_MATRIX[3].xyz));
		// The lean: hung cloth at distance d from its pin swings through
		// angle th, an arc — out along the wind, up as it streams. w*w
		// keeps calm barely breathing and lets a gale slam the top end.
		float th = min(w * w * 1.5, 1.35);
		float d = freedom * hang;
		vec3 disp = wdir * sin(th) * d + vec3(0.0, 1.0, 0.0) * (1.0 - cos(th)) * d;
		// Two sine octaves, the wave traveling pin -> free edge (freedom
		// is the along-cloth coordinate). Posterize holds the phase in
		// N poses per cycle: motion in brush strokes, not interpolation.
		float ph = TIME * (1.2 + 3.4 * w) + iphase + freedom * 3.0;
		if (flap_posterize > 0.5) {
			float pose = (2.0 * PI) / flap_posterize;
			ph = floor(ph / pose) * pose;
		}
		float flap = sin(ph) + 0.4 * sin(ph * 2.7 + iphase * 1.7);
		float amp = hang * freedom * (0.015 + 0.24 * w * w) * fade;
		disp += (vec3(0.0, 1.0, 0.0) + side * 0.6) * flap * amp;
		// World-space wind back into model space (props carry yaw and a
		// uniform scale; the meshes are a few hundred verts — inverse()
		// here costs nothing and reads honestly).
		VERTEX += (inverse(MODEL_MATRIX) * vec4(disp, 0.0)).xyz;
	}
}

void fragment() {
	vec3 col = COLOR.rgb; // the placeholder's paint lives in vertex color

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
