shader_type spatial;
render_mode unshaded, cull_disabled;
// UV.y = 0: a six-sided taper. UV.y = 1: ten mesh drops with staggered flights.
// The animation, not TIME, drives every vertex; seeking, pausing and replaying are deterministic.
uniform float beat : hint_range(0.0, 1.0) = 0.0;
uniform vec4 pool : source_color = vec4(0.32, 0.68, 0.76, 1.0);
uniform vec4 light_catcher : source_color = vec4(0.80, 0.94, 0.88, 1.0);
// Landing is stored relative to the moving lip, so the impact stays planted on one tile.
uniform vec3 landing = vec3(-0.108, -0.446, 0.246);
varying float sheen;
void vertex() {
    float t = UV.x;
    vec3 shape = VERTEX;
    vec3 fall = landing;
    if (UV.y < 0.5) {
        // Unroll from the lip; the last slug falls clear before the splash dies away.
        float head = smoothstep(0.0, 0.14, beat);
        float tail = smoothstep(0.65, 0.80, beat);
        float s = mix(tail, head, t);
        float width = (0.018 + 0.006 * s + 0.003 * sin(s * 18.0 - beat * 24.0));
        width *= smoothstep(0.0, 0.12, head - tail);
        vec3 center = vec3(fall.x*s, fall.y*s*(0.35+0.65*s), fall.z*s);
        vec3 side = vec3(0.915, 0.0, 0.404);
        vec3 tangent = normalize(vec3(fall.x, fall.y*(0.35+1.30*s), fall.z));
        VERTEX = center + width * (shape.x*side + shape.z*cross(tangent, side));
        sheen = smoothstep(-0.85, 0.93, shape.z) * (0.56 + 0.15*sin(8.0*s - 15.0*beat));
    } else {
        float spray = smoothstep(0.10, 0.24, beat) * (1.0-smoothstep(0.78, 1.0, beat));
        float age = fract(max(0.0, beat - 0.10)*2.6 + t);
        float a = t * 43.9823;
        vec2 dir = vec2(cos(a), sin(a));
        float radius = age*(0.10+0.065*fract(t*4.3));
        vec3 arc = vec3(dir.x*radius, 4.0*age*(1.0-age)*(0.065+0.080*fract(t*3.8)), dir.y*radius);
        float sz = spray * (0.012 + 0.007*fract(t*6.7)) * sin(3.14159*age);
        VERTEX = fall + arc + shape*vec3(sz, sz*1.6, sz);
        sheen = 0.55 + 0.25 * shape.y;
    }
}
void fragment() {
    ALBEDO = mix(pool.rgb, light_catcher.rgb, sheen);
}
