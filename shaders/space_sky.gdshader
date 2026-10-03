shader_type sky;

// A distant planetary limb and dust lane establish astronomical scale. They
// live in the sky: flying a few kilometres never makes the planet move past a
// rock, and a pilot cannot collide with a painted background.
uniform float ambient_boost : hint_range(0.0, 4.0) = 1.0;
uniform vec3 nebula_color_a : source_color = vec3(0.22, 0.185, 0.145);
uniform vec3 nebula_color_b : source_color = vec3(0.11, 0.16, 0.20);
uniform float nebula_amount : hint_range(0.0, 2.0) = 0.5;
uniform vec3 sun_direction = vec3(0.86, 0.32, -0.40);
uniform vec3 sun_color : source_color = vec3(1.0, 0.91, 0.76);
uniform float sun_disc : hint_range(0.0, 1.0) = 0.25;
uniform vec3 planet_direction = vec3(-0.29, 0.16, -0.944);
uniform float planet_angular_radius : hint_range(0.0, 0.6) = 0.28;
// Godot's Compatibility sky pipeline expects sRGB COLOR, unlike its RD sky
// pipeline. arena.gd sets this from the actual rendering method at startup.
uniform bool compatibility_srgb = false;

vec3 decode_sky_srgb(vec3 color) {
	vec3 high = pow((max(color, vec3(0.0)) + 0.055) / 1.055, vec3(2.4));
	return mix(high, color / 12.92, step(color, vec3(0.04045)));
}

vec3 encode_sky_srgb(vec3 color) {
	vec3 linear = max(color, vec3(0.0));
	vec3 high = 1.055 * pow(linear, vec3(1.0 / 2.4)) - 0.055;
	return mix(high, linear * 12.92, step(linear, vec3(0.0031308)));
}

float hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float amplitude = 0.5;
	float result = 0.0;
	for (int i = 0; i < 5; i++) {
		result += amplitude * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		amplitude *= 0.5;
	}
	return result;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 light_dir = normalize(sun_direction);
	// RD linearizes source_color uniforms; Compatibility supplies their sRGB
	// values. Keep all dust and planetary lighting arithmetic in linear space.
	vec3 dust_color_a = compatibility_srgb ? decode_sky_srgb(nebula_color_a) : nebula_color_a;
	vec3 dust_color_b = compatibility_srgb ? decode_sky_srgb(nebula_color_b) : nebula_color_b;
	vec3 stellar_color = compatibility_srgb ? decode_sky_srgb(sun_color) : sun_color;
	float clouds = fbm(dir * 3.1 + vec3(3.1, 1.7, 5.3));
	float detail = fbm(dir * 8.3 - vec3(1.3, 8.2, 2.9));
	float lane = pow(max(1.0 - abs(dot(dir, normalize(vec3(0.21, 0.91, -0.36)))), 0.0), 5.0);
	float mask = smoothstep(0.36, 0.75, clouds * 0.82 + detail * 0.32) * lane;
	float dust = smoothstep(0.38, 0.70, fbm(dir * 6.4 + vec3(17, 4, 9)));
	vec3 nebula = mix(dust_color_a, dust_color_b, smoothstep(0.24, 0.74, detail));
	vec3 color = vec3(0.0025, 0.004, 0.006) + nebula * mask * (1.0 - dust * 0.82) * nebula_amount * ambient_boost * 4.0;
	float sun_dot = max(dot(dir, light_dir), 0.0);
	float disc = smoothstep(0.999980 - sun_disc * 0.000012, 0.999990, sun_dot);
	float corona = pow(sun_dot, 3500.0) * 0.10 + pow(sun_dot, 230.0) * 0.006;
	color += (disc * 9.0 + corona) * stellar_color;

	// Intersect a unit-distance sphere, then shade its curved surface with the
	// same sun vector used by arena.gd's directional light.
	vec3 center = normalize(planet_direction);
	float planet_radius = sin(planet_angular_radius);
	float alignment = dot(dir, center);
	float discriminant = alignment * alignment - (1.0 - planet_radius * planet_radius);
	if (alignment > 0.0 && discriminant > 0.0) {
		float distance_to_surface = alignment - sqrt(discriminant);
		vec3 normal = normalize(dir * distance_to_surface - center);
		vec3 map = normal + vec3(2.8, 6.1, 1.3);
		float continents = fbm(map * 3.7);
		float relief = fbm(map * 29.0);
		float land = smoothstep(0.46, 0.52, continents);
		vec3 ocean = vec3(0.016, 0.041, 0.060);
		vec3 ground = mix(vec3(0.13, 0.125, 0.108), vec3(0.28, 0.25, 0.20), relief);
		vec3 surface = mix(ocean, ground, land);
		float clouds_on_planet = smoothstep(0.56, 0.70, fbm(map * vec3(13.0, 23.0, 13.0)));
		surface = mix(surface, vec3(0.52, 0.54, 0.53), clouds_on_planet * 0.80);
		float daylight = max(dot(normal, light_dir), 0.0);
		float limb = pow(1.0 - max(dot(normal, -dir), 0.0), 3.4);
		vec3 planetary_color = surface * (0.008 + daylight * 1.9) * stellar_color;
		planetary_color += vec3(0.085, 0.15, 0.21) * limb * smoothstep(-0.18, 0.35, dot(normal, light_dir)) * 0.75;
		float coverage = smoothstep(0.0, 0.00014, discriminant);
		color = mix(color, planetary_color, coverage);
	}
	COLOR = compatibility_srgb ? encode_sky_srgb(color) : color;
}
