shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.48, 0.71, 0.84);
uniform vec3 hit_direction = vec3(0.0, 0.0, -1.0);
uniform float pulse = 0.0;
varying vec3 local_dir;

void vertex() {
	local_dir = normalize(VERTEX);
}

void fragment() {
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.0);
	float remaining = clamp(pulse, 0.0, 1.0);
	float age = 1.0 - remaining;
	float separation = acos(clamp(dot(normalize(local_dir), normalize(hit_direction)), -1.0, 1.0));
	float ring_radius = 0.025 + age * 0.68;
	float ring_distance = (separation - ring_radius) / 0.045;
	float ring = exp(-ring_distance * ring_distance);
	float core = exp(-separation * separation * 90.0) * pow(remaining, 4.0);
	float local_mask = 1.0 - smoothstep(0.55, 0.83, separation);
	ALBEDO = tint * 1.3;
	ALPHA = (ring * 0.33 * remaining + core * 0.38) * local_mask * (0.7 + rim * 0.3);
}
