shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.18, 0.58, 1.0);
uniform float power = 1.0;
varying float axial;

void vertex() {
	axial = clamp(VERTEX.z + 0.5, 0.0, 1.0);
}

void fragment() {
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.65);
	float along = clamp(axial, 0.0, 1.0);
	float tail = 1.0 - along;
	float envelope = smoothstep(0.0, 0.07, along) * tail * tail;
	float wave = sin(along * 24.0 - TIME * 18.0);
	float diamonds = 0.72 + 0.28 * wave * wave;
	ALBEDO = mix(tint, vec3(0.68, 0.88, 1.0), 0.22) * power * diamonds;
	ALPHA = envelope * edge * 0.65;
}
