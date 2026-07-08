shader_type spatial;
render_mode cull_disabled;
// Painterly water that MOVES (tier 2.5): vertices ride the wave field
// (wading rings, rain pocks, wind chop), the bed shows through real
// refraction tinted toward the pool's pink with depth, foam gathers as
// painted pale bands at shorelines / wave crests / fast water, grazing
// light glints off the ripple normals. Elden Ring's recipe — moving
// surface + foam + refraction — spoken in gouache.

// The GOLDEN palette (the pool's signature pink) — worn only while the
// sun is low: day runs a quieter gouache teal, night a dark slate.
// day_night.gd publishes water_gold / water_night each frame.
uniform vec3 color_a : source_color = vec3(0.93, 0.55, 0.60); // deep tint (golden hour)
uniform vec3 color_b : source_color = vec3(0.99, 0.76, 0.77); // shallow tint (golden hour)
const vec3 DAY_A = vec3(0.20, 0.38, 0.47);
const vec3 DAY_B = vec3(0.42, 0.62, 0.66);
const vec3 NIGHT_A = vec3(0.14, 0.18, 0.28);
const vec3 NIGHT_B = vec3(0.28, 0.34, 0.46);
global uniform float water_gold;
global uniform float water_night;
// Whole-mesh drift (lakes/sea). Rivers carry a per-vertex FLOW MAP in
// UV2 (direction x local speed, baked from the drape: fast through
// rapids, slow in pools, curving with the bends) scaled by flow_scale —
// the hourly discharge, so current speed breathes with the hydrology.
uniform vec2 flow = vec2(0.0);
uniform float flow_scale = 0.0;
// Rapids: river ribbons write their local grade into COLOR.r (the
// drape's row-to-row drop) — steep runs foam like falls. Off (0.0) for
// lakes/sea, whose meshes carry no vertex color (default white would
// foam everything).
uniform float rapids_boost = 0.0;
// Ocean swell (W1, the Watershed): four Gerstner components summed in
// the vertex stage roll the SEA meshes only — swell_boost is 1 on the
// sea patch/discs, 0 (default) on lakes and rivers. SeaSwell publishes
// amplitude/wavelength/direction from the Elements' fronts (storm swell
// arrives before the storm). Physics never sees this: it is vertex
// displacement, exactly like the wave window. swell_step is the mesh's
// vertex spacing — components too short for the grid fade out instead
// of aliasing; swell_fade_radius eases the mid disc flat at its rim so
// the coarse far disc takes over without a seam.
uniform float swell_boost = 0.0;
uniform float swell_step = 3.0;
uniform float swell_fade_radius = 0.0;
global uniform float swell_amp;
global uniform vec2 swell_dir;
global uniform float swell_len;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
global uniform sampler2D wave_map; // tier-2.5 height field, meters
global uniform vec2 wave_center;
global uniform float wave_size;
global uniform sampler2D trace_map;
global uniform vec2 trace_center;
global uniform float trace_size;

varying vec3 wpos;
varying float wave_h;
varying float rapids_v;
varying vec2 flow_v;
varying float swell_crest;  // normalized crest phase, foams in storms
varying vec2 swell_grad;    // swell surface slope for the normal

// Window-edge fade so the wave field's border never shows on the mesh.
float wave_fade(vec2 uv) {
	vec2 e = abs(uv - 0.5) * 2.0;
	return 1.0 - smoothstep(0.85, 1.0, max(e.x, e.y));
}

