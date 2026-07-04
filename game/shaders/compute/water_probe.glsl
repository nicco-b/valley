#[compute]
#version 450
// One-thread readback probe: sample the water field at a world point
// (as grid uv) into a tiny SSBO the CPU reads at a few Hz — depth and
// net flow direction, for the current that pushes wading bodies. Keeps
// the whole-field textures GPU-resident; the CPU only ever sees these
// four floats.
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D depth;
layout(rgba32f, set = 0, binding = 1) uniform restrict readonly image2D flux;
layout(set = 0, binding = 2) buffer restrict writeonly Out { vec4 sample_out; };
layout(push_constant) uniform Push {
	int grid; float u; float v; float pad0;
} pc;

void main() {
	ivec2 p = clamp(ivec2(vec2(pc.u, pc.v) * float(pc.grid)),
		ivec2(0), ivec2(pc.grid - 1));
	vec4 f = imageLoad(flux, p);
	sample_out = vec4(imageLoad(depth, p).r,
		f.x - f.y, f.z - f.w, 0.0);
}
