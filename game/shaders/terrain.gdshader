shader_type spatial;
// Painterly terrain: color from height bands + slope, broken up by
// large noise blotches and fine grain so the ground reads as painted
// wash instead of a single flat fill. The wash itself lives in
// gouache.gdshaderinc so the shaping drape (preview_terrain.gdshader)
// wears the exact same paint — one look, not a fork.
#include "res://game/shaders/gouache.gdshaderinc"

uniform vec3 sand_floor : source_color = vec3(0.84, 0.785, 0.70);
uniform vec3 sand_warm : source_color = vec3(0.80, 0.655, 0.46);
uniform vec3 rock_high : source_color = vec3(0.63, 0.50, 0.36);
uniform vec3 rock_steep : source_color = vec3(0.56, 0.48, 0.41);
// E3.3: gouache_wash's band/frequency/blotch/grain constants, promoted to
// uniforms so game/world/look_data.gd can bind them from data/looks/gouache.json.
// Defaults here are the exact literals that used to live in gouache.gdshaderinc —
// a look-record load failure decays to this, not a different look.
uniform vec2 band_sand_to_warm = vec2(3.0, 20.0);
uniform vec2 band_warm_to_rock = vec2(24.0, 46.0);
uniform vec2 band_slope_to_steep = vec2(0.45, 0.75);
uniform float freq_blotch = 0.006;
uniform float freq_grain = 0.09;
uniform float blotch_amp = 9.0;
uniform vec2 grain_mix = vec2(0.95, 0.10);
uniform sampler2D variation : filter_linear, repeat_enable;
global uniform sampler2D trace_map;
global uniform vec2 trace_center;
global uniform float trace_size;
global uniform float ground_wetness; // Climate publishes this (0..1)
global uniform float snow_cover; // Climate: 0..1 cover above the snowline
global uniform float snow_line; // Climate: freezing altitude in meters
global uniform vec2 wind_dir; // Weather: where the wind blows
global uniform vec2 stream_center; // WorldStreamer: where full cells exist
global uniform sampler2D deform_map; // SandField: 4.7cm/px pressure field
global uniform vec2 deform_center; // where the deform window is anchored
global uniform float deform_size;
global uniform vec2 patch_center; // where the dense patch covers the hole
global uniform float sea_level; // LIVE sea surface (tide included)
global uniform vec4 home_rect; // home island rect (xy=min, zw=max)
global uniform bool biome_present; // a painted biome map is loaded
global uniform sampler2D biome_index_map; // R8 index/255 over the world
global uniform vec4 biome_index_rect; // xy=origin, zw=size
global uniform sampler2D biome_palette; // Nx1 ground albedo per biome
global uniform int biome_count;
uniform bool far_lod = false; // far terrain yields to the real cells
uniform bool sand_patch = false; // the dense patch replacing ground underfoot
const float PATCH_HOLE = 9.8; // terrain discards inside; patch owns it

varying vec3 wpos;
varying vec3 wnormal;
varying float wslope;
varying float v_fade; // patch: deformation amplitude fade toward the rim

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_fade = 0.0;
	if (sand_patch) {
		// The dense patch renders the granular sim: deform_map is SIGNED
		// sand volume in METERS (pits negative, ridges positive, mass
		// conserved by the sim). The geometry simply follows it.
		// Distance from the PATCH center in WORLD space — the kernel-
		// built patch mesh is corner-origin, so local VERTEX.xz no
		// longer measures from the patch center (lost-footsteps bug,
		// 2026-07-05). patch_center, not deform_center: the fade ring
		// must track the hole in the terrain, and the field anchor
		// snaps on a different grid.
		float r = length(wpos.xz - patch_center);
		vec2 d_uv = (wpos.xz - deform_center) / deform_size + 0.5;
		float sand = 0.0;
		if (all(greaterThan(d_uv, vec2(0.0))) && all(lessThan(d_uv, vec2(1.0)))) {
			sand = textureLod(deform_map, d_uv, 0.0).r;
		}
		v_fade = 1.0 - smoothstep(9.0, PATCH_HOLE, r);
		float proud = 0.012 * smoothstep(8.8, 9.6, r);
		VERTEX.y += proud + sand * v_fade;
		wpos.y = VERTEX.y;
	} else {
		// Coarse cells: trodden ground sinks by the 80m trace map —
		// worn paths and distant trails keep their broad grooves.
		vec2 t_uv = (wpos.xz - trace_center) / trace_size + 0.5;
		if (all(greaterThan(t_uv, vec2(0.0))) && all(lessThan(t_uv, vec2(1.0)))) {
			vec2 edge = min(t_uv, 1.0 - t_uv);
			float region_fade = smoothstep(0.0, 0.06, min(edge.x, edge.y));
			float press = min(textureLod(trace_map, t_uv, 1.0).r, 1.0);
			VERTEX.y -= press * (0.14 + 0.10 * ground_wetness) * region_fade;
			wpos.y = VERTEX.y;
		}
	}
	wnormal = NORMAL; // terrain meshes are unrotated: model = world
	wslope = 1.0 - NORMAL.y;
}

