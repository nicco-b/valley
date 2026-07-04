#[compute]
#version 450
// Tier-2 water dynamics, pass 1 of 2: outflow fluxes. Each cell pushes
// water toward any lower neighboring surface (terrain base + depth),
// scaled so a cell can never send more than most of what it holds — the
// limiter keeps depth non-negative and the scheme mass-exact (pass 2
// adds exactly what neighbors recorded here). Domain edges drain: an
// out-of-bounds neighbor reads as far lower, so storm water leaves the
// watershed instead of piling at the rim.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D depth;
layout(set = 0, binding = 1) uniform sampler2D base; // terrain heights, meters
layout(rgba32f, set = 0, binding = 2) uniform restrict writeonly image2D flux;
layout(push_constant) uniform Push {
	int grid; float flow; float pad0; float pad1;
} pc;

float surf(ivec2 p, float fallback) {
	if (p.x < 0 || p.y < 0 || p.x >= pc.grid || p.y >= pc.grid) { return fallback; }
	return texture(base, (vec2(p) + 0.5) / float(pc.grid)).r + imageLoad(depth, p).r;
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= pc.grid || p.y >= pc.grid) { return; }
	float d0 = imageLoad(depth, p).r;
	if (d0 <= 0.0) { imageStore(flux, p, vec4(0.0)); return; }
	float h0 = surf(p, 0.0);
	float edge = h0 - 5.0; // out-of-domain reads as a drop: water exits
	vec4 outflow = vec4(
		max(h0 - surf(p + ivec2(1, 0), edge), 0.0),
		max(h0 - surf(p + ivec2(-1, 0), edge), 0.0),
		max(h0 - surf(p + ivec2(0, 1), edge), 0.0),
		max(h0 - surf(p + ivec2(0, -1), edge), 0.0)) * pc.flow;
	float total = outflow.x + outflow.y + outflow.z + outflow.w;
	if (total > d0 * 0.8) {
		outflow *= d0 * 0.8 / total;
	}
	imageStore(flux, p, outflow);
}
