shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

// Reserved for genuinely distant atmospheric bodies. Local asteroid remnants
// are airless and never use this material.
uniform vec3 tint : source_color = vec3(0.24, 0.36, 0.47);
uniform float density = 0.14;
uniform vec3 sun_direction = vec3(0.86, 0.32, -0.40);
varying vec3 world_normal;

void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float rim = pow(1.0 - facing, 5.5);
	float sunlit = smoothstep(-0.10, 0.50, dot(normalize(world_normal), normalize(sun_direction)));
	ALBEDO = tint;
	ALPHA = rim * density * sunlit;
}
