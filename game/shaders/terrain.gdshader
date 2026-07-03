shader_type spatial;
// Painterly terrain: color from height bands + slope, broken up by
// large noise blotches and fine grain so the ground reads as painted
// wash instead of a single flat fill.

uniform vec3 sand_floor : source_color = vec3(0.84, 0.785, 0.70);
uniform vec3 sand_warm : source_color = vec3(0.80, 0.655, 0.46);
uniform vec3 rock_high : source_color = vec3(0.63, 0.50, 0.36);
uniform vec3 rock_steep : source_color = vec3(0.56, 0.48, 0.41);
uniform sampler2D variation : filter_linear, repeat_enable;
global uniform sampler2D trace_map;
global uniform vec2 trace_center;
global uniform float trace_size;
global uniform float ground_wetness; // Climate publishes this (0..1)
global uniform float snow_cover; // Climate: 0..1 cover above the snowline
global uniform float snow_line; // Climate: freezing altitude in meters
global uniform vec2 wind_dir; // Weather: where the wind blows

varying vec3 wpos;
varying vec3 wnormal;
varying float wslope;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = NORMAL; // terrain meshes are unrotated: model = world
	wslope = 1.0 - NORMAL.y;
}

void fragment() {
	float blotch = texture(variation, wpos.xz * 0.006).r;
	float grain = texture(variation, wpos.xz * 0.09).r;

	float h = wpos.y + (blotch - 0.5) * 9.0;
	vec3 col = mix(sand_floor, sand_warm, smoothstep(3.0, 20.0, h));
	col = mix(col, rock_high, smoothstep(24.0, 46.0, h));
	col = mix(col, rock_steep, smoothstep(0.45, 0.75, wslope));
	col *= 0.95 + 0.10 * grain;

	// Sand lives on low, flat ground; rock faces get none of the detail.
	float sandiness = (1.0 - smoothstep(16.0, 28.0, wpos.y))
			* (1.0 - smoothstep(0.28, 0.5, wslope));

	// Aeolian ripples: wind-aligned sine crests wandered by the blotch
	// noise, ~1.1m wavelength. Shading depth comes from perturbing the
	// normal, so the sun models them like real micro-dunes.
	vec2 rip_dir = normalize(wind_dir + vec2(0.001, 0.0));
	float wander = (texture(variation, wpos.xz * 0.02).r - 0.5) * 5.0;
	float phase = dot(wpos.xz, rip_dir) * 5.7 + wander;
	float crest = sin(phase);
	vec3 n = wnormal;
	n.xz += rip_dir * cos(phase) * 0.22 * sandiness;
	col *= 1.0 - 0.06 * (crest * 0.5 + 0.5) * sandiness;

	// Footprints: darkened AND pressed — a normal dimple from the trace
	// gradient gives prints and trails actual relief.
	vec2 trace_uv = (wpos.xz - trace_center) / trace_size + 0.5;
	if (all(greaterThan(trace_uv, vec2(0.0))) && all(lessThan(trace_uv, vec2(1.0)))) {
		float px = 1.0 / 256.0;
		float tC = texture(trace_map, trace_uv).r;
		float tX = texture(trace_map, trace_uv + vec2(px, 0.0)).r;
		float tY = texture(trace_map, trace_uv + vec2(0.0, px)).r;
		n.xz += vec2(tX - tC, tY - tC) * 6.0;
		col *= 1.0 - 0.13 * tC;
	}

	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n), 0.0)).xyz);

	// Sun glints: sparse micro-facets with low roughness sparkle in
	// direct light (the Journey trick, gently).
	float g = fract(sin(dot(floor(wpos.xz * 16.0), vec2(127.1, 311.7))) * 43758.5453);
	float glint = step(0.986, g) * sandiness;

	// Rain memory: wet ground darkens (sand most, rock least) and takes a
	// faint sheen while it dries out.
	col *= 1.0 - ground_wetness * (0.08 + 0.12 * sandiness);

	// Snow: whitens above the freezing altitude (the lapse rate draws the
	// snowline), settling on flats more than faces.
	float snowiness = snow_cover
			* smoothstep(snow_line - 6.0, snow_line + 10.0, wpos.y)
			* (1.0 - smoothstep(0.5, 0.8, wslope));
	col = mix(col, vec3(0.93, 0.94, 0.97), snowiness * 0.85);

	ALBEDO = col;
	ROUGHNESS = mix(mix(1.0, 0.25, glint), 0.55, ground_wetness * sandiness * 0.6);
	SPECULAR = mix(0.08, 0.6, glint);
}
