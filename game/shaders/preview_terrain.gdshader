shader_type spatial;
// PreviewTerrain (engine-viewport M2): a single GPU-displaced grid that
// wears a Strata export DIRECTLY — height.exr as a vertex texture, the
// data layers (moisture/temperature/biome/slope) as false-color modes
// with a hillshade blend, hypsometric shaded mode as the default. This is
// the SHAPING viewport: no cells, no collision, no flora — a slider push
// swaps textures and the ground is new next frame. Exact Metal-ramp
// parity is M3; these ramps approximate the Metal data views.
render_mode cull_back;

uniform sampler2D height_map : filter_linear, repeat_disable;
uniform sampler2D data_map : filter_linear, repeat_disable;   // gray layer
uniform sampler2D color_map : filter_linear, repeat_disable;  // biome colormap
uniform float world_size = 16384.0;
uniform float sea_level = 0.0;
uniform int mode = 0;        // 0 shaded, 1 moisture, 2 temperature, 3 slope, 4 biome
uniform float data_min = 0.0;
uniform float data_max = 1.0;
uniform bool contours = true;    // parity extras: 50m contour lines
uniform float hillshade = 0.65;  // how much relief shading rides data views

varying vec2 v_uv;
varying float v_h;

void vertex() {
	// The grid is a UNIT plane (local -1..1), scaled to the world frame by
	// the node — UVs come from local space, displacement in meters rides
	// the un-scaled Y axis.
	v_uv = VERTEX.xz * 0.5 + 0.5;
	float h = texture(height_map, v_uv).r;
	VERTEX.y = h;
	v_h = h;
}

// Normal from height-texture neighbors (the mesh is a flat grid; real
// normals live in the texture, one texel step apart).
vec3 height_normal(vec2 uv) {
	vec2 texel = 1.0 / vec2(textureSize(height_map, 0));
	float step_m = world_size * texel.x;
	float hl = texture(height_map, uv - vec2(texel.x, 0.0)).r;
	float hr = texture(height_map, uv + vec2(texel.x, 0.0)).r;
	float hd = texture(height_map, uv - vec2(0.0, texel.y)).r;
	float hu = texture(height_map, uv + vec2(0.0, texel.y)).r;
	return normalize(vec3(hl - hr, 2.0 * step_m, hd - hu));
}

// The Metal view's colormap family: simple two-tone ramps, readable at a
// glance (moisture blue, temperature cold→hot, slope green→red).
vec3 ramp(int m, float t) {
	t = clamp(t, 0.0, 1.0);
	if (m == 1) { // moisture: parchment -> deep blue
		return mix(vec3(0.93, 0.90, 0.80), vec3(0.06, 0.25, 0.65), t);
	}
	if (m == 2) { // temperature: ice -> ember
		return mix(vec3(0.25, 0.45, 0.85), vec3(0.90, 0.30, 0.12), t);
	}
	// slope: meadow -> brick
	return mix(vec3(0.55, 0.75, 0.40), vec3(0.75, 0.15, 0.10), t);
}

void fragment() {
	vec3 n = height_normal(v_uv);
	float lambert = clamp(dot(n, normalize(vec3(0.5, 0.8, 0.35))), 0.0, 1.0);
	vec3 col;
	if (mode == 0) {
		// Hypsometric shaded relief (the Metal view's default look).
		float t = clamp((v_h - sea_level) / 400.0, 0.0, 1.0);
		col = mix(vec3(0.45, 0.60, 0.35), vec3(0.72, 0.62, 0.48), t);
		col = mix(col, vec3(0.85, 0.85, 0.88), smoothstep(0.75, 1.0, t));
		if (v_h < sea_level) {
			float d = clamp((sea_level - v_h) / 60.0, 0.0, 1.0);
			col = mix(vec3(0.45, 0.65, 0.75), vec3(0.10, 0.25, 0.45), d);
		}
	} else if (mode == 4) {
		col = texture(color_map, v_uv).rgb;
	} else if (mode == 3) {
		float s = 1.0 - n.y;
		col = ramp(3, s * 3.0);
	} else {
		float raw = texture(data_map, v_uv).r;
		col = ramp(mode, (raw - data_min) / max(data_max - data_min, 1e-5));
	}
	// Hillshade drape so data views still read as terrain (Metal parity).
	if (mode != 0) {
		col *= mix(1.0, 0.45 + 0.75 * lambert, hillshade);
	} else {
		col *= 0.35 + 0.75 * lambert;
	}
	// Contour lines every 50m (the "what's missing for parity" probe).
	if (contours && v_h > sea_level) {
		float c = abs(fract(v_h / 50.0) - 0.5) * 2.0;
		float w = fwidth(v_h / 50.0) * 2.0;
		col *= mix(0.75, 1.0, smoothstep(0.0, w * 2.0, 1.0 - c));
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
