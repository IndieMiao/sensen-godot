extends SceneTree
## C-191: the Request Board at the Washington Square Travel Post. The client copy of the rules against the server on
## the shared cases (fixtures/request_cases.json, also run by server/test/parcels/requests.test.ts) and the hash's
## reference values; the local stand-in answers reads with the board settled; the drawer (parcel_board.gd through
## parcel_town.gd): Track, Deliver (the coins, the bag, the slot refilled at once), the gaps on the key, the request
## sheet, Drop request and Dropped, the day's cap.
##   godot --headless --path "$QA" --script res://tests/dynamic_farm/test_parcel_board.gd
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
## Loaded at run time: these use autoloads (Avatar, Localization), which a preload here would compile before.
var Town: GDScript
var Board: GDScript
const T0 := 1795406400000
const H := 3600000
const DIR := "user://test_parcel_board"
const PARCEL := "p-3512001"
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)

func _run() -> void:
	Town = load("res://scenes/dynamic_farm/parcel_town.gd")
	Board = load("res://scenes/dynamic_farm/parcel_board.gd")
	_clean()
	_rules()
	_hash()
	_cases()
	_saves()
	_store()
	_model()
	await _drawer()
	await _drop()
	_clean()
	print("PARCEL_BOARD checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _clean() -> void:
	if not DirAccess.dir_exists_absolute(DIR): return
	for name in DirAccess.get_files_at(DIR): DirAccess.remove_absolute(DIR.path_join(name))

## The shipped requests as the server reads them; malformed ones are refused as the server refuses them.
func _rules() -> void:
	var q: Dictionary = ParcelFarm.rules().requests
	_check(q.slots == 2 and q.done_refill_seconds == 0 and q.drop_refill_seconds == 8 * 3600 and q.expire_seconds == 72 * 3600
		and q.daily_max == 6 and q.daily_bonus_max == 100 and q.floor_percent == 100, "rules: 2 slots, at once / 8 h / 72 h, 6 a day, 100, Jasmine's price")
	# C-197 (SEN-Q-281): count and bonus by item, Lv3 and below / Lv4 on.
	var band := func(low: Array, high: Array, bonus: int) -> Array:
		return [{"level": 1, "qty": low, "bonus": bonus}, {"level": 4, "qty": high, "bonus": bonus}]
	_check(q.item_tiers == {"crop_carrot": band.call([3, 5], [5, 8], 10), "wood": band.call([4, 6], [6, 10], 10), "stone": band.call([4, 6], [6, 10], 10),
		"egg": band.call([2, 3], [3, 5], 20), "milk": band.call([1, 2], [2, 3], 20), "wool": band.call([1, 2], [2, 3], 20)},
		"rules: SEN-Q-281's counts and bonuses by item (%s)" % [q.item_tiers])
	_check(q.tiers == band.call([3, 5], [5, 8], 10), "rules: the shared tiers (for an item with none of its own)")
	_check(q.templates.keys() == ["fresh_greens", "timber_run", "stone_order", "egg_basket", "fresh_milk"] and q.templates.egg_basket == {"item": "egg", "building": "coop"}
		and q.templates.fresh_milk == {"item": "milk", "building": "barn"},
		"rules: carrots, timber, stone, eggs with a coop and milk with a barn (C-192), in the file's order")
	var rules := ParcelFarm.rules()
	_check(["crop_carrot", "wood", "stone", "egg", "milk"].map(func(i): return ParcelFarm.floor_price(rules, i)) == [12, 2, 2, 20, 45],
		"prices 12 / 2 / 2 / 20 / 45, Jasmine's own")
	for pair in [["fresh_greens", "crop_carrot"], ["timber_run", "wood"], ["stone_order", "stone"], ["egg_basket", "egg"], ["fresh_milk", "milk"]]:
		for level in [1, 3, 4, 7]:
			_check(ParcelFarm.tier_for(rules, level, pair[0]) == q.item_tiers[pair[1]][0 if level < 4 else 1], "rules: %s at Lv%d by its item" % [pair[0], level])
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ParcelFarm.RULES_PATH))
	var bad := func(change: Callable) -> bool:
		var copy: Dictionary = raw.duplicate(true)
		change.call(copy.requests)
		return ParcelFarm.parse_rules(copy).is_empty()
	_check(not bad.call(func(_q): pass), "rules: the shipped requests parse")
	_check(bad.call(func(r): r.slots = 0), "rules: no slots refused")
	_check(bad.call(func(r): r.expire_seconds = 60), "rules: a swap under an hour refused")
	_check(bad.call(func(r): r.tiers = [{"level": 2, "qty": [2, 3], "bonus": 10}]), "rules: tiers not from Lv1 refused")
	_check(bad.call(func(r): r.tiers = [{"level": 1, "qty": [3, 2], "bonus": 10}]), "rules: a count range upside down refused")
	_check(bad.call(func(r): r.templates = {"x": {"item": "seed_carrot"}}), "rules: an item Jasmine does not buy refused")
	_check(bad.call(func(r): r.templates = {"x": {"item": "egg", "building": "pen"}}), "rules: an unknown building refused")
	_check(bad.call(func(r): r.templates.egg_basket.tiers = [{"level": 2, "qty": [1, 2], "bonus": 20}]), "rules: a template's own tiers from Lv1 too")
	_check(bad.call(func(r): r.item_tiers = []), "rules: item tiers not a map refused")
	_check(bad.call(func(r): r.item_tiers.egg = [{"level": 1, "qty": [3, 2], "bonus": 20}]), "rules: an item's count range upside down refused")
	_check(not bad.call(func(r): r.erase("item_tiers")), "rules: no item tiers is fine (the shared ones)")
	# A milk template (C-192's line) takes milk's tiers with no other change.
	var milk: Dictionary = raw.duplicate(true)
	milk.economy.sell_prices["milk"] = 45
	milk.requests.templates = {"fresh_milk": {"item": "milk"}}
	var milk_rules := ParcelFarm.parse_rules(milk)
	_check(ParcelFarm.tier_for(milk_rules, 3, "fresh_milk") == {"level": 1, "qty": [1, 2], "bonus": 20}
		and ParcelFarm.tier_for(milk_rules, 4, "fresh_milk") == {"level": 4, "qty": [2, 3], "bonus": 20}, "rules: milk 1–2 / 2–3 for +20 by its item")
	var own: Dictionary = raw.duplicate(true)
	own.requests.templates.egg_basket.tiers = [{"level": 1, "qty": [1, 1], "bonus": 20}, {"level": 4, "qty": [3, 3], "bonus": 25}]
	var own_rules := ParcelFarm.parse_rules(own)
	_check(ParcelFarm.tier_for(own_rules, 1, "egg_basket") == {"level": 1, "qty": [1, 1], "bonus": 20}
		and ParcelFarm.tier_for(own_rules, 5, "egg_basket") == {"level": 4, "qty": [3, 3], "bonus": 25}
		and ParcelFarm.tier_for(own_rules, 5, "fresh_greens") == own_rules.requests.item_tiers.crop_carrot[1], "rules: a template's own tiers, the others their item's")
	var none: Dictionary = raw.duplicate(true)
	none.erase("requests")
	var parsed := ParcelFarm.parse_rules(none)
	_check(not parsed.is_empty() and parsed.requests.is_empty(), "rules: without requests, no board")
	var s := ParcelFarm.view(parsed, ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {},
		"welcomed_at": T0}), T0)
	_check(s.board.slots.is_empty(), "rules: without requests the board stays empty")

