shader_type canvas_item;
render_mode unshaded, blend_disabled;
// SGODOT-422 wild ground's bake (盘古; pond_wild_ground_bake.gd draws it once into a SubViewport on entering a pond): the
// painted ground top-down over bake_rect, but its large smooth light, terraces and rock sides (the baked material lays
// those on live). A 2D pass stores COLOR as it is on every renderer (Mobile, Forward+, Compatibility: no colour
// conversion, alpha written straight with blending off). No source_color here (a 2D pass converts nothing): the colours
// come in the space the full spatial shader sees them in on this renderer — linear on Mobile / Forward+, as given on
// Compatibility — so the bake holds what that shader would draw (pond_wild_ground_bake.gd).
//   rgb: the colour, sRGB-encoded (the 8-bit steps where the eye sees them; the baked shader decodes it)
//   a:   how much of it is the meadow's — the share the live light multiplies (the sand, path and pale band's rest not)
#define WILD_COLOR
#include "res://modules/ponds/pond_wild_ground_paint.gdshaderinc"
uniform vec4 bake_rect = vec4(-6.0, -24.0, 26.0, 37.0);   // x0, z0, width, depth (metres): the image's area, row 0 at z0

vec3 to_srgb(vec3 c) {
    c = clamp(c, vec3(0.0), vec3(1.0));
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void fragment() {
    vec2 p = bake_rect.xy + UV * bake_rect.zw;
    vec3 g, k;
    float s;
    wild_paint(p, 0.0, 0.0, 0.0, g, k, s);
    vec3 c = g + k;
    COLOR = vec4(to_srgb(c), clamp((g.r + g.g + g.b) / max(c.r + c.g + c.b, 1e-4), 0.0, 1.0));
}
