extends SceneTree
## C-59: the market (Jasmine) and the carpenter (Scott), on the local stand-in for the
## parcel save (C-58 rules mirrored in parcel_farm.gd). Headless: portraits stay blank, the flow and saves are real.
## C-152: Scott upgrades the farm (Upgrade Farm → the upgrade sheet → upgrade_farm).
## C-181: Scott sells the barn blueprint for 600 coins from farm level 2 (C-192, SEN-Q-282; Buy Barn Blueprint · 600 coins →
## claim_blueprint); below level 2 the key reads `Farm Lv2 needed`.
## C-182: Scott sells the sheep pen blueprint for 1,200 coins after 15 delivered requests at farm level 3 (SEN-Q-282): short of
## requests the key reads `Need N more requests`, then `Farm Lv3 needed`, then the coins.
## C-197: Jasmine's seed aid (owner SEN-Q-281): the client rules against the server's on the shared cases
## (fixtures/seed_aid_cases.json, also run by server/test/parcels/seed_aid.test.ts) and her greeting giving the seeds.
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
	await _buy()
	await _carpenter()
	await _upgrade()
	await _level_card_first_frame()
	await _barn_blueprint()
	await _sheep_pen_blueprint()
	await _failures()
	await _entries()
	_seed_aid_rules()
	await _seed_aid()
	_portraits()
	_clean()
	print("PARCEL_TOWN checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _clean() -> void:
	for name in DirAccess.get_files_at(DIR): DirAccess.remove_absolute(DIR.path_join(name))

func _rules() -> void:
	var eco: Dictionary = ParcelFarm.rules().economy
	_check(eco.sell_prices == {"crop_carrot": 12, "wood": 2, "wild_herb": 1, "stone": 2, "egg": 20, "milk": 45, "wool": 30},
		"C-30#36 prices: carrot 12, wood 2, herb 1, stone 2; C-154 egg 20; C-181 milk 45; C-182 wool 30")
	# C-181: every blueprint reads a price in coins (0 when the rules give none) and, since C-192, the farm level it is sold
	# from (1 when the rules give none); the barn's is bought for 600 from level 2 (SEN-Q-282). C-182: and how many requests
	# the farm has delivered first (0 when the rules give none); the sheep pen's 1,200 after 15 at level 3 (SEN-Q-282).
	_check(eco.blueprints.coop == {"item": "blueprint_coop", "amount": 1, "min_sales": 1, "min_level": 1, "min_requests": 0, "coins": 0},
		"one coop blueprint after the first sale")
	_check(eco.blueprints.barn == {"item": "blueprint_barn", "amount": 1, "min_sales": 0, "min_level": 2, "min_requests": 0, "coins": 600},
		"the barn blueprint for 600 coins from farm level 2")
	_check(eco.blueprints.sheep_pen == {"item": "blueprint_sheep_pen", "amount": 1, "min_sales": 0, "min_level": 3, "min_requests": 15,
		"coins": 1200}, "the sheep pen blueprint for 1,200 coins after 15 requests at farm level 3")
	_check(eco.buy_prices == {"seed_carrot": 9}, "C-149: Jasmine sells carrot seeds at 9, the P0 seed price")
	var p0_carrot := {}
	var p0 = JSON.parse_string(FileAccess.get_file_as_string("res://assets/p0/p0_content.json"))
	for crop: Dictionary in p0.get("crops", []):
		if crop.get("id") == "crop_carrot": p0_carrot = crop
	_check(int(p0_carrot.get("seed_price", -1)) == eco.buy_prices.seed_carrot, "C-149: the seed price is P0's (C-137#15 question 3)")
	_check(ParcelFarm.parse_rules({"version": 1}).is_empty(), "malformed rules still read as none")
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
	# C-149 buy, as the server's farm.ts: 9 a seed from the rules, too few coins refuses the whole batch.
	var bought := ParcelFarm.apply(rules, sold.state, [{"type": "buy", "item": "seed_carrot", "count": 2, "price": 0}], T0)
	_check(bought.ok and bought.state.coins == 6 and bought.state.bag.seed_carrot == 3 and bought.state.sales == 1, "2 seeds cost 18; a price in the command is ignored")
	var broke := ParcelFarm.apply(rules, sold.state, [{"type": "buy", "item": "seed_carrot", "count": 1}, {"type": "buy", "item": "seed_carrot", "count": 2}], T0)
	_check(not broke.ok and broke.index == 1 and broke.code == "NOT_ENOUGH_COINS" and broke.detail == {"coins": 15, "need": 18}, "too few coins: the batch fails whole")
	_check(sold.state.coins == 24 and sold.state.bag.seed_carrot == 1, "a refused buy leaves the state as it was")
	_check(ParcelFarm.apply(rules, sold.state, [{"type": "buy", "item": "crop_carrot", "count": 1}], T0).code == "NOT_FOR_SALE", "only the shelf's items can be bought")
	_check(ParcelFarm.apply(rules, sold.state, [{"type": "buy", "item": "seed_carrot", "count": 0}], T0).code == "SCHEMA", "count 0 is malformed")
	_check(ParcelFarm.apply(rules, sold.state, [{"type": "buy", "item": "seed_carrot", "count": 1000}], T0).code == "SCHEMA", "at most 999 at once")

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
	_check(town.keys.trade.text == "Trade", "Jasmine's key is Trade (the P0 keeper greeting, LOCK-16)")
	town.keys.trade.activated.emit()
	await process_frame
	var counter = town.counter
	_check(counter != null and town.stack.has_drawer(), "Trade opens Jasmine's counter")
	_check(counter.sellable() == ["crop_carrot", "wood"], "the counter lists only what she buys (not seeds)")
	_check(counter.coins.value == "0", "the counter shows the parcel's coins")
	_check(counter.coins.icon == UiArt.COIN, "the counter's coins row shows the v3 coin (C-105)")
	counter.select("crop_carrot")
	var spec: Dictionary = counter.spec("crop_carrot")
	_check(spec.facts == ["12 each"] and spec.buttons[1].label == "Sell All · 36 coins", "the card reads like the main counter's")
	await town.sell("crop_carrot", 1)
	_check(town.farm.coins == 12 and town.farm.bag.crop_carrot == 2 and counter.coins.value == "12", "selling one carrot: +12 coins")
	_check(counter.keeper_bar.line == "Thanks! +12 coins", "Jasmine thanks")
	var sheet_at: int = counter.sheet.get_index()
	await town.sell("crop_carrot", 2)
	_check(town.farm.coins == 36 and not town.farm.bag.has("crop_carrot") and counter.sellable() == ["wood"], "Sell All: 36 coins, no carrots left")
	# C-211 MS-15: the sold-out card folds away in its place (clipped, shrinking), the carrot's grid icon fades.
	var fold: Control = counter._fold
	var ghost: Control = counter.find_child("SoldGhost", true, false)
	_check(fold != null and fold.clip_contents and counter.sheet.get_parent() == fold and fold.get_index() == sheet_at
		and ghost != null, "sold out: the card folds in its place, the carrot's icon fades")
	await process_frame
	_check(is_instance_valid(ghost) and ghost.size.x <= 64.0 and ghost.global_position.y > counter.sheet.get_global_rect().position.y,
		"…the icon where its cell was, not stretched over the drawer (%s)" % (ghost.get_global_rect() if is_instance_valid(ghost) else Rect2()))
	await create_timer(0.1).timeout
	_check(is_instance_valid(fold) and fold.custom_minimum_size.y < counter.sheet.size.y and fold.custom_minimum_size.y > 0.0,
		"…folding (%.0f of %.0f)" % [fold.custom_minimum_size.y, counter.sheet.size.y])
	await create_timer(0.25).timeout
	_check(counter._fold == null and not counter.sheet.is_open() and counter.sheet.get_parent() == counter.body
		and counter.sheet.get_index() == sheet_at and counter.sheet.modulate.a == 1.0 and counter.find_child("SoldGhost", true, false) == null,
		"folded: the card is closed, back in its place for the next pick")
	var again: Dictionary = store.read()
	_check(again.farm.coins == 36 and again.farm.sales == 2 and not again.farm.bag.has("crop_carrot"), "coins and bag are saved")
	town.stack.close_drawer()
	await process_frame
	await process_frame
	_check(town.stack.has_card() and town.card.line == Town.LINES.hello, "closing the counter returns to Jasmine")
	town.stack.back()
	await process_frame
	_check(not is_instance_valid(town) or town.is_queued_for_deletion(), "closing the greeting leaves")

## C-149: Jasmine's shelf (one carrot-seed row over the divider): the row reads like P0's counter_buy, buying takes the
## coins and fills the bag, too few coins greys Buy with the shortfall, and the save keeps it all.
func _buy() -> void:
	_clean()
	var store := _store_with({"crop_carrot": 3})
	var town := await _open(Town.MARKET, store)
	town.keys.trade.activated.emit()
	await process_frame
	var counter = town.counter
	var row: UiShopRow = counter.row_of("seed_carrot")
	_check(row != null and counter.shelf.get_child_count() == 1, "one shelf row: carrot seeds")
	var spec: Dictionary = row.spec()
	_check(spec.title == "Carrot Seeds" and spec.facts == ["Bag ×0"] and spec.price.text == "9 coins" and spec.price.line == "", "the row (C-149#10): name, bag count, 9 coins, no extra lines")
	_check(row.buy != null and row.buy.is_unavailable() and row.buy.reason == "Need 9 more coins" and row.stepper == null, "no coins: Buy is grey with the shortfall")
	await town.sell("crop_carrot", 2)
	row = counter.row_of("seed_carrot")
	_check(counter.coins.value == "24" and row.stepper != null and row.stepper.max_value == 2 and not row.buy.is_unavailable(), "24 coins: Buy, the stepper up to 2")
	row.stepper.value = 2
	_check(counter.row_of("seed_carrot").spec().price.text == "18 coins" and counter.row_of("seed_carrot").spec().price.line == "", "the stepper's count prices the row, no working shown")
	var bought := [{}]
	counter.buy_requested.connect(func(item: String, qty: int): bought[0] = {item = item, qty = qty})
	counter.row_of("seed_carrot").buy.activated.emit()
	await process_frame
	await process_frame
	_check(bought[0] == {item = "seed_carrot", qty = 2}, "Buy reports the item and the count")
	_check(town.farm.coins == 6 and town.farm.bag.seed_carrot == 2 and counter.coins.value == "6", "buying 2: −18 coins, +2 seeds")
	_check(town.toast.current_text() == "Received Carrot Seeds ×2", "the toast says what came in")
	var bag_line: Label = counter.row_of("seed_carrot")._effect
	_check(UiMotion.rolling(bag_line), "the row's `Bag ×N` rolls up (C-211 MS-15)")
	await create_timer(0.5).timeout
	_check(bag_line.text == "Bag ×2", "…to Bag ×2")
	row = counter.row_of("seed_carrot")
	_check(row.spec().facts[0] == "Bag ×2" and row.buy.is_unavailable() and row.buy.reason == "Need 3 more coins", "6 coins: grey again, 3 short")
	var refused: Dictionary = await town.buy("seed_carrot", 1)
	_check(not refused.ok and refused.code == "NOT_ENOUGH_COINS", "the store refuses a buy it cannot pay for")
	var saved: Dictionary = store.read()
	_check(saved.farm.coins == 6 and saved.farm.bag.seed_carrot == 2 and saved.farm.bag.crop_carrot == 1, "the refused buy left the save as it was")
	town.close()
	await process_frame
	town = await _open(Town.MARKET, store)
	_check(town.farm.coins == 6 and town.farm.bag.seed_carrot == 2, "coming back: the same coins and seeds")
	town.close()
	await process_frame

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

## C-152: Scott's Upgrade Farm opens the sheet; Upgrade pays the next level, the sheet moves on to the one after, a toast
## names the level (and Lv3's well blueprint); short, the key shows the gap and the store refuses; kept after reopening.
## C-186 (C-185 MS-17): the level-up card replaces the toast — `Farm LvN`, what changes as `from → to`, the level's gift as
## its strip, `OK` — and the sheet keeps its level until the card closes. Run with reduced motion (no waiting on tweens).
func _upgrade() -> void:
	_clean()
	UiMotion.reduced = true
	var store := LocalStore.new(PARCEL, DIR)
	store.now_ms = func() -> int: return T0
	store._save(ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {"wood": 16, "stone": 12},
		"welcomed_at": T0, "coins": 400}), 3)
	var town := await _open(Town.CARPENTER, store)
	_check(town.keys.has("upgrade") and town.keys.upgrade.label == "Upgrade Farm" and not town.keys.has("take"), "Scott offers Upgrade Farm")
	_check(town.keys.upgrade.kind == UiCommandButton.Kind.PRIMARY, "alone it is the primary key")
	town.keys.upgrade.activated.emit()
	await process_frame
	var sheet = town.upgrade_sheet
	_check(sheet != null and town.stack.drawer() == sheet and sheet.title.text == "Farm Lv1 → Lv2", "the sheet opens over the greeting: Farm Lv1 → Lv2")
	_check(sheet.button.reason == "" and not sheet.find_children("*", "Label", true, false).any(func(l): return "free of Energy" in l.text),
		"enough: Upgrade can go; no footer line under it (C-152#29)")
	var asked := [false]
	sheet.upgrade_requested.connect(func(): asked[0] = true)
	sheet.button.activated.emit()
	_check(asked[0], "Upgrade reports")
	for i in 3: await process_frame
	_check(town.farm.level == 2 and town.farm.coins == 300 and town.farm.bag == {"wood": 10, "stone": 8}, "Lv2: 100 coins, 6 Timber, 4 Stone taken")
	var card: UiRewardMoment = town.level_card
	_check(card != null and card.event == "Farm Lv2" and card.primary == "OK" and card.hero != null, "the level-up card: Farm Lv2, hero_home, OK (C-185 MS-17)")
	_check(card != null and card.rows.size() == 1 and card.rows[0].label == "Max Energy" and " → " in str(card.rows[0].value) and card.strip == "",
		"what changes as `from → to`, no gift at Lv2 (%s)" % [card.rows if card != null else []])
	_check(town.toast.current_text() != "Farm Lv2", "no level toast any more: the card says it")
	_check(sheet.title.text == "Farm Lv1 → Lv2", "the sheet keeps its level while the card shows")
	card.primary_pressed.emit()
	_check(town.level_card == null and sheet.title.text == "Farm Lv2 → Lv3" and sheet.button.reason == "", "OK closes it: the sheet moves on to Lv3")
	await town.upgrade()
	_check(town.farm.level == 3 and town.farm.bag == {"blueprint_well": 1} and town.farm.coins == 0, "Lv3: its price taken, a well blueprint given")
	card = town.level_card
	_check(card != null and card.event == "Farm Lv3" and card.strip == "+1 Well Blueprint" and card.rows.size() == 2,
		"Lv3's card: Max Energy and Wells, the well blueprint as its strip")
	_check(town.step_back() and town.level_card == null and town.upgrade_sheet == sheet, "Back closes the card first, the sheet stays")
	_check(sheet.title.text == "Farm Lv3 → Lv4" and sheet.button.reason == "Need 14 more Timber", "short for Lv4: the gap on the key")
	sheet.button.unavailable_pressed.emit(sheet.button.reason)
	_check(town.toast.current_text() != "Need 14 more Timber", "a tap on the grey key: the key already says why, no repeat toast (MS-02)")
	var refused: Dictionary = await town.upgrade()
	_check(not refused.ok and refused.code == "NOT_ENOUGH" and store.read().farm.level == 3, "the store refuses a short upgrade, still Lv3")
	sheet.close_requested.emit()
	for i in 2: await process_frame
	_check(town.upgrade_sheet == null and town.card != null and town.keys.has("upgrade"), "closing the sheet goes back to Scott")
	town.close()
	await process_frame
	town = await _open(Town.CARPENTER, store)
	_check(town.farm.level == 3 and store.read().farm.bag == {"blueprint_well": 1}, "kept after reopening")
	town.close()
	await process_frame
	# After a sale Scott offers the blueprint first; Upgrade Farm stays, second.
	_clean()
	store = _store_with({"crop_carrot": 1})
	store.send(3, [{"type": "sell", "item": "crop_carrot", "count": 1}])
	town = await _open(Town.CARPENTER, store)
	_check(town.keys.has("take") and town.keys.upgrade.kind == UiCommandButton.Kind.SECONDARY, "beside Take Blueprint, Upgrade Farm is secondary")
	town.close()
	await process_frame
	UiMotion.reduced = false

