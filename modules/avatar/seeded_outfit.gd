class_name SeededOutfit
extends RefCounted
## 由 `avatar_ref` 生成**确定性**外观：同一座农场每次看都是同一个人。
##
## 服务端没有装扮列（spec §7.5 的 NearbyEntry 只有 avatar_ref），MVP 用它做种子跑一遍
## 与地图路人同款的随机穿搭。预置农场的 `preset_a/b` 也走这条路，只是种子固定。

const PRESET_SEEDS := {"preset_a": 20260901, "preset_b": 20260902}

static func seed_of(avatar_ref: String) -> int:
	if PRESET_SEEDS.has(avatar_ref):
		return int(PRESET_SEEDS[avatar_ref])
	return avatar_ref.hash()

static func config_for(avatar_ref: String) -> AvatarConfig:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_of(avatar_ref)
	var cfg := Avatar.slot_table.default_config()
	for slot_def in Avatar.slot_table.slots:
		var pool := Avatar.catalog.parts_for_slot(slot_def.slot_name)
		if pool.is_empty():
			continue
		if slot_def.required or rng.randf() > 0.5:
			cfg.slots[slot_def.slot_name] = pool[rng.randi_range(0, pool.size() - 1)].id
	return cfg

## 卡片上的色块：3D rig 渲进 2D 卡片太重，MVP 用一块稳定的颜色代表这个人。
static func badge_color(avatar_ref: String) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_of(avatar_ref)
	return Color.from_hsv(rng.randf(), 0.45, 0.85)

## 卡片上的短名。不发主人名字（匿名玩家没有名字，也不该有），用种子后四位区分。
static func short_name(avatar_ref: String) -> String:
	match avatar_ref:
		"preset_a": return "Sample A"
		"preset_b": return "Sample B"
	var tail := avatar_ref.trim_prefix("seed:")
	return "Farmer %s" % tail.substr(maxi(0, tail.length() - 4)).to_upper()
