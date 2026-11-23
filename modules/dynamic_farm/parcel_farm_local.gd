extends RefCounted
## A local stand-in for the parcel farm save (C-31 farm_state v1, POST /v1/parcels/mine/enter and the place_house
## command), kept in user:// per parcel. Same shapes and answers as the server, so the scene does not change when
## the real save replaces it. Results arrive through `done` callbacks, as network replies would.
const House = preload("res://modules/dynamic_farm/farm_house.gd")
const DIR := "user://dynamic_farm"
## Q-39 / Q-40: the first entry's gift.
const WELCOME_GIFT := {"hoe_starter":1, "seed_carrot":3, "blueprint_cottage":1}

var block_id := ""
var farm := {}
var _path := ""
var _now := func() -> int: return int(Time.get_unix_time_from_system() * 1000.0)

func _init(parcel_block_id: String, directory := DIR) -> void:
	block_id = parcel_block_id
	_path = directory.path_join("parcel_%s.json" % block_id.validate_filename())
	var saved = JSON.parse_string(FileAccess.get_file_as_string(_path)) if FileAccess.file_exists(_path) else null
	farm = saved if saved is Dictionary and int(saved.get("v", 0)) == 1 else empty()

static func empty() -> Dictionary:
	return {"v":1, "house":null, "cleared":[], "tilled":[], "crops":{}, "bag":{}, "welcomed_at":null}

## Opening one's own parcel: the gift the first time only.
func enter(done: Callable) -> void:
	var granted: bool = farm.welcomed_at == null
	if granted:
		for id: String in WELCOME_GIFT: farm.bag[id] = int(farm.bag.get(id, 0)) + int(WELCOME_GIFT[id])
		farm.welcomed_at = _now.call()
		_save()
	done.call({"ok":true, "granted":granted, "farm":farm.duplicate(true)})

func place_house(x: int, y: int, rotation: int, done: Callable) -> void:
	var code := ""
	var taken := House.blocked([], {"tilled":farm.tilled, "crops":farm.crops})
	if farm.house != null: code = "HOUSE_PLACED"
	elif int(farm.bag.get(House.BLUEPRINT, 0)) <= 0: code = "NO_BLUEPRINT"
	elif House.cells(Vector2i(x, y), rotation).any(func(cell: Vector2i): return taken.has(cell)): code = "CELL_OCCUPIED"
	if code != "":
		done.call({"ok":false, "code":code, "farm":farm.duplicate(true)})
		return
	farm.bag[House.BLUEPRINT] = int(farm.bag[House.BLUEPRINT]) - 1
	if farm.bag[House.BLUEPRINT] <= 0: farm.bag.erase(House.BLUEPRINT)
	farm.house = {"model":House.MODEL, "x":x, "y":y, "width":House.SIZE.x, "depth":House.SIZE.y,
		"rotation":rotation, "built_at":_now.call()}
	_save()
	done.call({"ok":true, "farm":farm.duplicate(true)})

func _save() -> void:
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(farm))
