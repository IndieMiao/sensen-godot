shader_type spatial;
render_mode diffuse_burley, specular_disabled;

// 农场地面：一张 64×64 的状态纹理决定每格长什么样。逐格动作图标退役后，
// 「这块地处在哪一步」全靠这里的颜色差异传达——翻过的土是深棕垄沟，浇过水的更深，
// 能收的那格地面泛一圈暖光。绘制永远是 1 个 draw call，与格数无关。
//
// 通道（与 modules/farm/plot_surface.gd 对应）：
//   R 地面类型 0 草 / 1 土 / 2 路 / 3 不可通行
//   G 格状态   0 未开垦 / 1 已开垦 / 2 已播种 / 3 生长中 / 4 可收割
//   B 湿度     0..1
//   A 高亮     0 无 / 1 队列 / 2 刷子 / 3 当前作业

uniform sampler2D plot_state : filter_nearest, repeat_disable;
uniform sampler2D terrain_mask : filter_linear_mipmap, repeat_disable;
uniform sampler2D bank_grass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D meadow_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform vec2 grid_size = vec2(64.0, 64.0);
uniform float cell_m = 0.5;
uniform float woodland_start = 25.0;

uniform vec3 grass_color : source_color = vec3(0.60, 0.74, 0.37);
uniform vec3 path_color : source_color = vec3(0.89, 0.80, 0.58);
uniform vec3 soil_dry : source_color = vec3(0.55, 0.38, 0.23);
uniform vec3 soil_wet : source_color = vec3(0.30, 0.20, 0.12);
uniform vec3 ripe_glow : source_color = vec3(1.0, 0.82, 0.35);
uniform vec3 shore_color : source_color = vec3(0.73, 0.69, 0.49);
uniform vec4 water_basin = vec4(9.0, -30.75, 3.6, 2.325);

varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

// 世界坐标 → 格坐标。与 FarmBlueprint.cell_to_world 互逆：x = (i+0.5)*cell, z = -(j+0.5)*cell
vec2 cell_uv(vec2 world) {
	return vec2(world.x / cell_m, -world.y / cell_m) / grid_size;
}

float earth_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float earth_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 t = fract(p);
	t = t * t * (3.0 - 2.0 * t);
	return mix(mix(earth_hash(cell), earth_hash(cell + vec2(1.0, 0.0)), t.x),
		mix(earth_hash(cell + vec2(0.0, 1.0)), earth_hash(cell + vec2(1.0)), t.x), t.y);
}

