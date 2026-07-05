#[compute]
#version 450
// Tier-2.5 wave field: offset copy for window scrolling (and the zero-
// offset publish to the display texture the water shaders sample).
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D src;
layout(r32f, set = 0, binding = 1) uniform restrict writeonly image2D dst;
layout(push_constant) uniform Push { int grid; int off_x; int off_y; int pad; } pc;

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= pc.grid || p.y >= pc.grid) { return; }
	ivec2 q = p + ivec2(pc.off_x, pc.off_y);
	float v = 0.0;
	if (q.x >= 0 && q.y >= 0 && q.x < pc.grid && q.y < pc.grid) {
		v = imageLoad(src, q).r;
	}
	imageStore(dst, p, vec4(v));
}