void vertex() {
	rapids_v = COLOR.r;
	flow_v = UV2;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 wuv = (wpos.xz - wave_center) / wave_size + 0.5;
	wave_h = 0.0;
	if (all(greaterThan(wuv, vec2(0.0))) && all(lessThan(wuv, vec2(1.0)))) {
		wave_h = textureLod(wave_map, wuv, 0.0).r * wave_fade(wuv);
	}
	VERTEX.y += clamp(wave_h, -0.12, 0.12);
	wpos.y += clamp(wave_h, -0.12, 0.12);

	// The swell: big rolling trochoids, world-anchored so every sea
	// mesh agrees. Deep-water dispersion (long waves outrun short) keeps
	// the sum from ever reading as one marching pattern.
	swell_crest = 0.0;
	swell_grad = vec2(0.0);
	if (swell_boost > 0.0 && swell_amp > 0.001) {
		float fade = swell_boost;
		if (swell_fade_radius > 0.0) {
			fade *= 1.0 - smoothstep(swell_fade_radius * 0.75,
					swell_fade_radius, length(VERTEX.xz));
		}
		float rot[4] = float[](0.0, 0.35, -0.42, 0.83);
		float lsc[4] = float[](1.0, 0.62, 0.38, 0.23);
		float asc[4] = float[](0.44, 0.28, 0.17, 0.11);
		vec2 hoff = vec2(0.0);
		float voff = 0.0;
		for (int i = 0; i < 4; i++) {
			float wl = swell_len * lsc[i];
			// Grid gate: a component the mesh can't carry fades out.
			float a = swell_amp * asc[i] * fade
					* smoothstep(swell_step * 2.0, swell_step * 3.0, wl);
			if (a < 1e-4) { continue; }
			float cr = cos(rot[i]);
			float sr = sin(rot[i]);
			vec2 d = normalize(vec2(swell_dir.x * cr - swell_dir.y * sr,
					swell_dir.x * sr + swell_dir.y * cr));
			float k = TAU / wl;
			float w = sqrt(9.8 * k);
			float ph = k * dot(d, wpos.xz) - w * TIME;
			float s = sin(ph);
			float c = cos(ph);
			voff += a * s;
			hoff -= d * (3.0 * a * c);  // trochoid: crests gather, troughs stretch
			swell_grad += d * (k * a * c);
			swell_crest += s * asc[i];
		}
		VERTEX.y += voff;
		VERTEX.xz += hoff;
		wpos.y += voff;
		wpos.xz += hoff;
	}
}

float ripple(vec2 p, float t) {
	return sin(p.x * 1.7 + t * 1.1) * 0.5
			+ sin((p.x + p.y) * 0.9 - t * 0.7) * 0.3
			+ sin(p.y * 2.3 + t * 1.7) * 0.2;
}