## C-186#82: the level-up card is measured and centred a frame after it joins the scene; until then nothing of it shows —
## the card, its light and the scrim all start transparent — so it never flashes at (0, 0) over a full scrim. Both motions.
func _level_card_first_frame() -> void:
	for reduced in [false, true]:
		_clean()
		UiMotion.reduced = reduced
		var store := LocalStore.new(PARCEL, DIR)
		store.now_ms = func() -> int: return T0
		var town := await _open(Town.CARPENTER, store)
		town.show_level_card(2, [{"icon": null, "label": "Max Energy", "value": "200 → 210"}])
		var layer: Control = town.get_node(^"LevelUp")
		var card: Control = layer.get_node(^"LevelCard")
		var scrim: CanvasItem = layer.get_node(^"Scrim")
		var glow: CanvasItem = layer.get_node_or_null(^"Glow")
		var tag := "reduced" if reduced else "full"
		_check(card.modulate.a == 0.0 and scrim.modulate.a == 0.0 and (glow == null or glow.modulate.a == 0.0),
			"%s: before the first frame the card, its light and the scrim are all transparent" % tag)
		await process_frame
		var place: Vector2 = Town.level_card_place(layer.size, card.size)
		_check(card.position.is_equal_approx(place) and card.position != Vector2.ZERO, "%s: then the card is in its place (%s)" % [tag, card.position])
		# C-211 (C-186#82): centred across, its middle at 42 % of the height (figure 6), above the screen's middle.
		_check(is_equal_approx(card.position.x, (layer.size.x - card.size.x) * 0.5)
			and is_equal_approx(card.position.y + card.size.y * 0.5, layer.size.y * UiTokens.SIZE_LEVEL_CARD_CENTRE_Y)
			and card.position.y + card.size.y * 0.5 < layer.size.y * 0.5 and card.position.y >= UiRewardMoment.HERO_OVER,
			"%s: centred across, its middle at %.0f %% of the height, its hero on screen (%s of %s)" % [tag,
			UiTokens.SIZE_LEVEL_CARD_CENTRE_Y * 100.0, card.get_rect(), layer.size])
		_check(card.modulate.a < 0.5 and scrim.modulate.a < 0.5, "%s: and fades in from there (card %.2f, scrim %.2f)" % [tag, card.modulate.a, scrim.modulate.a])
		for i in 30: await process_frame
		_check(is_equal_approx(card.modulate.a, 1.0) and is_equal_approx(scrim.modulate.a, 1.0) and (glow == null or is_equal_approx(glow.modulate.a, 1.0)),
			"%s: card, scrim and light end fully in" % tag)
		town.close()
		await process_frame
	UiMotion.reduced = false

