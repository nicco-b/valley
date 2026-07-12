// gouache.gdshaderinc — the painterly ground wash shared by the game
// terrain (terrain.gdshader) and the shaping drape (preview_terrain.gdshader).
// ONE copy of the look so the survey/orbit view reads as the game's gouache,
// not a hypsometric relief chart, and can never drift from the game
// (PLAN_STRATA_TOOL "the gouache gap"). Extracted verbatim from
// terrain.gdshader's color block — the game shader now CALLS this, so its
// output is byte-for-byte what it always was; the drape gets the same wash.
//
// The wash: colour from height bands (sand_floor -> sand_warm -> rock_high)
// plus rock on steep slopes, broken up by a large low-frequency `variation`
// blotch (so band edges read ragged, not contoured) and a fine grain on
// brightness. Both callers pass the SAME variation texture + palette; height
// is world meters, slope is 1 - n.y. Biome tint stays with each caller (the
// game reads a world-space index map, the drape a pre-coloured colormap) —
// it recolours this wash the same way on both sides.

// E3.3: the band thresholds/frequencies/blotch-amp/grain-mix that used to
// be literals here now ride in from the caller (data/looks/gouache.json,
// game/world/look_data.gd) — an EXTEND, not a break: every existing call
// site is updated in the same commit, and the shader uniform defaults each
// caller declares are these exact numbers, so a look-record load failure
// decays to "the old literals" rather than a different look.
vec3 gouache_wash(sampler2D variation, vec2 world_xz, float height, float slope,
		vec3 sand_floor, vec3 sand_warm, vec3 rock_high, vec3 rock_steep,
		vec2 band_sand_to_warm, vec2 band_warm_to_rock, vec2 band_slope_to_steep,
		float freq_blotch, float freq_grain, float blotch_amp, vec2 grain_mix) {
	float blotch = texture(variation, world_xz * freq_blotch).r;
	float grain = texture(variation, world_xz * freq_grain).r;

	float h = height + (blotch - 0.5) * blotch_amp;
	vec3 col = mix(sand_floor, sand_warm,
			smoothstep(band_sand_to_warm.x, band_sand_to_warm.y, h));
	col = mix(col, rock_high,
			smoothstep(band_warm_to_rock.x, band_warm_to_rock.y, h));
	col = mix(col, rock_steep,
			smoothstep(band_slope_to_steep.x, band_slope_to_steep.y, slope));
	col *= grain_mix.x + grain_mix.y * grain;
	return col;
}
