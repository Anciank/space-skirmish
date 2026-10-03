shader_type spatial;
render_mode depth_draw_opaque;

uniform vec3 base_color : source_color = vec3(0.29, 0.28, 0.26);
uniform float metalness = 0.0;
uniform float surface_roughness = 0.94;
varying vec3 surface_position;

float grain(vec3 point) {
	point = fract(point * 0.1031);
	point += dot(point, point.yzx + 33.33);
	return fract((point.x + point.y) * point.z);
}

float mineral_noise(vec3 point) {
	vec3 cell = floor(point);
	vec3 part = fract(point);
	part = part * part * (3.0 - 2.0 * part);
	return mix(mix(mix(grain(cell), grain(cell + vec3(1, 0, 0)), part.x), mix(grain(cell + vec3(0, 1, 0)), grain(cell + vec3(1, 1, 0)), part.x), part.y),
		mix(mix(grain(cell + vec3(0, 0, 1)), grain(cell + vec3(1, 0, 1)), part.x), mix(grain(cell + vec3(0, 1, 1)), grain(cell + vec3(1, 1, 1)), part.x), part.y), part.z);
}

void vertex() {
	surface_position = VERTEX;
}

void fragment() {
	float strata = mineral_noise(surface_position * vec3(11.0, 24.0, 11.0));
	float grit = mineral_noise(surface_position * 80.0);
	ALBEDO = base_color * COLOR.rgb * (0.62 + strata * 0.43 + grit * 0.15);
	ROUGHNESS = surface_roughness;
	METALLIC = metalness;
	SPECULAR = 0.24;
	ALPHA = COLOR.a;
}
