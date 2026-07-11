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

vec3 gouache_wash(sampler2D variation, vec2 world_xz, float height, float slope,
		vec3 sand_floor, vec3 sand_warm, vec3 rock_high, vec3 rock_steep) {
	float blotch = texture(variation, world_xz * 0.006).r;
	float grain = texture(variation, world_xz * 0.09).r;

	float h = height + (blotch - 0.5) * 9.0;
	vec3 col = mix(sand_floor, sand_warm, smoothstep(3.0, 20.0, h));
	col = mix(col, rock_high, smoothstep(24.0, 46.0, h));
	col = mix(col, rock_steep, smoothstep(0.45, 0.75, slope));
	col *= 0.95 + 0.10 * grain;
	return col;
}
