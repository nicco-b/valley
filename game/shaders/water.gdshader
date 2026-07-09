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
// Shoaling + breakers (W2, the Watershed): sea meshes with bathy_boost=1
// carry baked bathymetry in CUSTOM0 — depth below sea level in .x, the
// horizontal depth gradient in .yz (water_bodies bakes it per vertex from
// the real seabed and rebakes as the discs follow the focus). In shallow
// water each swell component slows (phase lag from tanh(kd) dispersion),
// steepens (Green's-law gain, capped), and BREAKS where its crest height
// would top SURF_GAMMA of the water column — the classic 0.78 surf
// criterion — saturating to the column so waves die at the waterline.
// Breaking is gated by alignment with the shoreward direction: swell
// running offshore never breaks, so the lee shore stays calm (the island
// shelters itself). surf_boost is SeaSwell's Toolkit knob (default 1).
uniform float bathy_boost = 0.0;
global uniform float surf_boost;
const float SURF_GAMMA = 0.78;   // break when waveheight/depth tops this
const float SHOAL_MAX = 1.7;     // Green's-law amplitude gain cap
const float SLOW_M = 6.0;        // meters of phase lag at zero depth (crests bunch)
const float DEPTH_MIN = 0.05;    // the water column never divides by zero
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
global uniform sampler2D wave_map; // tier-2.5 height field, meters
global uniform vec2 wave_center;
global uniform float wave_size;
// ★ Ring posterization (PLAN_SUBSTANCES S1): quantize the wave-field
// READ into N height bands so dense rings hold as painted strokes
// instead of CG interference — flap_posterize's trick on water. The
// banded read feeds displacement AND the crest-foam term, so each ring
// wears a stepped foam edge. 0 = smooth field. 8 shipped from the
// wave_probe A/B (WAVE_POST=n re-shoots it): coarser bands (5) swallow
// a hound ring and a rain pock whole — held poses must never erase the
// speaker. Retune by eye.
uniform float ring_posterize = 8.0;
// ★ Foam memory (PLAN_SUBSTANCES S2): wave_map.g is a foam HISTORY —
// deposited by every disturbance, the breaker band, and travelling
// crests; advected by the window drift; decaying on WaterWaves.foam_decay
// seconds. Read here as painted curds: the age is quantized into bands
// sized to the WEAKEST speaker (a swimmer's wake deposits ~0.10 — the
// S1 posterize lesson: held poses must never erase the speaker), so
// foam dies in visible steps, not a smooth fade. 0 = smooth history.
uniform float foam_posterize = 6.0;
const float FOAM_SPAN = 0.8;  // the band ladder covers this much LIFTED history
// Foam distance-fade (S2, the "too white at distance" fix): far water is
// painted stillness — every foam term fades out across this window, so a
// lake at 400m reads as one quiet color field (gouache distance), not a
// white shimmer of aliased posterized foam. Uniforms so the probe can
// A/B the fade off (WAVE_FADE=off) — retune by eye, not by code.
uniform float foam_fade_near = 150.0;
uniform float foam_fade_far = 300.0;
global uniform sampler2D trace_map;
global uniform vec2 trace_center;
global uniform float trace_size;

varying vec3 wpos;
varying float wave_h;
varying float alpha_v;  // river-mouth feather (S2): COLOR.a ramps to 0
varying float rapids_v;
varying vec2 flow_v;
varying float swell_crest;  // normalized crest phase, foams in storms
varying vec2 swell_grad;    // swell surface slope for the normal
varying float surf_v;       // breaker band strength (W2): crest foam here
varying float after_v;      // afterfoam sheet shoreward of the break line

// Window-edge fade so the wave field's border never shows on the mesh.
float wave_fade(vec2 uv) {
	vec2 e = abs(uv - 0.5) * 2.0;
	return 1.0 - smoothstep(0.85, 1.0, max(e.x, e.y));
}

