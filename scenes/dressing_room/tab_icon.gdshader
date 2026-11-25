shader_type canvas_item;
// The dressing room's slot tabs (C-108; v3 C-I4): C-86 draws each tab icon once, in colour; an unselected tab shows it
// desaturated and darker (amount 1), the open one as drawn (amount 0).
uniform float amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float grey = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(c.rgb, vec3(grey) * 0.5, amount);
	COLOR = c;
}
