shader_type spatial;
render_mode cull_disabled;
// Painterly water that MOVES (tier 2.5): vertices ride the wave field
// (wading rings, rain pocks, wind chop), the bed shows through real
// refraction tinted toward the pool's pink with depth, foam gathers as
// painted pale bands at shorelines / wave crests / fast water, grazing
// light glints off the ripple normals. Elden Ring's recipe — moving
// surface + foam + refraction — spoken in gouache.

uniform vec3 color_a : source_color = vec3(0.93, 0.55, 0.60); // deep tint
uniform vec3 color_b : source_color = vec3(0.99, 0.76, 0.77); // shallow tint
uniform vec2 flow = vec2(0.0);
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

// Window-edge fade so the wave field's border never shows on the mesh.
float wave_fade(vec2 uv) {
	vec2 e = abs(uv - 0.5) * 2.0;
	return 1.0 - smoothstep(0.85, 1.0, max(e.x, e.y));
}

void vertex() {
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
	vec2 fp = wpos.xz - flow * TIME * 1.5;
	float wiggle = t * sin(TIME * 6.0) * 1.5;
	float r0 = ripple(fp * 0.8, TIME) + wiggle;
	float e = 0.35;
	float rx = ripple((fp + vec2(e, 0.0)) * 0.8, TIME) + wiggle - r0;
	float rz = ripple((fp + vec2(0.0, e)) * 0.8, TIME) + wiggle - r0;
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

	// The bed through the surface: refract the opaque screen by the
	// normal, more with depth, and drink the light toward the deep pink.
	vec2 refr = n_ws.xz * (0.015 + 0.035 * clamp(water_depth * 0.5, 0.0, 1.0));
	vec3 through = texture(screen_tex, clamp(SCREEN_UV - refr, vec2(0.001), vec2(0.999))).rgb;
	float shallow = exp(-water_depth * 1.1);
	through *= mix(vec3(1.0), color_a, clamp(1.0 - shallow, 0.0, 0.85) * 0.7);

	// Surface color: deep pink body rising with depth and grazing angle.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float body = clamp(0.18 + (1.0 - shallow) * 0.5 + fresnel * 0.35, 0.0, 0.9);
	vec3 surface_col = mix(color_a * 0.9, color_b * 1.04, 0.35 + fresnel * 0.5);
	vec3 col = mix(through, surface_col, body);

	// Foam: painted pale bands, posterized — shoreline lap, wave crests,
	// fast water streaks, stirred wading. Never photoreal spray.
	float foam = smoothstep(0.3, 0.05, water_depth) * 0.75;
	foam += smoothstep(0.035, 0.09, wave_h + length(wgrad) * 0.05) * 0.6;
	foam += smoothstep(0.8, 1.6, length(flow)) * (0.5 + 0.5 * sin(fp.x * 3.1 + fp.y * 1.7)) * 0.35;
	foam += t * 0.5;
	foam = floor(clamp(foam, 0.0, 1.0) * 3.0) / 3.0;  // stepped: gouache, not mist
	col = mix(col, color_b * 1.12 + vec3(0.04), foam * 0.85);

	ALBEDO = col;
	ALPHA = 1.0;  // opaque composite; the screen read does the seeing-through
	ROUGHNESS = mix(0.1, 0.5, foam);
	SPECULAR = 0.5;
}