## C-181: Scott sells the barn blueprint. Below farm level 2 (C-192, SEN-Q-282) the key reads `Farm Lv2 needed` whatever the
## coins, short of coins it reads the gap (secondary, Upgrade Farm stays primary), a tap says why and the store refuses; with
## the level and the coins it is the primary key, takes 600, gives the blueprint once.
func _barn_blueprint() -> void:
	_clean()
	var store := LocalStore.new(PARCEL, DIR)
	store.now_ms = func() -> int: return T0
	store._save(ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {"crop_carrot": 1},
		"welcomed_at": T0, "coins": 999, "sales": 1, "blueprints_claimed": {"coop": T0}}), 3)
	var town := await _open(Town.CARPENTER, store)
	_check(town.card.line == Town.LINES.scott_done, "the coop blueprint already taken: Scott's line as before")
	_check(town.keys.has("buy_barn") and town.keys.buy_barn.label == "Buy Barn Blueprint · 600 coins", "Scott sells the barn blueprint for 600 coins")
	_check(town.keys.buy_barn.reason == "Farm Lv2 needed" and town.keys.buy_barn.kind == UiCommandButton.Kind.SECONDARY,
		"farm level 1 with 999 coins: the key reads `Farm Lv2 needed`, secondary")
	_check(town.keys.upgrade.kind == UiCommandButton.Kind.PRIMARY, "below the level Upgrade Farm is the primary key")
	town.keys.buy_barn.unavailable_pressed.emit(town.keys.buy_barn.reason)
	_check(town.toast.current_text() != "Farm Lv2 needed" and town.keys.buy_barn.has_meta(&"_ui_shake"),
		"a tap on it shakes the key; the key already says why, so no repeat toast (C-185 MS-02)")
	var low: Dictionary = await town.claim_blueprint("barn")
	_check(not low.ok and low.code == "CONDITION_NOT_MET" and low.get("detail", {}).get("min_level") == 2 and store.read().farm.coins == 999 \
		and not store.read().farm.bag.has("blueprint_barn"), "the store refuses below level 2: coins and bag unchanged")
	town.close()
	await process_frame
	var leveled: Dictionary = store.read().farm
	leveled.level = 2
	leveled.coins = 570
	store._save(leveled, store.read().farm_version)
	town = await _open(Town.CARPENTER, store)
	_check(town.keys.buy_barn.reason == "Need 30 more coins" and town.keys.buy_barn.kind == UiCommandButton.Kind.SECONDARY,
		"short of 30 coins: the key reads the gap, secondary")
	_check(town.keys.upgrade.kind == UiCommandButton.Kind.PRIMARY, "Upgrade Farm stays the primary key")
	town.keys.buy_barn.unavailable_pressed.emit(town.keys.buy_barn.reason)
	_check(town.toast.current_text() != "Need 30 more coins" and town.keys.buy_barn.has_meta(&"_ui_shake"),
		"a tap on the short key shakes it, no repeat toast (MS-02)")
	var refused: Dictionary = await town.claim_blueprint("barn")
	_check(not refused.ok and refused.code == "NOT_ENOUGH_COINS" and store.read().farm.coins == 570 \
		and not store.read().farm.bag.has("blueprint_barn"), "the store refuses: coins and bag unchanged")
	town.close()
	await process_frame
	store.send(store.read().farm_version, [{"type": "sell", "item": "crop_carrot", "count": 1}])
	var saved: Dictionary = store.read().farm
	saved.coins = 620
	store._save(saved, store.read().farm_version)
	town = await _open(Town.CARPENTER, store)
	_check(town.keys.buy_barn.reason == "" and town.keys.buy_barn.kind == UiCommandButton.Kind.PRIMARY \
		and town.keys.upgrade.kind == UiCommandButton.Kind.SECONDARY, "with the coins it is the primary key, Upgrade Farm secondary")
	town.keys.buy_barn.activated.emit()
	for i in 3: await process_frame
	_check(town.farm.coins == 20 and town.farm.bag.get("blueprint_barn") == 1 and town.farm.blueprints_claimed.has("barn"),
		"600 coins taken, one barn blueprint in the bag")
	_check(town.toast.current_text() == "Received Barn Blueprint ×1", "the purchase is announced")
	_check(not town.keys.has("buy_barn"), "bought: no second offer")
	var again: Dictionary = await town.claim_blueprint("barn")
	_check(not again.ok and again.code == "BLUEPRINT_CLAIMED" and store.read().farm.coins == 20, "buying again is refused, nothing more taken")
	town.close()
	await process_frame
	town = await _open(Town.CARPENTER, store)
	_check(not town.keys.has("buy_barn") and store.read().farm.bag.blueprint_barn == 1, "kept after reopening")
	town.close()
	await process_frame

