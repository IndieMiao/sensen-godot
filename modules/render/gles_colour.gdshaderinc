// Colour in and out of a spatial shader alike under every renderer (SGODOT-458, 周瑜's spec).
// Compatibility (GLES3) wants the final ALBEDO / EMISSION sRGB-encoded — its scene shader turns them linear itself — and
// hands source_color textures and colours over as they are stored (sRGB); the RD renderers (Mobile, Forward+) give and
// want linear. A shader that only passes a source_color input through to ALBEDO reads the same on both; one that does
// arithmetic on colour (a factor, a mix with a constant, a linear vertex colour) does it in linear here: its source_color
// inputs through src_linear, its result through albedo_out. On the RD renderers both are the identity, compiled out.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
vec3 src_linear(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}
vec3 albedo_out(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(vec3(1.055) * pow(c, vec3(1.0 / 2.4)) - vec3(0.055), c * 12.92, lessThan(c, vec3(0.0031308)));
}
#else
vec3 src_linear(vec3 c) { return c; }
vec3 albedo_out(vec3 c) { return c; }
#endif
