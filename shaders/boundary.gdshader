shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// A near-field sensor warning, rather than a visible cage in space. The arena
// still owns a boundary node, but distant combat has a clear astronomical sky.
uniform vec3 line_color : source_color = vec3(0.36, 0.31, 0.21);
uniform vec3 warn_color : source_color = vec3(0.72, 0.26, 0.08);
uniform float danger : hint_range(0.0, 1.0) = 0.0;
uniform float fade_distance : hint_range(10.0, 900.0) = 140.0;
varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float distance_to_sensor = length(CAMERA_POSITION_WORLD - w_pos);
	float proximity = 1.0 - smoothstep(0.0, fade_distance, distance_to_sensor);
	float warning = proximity * proximity * smoothstep(0.12, 0.85, danger);
	ALBEDO = mix(line_color, warn_color, danger);
	ALPHA = warning * 0.028;
}