## The same four values as server/test/parcels/requests.test.ts.
func _hash() -> void:
	var got := ["", "a", "abc", "1795406400000:0:1795406400000:1:t"].map(ParcelFarm.hash32)
	_check(got == [2872998923, 444641715, 482950588, 3549447585], "hash32 matches the server's (%s)" % [got])

func _cases() -> void:
	var rules := ParcelFarm.rules()
	var shared = JSON.parse_string(FileAccess.get_file_as_string("res://tests/dynamic_farm/fixtures/request_cases.json"))
	_check(shared is Dictionary and shared.cases.size() >= 12, "request cases: the shared fixture reads")
	for c: Dictionary in shared.cases:
		var farm := ParcelFarm.normalize(c.farm)
		var frozen := JSON.stringify(farm, "", true)
		var got := {}
		if not c.has("commands") or c.commands == null:
			var v := ParcelFarm.view(rules, farm, int(c.now))
			got = {"ok": true, "board": v.board, "bag": v.bag, "coins": v.coins, "requests_done": v.requests_done}
		else:
			var r := ParcelFarm.apply(rules, farm, c.commands, int(c.now))
			got = {"ok": true, "board": r.state.board, "bag": r.state.bag, "coins": r.state.coins, "requests_done": r.state.requests_done} \
				if r.ok else {"ok": false, "index": r.index, "code": r.code, "detail": r.get("detail", {})}
		var want := JSON.stringify(_ints(c.expect), "", true)
		_check(JSON.stringify(_ints(got), "", true) == want, "request case '%s': %s, server %s" % [c.name, JSON.stringify(_ints(got)), want])
		_check(JSON.stringify(farm, "", true) == frozen, "request case '%s': the input save is untouched" % c.name)

