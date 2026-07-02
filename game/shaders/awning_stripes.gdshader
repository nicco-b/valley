shader_type spatial;
// Striped market-awning fabric: two palette colors in bands along
// the awning's local X. Matte, painterly, Agrabah-warm.

uniform vec3 color_a : source_color = vec3(0.91, 0.45, 0.52);
uniform vec3 color_b : source_color = vec3(0.96, 0.92, 0.84);
uniform float stripe_width = 0.35;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	float band = mod(floor(lpos.x / stripe_width), 2.0);
	ALBEDO = mix(color_a, color_b, band);
	ROUGHNESS = 1.0;
}
