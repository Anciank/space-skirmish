shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.42, 0.68, 0.86);
uniform float power = 1.0;
varying float axial;

void vertex() {
	axial = clamp(VERTEX.z + 0.5, 0.0, 1.0);
}

void fragment() {
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.85);
	float along = clamp(axial, 0.0, 1.0);
	// A magnetically confined plasma plume cools along the nozzle axis.
	// No alternating shock diamonds: there is no ambient air to compress it.
	float envelope = smoothstep(0.0, 0.045, along) * pow(1.0 - along, 2.4);
	float variation = 0.95 + 0.05 * sin(TIME * 21.0 + along * 9.0);
	float core = exp(-along * 7.0);
	ALBEDO = mix(tint, vec3(0.78, 0.9, 1.0), core * 0.65) * power;
	ALPHA = envelope * edge * variation * 0.45;
}