## The board and the count survive the save's JSON; a save from before C-191 reads with an empty board and 0.
func _saves() -> void:
	var rules := ParcelFarm.rules()
	var s := ParcelFarm.view(rules, _welcomed(), T0)
	var reread := ParcelFarm.normalize(JSON.parse_string(JSON.stringify(s)))
	_check(JSON.stringify(reread, "", true) == JSON.stringify(s, "", true), "saves: the board reads back as written")
	var old := ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {}, "welcomed_at": T0})
	_check(old.board == ParcelFarm.empty_board() and old.requests_done == 0, "saves: before C-191 an empty board, 0 done")
	var odd: Dictionary = JSON.parse_string(JSON.stringify(s))
	odd.board.slots.append({"req": {"id": "x"}, "refill_at": T0})
	odd.board.slots.append({"refill_at": T0})
	odd.board.seq = 0
	odd.requests_done = -2
	var cleaned := ParcelFarm.normalize(odd)
	_check(cleaned.board.slots.size() == 2 and cleaned.board.seq == 2 and cleaned.requests_done == 0,
		"saves: malformed slots left out, the id counter never below the board's")

## The local stand-in reads out the board settled to now, as the server's read does.
func _store() -> void:
	var store := LocalStore.new(PARCEL, DIR)
	store.now_ms = func() -> int: return T0
	store._save(_welcomed(), 1)
	var read: Dictionary = store.read()
	_check(read.farm.board.slots.size() == 2 and read.farm.board.slots.all(func(sl): return sl.req != null), "store: a read shows both requests")
	var sent: Dictionary = store.send(1, [{"type": "accept_request", "request": 1}])
	_check(sent.ok and sent.farm.board.slots[0].req.status == "accepted" and sent.farm.board.slots[0].req.id == read.farm.board.slots[0].req.id,
		"store: the request the read showed is the one the command finds")
	_clean()