## C-182: the sheep pen's blueprint, beside the barn's. Locked (secondary, a tap shakes the key, the store refuses) while the
## farm has delivered fewer than 15 requests (`Need N more requests`, the server's first check) or is below level 3
## (`Farm Lv3 needed`), then short of coins; with all three the primary key takes 1,200 and gives the blueprint once.
func _sheep_pen_blueprint() -> void:
	_clean()
	var store := LocalStore.new(PARCEL, DIR)
	store.now_ms = func() -> int: return T0
	store._save(ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {"crop_carrot": 1},
		"welcomed_at": T0, "coins": 5000, "sales": 1, "blueprints_claimed": {"coop": T0, "barn": T0}, "level": 1, "requests_done": 0}), 3)
	var town := await _open(Town.CARPENTER, store)
	_check(town.keys.has("buy_sheep_pen") and town.keys.buy_sheep_pen.label == "Buy Sheep Pen Blueprint · 1200 coins",
		"Scott sells the sheep pen blueprint for 1,200 coins (%s)" % town.keys.buy_sheep_pen.label)
	_check(town.keys.buy_sheep_pen.reason == "Need 15 more requests" and town.keys.buy_sheep_pen.kind == UiCommandButton.Kind.SECONDARY \
		and town.keys.upgrade.kind == UiCommandButton.Kind.PRIMARY,
		"no request delivered, level 1, 5,000 coins: the key reads `Need 15 more requests` first, secondary; Upgrade Farm primary")
	town.keys.buy_sheep_pen.unavailable_pressed.emit(town.keys.buy_sheep_pen.reason)
	_check(town.toast.current_text() != "Need 15 more requests" and town.keys.buy_sheep_pen.has_meta(&"_ui_shake"),
		"a tap on it shakes the key; the key already says why, so no repeat toast (C-185 MS-02)")
	var locked: Dictionary = await town.claim_blueprint("sheep_pen")
	_check(not locked.ok and locked.code == "CONDITION_NOT_MET" and locked.get("detail", {}) == {"requests_done": 0, "min_requests": 15} \
		and store.read().farm.coins == 5000 and not store.read().farm.bag.has("blueprint_sheep_pen"),
		"the store refuses short of requests: coins and bag unchanged")
	town.close()
	await process_frame
	var reason := func(requests: int, level: int, coins: int) -> String:
		var saved: Dictionary = store.read().farm
		saved.requests_done = requests
		saved.level = level
		saved.coins = coins
		store._save(saved, store.read().farm_version)
		var t: Control = await _open(Town.CARPENTER, store)
		var why: String = t.keys.buy_sheep_pen.reason
		t.close()
		await process_frame
		return why
	_check(await reason.call(14, 3, 5000) == "Need 1 more request", "14 requests at level 3: `Need 1 more request`")
	_check(await reason.call(15, 2, 5000) == "Farm Lv3 needed", "15 requests at level 2: `Farm Lv3 needed`")
	_check(await reason.call(3, 2, 5000) == "Need 12 more requests", "short of both: the requests first")
	_check(await reason.call(15, 3, 1100) == "Need 100 more coins", "15 requests at level 3, 1,100 coins: `Need 100 more coins`")
	var leveled: Dictionary = store.read().farm
	_check(leveled.requests_done == 15 and leveled.level == 3, "the save read back with 15 requests at level 3")
	town = await _open(Town.CARPENTER, store)
	var low: Dictionary = await town.claim_blueprint("sheep_pen")
	_check(not low.ok and low.code == "NOT_ENOUGH_COINS" and store.read().farm.coins == 1100, "the store refuses short of coins")
	town.close()
	await process_frame
	var saved: Dictionary = store.read().farm
	saved.coins = 1250
	store._save(saved, store.read().farm_version)
	town = await _open(Town.CARPENTER, store)
	_check(town.keys.buy_sheep_pen.reason == "" and town.keys.buy_sheep_pen.kind == UiCommandButton.Kind.PRIMARY \
		and town.keys.upgrade.kind == UiCommandButton.Kind.SECONDARY, "with all three it is the primary key, Upgrade Farm secondary")
	town.keys.buy_sheep_pen.activated.emit()
	for i in 3: await process_frame
	_check(town.farm.coins == 50 and town.farm.bag.get("blueprint_sheep_pen") == 1 and town.farm.blueprints_claimed.has("sheep_pen"),
		"1,200 coins taken, one sheep pen blueprint in the bag")
	_check(town.toast.current_text() == "Received Sheep Pen Blueprint ×1", "the purchase is announced")
	_check(not town.keys.has("buy_sheep_pen"), "bought: no second offer")
	var again: Dictionary = await town.claim_blueprint("sheep_pen")
	_check(not again.ok and again.code == "BLUEPRINT_CLAIMED" and store.read().farm.coins == 50, "buying again is refused, nothing more taken")
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
	_check(town.card.line == Town.LINES.unreachable and town.keys.has("retry") and not town.keys.has("trade"), "a failed read says so and offers Retry")
	flaky.fail = false
	town.keys.retry.activated.emit()
	for i in 3: await process_frame
	_check(town.keys.has("trade") and not town.keys.has("retry") and town.farm.bag.crop_carrot == 1, "Retry reads the farm")
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

