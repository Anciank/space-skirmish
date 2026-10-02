shader_type sky;

// Procedural deep-space backdrop: layered star fields, fbm nebula clouds with
// dust lanes, and a distant sun with a tight corona.

uniform float star_brightness : hint_range(0.0, 4.0) = 1.4;
// Boosted by the environment's ambient contribution so the sky still fills the
// frame with light; the nebula alone is too dark to read against pure black.
uniform float ambient_boost : hint_range(0.0, 4.0) = 1.0;
uniform vec3 nebula_color_a : source_color = vec3(0.34, 0.16, 0.62);
uniform vec3 nebula_color_b : source_color = vec3(0.05, 0.30, 0.62);
uniform float nebula_amount : hint_range(0.0, 2.0) = 0.55;
uniform vec3 sun_direction = vec3(0.42, 0.28, 0.86);
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.80);
uniform float sun_disc : hint_range(0.0, 1.0) = 0.25;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float amp = 0.5;
	float sum = 0.0;
	for (int i = 0; i < 5; i++) {
		sum += amp * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		amp *= 0.5;
	}
	return sum;
}

// Three octaves of star cells so the field has both sparse bright stars and a
// dense dusting of faint ones.
//
// The loop is unrolled explicitly and twinkle is passed in as an argument:
// GLSL ES 3.0 has no `continue` inside loops with this pattern on all drivers,
// and sky shaders cannot declare `m_twinkle` members, so both are avoided by
// computing each layer in its own function.
vec3 star_layer(vec3 dir, float scale, float thresh, float seed, float tw) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	vec3 local = p - cell - 0.5;
	float h = hash13(cell + seed);
	float layer = 0.0;
	if (h > thresh) {
		vec3 offset = vec3(
			hash13(cell + 1.7),
			hash13(cell + 5.3),
			hash13(cell + 8.9)) - 0.5;
		float d = length(local - offset * 0.72);
		float bright = (h - thresh) / max(1.0 - thresh, 0.001);
		// Slight colour variation: cool white through warm amber.
		vec3 tint = mix(vec3(0.72, 0.82, 1.0), vec3(1.0, 0.86, 0.66), hash13(cell + 21.0));
		layer = exp(-d * d * 320.0) * bright * tw;
		return tint * layer;
	}
	return vec3(layer);
}

vec3 starfield(vec3 dir, float tw) {
	vec3 col = vec3(0.0);
	col += star_layer(dir, 62.0, 0.982, 0.0, 0.72 + 0.28 * tw);
	col += star_layer(dir, 130.2, 0.941, 37.13, 0.78 + 0.22 * sin(tw * 3.1));
	col += star_layer(dir, 273.4, 0.900, 74.26, 0.82 + 0.18 * sin(tw * 5.7));
	return col;
}

void sky() {
	// Godot 4 sky shaders hand us the view ray directly as EYEDIR.
	vec3 dir = normalize(EYEDIR);
	// Twinkle phase, computed once and handed to the star layers.
	float tw = sin(TIME * 0.8) * 0.5 + sin(TIME * 1.9) * 0.3 + sin(TIME * 3.7) * 0.2;

	float clouds = fbm(dir * 2.1 + vec3(3.1, 1.7, 5.3));
	float detail = fbm(dir * 5.3 - vec3(1.3, 8.2, 2.9));
	float mask = smoothstep(0.34, 0.98, clouds * 0.72 + detail * 0.42);

	// Darken a slice of the cloud to fake dust lanes.
	float dust = smoothstep(0.42, 0.78, fbm(dir * 3.4 + vec3(17.0, 4.0, 9.0)));
	mask *= 1.0 - dust * 0.55;

	vec3 neb = mix(nebula_color_a, nebula_color_b, smoothstep(0.15, 0.9, detail));
	// Even the empty sky carries a faint wash so it is never pure black.
	vec3 col = vec3(0.012, 0.014, 0.030) + neb * mask * nebula_amount;

	col *= ambient_boost;
	col += starfield(dir, tw) * star_brightness;

	vec3 sun_dir = normalize(sun_direction);
	float sd = dot(dir, sun_dir);
	float disc = smoothstep(0.9993 - sun_disc * 0.0004, 0.99965, sd);
	float corona = pow(max(sd, 0.0), 900.0) * 0.9 + pow(max(sd, 0.0), 22.0) * 0.09;
	col += (disc * 2.4 + corona) * sun_color;

	COLOR = col;
}
