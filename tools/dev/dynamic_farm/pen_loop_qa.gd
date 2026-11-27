extends "res://tools/dev/dynamic_farm/trade_loop_qa.gd"
## Emulator QA entry for the sheep pen (C-182), on the trading loop's stand-in for the map (trade_loop_qa.gd): the
## Washington Square room (Scott, the Request Board, Jasmine) and the player's own parcel on one device save. On first
## start the parcel is saved one step short of each unlock (SEN-Q-282): 14 delivered requests at farm level 2, a carrot
## request (3) on the board with the 3 carrots for it, 1,460 coins, 25 Timber, 23 Stone and 3 Wild Herbs, its core
## obstacles cleared (as a player clears them before building, C-192's W-659 did the same by hand). Delivering the
## request (+46) makes 15, upgrading to Lv3 (300 coins, 10 Timber, 8 Stone) opens the blueprint, which then costs the
## 1,200 left; the pen's 15 Timber and 15 Stone and one feeding remain. Staged only by gather_qa_apk.sh with
## GATHER_QA_ENTRY=pen.
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")
const PEN_BAG := {"hoe_starter": 1, "crop_carrot": 3, "wood": 25, "stone": 23, "wild_herb": 3}

func start_save() -> Dictionary:
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
	return {"v": 1, "house": null, "cleared": cleared, "tilled": [], "crops": {}, "bag": PEN_BAG, "welcomed_at": now,
		"coins": 1460, "level": 2, "requests_done": 14, "grants": {"watering": now},
		"board": {"slots": [
			{"req": {"id": 1, "template": "fresh_greens", "item": "crop_carrot", "qty": 3, "bonus": 10, "drawn_at": now, "status": "open"}, "refill_at": now},
			{"req": {"id": 2, "template": "stone_order", "item": "stone", "qty": 40, "bonus": 10, "drawn_at": now, "status": "open"}, "refill_at": now},
		], "seq": 2, "day": null, "done_today": 0, "bonus_today": 0}}

func status(f: Dictionary) -> String:
	var bag: Dictionary = f.get("bag", {})
	return "QA · Lv%d · %d done · %d coins · %d herbs · %d wool" % [ParcelFarm.farm_level(f), int(f.get("requests_done", 0)),
		int(f.get("coins", 0)), int(bag.get("wild_herb", 0)), int(bag.get("wool", 0))]
