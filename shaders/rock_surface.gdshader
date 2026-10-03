shader_type spatial;

// Seamless mineral strata in object coordinates. Matte silicate, carbon dust
// and small exposed inclusions carry detail without emissive coloured patches.
uniform vec3 base_color : source_color = vec3(0.29, 0.28, 0.26);
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
				float rim = exp(-rim_distance * rim_distance) * 0.24;
				result += (bowl * 0.30 + rim) * smoothstep(0.24, 0.55, h);
			}
		}
	}
	return result;
}

void vertex() {
	surface_position = VERTEX / max(body_radius, 0.001);
}

void fragment() {
	vec3 p = surface_position + vec3(seed_offset, seed_offset * 0.73, 0.0);
	float strata = terrain(p * vec3(5.0, 13.0, 5.0));
	float detail = terrain(p * 38.0);
	float grit = noise(p * 160.0);
	float pits = crater(p * (body_type == 0 ? 13.0 : 20.0));
	float fracture = 1.0 - smoothstep(0.018, 0.065, abs(terrain(p * 19.0) - 0.47));
	float minerals = smoothstep(0.62, 0.78, detail) * 0.32;
	vec3 color = base_color * (0.62 + strata * 0.56 + detail * 0.23 + grit * 0.06);
	color *= 1.0 - fracture * 0.31;
	color = mix(color, vec3(0.39, 0.38, 0.35), minerals);
	color *= 1.0 + pits * 0.60;

	// Surface gradients add fine relief without relying on UV tangents. The
	// large silhouette and collision hull remain the actual mesh geometry.
	float height = (detail * 0.006 + pits * 0.009 - fracture * 0.001) * body_radius;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 gradient = sign(det) * (dFdx(height) * r1 + dFdy(height) * r2);
	NORMAL = normalize(max(abs(det), 0.000001) * NORMAL - gradient * 0.36);
	ALBEDO = color;
	ROUGHNESS = clamp(0.88 + grit * 0.11 - minerals * 0.14, 0.77, 1.0);
	METALLIC = minerals * 0.12;
	SPECULAR = 0.24;
}