## C-115: the map no longer opens Jasmine and Scott over itself; its Washington Square pin (town_entry.gd) opens the 3D room
## where they stand (test_parcel_outpost.gd, test_claim_controller.gd). Without a home nothing opens.
func _entries() -> void:
	for own in [false, true]:
		ProjectSettings.set_setting("sensen/dynamic_farm/own_farm", own)
		var map: Control = (load("res://scenes/dynamic_farm/dynamic_farm_map.tscn") as PackedScene).instantiate()
		root.add_child(map)
		await process_frame
		_check(not map.find_children("*", "Button", true, false).any(func(b): return b.text in ["Market", "Carpenter"]),
			"no Market or Carpenter button on the map with own_farm=%s" % own)
		_check(map._entry != null and not map._entry.visible, "the Washington Square pin waits for the map (own_farm=%s)" % own)
		# C-145 (C-115#62): the pin shows "Washington Square" whole, wider than a pin's usual 96 px name; same copy.
		var whole := UiMapDestination.label_size_for(map._entry.SHORT, false, 4096.0)
		_check(map._entry.pin.text == "Washington Square" and whole.x > UiMapDestination.SHORT_MAX_W and whole.x <= map._entry.NAME_MAX_W
			and map._entry.pin.label_size() == whole, "the Washington Square pin's name is not cut (own_farm=%s)" % own)
		map._open_town()
		_check(not map._opening and map.find_children("*", "ParcelTown", true, false).is_empty(), "nothing opens without a home")
		map.queue_free()
		await process_frame
	ProjectSettings.set_setting("sensen/dynamic_farm/own_farm", null)

