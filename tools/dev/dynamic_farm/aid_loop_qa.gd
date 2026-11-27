extends "res://tools/dev/dynamic_farm/board_loop_qa.gd"
## Emulator QA entry for C-197 (owner SEN-Q-281), on the Request Board's stand-in (board_loop_qa.gd): the same
## Washington Square room and parcel on one device save. On first start the parcel is saved welcomed with the hoe and
## 3 eggs only — no coins, no seeds, no crops, so Jasmine's greeting gives the seed aid (3 Carrot Seeds) — and its board
## holds a carrot request (4, +10) and an egg request (3, +20) drawn now, a QA preset within SEN-Q-281's Lv1 bands. Eggs
## do not count against the aid; delivering the eggs pays 3 × 20 + 20 = 80. Staged only by gather_qa_apk.sh with
## GATHER_QA_ENTRY=aid.
const AID_BAG := {"hoe_starter": 1, "egg": 3}

func start_save() -> Dictionary:
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	return {"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": AID_BAG, "welcomed_at": now,
		"board": {"slots": [
			{"req": {"id": 1, "template": "fresh_greens", "item": "crop_carrot", "qty": 4, "bonus": 10, "drawn_at": now, "status": "open"}, "refill_at": now},
			{"req": {"id": 2, "template": "egg_basket", "item": "egg", "qty": 3, "bonus": 20, "drawn_at": now, "status": "open"}, "refill_at": now},
		], "seq": 2, "day": null, "done_today": 0, "bonus_today": 0}}

func status(f: Dictionary) -> String:
	var bag: Dictionary = f.get("bag", {})
	return "QA · %d coins · %d seeds · %d eggs · %d done" % [int(f.get("coins", 0)), int(bag.get("seed_carrot", 0)),
		int(bag.get("egg", 0)), int(f.get("requests_done", 0))]
