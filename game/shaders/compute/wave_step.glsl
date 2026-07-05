#[compute]
#version 450
// Tier-2.5 wave field: one damped wave-equation step (Verlet in time,
// 5-point Laplacian in space). k = c^2*dt^2/dx^2, stable well under 0.5;
// damping bleeds energy so pools go still. Out-of-window reads clamp to
// the cell itself (zero-gradient boundary), and the renderer fades the
// window edge, so the border never shows.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D prev;
layout(r32f, set = 0, binding = 1) uniform restrict readonly image2D curr;
layout(r32f, set = 0, binding = 2) uniform restrict writeonly image2D next;
layout(push_constant) uniform Push { int grid; float k; float damp; float pad; } pc;

float at(ivec2 p, float c) {
	if (p.x < 0 || p.y < 0 || p.x >= pc.grid || p.y >= pc.grid) { return c; }
	return imageLoad(curr, p).r;
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= pc.grid || p.y >= pc.grid) { return; }
	float c = imageLoad(curr, p).r;
	float lap = at(p + ivec2(1, 0), c) + at(p + ivec2(-1, 0), c)
		+ at(p + ivec2(0, 1), c) + at(p + ivec2(0, -1), c) - 4.0 * c;
	float n = (2.0 * c - imageLoad(prev, p).r + pc.k * lap) * pc.damp;
	imageStore(next, p, vec4(n));
}
