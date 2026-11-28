extends "res://tools/dev/dynamic_farm/own_parcel_qa.gd"
## Emulator QA entry for the placement preview's start on a crowded yard (C-253): one's own parcel (gather_qa_apk.sh
## stages 711 PACIFIC AVE, p-0178001 from tests/dynamic_farm/fixtures/yard/) and on first start (no save for the parcel
## yet) a fresh yard, every core obstacle standing, with the cottage where the C-190 recording built it (19,73; on another
## parcel the save has no cottage), farm level 3, and the coop and sheep pen blueprints with the pen's 15 Timber and 15
## Stone. Build Coop / Build Sheep Pen from the book open their preview near the player with the cottage in view;
## clearing what stands there (the preview says so) lets the next preview build it beside the cottage. Nothing is
## cleared or moved by this entry. Staged only by gather_qa_apk.sh with GATHER_QA_ENTRY=yard; never the main scene of
## a delivered package.
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const YARD_BLOCK := "p-0178001"
const COTTAGE := Vector2i(19, 73)
const YARD_BAG := {"hoe_starter": 1, "pail": 1, "seed_carrot": 3, "blueprint_coop": 1, "blueprint_sheep_pen": 1,
	"wood": 15, "stone": 15}

func _ready() -> void:
	var path := str(ProjectSettings.get_setting(PARCEL_SETTING, ""))
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path)) if not path.is_empty() else null
	if raw is Dictionary:
		var store := LocalStore.new(str(raw.block_id))
		if not FileAccess.file_exists(store._path): store._save(ParcelFarm.normalize(start_save(raw)), 1)
	super()

func start_save(farm: Dictionary) -> Dictionary:
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	var house = null
	if str(farm.get("block_id", "")) == YARD_BLOCK:
		house = {"model": "cottage", "x": COTTAGE.x, "y": COTTAGE.y, "width": 3, "depth": 3, "rotation": 0, "built_at": now}
	return {"v": 1, "house": house, "cleared": [], "tilled": [], "crops": {}, "bag": YARD_BAG.duplicate(), "welcomed_at": now,
		"level": 3, "grants": {"watering": now}}
