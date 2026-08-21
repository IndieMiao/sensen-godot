extends Node
## Autoload 名: Avatar —— avatar 模块唯一门面。
## 二期原生嵌入时，消息桥只与本类交互。

const MANIFEST_PATH := "res://assets/avatar/parts_manifest.json"
const BASE_RIG_SCENE := "res://assets/avatar/base/base_rig.tscn"

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
	loader = PartLoader.new()
	loader.name = "PartLoader"
	loader.catalog = catalog
	loader.cache = cache
	add_child(loader)

func create_rig() -> AvatarRig:
	var rig := (load(BASE_RIG_SCENE) as PackedScene).instantiate() as AvatarRig
	rig.setup(loader)
	return rig

func load_outfit() -> AvatarConfig:
	var cfg := store.load_outfit(user_id)
	return cfg if cfg != null else slot_table.default_config()

func save_outfit(config: AvatarConfig) -> Error:
	return store.save_outfit(user_id, config)