## The list's rows as P0's Stall Board draws them: Track while open and short, Deliver when ready, gaps on the key.
func _model() -> void:
	var rules := ParcelFarm.rules()
	var s := _board_farm({"crop_carrot": 3})
	var m: Dictionary = Board.model(rules, s, T0 + H)
	_check(m.facts == [["Requests today", "0/6"]], "model: `Requests today 0/6` (%s)" % [m.facts])
	var carrot: Dictionary = m.cards[0]
	_check(carrot.title == "Fresh Greens" and carrot.status == "Ready to deliver" and carrot.facts == ["3 Carrots"]
		and carrot.reward == "46 coins" and carrot.command == "Deliver" and carrot.reason == ""
		and carrot.cmd == {"type": "deliver_request", "request": 1}, "model: 3 carrots in the bag, ready: Deliver · 46 coins (3 × 12 + 10) (%s)" % [carrot])
	var eggs: Dictionary = m.cards[1]
	_check(eggs.title == "Egg Basket" and eggs.status == "Tracked" and eggs.command == "Deliver" and eggs.reason == "Need 2 more Eggs"
		and eggs.cmd.is_empty() and eggs.reward == "60 coins", "model: tracked eggs, none in the bag: the gap on the key (%s)" % [eggs])
	# C-192: milk with a barn, drawn and named as the eggs: `Fresh Milk`, `2 Milk` (milk does not take an s).
	var milk_farm := _board_farm({"milk": 1})
	milk_farm.buildings.append({"id": 3, "type": "barn", "model": "cow_barn", "x": 20, "y": 10, "width": 8, "depth": 6, "rotation": 0,
		"built_at": T0, "animals": ["cow", "cow"]})
	_check(ParcelFarm.eligible_templates(rules, milk_farm).has("fresh_milk") and not ParcelFarm.eligible_templates(rules, _board_farm({})).has("fresh_milk"),
		"rules: milk is drawn only with a barn")
	milk_farm.board.slots[1].req = {"id": 2, "template": "fresh_milk", "item": "milk", "qty": 3, "bonus": 10, "drawn_at": T0, "status": "accepted"}
	var milk: Dictionary = Board.model(rules, milk_farm, T0 + H).cards[1]
	_check(milk.title == "Fresh Milk" and milk.facts == ["3 Milk"] and milk.reason == "Need 2 more Milk" and Board.noun_of("milk") == "milk",
		"model: a tracked milk request (%s)" % [milk])
	var open := _board_farm({})
	open.board.slots[1].req.status = "open"
	var o: Dictionary = Board.model(rules, open, T0 + H).cards[1]
	_check(o.status == "Open" and o.command == "Track" and o.cmd == {"type": "accept_request", "request": 2}, "model: open and short: Track")
	var capped := _board_farm({"crop_carrot": 3})
	capped.board.merge({"day": ParcelFarm.day_key(rules, T0 + H), "done_today": 6, "bonus_today": 95}, true)
	var c: Dictionary = Board.model(rules, capped, T0 + H)
	_check(c.facts == [["Requests today", "6/6"], ["Bonus today", "95/100"]] and c.cards[0].reason == "Requests today 6/6" and c.cards[0].cmd.is_empty(),
		"model: at the day's cap the key carries `Requests today 6/6` (%s)" % [c.cards[0]])
	_check(c.cards[0].reward.begins_with("41 coins · Bonus resets in "), "model: 5 of the bonus left pays 36 + 5 and says when it resets (%s)" % c.cards[0].reward)
	var waiting := _board_farm({})
	waiting.board.slots[1] = {"req": null, "refill_at": T0 + 9 * H}
	var w: Dictionary = Board.model(rules, waiting, T0 + H)
	_check(w.facts == [["Requests today", "0/6"], ["Next request", "8h"]] and w.cards.size() == 1 and w.due == T0 + 9 * H,
		"model: a dropped slot says `Next request 8h` (%s)" % [w.facts])

## The board opened from the room: the drawer, Track, Deliver (coins float, the slot refilled), the sheet.
func _drawer() -> void:
	var store := LocalStore.new(PARCEL, DIR)
	var clock := [T0 + H]
	store.now_ms = func() -> int: return clock[0]
	store._save(_board_farm({"crop_carrot": 3}), 4)
	var host := Control.new()
	host.size = Vector2(360, 800)
	root.add_child(host)
	var town: Control = Town.open(host, Town.BOARD, store, PARCEL, DIR.path_join("met.json"))
	await _settle(town)
	var board = town.board
	_check(board != null and town.card == null and board.title.text == "Request Board", "the board opens straight away, no greeting")
	_check(board.cards.size() == 2 and board.cards.has(1) and board.cards.has(2), "both requests are listed")
	var key: UiCommandButton = board.cards[1].command_button()
	_check(key.label == "Deliver" and key.reason == "", "the carrot row's key is Deliver")
	_check(board.cards[2].command_button().reason == "Need 2 more Eggs", "the egg row carries its gap")
	var sent: Dictionary = await town.board_command({"type": "deliver_request", "request": 1})
	var farm: Dictionary = store.read().farm
	_check(sent.ok and farm.coins == 46 and not farm.bag.has("crop_carrot") and farm.requests_done == 1, "Deliver: 3 carrots go, 46 coins come, the count is saved")
	_check(farm.board.slots[0].req != null and int(farm.board.slots[0].req.id) == 3, "the delivered slot shows its new request at once")
	await process_frame
	_check(town.board.cards.has(3) and not town.board.cards.has(1), "the list follows: the new request in its row")
	_check(host.find_children("*", "UiFloatText", true, false).size() == 1, "the coins float up from the key")
	board.open_request(2)
	_check(board.page == "request" and board.find_child("DropRequest", true, false) != null, "the tracked request's sheet offers Drop request")
	var header: UiObjectHeader = board.find_children("*", "UiObjectHeader", true, false)[0]
	_check(header.title == "Egg Basket" and header.state == "Tracked" and header.effect == "Bring the required eggs to the Request Board.",
		"BOARD-1: title, state and what to bring where")
	_check(town.step_back() and board.page == "list", "Back goes from the sheet to the list")
	town.close()
	await process_frame
	host.queue_free()
	_clean()