void fragment() {
	// Water column under this pixel, from the opaque scene depth.
	float d_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 vpos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d_raw, 1.0);
	float scene_dist = -(vpos.z / vpos.w);
	float water_depth = max(scene_dist + VERTEX.z, 0.0);

	// Wading trace still stirs and brightens.
	float t = 0.0;
	vec2 trace_uv = (wpos.xz - trace_center) / trace_size + 0.5;
	if (all(greaterThan(trace_uv, vec2(0.0))) && all(lessThan(trace_uv, vec2(1.0)))) {
		t = texture(trace_map, trace_uv).r;
	}

	// Normal: procedural drift + the wave field's real gradient.
	// Per-vertex flow needs FLOW-MAP PHASING: a spatially varying
	// current under one shared clock shears the pattern into streaks,
	// so two half-offset phases advect and cross-fade — each restarts
	// before its stretch can show (the industry flow-map trick).
	vec2 f = flow + flow_v * flow_scale;
	float period = 6.0;
	float ph1 = fract(TIME / period);
	float ph2 = fract(TIME / period + 0.5);
	float pw = abs(ph1 * 2.0 - 1.0);
	vec2 fp1 = wpos.xz - f * ph1 * period * 1.5;
	vec2 fp2 = wpos.xz - f * ph2 * period * 1.5;
	float wiggle = t * sin(TIME * 6.0) * 1.5;
	float e = 0.35;
	float r0 = mix(ripple(fp1 * 0.8, TIME), ripple(fp2 * 0.8, TIME), pw) + wiggle;
	float rx = mix(ripple((fp1 + vec2(e, 0.0)) * 0.8, TIME),
			ripple((fp2 + vec2(e, 0.0)) * 0.8, TIME), pw) + wiggle - r0;
	float rz = mix(ripple((fp1 + vec2(0.0, e)) * 0.8, TIME),
			ripple((fp2 + vec2(0.0, e)) * 0.8, TIME), pw) + wiggle - r0;
	vec2 fp = fp1;  // foam/streak anchor rides the primary phase
	vec2 wuv = (wpos.xz - wave_center) / wave_size + 0.5;
	vec2 wgrad = vec2(0.0);
	if (all(greaterThan(wuv, vec2(0.02))) && all(lessThan(wuv, vec2(0.98)))) {
		float px = 1.0 / float(textureSize(wave_map, 0).x);
		float f = wave_fade(wuv);
		wgrad = vec2(
			texture(wave_map, wuv + vec2(px, 0.0)).r - texture(wave_map, wuv - vec2(px, 0.0)).r,
			texture(wave_map, wuv + vec2(0.0, px)).r - texture(wave_map, wuv - vec2(0.0, px)).r
		) * f * 7.0;
	}
	vec3 n_ws = normalize(vec3(
			-rx * (0.3 + t * 0.5) - wgrad.x - swell_grad.x * 2.8, 1.0,
			-rz * (0.3 + t * 0.5) - wgrad.y - swell_grad.y * 2.8));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_ws, 0.0)).xyz);

	// The hour picks the palette: teal day, slate night, pink low sun.
	vec3 pal_a = mix(mix(DAY_A, NIGHT_A, water_night), color_a, water_gold);
	vec3 pal_b = mix(mix(DAY_B, NIGHT_B, water_night), color_b, water_gold);

	// The bed through the surface: refract the opaque screen by the
	// normal, more with depth, and drink the light toward the deep tint.
	vec2 refr = n_ws.xz * (0.015 + 0.035 * clamp(water_depth * 0.5, 0.0, 1.0));
	vec3 through = texture(screen_tex, clamp(SCREEN_UV - refr, vec2(0.001), vec2(0.999))).rgb;
	float shallow = exp(-water_depth * mix(2.4, 1.1, water_gold));
	through *= mix(vec3(1.0), pal_a, clamp(1.0 - shallow, 0.0, 0.85) * 0.7);

	// Surface color: the deep body rising with depth and grazing angle.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float body = clamp(mix(0.32, 0.18, water_gold) + (1.0 - shallow) * 0.5 + fresnel * 0.35, 0.0, 0.9);
	vec3 surface_col = mix(pal_a * 0.9, pal_b * 1.04, 0.35 + fresnel * 0.5);
	vec3 col = mix(through, surface_col, body);

	// Foam: painted pale bands, posterized — shoreline lap, wave crests,
	// fast water streaks, stirred wading. Never photoreal spray.
	float foam = smoothstep(0.3, 0.05, water_depth) * 0.75;
	foam += smoothstep(0.035, 0.09, wave_h + length(wgrad) * 0.05) * 0.6;
	foam += smoothstep(0.8, 1.6, length(f)) * (0.5 + 0.5 * sin(fp.x * 3.1 + fp.y * 1.7)) * 0.35;
	foam += t * 0.5;
	foam += rapids_v * rapids_boost * (0.38 + 0.28 * sin(fp.x * 2.3 + fp.y * 2.9));
	// Storm rollers wear painted caps: crest phase gated by amplitude, so
	// a calm sea stays clean and heavy swell reads from the strand. Kept
	// strong enough to survive the posterize floor in deep water (the
	// shoreline term carried it in the shallows; out here it is alone).
	foam += smoothstep(0.25, 0.75, swell_crest)
			* clamp((swell_amp - 0.12) * 1.6, 0.0, 0.9)
			* (0.65 + 0.35 * sin(fp.x * 0.37 + fp.y * 0.61));
	foam = floor(clamp(foam, 0.0, 1.0) * 3.0) / 3.0;  // stepped: gouache, not mist
	vec3 foam_col = pal_b * mix(1.04, 1.12, water_gold) + vec3(0.04 * water_gold + 0.01);
	col = mix(col, foam_col, foam * 0.85);

	ALBEDO = col;
	ALPHA = 1.0;  // opaque composite; the screen read does the seeing-through
	ROUGHNESS = mix(0.1, 0.5, foam);
	SPECULAR = 0.5;
}