void fragment() {
	vec2 uv = cell_uv(world_position);
	vec4 st = texture(plot_state, uv);
	int kind = int(round(st.r * 255.0));
	int state = int(round(st.g * 255.0));
	float moisture = st.b;

	float grain = texture(meadow_texture, world_position * 1.8).g;
	vec3 paint = texture(meadow_texture, world_position * 0.075).rgb;
	vec3 meadow = mix(grass_color, paint, 0.50) * (0.94 + grain * 0.12);
	float woodland = smoothstep(woodland_start, woodland_start + 4.5, -world_position.y + (grain - 0.45) * 1.2);
	meadow *= mix(vec3(1.0), vec3(0.50, 0.72, 0.76), woodland);
	vec3 albedo = meadow;
	vec2 within = fract(uv * grid_size);

	// The road is a continuous painted curve. Grid occupancy only decides actions.
	vec2 warp = vec2(texture(meadow_texture, world_position * 0.31).r - 0.5,
		texture(meadow_texture, world_position * 0.31 + vec2(0.4, 0.7)).b - 0.5);
	vec2 terrain_uv = uv + warp * 0.0045;
	vec2 verge = vec2(0.16) / (grid_size * cell_m);
	vec3 terrain = texture(terrain_mask, terrain_uv).rgb * 0.40;
	terrain += (texture(terrain_mask, terrain_uv + vec2(verge.x, 0.0)).rgb
		+ texture(terrain_mask, terrain_uv - vec2(verge.x, 0.0)).rgb
		+ texture(terrain_mask, terrain_uv + vec2(0.0, verge.y)).rgb
		+ texture(terrain_mask, terrain_uv - vec2(0.0, verge.y)).rgb) * 0.15;
	float trail = smoothstep(0.03, 0.97, terrain.r);
	float worn_center = smoothstep(0.45, 0.94, terrain.r);
	// Compacted earth has broad wear patches, finer grit and tiny pale stones.
	// The material stays continuous across all real road segments and joins.
	float wear = earth_noise(world_position * 1.15);
	float grit = earth_noise(world_position * 23.0);
	vec3 sand = path_color * vec3(0.94, 0.91, 0.83) * (0.91 + wear * 0.14 + grit * 0.06);
	sand *= mix(0.92, 1.03, worn_center);
	vec2 pebble_cell = world_position * 8.0;
	float pebble_seed = earth_hash(floor(pebble_cell));
	vec2 pebble_position = fract(pebble_cell) - vec2(0.33 + pebble_seed * 0.31, 0.40);
	float pebble = (1.0 - smoothstep(0.045, 0.14, length(pebble_position * vec2(1.0, 1.45)))) * step(0.77, pebble_seed);
	sand = mix(sand, path_color * vec3(1.02, 0.99, 0.91), pebble * 0.34);
	albedo = mix(meadow, sand, trail);
	// Bedrock and ponds have soft, irregular shores instead of grey grid rectangles.
	vec3 rock = mix(meadow, vec3(0.48, 0.52, 0.39), 0.20) * (0.94 + grain * 0.12);
	albedo = mix(albedo, rock, smoothstep(0.10, 0.95, terrain.g));
	// Match the rendered basin exactly; the legacy terrain mask becomes dry/wet bank.
	float bank_distance = (length((world_position - water_basin.xy) / water_basin.zw) - 1.0) * min(water_basin.z, water_basin.w);
	float shore = 1.0 - smoothstep(0.0, 0.11 + grain * 0.16, bank_distance);
	float bank_detail = 1.0 - smoothstep(0.5, 5.0, abs(bank_distance));
	vec3 grass_detail = texture(bank_grass, world_position * 1.05).rgb;
	albedo = mix(albedo, grass_detail * 1.18, bank_detail * (1.0 - trail) * 0.58);
	vec3 bank = shore_color * (0.74 + grain * 0.16);
	bank *= mix(0.64, 1.0, smoothstep(-0.03, 0.24, bank_distance));
	albedo = mix(albedo, bank, shore);
	if (state > 0) {
		// Adjacent cultivated cells share a bed; only exposed borders have a rounded soil lip.
		vec2 half_size = vec2(0.5);
		vec2 center = vec2(0.5);
		for (int axis = 0; axis < 2; axis++) {
			vec2 offset = axis == 0 ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
			float low = texture(plot_state, uv - offset / grid_size).g > 0.001 ? -0.5 : 0.07;
			float high = texture(plot_state, uv + offset / grid_size).g > 0.001 ? 1.5 : 0.93;
			half_size[axis] = (high - low) * 0.5;
			center[axis] = (high + low) * 0.5;
		}
		vec2 edge = abs(within - center) - half_size + vec2(0.18);
		float distance = length(max(edge, vec2(0.0))) + min(max(edge.x, edge.y), 0.0) - 0.18;
		float furrow = 0.93 + 0.07 * smoothstep(0.24, 0.48, abs(fract(within.x * 3.0) - 0.5));
		vec3 soil = mix(soil_dry, soil_wet, moisture * 0.72) * furrow * (0.90 + grain * 0.22);
		float lip = smoothstep(-0.13, -0.035, distance);
		soil *= 1.0 - lip * 0.20;
		albedo = mix(meadow, soil, 1.0 - smoothstep(-0.018, 0.014, distance));
	}

	// 可收割：地面透一圈暖光。远处可见、不随距离变大，取代过去每格一个的收割图标。
	if (state == 4) {
		float pulse = 0.5 + 0.5 * sin(TIME * 2.2);
		vec2 ring_position = within - 0.5;
		float ring = smoothstep(0.24, 0.44, length(ring_position));
		EMISSION = ripe_glow * ring * (0.12 + 0.10 * pulse);
	}

	// 交互高亮：薄荷色描边。刷子命中比队列更亮，当前作业格最亮。
	int flag = int(round(st.a * 255.0));
	if (flag > 0) {
		vec2 border_position = abs(within - 0.5);
		float edge = smoothstep(0.34, 0.48, max(border_position.x, border_position.y));
		float strength = float(flag) * 0.14;
		albedo = mix(albedo, vec3(0.62, 0.93, 0.74), edge * strength);
	}

	ALBEDO = albedo;
	ROUGHNESS = 1.0;
}
