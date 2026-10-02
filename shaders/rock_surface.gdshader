shader_type spatial;
render_mode specular_disabled;

uniform vec3 base_color : source_color = vec3(0.42, 0.38, 0.32);
uniform float body_radius = 1.0;
uniform float seed_offset = 0.0;
uniform int body_type = 0;
varying vec3 surface_position;

float hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float terrain(vec3 p) {
	return noise(p) * 0.55 + noise(p * 2.07 + 9.3) * 0.27 + noise(p * 4.13 - 4.8) * 0.12 + noise(p * 8.31) * 0.06;
}

float crater(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	float result = 0.0;
	for (int z = 0; z <= 1; z++) {
		for (int y = 0; y <= 1; y++) {
			for (int x = 0; x <= 1; x++) {
				vec3 corner = vec3(float(x), float(y), float(z));
				float h = hash(cell + corner);
				float r = 0.16 + h * 0.27;
				float d = length(f - corner) / r;
				float bowl = smoothstep(0.0, 1.0, d) - 1.0;
				float rim_distance = (d - 1.0) * 9.0;
				float rim = exp(-rim_distance * rim_distance) * 0.28;
				result += (bowl * 0.45 + rim) * smoothstep(0.24, 0.55, h);
			}
		}
	}
	return result;
}

void vertex() {
	surface_position = VERTEX / body_radius;
}

void fragment() {
	vec3 p = surface_position + vec3(seed_offset, seed_offset * 0.73, 0.0);
	float continents = terrain(p * 4.0);
	float detail = terrain(p * 32.0);
	float grit = noise(p * 180.0);
	vec3 color = base_color * (0.55 + continents * 0.85);
	if (body_type == 0) {
		color *= 0.7 + detail * 0.55 + grit * 0.2;
		color = mix(color, color * vec3(0.65, 0.7, 0.75), smoothstep(0.61, 0.8, detail));
	} else if (body_type == 1) {
		float craters = crater(p * 9.0) + crater(p * 22.0) * 0.4;
		color *= 0.8 + detail * 0.35 + grit * 0.1 + craters;
		color *= mix(0.64, 1.0, smoothstep(0.34, 0.52, continents));
	} else {
		float bands = terrain(p * vec3(9.0, 26.0, 9.0) + detail * 0.7);
		vec3 basalt = vec3(0.14, 0.16, 0.18);
		vec3 sand = base_color * vec3(1.18, 1.04, 0.87);
		color = mix(basalt, sand, smoothstep(0.3, 0.63, continents));
		color *= 0.72 + bands * 0.4 + detail * 0.2 + grit * 0.1;
	}
	ALBEDO = color;
	ROUGHNESS = 0.96;
}
