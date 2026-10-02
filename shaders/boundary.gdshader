shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Enclosing energy shell for the arena. Two grid frequencies, a fresnel rim so
// the wall reads as a sphere from inside, and a global `danger` value the arena
// script raises as ships approach the limit.

uniform vec3 line_color : source_color = vec3(0.16, 0.62, 1.0);
uniform vec3 warn_color : source_color = vec3(1.0, 0.34, 0.22);
uniform float grid_density : hint_range(4.0, 60.0) = 18.0;
uniform float pulse_speed : hint_range(0.0, 8.0) = 1.1;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.012;
uniform float danger : hint_range(0.0, 1.0) = 0.0;
// Metres of proximity over which the wall fades in. Without this the shell
// fills the entire view the moment a ship drifts near it, which reads as a
// solid wall rather than a distant boundary.
uniform float fade_distance : hint_range(10.0, 900.0) = 320.0;
uniform float line_strength : hint_range(0.0, 2.0) = 0.55;

varying vec3 w_pos;
varying vec3 w_normal;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid_line(float coord, float thickness) {
	float g = abs(fract(coord - 0.5) - 0.5) / max(fwidth(coord), 0.0001);
	return 1.0 - min(g / thickness, 1.0);
}

void fragment() {
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - w_pos);
	float dist = length(CAMERA_POSITION_WORLD - w_pos);
	float near = 1.0 - smoothstep(0.0, fade_distance, dist);
	float fresnel = pow(1.0 - clamp(dot(normalize(w_normal), view_dir), 0.0, 1.0), 3.0);

	// Spherical parameterisation for the lat/long grid.
	vec3 d = normalize(w_pos);
	float lat = asin(clamp(d.y, -1.0, 1.0)) / PI + 0.5;
	float lon = atan(d.z, d.x) / TAU + 0.5;

	float u = lon * grid_density;
	float v = lat * grid_density;
	float major = max(grid_line(u, 1.3), grid_line(v, 1.3));

	// One finer subdivision only, and only once the wall is close enough to read.
	float u2 = u * 2.0;
	float v2 = v * 2.0;
	float minor = max(grid_line(u2, 1.1), grid_line(v2, 1.1));

	float pulse = 0.7 + 0.3 * sin(TIME * pulse_speed);
	vec3 tint = mix(line_color, warn_color, danger);

	// Grid lines fade with distance; the fresnel rim is what keeps the sphere's
	// silhouette readable from far away, when the grid itself is sub-pixel.
	float lines = (major * 0.8 + minor * 0.25 * near) * near;
	float alpha = (lines * 0.5 + fresnel * 0.10 + base_alpha) * pulse;
	alpha *= 1.0 + danger * 2.0;

	ALBEDO = tint * (lines * line_strength + fresnel * 0.25) * pulse;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
