#[compute]
#version 450
// Tier-2.5 wave field: one damped wave-equation step (Verlet in time,
// 5-point Laplacian in space). k = c^2*dt^2/dx^2, stable well under 0.5;
// damping bleeds energy so pools go still. Out-of-window reads clamp to
// the cell itself (zero-gradient boundary), and the renderer fades the
// window edge, so the border never shows.
// S2 foam memory (G channel): each step the foam history is pulled back
// along the window drift (semi-Lagrangian, bilinear — breaker foam rides
// ashore, river foam rides downstream), decayed by a TIME-based factor
// the CPU computes as exp(-dt/tau) (a per-step constant would decay at
// whatever the frame rate happens to be — the DAMP lesson), and fed by
// travelling crests: a ring strong enough to crest re-deposits as it
// goes, so a big splash leaves a trail, not just a birthmark.
// CPU mirror: WaveReference (the sand discipline) — keep in lockstep.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rg16f, set = 0, binding = 0) uniform restrict readonly image2D prev;
layout(rg16f, set = 0, binding = 1) uniform restrict readonly image2D curr;
layout(rg16f, set = 0, binding = 2) uniform restrict writeonly image2D next;
layout(push_constant) uniform Push {
	int grid; float k; float damp; float foam_decay;
	vec2 drift; float dt; float pad;
} pc;

const float CREST_H = 0.05;    // meters of |height| before a crest feeds foam
const float CREST_GAIN = 6.0;  // foam/sec deposited by a full-rail crest

float at(ivec2 p, float c) {
	if (p.x < 0 || p.y < 0 || p.x >= pc.grid || p.y >= pc.grid) { return c; }
	return imageLoad(curr, p).r;
}

float foam_at(ivec2 p) {
	p = clamp(p, ivec2(0), ivec2(pc.grid - 1));
	return imageLoad(curr, p).g;
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= pc.grid || p.y >= pc.grid) { return; }
	float c = imageLoad(curr, p).r;
	float lap = at(p + ivec2(1, 0), c) + at(p + ivec2(-1, 0), c)
		+ at(p + ivec2(0, 1), c) + at(p + ivec2(0, -1), c) - 4.0 * c;
	float n = (2.0 * c - imageLoad(prev, p).r + pc.k * lap) * pc.damp;
	// Rails: a texel that overflows to Inf/NaN would spread through the
	// Laplacian and kill the whole field silently (freak-out -> settle ->
	// dead). Clamp hard and heal NaN to rest.
	if (isnan(n) || isinf(n)) { n = 0.0; }
	n = clamp(n, -0.2, 0.2);
	// Foam: pull back along the drift (bilinear), decay on time, let a
	// travelling crest re-deposit. Sub-texel drifts still move — the
	// bilinear weights carry the fraction frame to frame.
	float fm;
	if (pc.drift == vec2(0.0)) {
		fm = imageLoad(curr, p).g;
	} else {
		vec2 s = vec2(p) - pc.drift;
		vec2 fl = floor(s);
		vec2 fr = s - fl;
		ivec2 s0 = ivec2(fl);
		fm = mix(
			mix(foam_at(s0), foam_at(s0 + ivec2(1, 0)), fr.x),
			mix(foam_at(s0 + ivec2(0, 1)), foam_at(s0 + ivec2(1, 1)), fr.x),
			fr.y);
	}
	fm = fm * pc.foam_decay
		+ max(0.0, abs(c) - CREST_H) * CREST_GAIN * pc.dt;
	if (isnan(fm) || isinf(fm)) { fm = 0.0; }
	imageStore(next, p, vec4(n, clamp(fm, 0.0, 1.0), 0.0, 0.0));
}
