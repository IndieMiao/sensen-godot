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
	return cfg if cfg != null else slot_table.default_config()

func save_outfit(config: AvatarConfig) -> Error:
	return store.save_outfit(user_id, config)
