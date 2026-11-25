extends Node
signal outfit_saved(config: AvatarConfig)
## Autoload 名: Avatar —— avatar 模块唯一门面。
## 二期原生嵌入时，消息桥只与本类交互。

const MANIFEST_PATH := "res://assets/avatar/parts_manifest.json"
const BASE_RIG_SCENE := "res://assets/avatar/base/base_rig.tscn"
## demo 部件剔除名单。独立文件而非 manifest 字段——manifest 是管线产物会被覆写。
const DENYLIST_PATH := "res://assets/avatar/demo_denylist.json"
## NPC-only parts (SGODOT-229): in the catalogue for the outpost NPCs, out of every player pool. Separate file for
## the same reason as the denylist.
const NPC_ONLY_PATH := "res://assets/avatar/npc_only.json"

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
	var npc := catalog.apply_npc_only(PartCatalog.load_npc_only(NPC_ONLY_PATH))
	if npc > 0:
		print("AvatarService: %d NPC-only parts kept out of the player pools" % npc)
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
## 这是想要的：剔除名单上的东西不该还穿在身上。NPC-only parts (SGODOT-229) are swapped out the same way.
func _drop_missing_parts(cfg: AvatarConfig) -> void:
	for slot_def in slot_table.slots:
		var id := String(cfg.slots.get(slot_def.slot_name, ""))
		if id.is_empty() or (catalog.has_part(id) and not catalog.is_npc_only(id)):
			continue
		var replacement := slot_def.default_part if slot_def.required else ""
		cfg.slots[slot_def.slot_name] = replacement
		push_warning("AvatarService: 存档里的 %s 已不存在，%s 回落为 '%s'"
			% [id, slot_def.slot_name, replacement])

func save_outfit(config: AvatarConfig) -> Error:
	var error := store.save_outfit(user_id, config)
	if error == OK: outfit_saved.emit(config.duplicate_config())
	return error

## Starts loading the saved outfit's parts into the cache on the loader's threads, so the first rig to wear it later
## shows at once instead of waiting for a cold load (C-133: the dynamic farm map has no player of its own, so after a
## cold start its profile's figure waited ~3 s). Nothing is applied or saved; a part already cached is not asked for
## again, and one still loading is joined, not loaded twice (PartLoader). Not under Compatibility (AppRouter.sync_loads), where the loader would load on the main thread.
## The parts asked for, by id.
func warm_saved_outfit() -> Array[String]:
	var asked: Array[String] = []
	var router := get_node_or_null("/root/AppRouter")
	if loader == null or (router != null and router.sync_loads): return asked
	var cfg := load_outfit()
	for slot in slot_table.slot_names():
		var id := String(cfg.slots.get(slot, ""))
		if id.is_empty() or asked.has(id) or cache.get_part(id) != null: continue
		loader.request_part(id)
		asked.append(id)
	return asked

## Local player rigs follow committed outfits; editor drafts and remote rigs do not.
func follow_saved_outfit(rig: AvatarRig) -> void:
	rig.apply_config(load_outfit())
	outfit_saved.connect(rig.apply_config)