## Drop request → BOARD-3 → Dropped; the slot waits 8 h, then the read draws again.
func _drop() -> void:
	var store := LocalStore.new(PARCEL, DIR)
	var clock := [T0 + H]
	store.now_ms = func() -> int: return clock[0]
	store._save(_board_farm({}), 4)
	var host := Control.new()
	host.size = Vector2(360, 800)
	root.add_child(host)
	var town: Control = Town.open(host, Town.BOARD, store, PARCEL, DIR.path_join("met.json"))
	await _settle(town)
	var board = town.board
	board.open_request(2)
	board.confirm_drop()
	_check(board.page == "drop" and board.find_child("Drop", true, false) is UiCommandButton, "BOARD-3: the destructive Drop request")
	var dropped: Dictionary = await town.board_command({"type": "drop_request", "request": 2})
	_check(dropped.ok and board.page == "dropped", "the server took it: Dropped")
	var farm: Dictionary = store.read().farm
	_check(farm.board.slots[1].req == null and int(farm.board.slots[1].refill_at) == T0 + 9 * H, "the slot refills 8 h after the drop")
	board.back_to_list()
	_check(board.cards.size() == 1 and board.find_children("*", "Label", true, false).any(func(l): return l.text == "8h"), "the list: one request, `Next request 8h`")
	clock[0] = T0 + 9 * H
	await town._reload_board()
	_check(town.board.cards.size() == 2, "8 h later the read brings a new request")
	town.close()
	await process_frame
	host.queue_free()
	_clean()

func _settle(town: Control) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	await process_frame
	while town.busy and Time.get_ticks_msec() < deadline: await process_frame
	await process_frame

func _welcomed() -> Dictionary:
	return ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {"hoe_starter": 1}, "welcomed_at": T0})

## A farm with a coop whose board holds 3 carrots (open) and 2 eggs (tracked), drawn at T0.
func _board_farm(bag: Dictionary) -> Dictionary:
	var s := _welcomed()
	s.bag.merge(bag, true)
	s.buildings = [{"id": 2, "type": "coop", "model": "chicken_yard", "x": 10, "y": 10, "width": 7, "depth": 5, "rotation": 0, "built_at": T0,
		"animals": ["hen_white"]}]
	s.board = {"slots": [
		{"req": {"id": 1, "template": "fresh_greens", "item": "crop_carrot", "qty": 3, "bonus": 10, "drawn_at": T0, "status": "open"}, "refill_at": T0},
		{"req": {"id": 2, "template": "egg_basket", "item": "egg", "qty": 2, "bonus": 20, "drawn_at": T0, "status": "accepted"}, "refill_at": T0},
	], "seq": 2, "day": null, "done_today": 0, "bonus_today": 0}
	return s

func _ints(v: Variant) -> Variant:
	if v is float and v == floorf(v): return int(v)
	if v is Dictionary:
		var out := {}
		for k in v: out[k] = _ints(v[k])
		return out
	if v is Array: return v.map(_ints)
	return v
