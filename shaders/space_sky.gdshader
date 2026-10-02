shader_type sky;

// Static clouds leave dark space around silhouettes. Point stars use a single
// mesh, so time does not force the environment radiance to rebuild every frame.
uniform float ambient_boost : hint_range(0.0, 4.0) = 1.0;
uniform vec3 nebula_color_a : source_color = vec3(0.34, 0.16, 0.62);
uniform vec3 nebula_color_b : source_color = vec3(0.05, 0.30, 0.62);
uniform float nebula_amount : hint_range(0.0, 2.0) = 0.5;
uniform vec3 sun_direction = vec3(0.42, 0.28, 0.86);
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.80);
uniform float sun_disc : hint_range(0.0, 1.0) = 0.25;

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
	for (int i = 0; i < 4; i++) {
		result += amplitude * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		amplitude *= 0.5;
	}
	return result;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float clouds = fbm(dir * 3.1 + vec3(3.1, 1.7, 5.3));
	float detail = fbm(dir * 8.3 - vec3(1.3, 8.2, 2.9));
	float mask = smoothstep(0.42, 0.76, clouds * 0.8 + detail * 0.3);
	float dust = smoothstep(0.36, 0.7, fbm(dir * 4.4 + vec3(17, 4, 9)));
	mask *= 1.0 - dust * 0.8;
	vec3 nebula = mix(nebula_color_a, nebula_color_b, smoothstep(0.2, 0.8, detail));
	vec3 color = vec3(0.001, 0.002, 0.006) + nebula * mask * nebula_amount * ambient_boost;
	float sun_dot = max(dot(dir, normalize(sun_direction)), 0.0);
	float disc = smoothstep(0.9993 - sun_disc * 0.0004, 0.99965, sun_dot);
	float corona = pow(sun_dot, 1000.0) * 0.3 + pow(sun_dot, 40.0) * 0.012;
	COLOR = color + (disc * 2.2 + corona) * sun_color;
}
