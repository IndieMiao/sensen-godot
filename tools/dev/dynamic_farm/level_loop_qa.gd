extends "res://tools/dev/dynamic_farm/trade_loop_qa.gd"
## Emulator QA entry for farm levels (C-152), on the trading loop's stand-in for the map (trade_loop_qa.gd): the
## Washington Square room (Scott's Upgrade Farm) and the player's own parcel on one device save. On first start the
## parcel is saved welcomed with the hoe, the cottage and well blueprints, the pail, 100 coins, 12 Stone and 15 Timber:
## Lv2 goes at once, Lv3 is one Timber short (`Need 1 more Timber`) until a tree of the outer ring is picked, and Lv3's
## second well and 220 Max Energy show in the parcel. Staged only by gather_qa_apk.sh with GATHER_QA_ENTRY=level.
const LEVEL_BAG := {"hoe_starter": 1, "seed_carrot": 3, "blueprint_cottage": 1, "blueprint_well": 1, "pail": 1, "wood": 15, "stone": 12}

func start_save() -> Dictionary:
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	return {"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": LEVEL_BAG, "welcomed_at": now,
		"coins": 100, "grants": {"watering": now}}

func status(f: Dictionary) -> String:
	var bag: Dictionary = f.get("bag", {})
	return "QA · Lv%d · %d coins · %d Timber · %d Stone" % [ParcelFarm.farm_level(f), int(f.get("coins", 0)),
		int(bag.get("wood", 0)), int(bag.get("stone", 0))]
