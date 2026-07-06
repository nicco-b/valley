#[compute]
#version 450
// Tier-2 water dynamics, pass 2 of 2: integrate. Depth loses what this
// cell's flux sent out, gains what each neighbor's flux sent toward us,
// gains rain, loses ground soak (dry ground drinks faster), and drains
// hard at authored water cells (the pond and sea are this field's sinks
// — their own level is Hydrology's, tier 1). Gains per-cell SOURCE
// water: the fill-channels experiment springs rivers here at a
// discharge-scaled rate (source_map, baked with the rate folded in,
// scaled live by source_dt) so the pipe model fills their carved beds
// instead of treating them as sinks. Also writes the display texture
// the water sheet samples: R = depth, G = flow speed.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D src;
layout(rgba32f, set = 0, binding = 1) uniform restrict readonly image2D flux;
layout(r32f, set = 0, binding = 2) uniform restrict writeonly image2D dst;
layout(set = 0, binding = 3) uniform sampler2D sink_mask; // 1 = authored water
layout(rg32f, set = 0, binding = 4) uniform restrict writeonly image2D display;
layout(r32f, set = 0, binding = 5) uniform restrict readonly image2D source_map; // m/s river spring
layout(push_constant) uniform Push {
	int grid; float rain; float soak; float sink_keep; float seep; float source_dt;
} pc;

vec4 flux_at(ivec2 p) {
	if (p.x < 0 || p.y < 0 || p.x >= pc.grid || p.y >= pc.grid) { return vec4(0.0); }
	return imageLoad(flux, p);
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= pc.grid || p.y >= pc.grid) { return; }
	vec4 out0 = imageLoad(flux, p);
	float d = imageLoad(src, p).r
		- (out0.x + out0.y + out0.z + out0.w)
		+ flux_at(p + ivec2(-1, 0)).x + flux_at(p + ivec2(1, 0)).y
		+ flux_at(p + ivec2(0, -1)).z + flux_at(p + ivec2(0, 1)).w;
	d += pc.rain;
	d += imageLoad(source_map, p).r * pc.source_dt;  // river spring (fill experiment)
	// Ground drinks a constant film plus seepage proportional to depth:
	// this gives flat ground a shallow equilibrium (below the sheet's
	// render threshold — no flood sheen), while hollows the flux keeps
	// feeding still pool visibly above it.
	d = max(d - pc.soak - d * pc.seep, 0.0);
	if (texture(sink_mask, (vec2(p) + 0.5) / float(pc.grid)).r > 0.5) {
		d *= pc.sink_keep;
	}
	imageStore(dst, p, vec4(d));
	// Net flow this step, as a speed the sheet can shade by (foam-bright
	// where the run is fast) and the probe can push swimmers with.
	vec2 net = vec2(out0.x - out0.y, out0.z - out0.w);
	imageStore(display, p, vec4(d, length(net) / max(d, 0.003), 0.0, 0.0));
}
