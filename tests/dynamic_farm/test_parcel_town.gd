extends SceneTree
## C-59: the market (Jasmine) and the carpenter (Scott), on the local stand-in for the
## parcel save (C-58 rules mirrored in parcel_farm.gd). Headless: portraits stay blank, the flow and saves are real.
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
## Loaded at run time: these use autoloads (Avatar, Localization), which a preload here would compile before.
var Town: GDScript
var Portraits: GDScript
const T0 := 1795392000000
const DIR := "user://test_parcel_town"
const PARCEL := "p-3512001"
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	Town = load("res://scenes/dynamic_farm/parcel_town.gd")
	Portraits = load("res://modules/p0/p0_keeper_portraits.gd")
	_clean()
	_rules()
	_commands()
	await _market()
	await _carpenter()
	await _failures()
	await _entries()
	_portraits()
	_clean()
	print("PARCEL_TOWN checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _clean() -> void:
	for name in DirAccess.get_files_at(DIR): DirAccess.remove_absolute(DIR.path_join(name))

func _rules() -> void:
	var eco: Dictionary = ParcelFarm.rules().economy
	_check(eco.sell_prices == {"crop_carrot": 12, "wood": 2, "wild_herb": 1, "stone": 2}, "C-30#36 prices: carrot 12, wood 2, herb 1, stone 2")
	_check(eco.blueprints.coop == {"item": "blueprint_coop", "amount": 1, "min_sales": 1}, "one coop blueprint after the first sale")
	var old := {"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {"crop_carrot": 2}, "welcomed_at": T0}
	var read := ParcelFarm.normalize(old)
	_check(read.coins == 0 and read.sales == 0 and read.gathered.is_empty() and read.blueprints_claimed.is_empty(), "a save from before C-58 reads as 0 coins")
	var saved := old.duplicate(true)
	saved.merge({"coins": 36, "sales": 2, "gathered": {"x": T0}, "blueprints_claimed": {"coop": T0}})
	read = ParcelFarm.normalize(saved)
	_check(read.coins == 36 and read.sales == 2 and read.gathered.x == T0 and read.blueprints_claimed.coop == T0, "economy fields are kept")
	saved.coins = -1
	_check(ParcelFarm.normalize(saved).is_empty(), "negative coins are refused")

func _commands() -> void:
	var rules := ParcelFarm.rules()
	var state := ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {"crop_carrot": 3, "seed_carrot": 1}, "welcomed_at": T0})
	_check(ParcelFarm.apply(rules, state, [{"type": "claim_blueprint", "blueprint": "coop"}], T0).code == "CONDITION_NOT_MET", "no blueprint before a sale")
	_check(ParcelFarm.apply(rules, state, [{"type": "sell", "item": "seed_carrot", "count": 1}], T0).code == "NOT_SELLABLE", "seeds are not sold")
	var short := ParcelFarm.apply(rules, state, [{"type": "sell", "item": "crop_carrot", "count": 4}], T0)
	_check(short.code == "NOT_ENOUGH" and short.detail.have == 3, "cannot sell more than the bag holds")
	_check(ParcelFarm.apply(rules, state, [{"type": "sell", "item": "crop_carrot", "count": 0}], T0).code == "SCHEMA", "count 0 is malformed")
	var sold := ParcelFarm.apply(rules, state, [{"type": "sell", "item": "crop_carrot", "count": 2, "price": 5000}], T0)
	_check(sold.ok and sold.state.coins == 24 and sold.state.bag.crop_carrot == 1 and sold.state.sales == 1, "2 carrots sell for 24; a price in the command is ignored")
	_check(state.coins == 0, "apply does not touch its input")
	var batch := ParcelFarm.apply(rules, state, [{"type": "sell", "item": "crop_carrot", "count": 1}, {"type": "claim_blueprint", "blueprint": "coop"}, {"type": "claim_blueprint", "blueprint": "coop"}], T0)
	_check(not batch.ok and batch.code == "BLUEPRINT_CLAIMED" and batch.index == 2, "a batch claiming twice fails whole")
	var claimed := ParcelFarm.apply(rules, sold.state, [{"type": "claim_blueprint", "blueprint": "coop"}], T0 + 1)
	_check(claimed.ok and claimed.state.bag.blueprint_coop == 1 and claimed.state.blueprints_claimed.coop == T0 + 1, "the coop blueprint goes into the bag")
	_check(ParcelFarm.apply(rules, claimed.state, [{"type": "claim_blueprint", "blueprint": "coop"}], T0).code == "BLUEPRINT_CLAIMED", "only once")
	_check(ParcelFarm.apply(rules, sold.state, [{"type": "claim_blueprint", "blueprint": "chicken"}], T0).code == "UNKNOWN_BLUEPRINT", "unknown blueprints are refused")

