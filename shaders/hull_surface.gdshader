shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.45, 0.48, 0.5, 1.0);
uniform float metalness : hint_range(0.0, 1.0) = 0.65;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.5;
uniform vec3 impact_position = vec3(0.0);
uniform float impact_heat = 0.0;
varying vec3 local_position;
varying vec3 local_normal;

float hash3(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}
void vertex() {
    local_position = VERTEX;
    local_normal = NORMAL;
}
void fragment() {
    // Object-space machining and uneven finish: no texture seams on cached meshes.
    vec3 n = abs(local_normal);
    vec2 plane = n.y > max(n.x, n.z) ? local_position.xz :
        (n.x > n.z ? local_position.zy : local_position.xy);
    vec2 cell = plane * vec2(2.8, 4.2);
    vec2 edge = min(fract(cell), 1.0 - fract(cell));
    float seam = 1.0 - smoothstep(0.006, 0.018, min(edge.x, edge.y));
    float plate = hash3(vec3(floor(cell), 3.0));
    float grain = hash3(floor(local_position * 260.0));
    float brushed = sin(plane.y * 920.0) * 0.012;
    float wear = smoothstep(0.82, 0.98, hash3(floor(local_position * 45.0))) * 0.07;
    ALBEDO = base_color.rgb * (0.92 + plate * 0.12 + grain * 0.035 + brushed - seam * 0.16) + wear * 0.15;
    float heat = exp(-dot(local_position - impact_position, local_position - impact_position) * 4.5) * impact_heat;
    EMISSION = vec3(1.0, 0.29, 0.06) * heat;
    METALLIC = metalness;
    ROUGHNESS = clamp(surface_roughness + (grain - 0.5) * 0.07 + seam * 0.1 + wear, 0.12, 0.92);
}