## C-197: the shipped seed aid, malformed ones refused as the server refuses them, and the shared cases.
func _seed_aid_rules() -> void:
	var rules := ParcelFarm.rules()
	_check(rules.seed_aid == {"item": "seed_carrot", "amount": 3}, "seed aid: 3 carrot seeds (SEN-Q-281)")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ParcelFarm.RULES_PATH))
	var bad := func(aid: Variant) -> bool:
		var copy: Dictionary = raw.duplicate(true)
		copy.seed_aid = aid
		return ParcelFarm.parse_rules(copy).is_empty()
	_check(not bad.call({"item": "seed_carrot", "amount": 3}), "seed aid: the shipped one parses")
	_check(bad.call({"item": "seed_carrot", "amount": 0}) and bad.call({"item": "seed_carrot", "amount": 100}), "seed aid: 1–99 seeds")
	_check(bad.call({"item": "egg", "amount": 3}), "seed aid: only a crop's seed")
	_check(bad.call([]), "seed aid: malformed refused")
	var unsold: Dictionary = raw.duplicate(true)
	unsold.economy.buy_prices = {}
	_check(ParcelFarm.parse_rules(unsold).is_empty(), "seed aid: a seed Jasmine does not sell is refused (no price to say \"no coins\")")
	var none: Dictionary = raw.duplicate(true)
	none.erase("seed_aid")
	var without := ParcelFarm.parse_rules(none)
	_check(not without.is_empty() and without.seed_aid.is_empty(), "seed aid: rules without it parse, no aid")
	_check(ParcelFarm.apply(without, _broke(), [{"type": "claim_seed_aid"}], T0).code == "NO_SEED_AID", "seed aid: without it, refused")
	var shared = JSON.parse_string(FileAccess.get_file_as_string("res://tests/dynamic_farm/fixtures/seed_aid_cases.json"))
	_check(shared is Dictionary and shared.cases.size() >= 12, "seed aid cases: the shared fixture reads")
	for c: Dictionary in shared.cases:
		var farm := ParcelFarm.normalize(c.farm)
		var frozen := JSON.stringify(farm, "", true)
		var r := ParcelFarm.apply(rules, farm, c.commands, int(c.now))
		var got := {"ok": true, "bag": r.state.bag, "coins": r.state.coins, "seed_aid_day": r.state.seed_aid_day} if r.ok \
			else {"ok": false, "index": r.index, "code": r.code, "detail": r.get("detail", {})}
		var want := JSON.stringify(_ints(c.expect), "", true)
		_check(JSON.stringify(_ints(got), "", true) == want, "seed aid case '%s': %s, server %s" % [c.name, JSON.stringify(_ints(got)), want])
		_check(JSON.stringify(farm, "", true) == frozen, "seed aid case '%s': the input save is untouched" % c.name)
	var given := ParcelFarm.apply(rules, _broke(), [{"type": "claim_seed_aid"}], T0)
	var reread := ParcelFarm.normalize(JSON.parse_string(JSON.stringify(given.state)))
	_check(reread.seed_aid_day == ParcelFarm.day_key(rules, T0), "seed aid: the day reads back from the save")
	_check(ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {}, "welcomed_at": T0}).seed_aid_day == null,
		"seed aid: a save from before it reads as never given")

