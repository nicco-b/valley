shader_type spatial;
// Y-billboard flora with gentle wind sway. Replicates BaseMaterial3D's
// fixed-Y billboard + keep-scale, then displaces vertices toward the top
// of the card, phase-offset by world position so instances don't sync.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
global uniform float wind_strength; // Weather publishes this (0..1)
global uniform float flora_vitality; // FloraLife publishes this (0..1)

void vertex() {
	float h = 1.0 - UV.y; // 1 at the top of the card, 0 at the root
	float phase = MODEL_MATRIX[3].x * 0.71 + MODEL_MATRIX[3].z * 1.33;
	float amp = 0.02 + 0.14 * wind_strength;
	float spd = 0.7 + 1.6 * wind_strength;
	VERTEX.x += (sin(TIME * spd + phase)
			+ 0.4 * sin(TIME * spd * 2.7 + phase * 1.7))
			* amp * h * h;

	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
			vec4(0.0, 1.0, 0.0, 0.0),
			vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
			MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	// Lifecycle: low vitality dries the paint toward straw (keeps the
	// painting's value structure, shifts its hue) — the whole valley
	// greens and browns with FloraLife.
	vec3 dry = vec3(dot(tex.rgb, vec3(0.333))) * vec3(1.12, 0.94, 0.62);
	ALBEDO = mix(dry, tex.rgb, 0.4 + 0.6 * flora_vitality);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}
