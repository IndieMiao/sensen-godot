shader_type spatial;
// The P0 float's outline (不知火舞 on 231, camera unification): a screen-facing ellipse ring of fixed pixel width,
// drawn over everything, so a float behind the player's head still reads as a ring on the hair.
render_mode unshaded, depth_test_disabled, cull_disabled, blend_mix, shadows_disabled, fog_disabled;

uniform vec2 radii_px = vec2(8.0, 12.0);   // the ring's centre line on screen
uniform vec2 quad_px = vec2(24.0, 32.0);   // the quad's size on screen
uniform float width_px = 1.5;
uniform vec4 ink : source_color = vec4(0.184, 0.227, 0.2, 0.8);

void fragment() {
	vec2 p = (UV - 0.5) * quad_px;
	float k = length(p / radii_px);
	vec2 g = p / (radii_px * radii_px) / max(k, 1e-4);   // the gradient of k: distance to the ellipse ≈ |k - 1| / |∇k|
	float d = abs(k - 1.0) / max(length(g), 1e-4);
	ALBEDO = ink.rgb;
	ALPHA = ink.a * (1.0 - smoothstep(width_px * 0.5 - 0.5, width_px * 0.5 + 0.5, d));
}
