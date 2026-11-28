extends "res://tools/dev/dynamic_farm/own_parcel_qa.gd"
## Emulator QA entry for the blueprint book (C-228): opens one's own parcel as own_parcel_qa.gd does, and on first start
## (no save for the parcel yet) saves it welcomed with its core obstacles cleared (as a player clears them before
## building; pen_loop_qa.gd does the same) and four blueprints in the bag: the cottage, the coop and the well to place
## in any order, and the barn with 20 Timber but 4 Stone, so its card reads `Need 6 more Stone`. Staged only by
## gather_qa_apk.sh with GATHER_QA_ENTRY=book; never the main scene of a delivered package.
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")
const BOOK_BAG := {"hoe_starter": 1, "pail": 1, "seed_carrot": 3, "blueprint_cottage": 1, "blueprint_coop": 1, "blueprint_well": 1,
	"blueprint_barn": 1, "wood": 20, "stone": 4}

func _ready() -> void:
	var path := str(ProjectSettings.get_setting(PARCEL_SETTING, ""))
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path)) if not path.is_empty() else null
	if raw is Dictionary:
		var store := LocalStore.new(str(raw.block_id))
		if not FileAccess.file_exists(store._path): store._save(ParcelFarm.normalize(start_save(raw)), 1)
	super()

func start_save(farm: Dictionary) -> Dictionary:
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	var cleared := []
	var data := Data.decode(farm)
	if data.ok:
		var walk := Walk.new(data)
		var planned := Scenery.plan(data, walk)
		Shade.enforce_budget(planned, data, walk)
		for item: Dictionary in planned.core_obstacles.layout:
			var key := "%d,%d" % [item.cell.x, item.cell.y]
			if not cleared.has(key): cleared.append(key)
	return {"v": 1, "house": null, "cleared": cleared, "tilled": [], "crops": {}, "bag": BOOK_BAG, "welcomed_at": now,
		"grants": {"watering": now}}
