extends "res://tools/dev/dynamic_farm/trade_loop_qa.gd"
## Emulator QA entry for the Request Board (C-191), on the trading loop's stand-in for the map (trade_loop_qa.gd): the
## Washington Square room (the Request Board on the left wall) and the player's own parcel on one device save. On first
## start the parcel is saved welcomed with 3 carrots and 2 eggs, and its board holds a carrot request (3) and an egg
## request (2) drawn now — a QA preset, as a coop's eggs would bring one; the draws after that are the rules' own (no
## coop in this save, so no new egg request). Staged only by gather_qa_apk.sh with GATHER_QA_ENTRY=board.
const BOARD_BAG := {"hoe_starter": 1, "crop_carrot": 3, "egg": 2}

func start_save() -> Dictionary:
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	return {"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": BOARD_BAG, "welcomed_at": now,
		"board": {"slots": [
			{"req": {"id": 1, "template": "fresh_greens", "item": "crop_carrot", "qty": 3, "bonus": 10, "drawn_at": now, "status": "open"}, "refill_at": now},
			{"req": {"id": 2, "template": "egg_basket", "item": "egg", "qty": 2, "bonus": 10, "drawn_at": now, "status": "open"}, "refill_at": now},
		], "seq": 2, "day": null, "done_today": 0, "bonus_today": 0}}

func status(f: Dictionary) -> String:
	var bag: Dictionary = f.get("bag", {})
	return "QA · %d coins · %d carrots · %d eggs · %d done" % [int(f.get("coins", 0)), int(bag.get("crop_carrot", 0)),
		int(bag.get("egg", 0)), int(f.get("requests_done", 0))]
