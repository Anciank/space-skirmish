shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.65, 0.25, 1.0);
uniform float energy = 2.0;
uniform float opacity = 1.0;
uniform float rays : hint_range(0.0, 1.0) = 0.0;
uniform bool billboard = true;
uniform bool use_vertex_color = false;

void vertex() {
	if (billboard) {
		mat4 facing = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		facing[0].xyz *= length(MODEL_MATRIX[0].xyz);
		facing[1].xyz *= length(MODEL_MATRIX[1].xyz);
		facing[2].xyz *= length(MODEL_MATRIX[2].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * facing;
	}
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float halo = exp(-radius * radius * 12.0) * (1.0 - smoothstep(0.65, 1.0, radius));
	float core = exp(-radius * radius * 85.0);
	float star = (exp(-abs(p.x) * 90.0) + exp(-abs(p.y) * 90.0)) * pow(max(1.0 - radius, 0.0), 5.0);
	vec4 vertex_tint = use_vertex_color ? COLOR : vec4(1.0);
	ALBEDO = mix(tint.rgb, vec3(1.0), core * 0.7) * energy * vertex_tint.rgb;
	ALPHA = clamp(halo + core * 0.4 + star * rays, 0.0, 1.0) * tint.a * opacity * vertex_tint.a;
}
