extends Node
## Autoload 名: Avatar —— avatar 模块唯一门面。
## 二期原生嵌入时，消息桥只与本类交互。

const MANIFEST_PATH := "res://assets/avatar/parts_manifest.json"
const BASE_RIG_SCENE := "res://assets/avatar/base/base_rig.tscn"
## demo 部件剔除名单。独立文件而非 manifest 字段——manifest 是管线产物会被覆写。
const DENYLIST_PATH := "res://assets/avatar/demo_denylist.json"

var slot_table: AvatarSlotTable = preload("res://modules/avatar/data/slot_table.tres")
var catalog: PartCatalog
var cache := PartCache.new()
var store := LocalOutfitStore.new()
var loader: PartLoader
var user_id := "local"

func _ready() -> void:
	catalog = PartCatalog.load_from_file(MANIFEST_PATH)
	if catalog == null:
		push_error("AvatarService: manifest 加载失败，先运行转换管线")
		catalog = PartCatalog.new()
	var denied := catalog.apply_denylist(PartCatalog.load_denylist(DENYLIST_PATH))
	if denied > 0:
		print("AvatarService: demo denylist 剔除 %d 个部件" % denied)
	loader = PartLoader.new()
	loader.name = "PartLoader"
	loader.catalog = catalog
	loader.cache = cache
	add_child(loader)

func create_rig() -> AvatarRig:
	var rig := (load(BASE_RIG_SCENE) as PackedScene).instantiate() as AvatarRig
	rig.setup(loader)
	rig.add_child(RigActivity.new())
	BlobShadow.attach(rig)
	return rig

func load_outfit() -> AvatarConfig:
	var cfg := store.load_outfit(user_id)
	if cfg == null:
		return slot_table.default_config()
	_drop_missing_parts(cfg)
	return cfg

## 把存档里已经不存在的部件换掉：必选槽回落到默认件，可选槽清空。
##
## 部件池会随版本增删（下架特殊材质件、denylist 剔除、改名），而存档是上个版本写的。
## 不清洗的话这些 id 会原样送进 rig，装配失败后弹一条 "Couldn't load ... Previous look
## kept."——2026-09-02 真机上就是这样：旧存档写着 cloth87/hairhat101，一进换装房就报错。
##
## 注意 catalog 此时已经过 denylist 过滤，所以被剔除的部件同样会在这里被换掉——
## 这是想要的：剔除名单上的东西不该还穿在身上。
func _drop_missing_parts(cfg: AvatarConfig) -> void:
	for slot_def in slot_table.slots:
		var id := String(cfg.slots.get(slot_def.slot_name, ""))
		if id.is_empty() or catalog.has_part(id):
			continue
		var replacement := slot_def.default_part if slot_def.required else ""
		cfg.slots[slot_def.slot_name] = replacement
		push_warning("AvatarService: 存档里的 %s 已不存在，%s 回落为 '%s'"
			% [id, slot_def.slot_name, replacement])

func save_outfit(config: AvatarConfig) -> Error:
	return store.save_outfit(user_id, config)

## —— 与服务端资料里的 avatar 字段互转（B7）。服务端不解释内容，只存 AvatarConfig 的 JSON 字典。——

func has_saved_outfit() -> bool:
	return store.load_outfit(user_id) != null

## 本地存档 → 可直接放进 PUT /users/me/profile {avatar} 的字典；没有存档返回空字典。
func outfit_dict() -> Dictionary:
	var cfg := store.load_outfit(user_id)
	if cfg == null:
		return {}
	return config_to_dict(cfg)

static func config_to_dict(cfg: AvatarConfig) -> Dictionary:
	var parsed = JSON.parse_string(cfg.to_json_text())
	return parsed if parsed is Dictionary else {}

static func config_from_dict(d: Variant) -> AvatarConfig:
	if not (d is Dictionary) or (d as Dictionary).is_empty():
		return null
	return AvatarConfig.from_json_text(JSON.stringify(d))

## 服务端下来的装扮落到本地（换机 / 重装后第一次登录）；缺失部件按本地部件池清洗。
func adopt_outfit(d: Variant) -> Error:
	var cfg := config_from_dict(d)
	if cfg == null:
		return ERR_INVALID_DATA
	_drop_missing_parts(cfg)
	return store.save_outfit(user_id, cfg)
