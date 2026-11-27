shader_type spatial;
render_mode specular_disabled;
#include "res://modules/render/gles_colour.gdshaderinc"
#include "res://modules/render/ground_shade.gdshaderinc"
// Linear packed paint: pigment clouds, small soil inclusions, grass strokes.
uniform sampler2D pigments : repeat_enable,filter_linear_mipmap;
// Parcel-local coverage, 0=grass, 0.54=earth, 1=worn path (no colour-space conversion).
uniform sampler2D field_mask : repeat_disable,filter_linear;
uniform vec2 parcel_metres = vec2(1.0);
uniform vec4 clearing_color : source_color = vec4(1.0);
uniform vec3 grass_sun : source_color = vec3(0.68,0.78,0.29);
uniform vec3 grass_shade : source_color = vec3(0.48,0.64,0.24);
uniform vec3 earth : source_color = vec3(0.93,0.77,0.57);
uniform vec3 path : source_color = vec3(0.98,0.84,0.66);
uniform bool grid_overlay = false;
varying vec2 world_xz;
varying vec2 field_uv;
varying vec3 leaf_color;
varying float wash_level;
varying float shade;
void vertex(){
 world_xz=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz;
 // These broad pigment clouds span many cells. Sample them once per vertex;
 // keep the narrow meandering edge and the grain at pixel resolution.
 wash_level=textureLod(pigments,world_xz*0.055+vec2(0.31,0.67),1.0).r;
 field_uv=world_xz*vec2(1.,-1.)/parcel_metres+0.5;
 leaf_color=mix(src_linear(grass_shade),src_linear(grass_sun),smoothstep(0.22,0.78,wash_level));
}
void fragment(){
 vec3 gain=src_linear4(clearing_color).rgb;
 if(!grid_overlay){
  vec3 detail=texture(pigments,world_xz*0.25).rgb;
  vec2 bend=(vec2(detail.r,wash_level)-0.5)*0.92;
  float cover=texture(field_mask,field_uv+bend/parcel_metres).r+(detail.r-0.5)*0.16;
  vec3 grass=leaf_color*(0.88+0.24*detail.b);
  vec3 loam=mix(src_linear(earth),src_linear(path),smoothstep(0.59,0.96,cover));
  loam*=0.85+0.18*wash_level+0.14*detail.r+(detail.g-0.5)*0.65;
  gain*=mix(grass,loam,smoothstep(0.21,0.34,cover));
 }
 ALBEDO=albedo_out(gain);
 ROUGHNESS=1.0;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
 shade=ground_shade(world_xz);
#else
 shade=0.0;
#endif
}
void light(){
 float ndl=max(dot(NORMAL,LIGHT),0.0);
 float att=shade_att(ATTENUATION,shade);
 DIFFUSE_LIGHT+=ndl*mix(vec3(0.025,0.045,0.085),vec3(1.),att)*LIGHT_COLOR/PI;
}
