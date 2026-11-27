shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D pigments : repeat_enable,filter_linear_mipmap;
void fragment(){
 vec2 q=abs(UV-vec2(0.5));
 float rim=texture(pigments,UV*1.73+vec2(0.14,0.32)).r;
 vec2 rounded=max(q-vec2(0.33),0.0);
 float ink=1.0-smoothstep(0.08,0.15,length(rounded)+(rim-0.5)*0.07);
 ALBEDO=vec3(0.14,0.076,0.036);
 ALPHA=ink*0.32;
}