func _store_with(bag: Dictionary) -> RefCounted:
	var store := LocalStore.new(PARCEL, DIR)
	store.now_ms = func() -> int: return T0
	store._save(ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": bag, "welcomed_at": T0}), 3)
	return store

func _open(who: String, store: RefCounted) -> Control:
	var town: Control = Town.open(root, who, store, PARCEL, DIR.path_join("met.json"))
	for i in 4: await process_frame
	return town

func _market() -> void:
	var store := _store_with({"crop_carrot": 3, "wood": 1, "seed_carrot": 2})
	var read: Dictionary = store.read()
	_check(read.ok and read.farm_version == 3 and not read.farm.bag.has("hoe_starter"), "read() does not enter the farm (no gift)")
	var town := await _open(Town.MARKET, store)
	_check(town.card != null and town.card.title == "Market · Jasmine", "Jasmine greets")
	_check(town.card.line == Town.LINES.intro, "first meeting: the coin introduction")
	_check(town.met(Town.MARKET), "the introduction is remembered")
	town.close()
	await process_frame
	town = await _open(Town.MARKET, store)
	_check(town.card.line == Town.LINES.hello, "second meeting: no introduction again")
	town.keys.sell.activated.emit()
	await process_frame
	var counter = town.counter
	_check(counter != null and town.stack.has_drawer(), "Sell opens Jasmine's counter")
	_check(counter.sellable() == ["crop_carrot", "wood"], "the counter lists only what she buys (not seeds)")
	_check(counter.coins.value == "0", "the counter shows the parcel's coins")
	counter.select("crop_carrot")
	var spec: Dictionary = counter.spec("crop_carrot")
	_check(spec.facts == ["12 each"] and spec.buttons[1].label == "Sell All · 36 coins", "the card reads like the main counter's")
	await town.sell("crop_carrot", 1)
	_check(town.farm.coins == 12 and town.farm.bag.crop_carrot == 2 and counter.coins.value == "12", "selling one carrot: +12 coins")
	_check(counter.keeper_bar.line == "Thanks! +12 coins", "Jasmine thanks")
	await town.sell("crop_carrot", 2)
	_check(town.farm.coins == 36 and not town.farm.bag.has("crop_carrot") and counter.sellable() == ["wood"], "Sell All: 36 coins, no carrots left")
	var again: Dictionary = store.read()
	_check(again.farm.coins == 36 and again.farm.sales == 2 and not again.farm.bag.has("crop_carrot"), "coins and bag are saved")
	town.stack.close_drawer()
	await process_frame
	await process_frame
	_check(town.stack.has_card() and town.card.line == Town.LINES.hello, "closing the counter returns to Jasmine")
	town.stack.back()
	await process_frame
	_check(not is_instance_valid(town) or town.is_queued_for_deletion(), "closing the greeting leaves")

func _carpenter() -> void:
	_clean()
	var store := _store_with({"crop_carrot": 1})
	var town := await _open(Town.CARPENTER, store)
	_check(town.card.title == "Carpenter · Scott", "Scott greets")
	_check(town.card.line == Town.LINES.scott_wait and not town.keys.has("take"), "no blueprint before a sale")
	town.close()
	await process_frame
	store.send(3, [{"type": "sell", "item": "crop_carrot", "count": 1}])
	town = await _open(Town.CARPENTER, store)
	_check(town.card.line == Town.LINES.scott_give and town.keys.has("take"), "after a sale Scott offers the blueprint")
	_check(town.keys.take.text == "Take Blueprint", "the key names it")
	await town.claim_blueprint()
	_check(town.farm.bag.get("blueprint_coop") == 1, "one coop blueprint in the bag")
	_check(town.toast.current_text() == "Received Coop Blueprint ×1", "the gift is announced")
	_check(town.card.line == Town.LINES.scott_done and not town.keys.has("take"), "no second offer")
	var second: Dictionary = await town.claim_blueprint()
	_check(not second.ok and second.code == "BLUEPRINT_CLAIMED" and town.farm.bag.blueprint_coop == 1, "claiming again gives nothing")
	town.close()
	await process_frame
	town = await _open(Town.CARPENTER, store)
	_check(town.card.line == Town.LINES.scott_done and store.read().farm.bag.blueprint_coop == 1, "kept after reopening")
	town.close()
	await process_frame

## A read that fails offers Retry; Scott without a coop rule does not wait on "…" (V-122, C-59#29).
class FlakyStore extends RefCounted:
	var inner: RefCounted
	var fail := true
	func _init(p_inner: RefCounted) -> void: inner = p_inner
	func read() -> Dictionary:
		if fail: return {"ok": false, "code": "NETWORK", "index": 0}
		return inner.read()
	func send(base_version: int, commands: Array) -> Dictionary: return inner.send(base_version, commands)

func _failures() -> void:
	_clean()
	var flaky := FlakyStore.new(_store_with({"crop_carrot": 1}))
	var town := await _open(Town.MARKET, flaky)
	_check(town.card.line == Town.LINES.unreachable and town.keys.has("retry") and not town.keys.has("sell"), "a failed read says so and offers Retry")
	flaky.fail = false
	town.keys.retry.activated.emit()
	for i in 3: await process_frame
	_check(town.keys.has("sell") and not town.keys.has("retry") and town.farm.bag.crop_carrot == 1, "Retry reads the farm")
	town.close()
	await process_frame
	var blueprints: Dictionary = ParcelFarm.rules().economy.blueprints
	var coop = blueprints.coop
	blueprints.erase("coop")
	town = await _open(Town.CARPENTER, _store_with({}))
	_check(town.card.line == Town.LINES.scott_none and not town.keys.has("take"), "no coop rule: Scott says a line, no key")
	blueprints.coop = coop
	town.close()
	await process_frame

## C-115: the map no longer opens Jasmine and Scott over itself; its Union Square pin (town_entry.gd) opens the 3D room
## where they stand (test_parcel_outpost.gd, test_claim_controller.gd). Without a home nothing opens.
func _entries() -> void:
	for own in [false, true]:
		ProjectSettings.set_setting("sensen/dynamic_farm/own_farm", own)
		var map: Control = (load("res://scenes/dynamic_farm/dynamic_farm_map.tscn") as PackedScene).instantiate()
		root.add_child(map)
		await process_frame
		_check(not map.find_children("*", "Button", true, false).any(func(b): return b.text in ["Market", "Carpenter"]),
			"no Market or Carpenter button on the map with own_farm=%s" % own)
		_check(map._entry != null and not map._entry.visible, "the Union Square pin waits for the map (own_farm=%s)" % own)
		map._open_town()
		_check(not map._opening and map.find_children("*", "ParcelTown", true, false).is_empty(), "nothing opens without a home")
		map.queue_free()
		await process_frame
	ProjectSettings.set_setting("sensen/dynamic_farm/own_farm", null)

func _portraits() -> void:
	Town.npc(Town.MARKET)
	Town.npc(Town.CARPENTER)
	_check(Portraits._slots("parcel:jasmine") == Town.NPCS.market.slots, "Jasmine's look is registered for her portrait")
	var finn: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/p0/outpost_npcs.json")).npcs.finn.slots
	_check(Portraits._slots("npc:finn") == finn, "P0 keepers keep their own looks")
	var parts := {}
	for p: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://assets/avatar/parts_manifest.json")).parts: parts[p.id] = p.slot
	var npc_only: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/avatar/npc_only.json")).npc_only
	var others: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/p0/outpost_npcs.json")).npcs
	for role in Town.NPCS:
		var slots: Dictionary = Town.NPCS[role].slots
		for slot: String in slots:
			_check(parts.get(slots[slot]) == slot, "%s wears an existing %s part" % [role, slot])
			_check(not npc_only.has(slots[slot]), "%s wears no other keeper's own part" % role)
		for other: Dictionary in others.values():
			_check(not (other.slots.get("hairHat") == slots.hairHat and other.slots.get("cloth") == slots.cloth), "%s does not look like %s" % [role, other.name])
