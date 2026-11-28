shader_type spatial;
render_mode cull_disabled;
#include "res://modules/render/gles_colour.gdshaderinc"
// Local to the active target; coarse opaque cutout avoids a transparent crown sorting pass.
uniform float coverage : hint_range(0,1) = 1.;
uniform int fracture_stage : hint_range(0,2) = 0;
uniform float flash : hint_range(0,1) = 0.;
uniform float rock_height = 1.;
uniform vec4 pigment : source_color = vec4(1.);
varying vec3 model;
void vertex(){model = VERTEX;}
void fragment(){
 if (coverage < 1. && fract(dot(floor(FRAGCOORD.xy),vec2(.75487766,.56984029))) >= coverage) discard;
 vec3 c=COLOR.rgb * src_linear(pigment.rgb);
 if(fracture_stage > 0){
  float h=model.y/rock_height;
  float seam=abs(model.x-.095+.125*h+.25*abs(h-.57)-.28*abs(h-.82)-.24*model.z);
  float secondary=abs(model.z+.06-.12*h+.30*abs(h-.38)-.19*model.x);
  float width=fracture_stage==1?.015:.029;
  float d=fracture_stage==2?min(seam,secondary):seam;
  float fissure=(1.-smoothstep(width*.60,width+fwidth(d),d))*smoothstep(fracture_stage==1?.38:.09,fracture_stage==1?.62:.30,h);
  c=mix(c,c*vec3(.26,.24,.22),fissure);
 }
 ALBEDO=albedo_out(mix(c,vec3(.94,.91,.77),flash)); ROUGHNESS=.94; SPECULAR=.18;
}
