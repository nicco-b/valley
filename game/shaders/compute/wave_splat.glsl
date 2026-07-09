#[compute]
#version 450
// Tier-2.5 wave field: stamp disturbances (wading bodies, rain drops,
// wind chop) into the height field as smooth dents; the wave equation
// rings them outward next pass.
// S2 foam memory: every disturbance is a foam deposit site (the S1
// inheritance) — the same cosine stamp writes the G channel, scaled by
// strength over a floor so wind chop stays clean while strides, wakes
// and splashes each leave their own weight of curds. A second op list
// (after ops[foam_off]) deposits foam WITHOUT denting the water: the
// breaker band speaks through it. CPU mirror: WaveReference.foam_deposit.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rg16f, set = 0, binding = 0) uniform restrict image2D field;
layout(set = 0, binding = 1) buffer restrict readonly Ops { vec4 ops[]; };
layout(push_constant) uniform Push { int grid; int count; int foam_count; int foam_off; } pc;

const float FOAM_FLOOR = 0.004;  // meters of dent that deposit nothing (chop)
const float FOAM_GAIN = 25.0;    // foam per meter of dent past the floor
	// (25: a hound stride (~0.014m) lands ~3 age bands — the weakest
	// speaker must survive BOTH posterizes; the first shoot at 12 painted
	// trails the final 3-step quantize then swallowed whole.)

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= pc.grid || p.y >= pc.grid) { return; }
	vec2 v = imageLoad(field, p).rg;
	for (int i = 0; i < pc.count; i++) {
		vec4 op = ops[i];  // x, y px; z radius px; w strength m
		float d = distance(vec2(p), op.xy) / max(op.z, 1.0);
		if (d < 1.0) {
			float kern = 0.5 + 0.5 * cos(d * 3.14159265);
			v.r += op.w * kern;
			v.g += max(0.0, abs(op.w) - FOAM_FLOOR) * FOAM_GAIN * kern;
		}
	}
	for (int i = 0; i < pc.foam_count; i++) {
		vec4 op = ops[pc.foam_off + i];  // x, y px; z radius px; w foam 0..1
		float d = distance(vec2(p), op.xy) / max(op.z, 1.0);
		if (d < 1.0) {
			v.g += op.w * (0.5 + 0.5 * cos(d * 3.14159265));
		}
	}
	imageStore(field, p, vec4(clamp(v.r, -0.2, 0.2), clamp(v.g, 0.0, 1.0), 0.0, 0.0));
}
