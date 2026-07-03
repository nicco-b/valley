#[compute]
#version 450
// Offset copy: re-anchor scroll (window moved off_x/off_y texels) and
// the plain copy into the display texture (offset zero).
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D src;
layout(r32f, set = 0, binding = 1) uniform restrict writeonly image2D dst;
layout(push_constant) uniform Push { int grid; int off_x; int off_y; int _pad; } pc;

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= pc.grid || p.y >= pc.grid) { return; }
	ivec2 s = p + ivec2(pc.off_x, pc.off_y);
	float v = 0.0;
	if (s.x >= 0 && s.y >= 0 && s.x < pc.grid && s.y < pc.grid) {
		v = imageLoad(src, s).r;
	}
	imageStore(dst, p, vec4(v));
}
