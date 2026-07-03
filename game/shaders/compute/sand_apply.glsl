#[compute]
#version 450
// Apply this frame's displacement ops to the sand field (meters, signed).
// Each thread owns one texel; ops are few (<=64), so the loop is cheap.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict image2D sand;
layout(set = 0, binding = 1) uniform sampler2D masks; // signed atlas: 4 slots side by side
layout(std430, set = 0, binding = 2) restrict readonly buffer Ops { vec4 data[]; } ops;
// per op: data[2i]   = (center_px.x, center_px.y, yaw, strength_or_depth_m)
//         data[2i+1] = (type, aux.x, aux.y, radius_px)
layout(push_constant) uniform Push {
	int grid; int op_count; float max_delta; float _pad;
} pc;

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= pc.grid || p.y >= pc.grid) { return; }
	float v = imageLoad(sand, p).r;
	for (int i = 0; i < pc.op_count; i++) {
		vec4 a = ops.data[i * 2];
		vec4 b = ops.data[i * 2 + 1];
		vec2 d = vec2(p) + 0.5 - a.xy; // texels from the op's center
		int type = int(b.x);
		if (type <= 3) { // rotated signed footprint mask (meters in atlas)
			float c = cos(-a.z);
			float s = sin(-a.z);
			vec2 m = vec2(c * d.x - s * d.y, s * d.x + c * d.y) / 18.0 + 0.5;
			if (all(greaterThan(m, vec2(0.0))) && all(lessThan(m, vec2(1.0)))) {
				v += texture(masks, vec2((float(type) + m.x) * 0.25, m.y)).r * a.w;
			}
		} else if (type == 4) { // crater: bowl + thrown rim, mass-balanced-ish
			float dist = length(d) / b.w;
			if (dist < 1.0) { v -= a.w * (1.0 - dist * dist); }
			else if (dist < 1.5) { v += a.w * 0.9 * (1.5 - dist) * 2.0; }
		} else if (type == 5) { // plow: scoop here, throw along aux (texels)
			float dig = exp(-dot(d, d) / 18.0);
			vec2 t = d - b.yz;
			v += a.w * (exp(-dot(t, t) / 18.0) - dig);
		}
	}
	imageStore(sand, p, vec4(clamp(v, -pc.max_delta, pc.max_delta)));
}
