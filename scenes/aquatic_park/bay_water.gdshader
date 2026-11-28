shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://modules/render/gles_colour.gdshaderinc"

// R: waterline distance; G: under-deck occlusion; B: coastal shelf.
// The plane is centred on the art origin. No scene colour/depth reads.
uniform sampler2D contact_field : filter_linear, repeat_disable;
uniform vec4 offshore : source_color = vec4(0.245, 0.535, 0.685, 1.0);
uniform vec4 channel : source_color = vec4(0.273, 0.660, 0.727, 1.0);
uniform vec4 shallows : source_color = vec4(0.485, 0.796, 0.757, 1.0);
uniform vec4 spindrift : source_color = vec4(0.843, 0.902, 0.852, 1.0);
varying vec2 bay;

void vertex() {
	bay = vec2(VERTEX.x, -VERTEX.z);
}

void fragment() {
	vec2 uv = (bay + vec2(10.0, 19.0)) / 36.0;
	// The outside edge of the authoring tile carries no contact or shelf.
	vec2 inner = min(uv, 1.0 - uv);
	float inside = smoothstep(0.0, 0.055, min(inner.x, inner.y));
	vec3 field = mix(vec3(1.,1.,0.), texture(contact_field, uv).rgb, inside);
	float t = mod(TIME, 8.0) * 0.78539816;
	vec2 p = vec2(dot(bay, vec2(.9487,.3162)), dot(bay,vec2(-.3162,.9487)));
	float sweep = sin(p.x * .36 + p.y * .16 + .46 * sin(t));
	p.y += .32 * sin(.57*p.x + .43*p.y) + .22 * sin(1.13*p.x - .45*p.y + .45*sin(t));
	float swell = sin(p.y * 4.1 + .92 * sin(p.x * .76 + t) + 1.43 * sweep - t);
	float cap = sin(p.x * 1.98 + p.y * .82 + .9 * sin(p.y * 1.7 + t));
	float crests = smoothstep(.87, .995, swell) * smoothstep(.36, .94, cap) * (.52+.48*sin(p.x*.46+p.y*.33-t));
	float basin = smoothstep(-5.,17., bay.x*.67 + bay.y*.83 + 1.8*sweep);
	vec3 water = mix(src_linear(channel.rgb), src_linear(offshore.rgb), basin);
	water = mix(water, src_linear(shallows.rgb), field.b * .85);
	water *= .97 + .032 * sweep + .015 * swell;
	water *= mix(.73, 1.0, field.g);
	// Short curved laps hugging the actual pairs of pilings, not rings on open water.
	float line = .33 + .06*sin(t + bay.y*.83) + .06*sweep;
	float laps = (1.0-smoothstep(.022,.087,abs(field.r-line))) * smoothstep(-.75,.70,sin(bay.x*2.1 + bay.y*2.47 + .6*sin(t)));
	float lace = (1.0-smoothstep(.04,.19,field.r)) * (.77+.23*sweep);
	water = mix(water, src_linear(spindrift.rgb), crests*(.085+.055*field.b) + laps*.17 + lace*.28);
	ALBEDO = albedo_out(water);
	NORMAL = normalize(NORMAL + VIEW_MATRIX[0].xyz * (.018*cap) + VIEW_MATRIX[2].xyz * (.026*swell));
	ROUGHNESS = .65;
	SPECULAR = .25;
}
