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
	vec3 n_ws = normalize(vec3(-rx * (0.3 + t * 0.5) - wgrad.x, 1.0,
			-rz * (0.3 + t * 0.5) - wgrad.y));
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
	foam = floor(clamp(foam, 0.0, 1.0) * 3.0) / 3.0;  // stepped: gouache, not mist
	vec3 foam_col = pal_b * mix(1.04, 1.12, water_gold) + vec3(0.04 * water_gold + 0.01);
	col = mix(col, foam_col, foam * 0.85);

	ALBEDO = col;
	ALPHA = 1.0;  // opaque composite; the screen read does the seeing-through
	ROUGHNESS = mix(0.1, 0.5, foam);
	SPECULAR = 0.5;
}