void vertex() {
	rapids_v = COLOR.r;
	alpha_v = COLOR.a;  // 1 everywhere except a feathered river mouth
	flow_v = UV2;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 wuv = (wpos.xz - wave_center) / wave_size + 0.5;
	wave_h = 0.0;
	if (all(greaterThan(wuv, vec2(0.0))) && all(lessThan(wuv, vec2(1.0)))) {
		wave_h = textureLod(wave_map, wuv, 0.0).r * wave_fade(wuv);
	}
	if (ring_posterize > 0.5) {
		// Hold the height in N bands across the WADING-ring span (±0.05m)
		// — not the field's ±0.12 clamp, which would drop a hound-sized
		// ring (±0.015m) below the first band and erase it. Splashes just
		// saturate more bands; sub-band chop rounds to honest stillness.
		float band = 0.096 / ring_posterize;
		wave_h = floor(wave_h / band + 0.5) * band;
	}
	VERTEX.y += clamp(wave_h, -0.12, 0.12);
	wpos.y += clamp(wave_h, -0.12, 0.12);

	// The swell: big rolling trochoids, world-anchored so every sea
	// mesh agrees. Deep-water dispersion (long waves outrun short) keeps
	// the sum from ever reading as one marching pattern.
	swell_crest = 0.0;
	swell_grad = vec2(0.0);
	surf_v = 0.0;
	after_v = 0.0;
	if (swell_boost > 0.0 && swell_amp > 0.001) {
		float fade = swell_boost;
		if (swell_fade_radius > 0.0) {
			fade *= 1.0 - smoothstep(swell_fade_radius * 0.75,
					swell_fade_radius, length(VERTEX.xz));
		}
		// Bathymetry (W2): baked depth + shoreward direction, or "deep
		// everywhere" (the exact W1 sea) when the mesh carries none.
		float depth = 1000.0;
		vec2 shoreward = vec2(0.0);
		if (bathy_boost > 0.5) {
			depth = CUSTOM0.x;
			vec2 g = CUSTOM0.yz;  // ∇depth: shallower is -g
			float gl = length(g);
			if (gl > 1e-4) { shoreward = -g / gl; }
		}
		float col = max(depth, DEPTH_MIN);  // the water column
		float rot[4] = float[](0.0, 0.35, -0.42, 0.83);
		float lsc[4] = float[](1.0, 0.62, 0.38, 0.23);
		float asc[4] = float[](0.44, 0.28, 0.17, 0.11);
		vec2 hoff = vec2(0.0);
		float voff = 0.0;
		float break_x = 0.0;   // waveheight over the surf criterion, best band
		float crest_raw = 0.0; // ungated crest phase — times the surf band
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
			// Shallow-water dispersion: tanh(kd) is 1 in the deep and
			// falls toward 0 up the shelf — everything below keys off it.
			float tk = tanh(k * col);
			float shal = 1.0 - tk;
			// The lee gate: only swell RUNNING AT the shallows shoals and
			// breaks. Offshore-bound waves leave the sheltered shore calm.
			float align = clamp(dot(d, shoreward), 0.0, 1.0);
			// Slow: shrinking phase speed reads as a bounded phase lag —
			// crests bunch as they climb the shelf (never unbounded k).
			float ph = k * dot(d, wpos.xz) - w * TIME + k * SLOW_M * shal;
			// Steepen: Green's-law gain, capped, windward only...
			float gain = mix(1.0, clamp(pow(max(tk, 0.02), -0.25), 1.0, SHOAL_MAX), align);
			// ...and sheltered shallows genuinely calmer than open water.
			float a_s = a * gain * mix(1.0, mix(0.45, 1.0, align), shal);
			// Break: crest height saturates to SURF_GAMMA of the column,
			// so waves collapse at the bar/strand instead of clipping it.
			float hcap = 0.5 * SURF_GAMMA * col;
			float a_f = min(a_s, hcap);
			float s = sin(ph);
			float c = cos(ph);
			voff += a_f * s;
			// Trochoid gather, sharpening as the wave feels the bottom.
			hoff -= d * ((3.0 + 2.5 * shal * align) * a_f * c);
			swell_grad += d * (k * a_f * c);
			// Cap foam rides what the wave ACTUALLY carries: full in the
			// deep (pure W1), fading where the lee damps or the surf
			// saturation eats the swell — the breaker band takes over.
			swell_crest += s * asc[i] * (a_f / max(a, 1e-5));
			crest_raw += s * asc[i];
			break_x = max(break_x, (a_s / hcap) * align);
		}
		// The surf bands (fragment paints them): a posterized breaker
		// line where the criterion trips, and a softer afterfoam sheet
		// riding shoreward of it, gone before the waterline (the wave
		// window's shoreline lap takes over there). Dead calm keeps a
		// clean strand — lap foam, no surf line.
		float surf_e = surf_boost * clamp((swell_amp - 0.08) * 6.0, 0.0, 1.0);
		surf_v = smoothstep(0.7, 1.15, break_x) * surf_e
				* (0.6 + 0.4 * smoothstep(-0.2, 0.8, crest_raw));
		after_v = smoothstep(1.05, 1.8, break_x)
				* (1.0 - smoothstep(4.0, 8.0, break_x)) * surf_e;
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
	float foam_hist = 0.0;  // S2: the foam memory channel, read per-texel
	if (all(greaterThan(wuv, vec2(0.02))) && all(lessThan(wuv, vec2(0.98)))) {
		float px = 1.0 / float(textureSize(wave_map, 0).x);
		float f = wave_fade(wuv);
		wgrad = vec2(
			texture(wave_map, wuv + vec2(px, 0.0)).r - texture(wave_map, wuv - vec2(px, 0.0)).r,
			texture(wave_map, wuv + vec2(0.0, px)).r - texture(wave_map, wuv - vec2(0.0, px)).r
		) * f * 7.0;
		foam_hist = texture(wave_map, wuv).g * f;
		// The gouache lift: thin foam is still PAINT — a square root
		// keeps the weakest speaker (a hound's minutes-old trail, a
		// wake's edge) reading as curds while a saturated splash stays
		// 1. Perceptual, not physical: paint thins, it never dims.
		foam_hist = sqrt(clamp(foam_hist, 0.0, 1.0));
		if (foam_posterize > 0.5) {
			// The age dies in visible steps — painted curds that hold,
			// then vanish (the gouache read), banded to the weakest
			// speaker so a wake survives its own quantization.
			float band = FOAM_SPAN / foam_posterize;
			foam_hist = floor(foam_hist / band + 0.5) * band;
		}
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
	// The surf (W2): breakers wear their foam ON the crest face — the
	// band tracks the seabed (bars break offshore, the deep coast never
	// does) — and the afterfoam sheet drifts shoreward of the line,
	// mottled by hand so it reads painted, not misted.
	foam += surf_v * (0.85 + 0.15 * sin(fp.x * 0.9 + fp.y * 1.3));
	foam += after_v * (0.42 + 0.28 * sin(fp.x * 0.23 + fp.y * 0.31)
			* sin(fp.x * 0.07 - fp.y * 0.11));
	// Distance is stillness (S2): every foam term fades out with camera
	// distance INTO the calm palette — far water is a flat color field,
	// not a white shimmer. VERTEX is view-space here; its length is the
	// camera distance.
	float dist_still = 1.0 - smoothstep(foam_fade_near, foam_fade_far, length(VERTEX));
	foam *= dist_still;
	foam = floor(clamp(foam, 0.0, 1.0) * 3.0) / 3.0;  // stepped: gouache, not mist
	// The memory (S2): foam born by events outlives them — a wake trails
	// a swimmer, breaker curds ride ashore and die on the sand. Composed
	// AFTER the 3-step quantize: the history carries its own age bands
	// (foam_posterize above), and the instant terms' floor must never
	// swallow a fading trail (the S1 lesson, twice now).
	foam = max(foam, foam_hist * 0.85 * dist_still);
	vec3 foam_col = pal_b * mix(1.04, 1.12, water_gold) + vec3(0.04 * water_gold + 0.01);
	col = mix(col, foam_col, foam * 0.85);

	ALBEDO = col;
	// The composite is opaque (the screen read does the seeing-through)
	// everywhere but a feathered river mouth, where the ribbon dissolves
	// into its lake disc (S2 — the mouth-seam fix).
	ALPHA = alpha_v;
	ROUGHNESS = mix(0.1, 0.5, foam);
	SPECULAR = 0.5;
}