void fragment() {
	// The far LOD never draws where full-resolution cells are streamed:
	// its coarse sampling can bulge over sharp sculpts, and the real
	// ground is always there to win.
	if (far_lod && distance(wpos.xz, stream_center) < 240.0) {
		discard;
	}
	// The streamed cells yield the disc under the player to the dense
	// sand patch (which discards outside it — complementary with an
	// overlap band so neither gaps nor fights).
	if (sand_patch) {
		if (length(wpos.xz - patch_center) > PATCH_HOLE + 0.2) {
			discard;
		}
	} else if (!far_lod && distance(wpos.xz, patch_center) < PATCH_HOLE) {
		discard;
	}
	// The painted wash — shared verbatim with the shaping drape
	// (gouache.gdshaderinc); the ground reads identically here and there.
	vec3 col = gouache_wash(variation, wpos.xz, wpos.y, wslope,
			sand_floor, sand_warm, rock_high, rock_steep,
			band_sand_to_warm, band_warm_to_rock, band_slope_to_steep,
			freq_blotch, freq_grain, blotch_amp, grain_mix);

	// Biome ground (Stage B): tint toward the painted biome's albedo.
	// A tint, not a replace, so the painterly bands/grain/relief survive
	// — the biome recolors the wash, it doesn't flatten it.
	if (biome_present) {
		vec2 buv = (wpos.xz - biome_index_rect.xy) / biome_index_rect.zw;
		if (all(greaterThanEqual(buv, vec2(0.0))) && all(lessThan(buv, vec2(1.0)))) {
			float bidx = floor(texture(biome_index_map, buv).r * 255.0 + 0.5);
			vec3 g = texture(biome_palette,
					vec2((bidx + 0.5) / float(biome_count), 0.5)).rgb;
			col = mix(col, col * 0.5 + g * 0.5, 0.6);
		}
	}

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

	// Coarse-field relief (worn desire paths; fresh prints live in the
	// granular patch now). Never doubled onto the patch.
	vec2 trace_uv = (wpos.xz - trace_center) / trace_size + 0.5;
	if (!sand_patch
			&& all(greaterThan(trace_uv, vec2(0.0))) && all(lessThan(trace_uv, vec2(1.0)))) {
		// Full-res taps (textureLod 0): auto-mip blurred prints into
		// soft ovals past ~10m — every gradient (rim, dimple) vanished
		// with distance. The map is 512px; full-res is cheap.
		float px = 1.0 / 512.0;
		float tC = textureLod(trace_map, trace_uv, 0.0).r;
		float tX = textureLod(trace_map, trace_uv + vec2(px, 0.0), 0.0).r;
		float tY = textureLod(trace_map, trace_uv + vec2(0.0, px), 0.0).r;
		vec2 grad = vec2(tX - tC, tY - tC);
		// Physical relief shading, same empirical sign as the patch —
		// the original += was inverted, so every print ever rendered
		// shaded as a bump. Scale ~= depth/texel, mildly exaggerated.
		n.xz -= grad * 1.6;
		// Dry sand doesn't stain — the pit reads as shadowed relief, and
		// only truly darkens when the ground is wet.
		col *= 1.0 - min(tC, 1.0) * (0.03 + 0.07 * ground_wetness);
	}

	// On the dense patch: NO painted shading. The surface normal is
	// derived PHYSICALLY from the deformed height field (central
	// differences over the 4.7cm texels, scaled by the true depth), and
	// the actual sun does the rest — a pit reads concave at every hour
	// because the light model, not a paint trick, says so. The only
	// paint left is a whisper of compaction tint on wet ground.
	if (sand_patch) {
		vec2 d_uv = (wpos.xz - deform_center) / deform_size + 0.5;
		if (all(greaterThan(d_uv, vec2(0.0))) && all(lessThan(d_uv, vec2(1.0)))) {
			float field_px = float(textureSize(deform_map, 0).x);
			float dpx = 1.0 / field_px;
			float texel_m = deform_size / field_px;
			float dC = textureLod(deform_map, d_uv, 0.0).r;
			float dXp = textureLod(deform_map, d_uv + vec2(dpx, 0.0), 0.0).r;
			float dXm = textureLod(deform_map, d_uv - vec2(dpx, 0.0), 0.0).r;
			float dYp = textureLod(deform_map, d_uv + vec2(0.0, dpx), 0.0).r;
			float dYm = textureLod(deform_map, d_uv - vec2(0.0, dpx), 0.0).r;
			// The field is height in meters: the normal is its exact
			// gradient (sign verified empirically vs a shadow reference).
			n.xz -= (v_fade / texel_m) * 0.5 * vec2(dXp - dXm, dYp - dYm);
			// Disturbed sand tint: pressed-below-base compacts (darker
			// when wet); freshly piled sand is looser and lighter.
			col *= 1.0 - clamp(-dC * 6.0, 0.0, 1.0) * (0.02 + 0.10 * ground_wetness);
			col += vec3(0.05, 0.04, 0.028) * clamp(dC * 10.0, 0.0, 1.0) * sandiness;
		}
	}

	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n), 0.0)).xyz);

	// Sun glints: sparse micro-facets with low roughness sparkle in
	// direct light (the Journey trick, gently).
	float g = fract(sin(dot(floor(wpos.xz * 16.0), vec2(127.1, 311.7))) * 43758.5453);
	float glint = step(0.986, g) * sandiness;

	// Rain memory: wet ground darkens (sand most, rock least) and takes a
	// faint sheen while it dries out.
	col *= 1.0 - ground_wetness * (0.08 + 0.12 * sandiness);

	// The tide line: ground within ~2m over the LIVE sea reads as wet
	// strand — darker, slightly cool, a sheen. Gated outside the home
	// island (same rect guard as Terrain.home_guard) so low valley
	// floor never reads as beach.
	vec2 g_d = max(max(home_rect.xy - wpos.xz, wpos.xz - home_rect.zw), vec2(0.0));
	float strand = (1.0 - smoothstep(sea_level + 0.35, sea_level + 2.1, wpos.y))
			* smoothstep(150.0, 550.0, length(g_d));
	col = mix(col, col * vec3(0.66, 0.66, 0.70), strand * 0.85);

	// Snow: whitens above the freezing altitude (the lapse rate draws the
	// snowline), settling on flats more than faces.
	float snowiness = snow_cover
			* smoothstep(snow_line - 6.0, snow_line + 10.0, wpos.y)
			* (1.0 - smoothstep(0.5, 0.8, wslope));
	col = mix(col, vec3(0.93, 0.94, 0.97), snowiness * 0.85);

	ALBEDO = col;
	ROUGHNESS = mix(mix(1.0, 0.25, glint), 0.55, ground_wetness * sandiness * 0.6);
	ROUGHNESS = mix(ROUGHNESS, 0.4, strand * 0.7); // wet strand sheen
	SPECULAR = mix(0.08, 0.6, glint);
}
