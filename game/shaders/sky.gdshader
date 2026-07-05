shader_type sky;
// Painted-gradient sky: palette colors from day_night, a big soft sun
// disc that swells and reddens at the horizon (the reference painting's
// red sun), and hash stars after dark.

uniform vec3 top_color : source_color = vec3(0.976, 0.812, 0.827);
uniform vec3 horizon_color : source_color = vec3(0.988, 0.933, 0.894);
uniform vec3 sun_color : source_color = vec3(1.0, 0.45, 0.35);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float sun_size = 0.04;
uniform float night = 0.0;
uniform float moon_light = 0.5; // illuminated fraction; full moon washes stars
global uniform float lightning_flash; // Atmosphere pulses this 0..1
global uniform float air_humidity; // Climate: humid air dims the stars

void sky() {
	float t = clamp(EYEDIR.y, 0.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(t, 0.45));
	if (EYEDIR.y < 0.0) {
		col = horizon_color * mix(1.0, 0.82, clamp(-EYEDIR.y * 2.5, 0.0, 1.0));
	}

	// Sun: hard-ish disc + soft halo.
	float d = distance(EYEDIR, normalize(sun_dir));
	col += sun_color * (smoothstep(sun_size, sun_size * 0.72, d) * 1.15
			+ exp(-d * 8.0) * 0.22);

	// Stars fade in with night.
	if (night > 0.01 && EYEDIR.y > 0.02) {
		vec2 sc = EYEDIR.xz / (EYEDIR.y + 0.35) * 28.0;
		vec2 cell = floor(sc);
		vec2 f = fract(sc) - 0.5;
		float h = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		vec2 off = vec2(fract(h * 17.0), fract(h * 91.0)) - 0.5;
		float star = step(0.82, h) * smoothstep(0.09, 0.0, length(f - off * 0.8));
		// Extinction: the moon washes stars out, and so does humid air —
		// the clearest sky of the year is a cold dry winter night.
		col += vec3(1.0, 0.96, 0.9) * star * night * (0.35 + 0.65 * fract(h * 7.0))
				* smoothstep(0.02, 0.25, EYEDIR.y)
				* (1.0 - 0.55 * moon_light)
				* (1.0 - 0.45 * clamp(air_humidity, 0.0, 1.0));
	}

	// Lightning: the whole sky blinks toward white-violet for a beat.
	col = mix(col, vec3(0.93, 0.93, 1.0), clamp(lightning_flash, 0.0, 1.0) * 0.85);
	COLOR = col;
}
