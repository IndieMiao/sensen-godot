shader_type spatial;
render_mode cull_disabled;
uniform bool foliage = true;
varying vec3 local;
void vertex() { local = VERTEX; }
void fragment() {
    if (foliage) {
        float grain = sin(local.x * 139.0 + sin(local.z * 131.0)) * sin(local.y * 113.0) * 0.012;
        float lower = smoothstep(1.05, 2.25, local.y);
        ALBEDO = COLOR.rgb * (0.88 + lower * 0.12 + grain);
        BACKLIGHT = COLOR.rgb * 0.10;
    } else {
        float angle = atan(local.z, local.x);
        float furrow = pow(0.5 + 0.5 * sin(angle * 16.0 + sin(local.y * 3.0) * 0.35), 8.0);
        float grain = sin(angle * 71.0 + local.y * 5.0) * 0.028;
        ALBEDO = COLOR.rgb * (1.02 - furrow * 0.20 + grain);
    }
    ROUGHNESS = 0.94;
    SPECULAR = 0.12;
}
