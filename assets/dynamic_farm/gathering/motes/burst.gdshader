shader_type particles;
render_mode disable_velocity;
uniform vec2 speed;
uniform vec2 diameter;
uniform float gravity;
uniform float cone;
uniform float sway_hz;
float rand01(inout uint s) {s = s * 1664525u + 1013904223u; return float(s >> 8u) / 16777216.;}
void start(){
 uint s = RANDOM_SEED ^ (NUMBER*747796405u + 2891336453u);
 float theta = rand01(s)*6.2831853; float y = mix(cos(radians(cone)),1.,rand01(s));
 float h=sqrt(max(0.,1.-y*y)); vec3 dir=vec3(cos(theta)*h,y,sin(theta)*h);
 VELOCITY=normalize(mat3(EMISSION_TRANSFORM)*dir)*mix(speed.x,speed.y,rand01(s));
 float size=mix(diameter.x,diameter.y,rand01(s)); TRANSFORM=mat4(1.);
 TRANSFORM[0].x=size; TRANSFORM[1].y=size; TRANSFORM[2].z=size;
 TRANSFORM[3]=vec4(EMISSION_TRANSFORM[3].xyz,1.);
 CUSTOM=vec4(theta,0.,rand01(s)*6.2831853,0.); COLOR=vec4(1.);
}
void process(){
 CUSTOM.w+=DELTA; float t=CUSTOM.w;
 vec3 wind=vec3(0.); if(sway_hz>0.){float p=6.2831853*sway_hz*t+CUSTOM.z;wind=vec3(cos(p),0.,sin(p))*.24;}
 TRANSFORM[3].xyz+=(VELOCITY+wind-vec3(0.,gravity*.5*DELTA,0.))*DELTA;
 VELOCITY.y-=gravity*DELTA; CUSTOM.x+=DELTA*(1.55+cos(CUSTOM.z)*3.3);
 COLOR.a=1.-smoothstep(.46,1.,t/LIFETIME);
}
