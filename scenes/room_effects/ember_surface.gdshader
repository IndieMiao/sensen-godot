shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// GLES (SGODOT-458): source_color inputs to linear where read, ALBEDO / EMISSION handed over as GLES wants them.
#include "res://modules/render/gles_colour.gdshaderinc"
uniform sampler2D room_atlas : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 ember_min = vec3(-.31,.155,-.12);
uniform vec3 ember_max = vec3(.31,.26,.35);
uniform float ember_energy = .38;
varying vec3 authored_position;
void vertex() { authored_position = VERTEX; }
void fragment() {
 vec3 base = src_linear4(texture(room_atlas, UV)).rgb;
 ALBEDO = base;
 ROUGHNESS = .80;
 SPECULAR = .28;
 vec3 inside = step(ember_min,authored_position)*step(authored_position,ember_max);
 float red_coal = step(base.g,base.r*.26)*step(base.b,base.r*.22)*step(.015,base.r);
 EMISSION = base * ember_energy * red_coal * inside.x*inside.y*inside.z;
	ALBEDO = albedo_out(ALBEDO);
	EMISSION = albedo_out(EMISSION);
}
