#[compute]
#version 450
// Tier-2.5 wave field: stamp disturbances (wading bodies, rain drops,
// wind chop) into the height field as smooth dents; the wave equation
// rings them outward next pass.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict image2D field;
layout(set = 0, binding = 1) buffer restrict readonly Ops { vec4 ops[]; };
layout(push_constant) uniform Push { int grid; int count; float pad0; float pad1; } pc;

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= pc.grid || p.y >= pc.grid) { return; }
	float v = imageLoad(field, p).r;
	for (int i = 0; i < pc.count; i++) {
		vec4 op = ops[i];  // x, y px; z radius px; w strength m
		float d = distance(vec2(p), op.xy) / max(op.z, 1.0);
		if (d < 1.0) {
			v += op.w * (0.5 + 0.5 * cos(d * 3.14159265));
		}
	}
	imageStore(field, p, vec4(clamp(v, -0.2, 0.2)));
}
