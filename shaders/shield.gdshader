shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.22, 0.65, 1.0);
uniform vec3 hit_direction = vec3(0.0, 0.0, -1.0);
uniform float pulse = 0.0;
varying vec3 local_dir;

void vertex() {
	local_dir = normalize(VERTEX);
}

void fragment() {
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.5);
	float patch = pow(max(dot(normalize(local_dir), hit_direction), 0.0), 5.0);
	float wave = smoothstep(0.0, 0.18, patch) * (0.6 + 0.4 * rim);
	ALBEDO = tint * 1.8;
	ALPHA = pulse * (wave * 0.3 + rim * 0.45);
}
