// Carrots shaken by a passing player and ripe ones swaying (C-141, the design owner-confirmed on C-140:
// attachment-1069, SEN-Q-321). A vertex bend only: no physics, no extra nodes or draws.
// One material per plant stage layer of ParcelCropArt (C-139's painted carrot meshes; one MultiMesh per stage and 4 × 4
// cell chunk since C-208, every chunk at the layer's origin, so MODEL_MATRIX is the plant's own placement).
// Mesh local space: the plant stands on y = plant_base .. plant_top; instance transform = a turn about Y × the cell's
// scale, origin on the ground. INSTANCE_CUSTOM: xy = push direction (world XZ; its length is the stage's amplitude
// factor, 0 = no shake), z = trigger time on shake_clock (s), w unused. GLES3 keeps custom data as truncated half
// floats (V-652), so shakes run on their own clock wrapping every 64 s and the CPU writes trigger times on a 1/32 s
// grid (ParcelCropArt.shake_stamp), exact in a half float; the ripe sway keeps the unbounded float32 crop_clock.
// The ripe sway is this layer's `ripe` (only the Maturity layer has it on): every instance on one stage layer shares
// that flag, so it is not written per plant.
// The fragment draws what the imported StandardMaterial3D draws (painted atlas, roughness 0.9, both faces).
shader_type spatial;
// The imported StandardMaterial3D's render modes, spelled out so the defaults cannot drift apart.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://modules/render/gles_colour.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 0.9;

uniform float crop_clock = 0.0;          // written by the CPU every frame (s), drives the ripe sway
uniform float shake_clock = 0.0;         // crop_clock wrapped to [0, shake_wrap): the trigger times use this clock
uniform float shake_wrap = 64.0;         // = ParcelCropArt.SHAKE_WRAP_S
uniform bool sway_enabled = true;
uniform bool ripe = false;               // this layer's plants are ripe: they sway
uniform float plant_base = 0.0;          // this stage mesh's lowest local y
uniform float plant_top = 1.0;           // and highest
uniform float shake_amp = 0.34;          // rad, damped sine amplitude; first peak ≈ 0.235 rad ≈ 13.5°
uniform float shake_freq = 2.2;          // Hz
uniform float shake_decay = 3.3;         // 1/s, below 1° after about 1.0 s
uniform float shake_len = 1.2;           // s, not evaluated after this
uniform float sway_amp = 0.087;          // rad ≈ 5°
uniform float sway_period = 2.6;         // s
uniform float sway_wave = 0.9;           // phase per metre along the wind (rad/m): a gust sweeping the field
uniform vec2 wind_dir = vec2(0.8, -0.6); // world XZ, normalised
uniform float bend_start = 0.3;          // height share below which nothing moves (the carrot's shoulder)

void vertex() {
	if (sway_enabled) {
		vec4 c = INSTANCE_CUSTOM;
		vec2 lean = vec2(0.0);
		float t = mod(shake_clock - c.z, shake_wrap);
		if (t >= 0.0 && t < shake_len) {
			lean += c.xy * shake_amp * exp(-shake_decay * t) * sin(6.2831853 * shake_freq * t);
		}
		vec3 origin = MODEL_MATRIX[3].xyz;
		if (ripe) {
			float jitter = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453);
			float phase = 6.2831853 * crop_clock / sway_period - dot(origin.xz, wind_dir) * sway_wave - jitter * 1.2;
			vec2 side = vec2(-wind_dir.y, wind_dir.x);
			lean += (wind_dir * sin(phase) + side * 0.3 * cos(phase * 0.7)) * sway_amp;
		}
		// A young plant at rest (no shake, no sway) skips the bend: the same for every vertex of the instance.
		if (lean.x != 0.0 || lean.y != 0.0) {
			float height = max(plant_top - plant_base, 0.001);
			float w = clamp(((VERTEX.y - plant_base) / height - bend_start) / (1.0 - bend_start), 0.0, 1.0);
			w *= w;
			vec3 col0 = MODEL_MATRIX[0].xyz;
			vec3 col1 = MODEL_MATRIX[1].xyz;
			vec3 col2 = MODEL_MATRIX[2].xyz;
			// World offset = lean × weight × the plant's world height; back to local through the orthogonal columns.
			vec3 off = vec3(lean.x, 0.0, lean.y) * w * height * length(col1);
			VERTEX.x += dot(off, col0) / dot(col0, col0);
			VERTEX.z += dot(off, col2) / dot(col2, col2);
			VERTEX.y -= 0.5 * dot(lean, lean) * w * height;   // sink a little while bent so tips do not stretch
		}
	}
}

void fragment() {
	vec4 painted = texture(albedo_tex, UV);
	ALBEDO = albedo_out(src_linear(painted.rgb) * src_linear(albedo.rgb));
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