## C-197: opening Jasmine with no coins, no seeds and no crops gives 3 carrot seeds once a player day: her greeting line
## says so, the toast names them, Trade stays the one key; the second visit that day gives nothing.
func _seed_aid() -> void:
	_clean()
	var store := _store_with({"hoe_starter": 1, "wood": 2})
	var town := await _open(Town.MARKET, store)
	for i in 4: await process_frame
	var farm: Dictionary = store.read().farm
	_check(farm.bag.get("seed_carrot", 0) == 3 and farm.seed_aid_day == ParcelFarm.day_key(ParcelFarm.rules(), T0),
		"broke at Jasmine's: 3 carrot seeds go into the bag and the day is saved")
	_check(town.card.line == "Out of coins and seeds? Here are 3 Carrot Seeds, on me.", "her line says so (%s)" % town.card.line)
	_check(town.toast.current_text() == "Received Carrot Seeds ×3", "the toast names the seeds (%s)" % town.toast.current_text())
	_check(town.toast.label().get_global_rect().end.y <= town.card_top() - 4.0 and town.card_top() <= town.card.line_label().get_global_rect().position.y,
		"C-186#9: the toast sits over the greeting card, clear of her line, portrait and name (q(16), C-185 §3.5)")
	_check(town.keys.size() == 1 and town.keys.has("trade") and town.keys.trade.text == "Trade", "Trade is still her one key (LOCK-16) (%s)" % [town.keys.keys()])
	town.close()
	await process_frame
	# Seeds sown and broke again the same player day: nothing more, her usual greeting.
	var saved: Dictionary = store.read()
	var sown: Dictionary = saved.farm.duplicate(true)
	sown.bag.erase("seed_carrot")
	store._save(sown, int(saved.farm_version))
	town = await _open(Town.MARKET, store)
	for i in 4: await process_frame
	_check(not store.read().farm.bag.has("seed_carrot") and town.card.line == Town.LINES.hello, "the same day: no second gift, her usual hello")
	town.close()
	await process_frame
	# The next player day (4 am Pacific) it comes again.
	store.now_ms = func() -> int: return ParcelFarm.next_rollover(ParcelFarm.rules(), T0)
	town = await _open(Town.MARKET, store)
	for i in 4: await process_frame
	_check(store.read().farm.bag.get("seed_carrot", 0) == 3, "the next player day: 3 more")
	town.close()
	await process_frame
	# Not broke (a carrot to sell): nothing is asked, nothing is given.
	_clean()
	store = _store_with({"crop_carrot": 1})
	town = await _open(Town.MARKET, store)
	for i in 4: await process_frame
	_check(not store.read().farm.bag.has("seed_carrot") and store.read().farm.seed_aid_day == null and town.aid_given.is_empty(),
		"with a carrot in the bag Jasmine gives nothing")
	town.close()
	await process_frame
	_clean()

func _broke() -> Dictionary:
	return ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {"hoe_starter": 1}, "welcomed_at": T0})

func _ints(v: Variant) -> Variant:
	if v is float and v == floorf(v): return int(v)
	if v is Dictionary:
		var out := {}
		for k in v: out[k] = _ints(v[k])
		return out
	if v is Array: return v.map(_ints)
	return v

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
