shader_type spatial;
// PreviewTerrain (engine-viewport M2 + data parity M3): a single
// GPU-displaced grid that wears a Strata export DIRECTLY — height.exr as
// a vertex texture, the data layers (moisture/temperature/flow/slope/
// biome) as false-color drapes, hypsometric shaded mode as the default.
// This is the SHAPING viewport: no cells, no collision, no flora — a
// slider push swaps textures and the ground is new next frame.
//
// Data parity (M3): the drape colours come from the export's ramps.png —
// the LUT strip Strata writes from its DataRamps table (the one colormap
// truth; flow's sqrt curve baked in). An old export without ramps.png
// falls back to ramp_fallback(), hand-mirrored from Strata's
// Sources/StrataCore/Shaders/render.metal dataColor() — same numbers as
// Engine/DataRamps.swift. Data modes are CHART renders: colour × the
// Metal view's exact hillshade (0.55 + 0.45·lambert, same fixed sun),
// emitted unlit so scene lighting can't re-grade the measurement (the
// chart-air environment in preview_terrain.gd handles fog/tonemap).
render_mode cull_back;

uniform sampler2D height_map : filter_linear, repeat_disable;
uniform sampler2D data_map : filter_linear, repeat_disable;   // gray layer
uniform sampler2D color_map : filter_linear, repeat_disable;  // biome colormap
uniform float world_size = 16384.0;
uniform float sea_level = 0.0;
// Mode ids mirror render.metal's viewMode:
// 0 shaded · 1 moisture · 2 temperature · 3 flow · 4 slope · 5 biome
uniform int mode = 0;
// Raw texture value -> ramp t in one fma (encoding + view range folded
// together by _apply_layer): t = raw * data_scale + data_offset.
uniform float data_scale = 1.0;
uniform float data_offset = 0.0;
// ramps.png: one row per ramped layer (DataRamps.lutRows order), curve
// baked in — sample with plain t.
uniform sampler2D ramp_lut : filter_linear, repeat_disable;
uniform bool has_lut = false;
uniform int ramp_row = 0;
uniform int lut_rows = 4;
uniform bool contours = true;    // 50m contour lines (shaded mode only)

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
// normals live in the texture, one texel step apart). Numerically the
// same central-difference estimator render.metal uses (its ±half-texel
// taps under bilinear collapse to this ±1-texel form).
vec3 height_normal(vec2 uv) {
	vec2 texel = 1.0 / vec2(textureSize(height_map, 0));
	float step_m = world_size * texel.x;
	float hl = texture(height_map, uv - vec2(texel.x, 0.0)).r;
	float hr = texture(height_map, uv + vec2(texel.x, 0.0)).r;
	float hd = texture(height_map, uv - vec2(0.0, texel.y)).r;
	float hu = texture(height_map, uv + vec2(0.0, texel.y)).r;
	return normalize(vec3(hl - hr, 2.0 * step_m, hd - hu));
}

// FALLBACK ramps (export predates ramps.png) — hand-mirrored from
// Strata's render.metal dataColor() / DataRamps.swift, including flow's
// sqrt curve. Edit those first; this copy follows.
vec3 ramp_fallback(int m, float t) {
	t = clamp(t, 0.0, 1.0);
	if (m == 1) { // moisture: dry sand -> deep blue
		return mix(vec3(0.80, 0.72, 0.52), vec3(0.10, 0.35, 0.72), t);
	}
	if (m == 2) { // temperature: cold blue -> hot red
		return mix(vec3(0.16, 0.34, 0.78), vec3(0.86, 0.24, 0.16), t);
	}
	if (m == 3) { // flow: near-black water -> bright cyan, sqrt curve
		return mix(vec3(0.05, 0.10, 0.14), vec3(0.30, 0.85, 0.95), sqrt(t));
	}
	// slope: green -> red
	return mix(vec3(0.20, 0.55, 0.25), vec3(0.85, 0.20, 0.15), t);
}

// The ramp colour for a normalized t: the export's own LUT when it
// shipped one (exact Strata parity), the mirrored constants otherwise.
vec3 ramp_color(int m, float t) {
	t = clamp(t, 0.0, 1.0);
	if (has_lut) {
		float w = float(textureSize(ramp_lut, 0).x);
		float u = (t * (w - 1.0) + 0.5) / w;
		float v = (float(ramp_row) + 0.5) / float(lut_rows);
		return texture(ramp_lut, vec2(u, v)).rgb;
	}
	return ramp_fallback(m, t);
}

// Ramp colours are display (sRGB-encoded) values — exactly what the
// Metal view writes to its framebuffer. Godot shades in linear, so
// decode; the chart-air linear tonemap re-encodes on the way out and
// the screen sees the table's numbers.
vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)),
		step(vec3(0.04045), c));
}

void fragment() {
	vec3 n = height_normal(v_uv);
	float lambert = clamp(dot(n, normalize(vec3(0.5, 0.8, 0.35))), 0.0, 1.0);
	if (mode == 0) {
		// Hypsometric shaded relief under the world's real light and air
		// (the game look is shaded mode's point).
		vec3 col;
		float t = clamp((v_h - sea_level) / 400.0, 0.0, 1.0);
		col = mix(vec3(0.45, 0.60, 0.35), vec3(0.72, 0.62, 0.48), t);
		col = mix(col, vec3(0.85, 0.85, 0.88), smoothstep(0.75, 1.0, t));
		if (v_h < sea_level) {
			float d = clamp((sea_level - v_h) / 60.0, 0.0, 1.0);
			col = mix(vec3(0.45, 0.65, 0.75), vec3(0.10, 0.25, 0.45), d);
		}
		col *= 0.35 + 0.75 * lambert;
		// Contour lines every 50m — a terrain-reading aid for the game
		// look only; data modes stay honest (the Metal view has none).
		if (contours && v_h > sea_level) {
			float c = abs(fract(v_h / 50.0) - 0.5) * 2.0;
			float w = fwidth(v_h / 50.0) * 2.0;
			col *= mix(0.75, 1.0, smoothstep(0.0, w * 2.0, 1.0 - c));
		}
		ALBEDO = col;
	} else {
		// DATA drape — render.metal's exact recipe: colormap the layer
		// (slope from the normal), shade by 0.55 + 0.45·lambert.
		vec3 dc;
		if (mode == 5) {
			dc = texture(color_map, v_uv).rgb;  // biome palette (pre-coloured)
		} else {
			float t = (mode == 4) ? (1.0 - n.y)
				: (texture(data_map, v_uv).r * data_scale + data_offset);
			dc = ramp_color(mode, t);
		}
		vec3 chart = dc * (0.55 + 0.45 * lambert);
		// Emit unlit: the chart owes nothing to the sun or the hour.
		ALBEDO = vec3(0.0);
		EMISSION = srgb_to_linear(chart);
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
