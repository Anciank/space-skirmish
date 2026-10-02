shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.38, 0.61, 0.83);
uniform float density = 0.35;

void fragment() {
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float rim = pow(1.0 - facing, 5.5);
	ALBEDO = tint * 0.75;
	ALPHA = rim * density;
}
