#[compute]
#version 450
// One granular relaxation step (Jacobi): every cell exchanges material
// with its 4 neighbors wherever total height (terrain base + sand)
// exceeds the angle of repose. The flux formula is antisymmetric, so
// mass is conserved exactly (both sides compute the same q). Wind decay
// pulls the field toward rest.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D src;
layout(r32f, set = 0, binding = 1) uniform restrict writeonly image2D dst;
layout(set = 0, binding = 2) uniform sampler2D base; // low-res terrain heights, meters
layout(push_constant) uniform Push {
	int grid; float repose_h; float flow; float decay;
} pc;

float total(ivec2 p) {
	return texture(base, (vec2(p) + 0.5) / float(pc.grid)).r + imageLoad(src, p).r;
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= pc.grid || p.y >= pc.grid) { return; }
	float d0 = imageLoad(src, p).r;
	float h0 = total(p);
	float dv = 0.0;
	const ivec2 off[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
	for (int k = 0; k < 4; k++) {
		ivec2 q = p + off[k];
		if (q.x < 0 || q.y < 0 || q.x >= pc.grid || q.y >= pc.grid) { continue; }
		float hq = total(q);
		dv += pc.flow * 0.5 *
			(max(hq - h0 - pc.repose_h, 0.0) - max(h0 - hq - pc.repose_h, 0.0));
	}
	float v = d0 + dv;
	v -= clamp(v, -pc.decay, pc.decay); // erosion toward rest
	imageStore(dst, p, vec4(v));
}
