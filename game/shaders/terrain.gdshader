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

varying vec3 wpos;
varying float wslope;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wslope = 1.0 - NORMAL.y; // terrain meshes are unrotated: model = world
}

void fragment() {
	float blotch = texture(variation, wpos.xz * 0.006).r;
	float grain = texture(variation, wpos.xz * 0.09).r;

	float h = wpos.y + (blotch - 0.5) * 9.0;
	vec3 col = mix(sand_floor, sand_warm, smoothstep(3.0, 20.0, h));
	col = mix(col, rock_high, smoothstep(24.0, 46.0, h));
	col = mix(col, rock_steep, smoothstep(0.45, 0.75, wslope));
	col *= 0.95 + 0.10 * grain;

	// Footprint trails: pressed, slightly darkened ground where feet went.
	vec2 trace_uv = (wpos.xz - trace_center) / trace_size + 0.5;
	if (all(greaterThan(trace_uv, vec2(0.0))) && all(lessThan(trace_uv, vec2(1.0)))) {
		float t = texture(trace_map, trace_uv).r;
		col *= 1.0 - 0.16 * t;
	}

	ALBEDO = col;
	ROUGHNESS = 1.0;
}
