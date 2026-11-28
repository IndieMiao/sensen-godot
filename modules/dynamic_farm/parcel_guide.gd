extends RefCounted
## The first visit's next step on one's own parcel, read from the save alone, so a parcel reopened halfway picks up at
## the same step. 0.4.2 (C-35): place the cottage, till, sow, harvest. 0.4.3 (C-61) goes on from the first carrot:
## sell it at the Market, gather round the yard, sell what was gathered, then take the Coop Blueprint from the
## Carpenter (C-175 goes on from there, below). The parcel shows the step as the main farm's TipCard (UiTipCard);
## the community map says where to go for the steps done off the parcel (`map_text`).
## The 0.4.3 copy is for PM to finalise (C-45 / Q-61; docs/plans/C-61.md); English only, as the parcel's UI. C-115: the
## map's Market and Carpenter buttons became the Washington Square pin (Jasmine and Scott in its room; C-115#30), so the lines name it.
## C-151: a sown carrot needs water before it grows, so while one waits dry the guide asks for the well (while its
## blueprint waits) and then for watering, before any other step and also on farms past the first ten minutes (the
## farms that get the well and the pail on their next entry). Their copy is for PM to finalise.
## C-175 (0.4.5 run-through): a ripe carrot asks for Harvest before anything else; a pail that still holds water asks
## only for Water. Past the first sale the guide follows 0.4.5's content instead of C-61's gathering loop, whose
## "sell what you gathered" sold the Timber and Stone the farm upgrade (C-152) needs: Scott's coop blueprint, build the
## coop (C-154), feed a hen (growing or buying a carrot first when the bag has none), pick up and sell the egg, gather
## Timber and Stone, sell carrots and eggs if the upgrade's coins are short, and upgrade the farm at Scott's; nothing once
## the farm is past Lv1 (and its coop fed). `stage` is that milestone (the
## phone's task rows, ParcelTasks), `step` what to do next for it. The new copy is for PM to finalise (C-45).
## C-228 (0.4.7): the Build key became the Blueprints key (the blueprint book, any blueprint in any order), so the
## build, well and coop lines point at Blueprints (SEN-C-227 README §6 draft; PM finalises it per C-45).

const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const BLUEPRINT := "blueprint_cottage"
const SEED := "seed_carrot"
const CROP := "crop_carrot"
## The economy's blueprint the Carpenter gives (C-58 `economy.blueprints`); also the coop's building type (C-154).
const COOP := "coop"
const WELL_BLUEPRINT := "blueprint_well"
const TIPS := {
	"build": "Tap Blueprints to place your first home.",
	"till": "Pick a spot in your yard and press Till.",
	"sow": "Press Sow to plant Carrot Seeds in your soil.",
	"well": "Tap Blueprints to place your well.",
	"water": "Fill your pail at the well, then press Water on your seeds.",
	"water_pail": "Press Water on your seeds.",
	"harvest": "Your carrot is ripe. Press Harvest!",
	"sell": "Head back to the map and tap Washington Square to sell your carrot.",
	"blueprint": "Head back to the map and tap Washington Square for a coop blueprint.",
	"coop": "Tap Blueprints to place your coop.",
	"feed": "Walk up to the feeder in your coop and press Feed.",
	"buy_seeds": "Head back to the map and tap Washington Square to buy Carrot Seeds.",
	"egg": "Your hen lays an egg soon. Walk over to pick it up.",
	"sell_egg": "Head back to the map and tap Washington Square to sell your egg.",
	"gather_upgrade": "Gather Timber from trees and Stone from rocks for your farm upgrade.",
	"upgrade": "Head back to the map and tap Washington Square. Scott upgrades your farm.",
	"sell_for_coins": "Need more coins to upgrade. Sell carrots and eggs at Washington Square.",
	"earn_coins": "Need more coins to upgrade. Grow carrots to sell.",
}
## The map's line for the steps done off the parcel (and gathering, done back on it).
const MAP_TIPS := {
	"sell": "Tap Washington Square to sell your carrot.",
	"blueprint": "Tap Washington Square to get your coop blueprint.",
	"buy_seeds": "Tap Washington Square to buy Carrot Seeds.",
	"sell_egg": "Tap Washington Square to sell your egg.",
	"gather_upgrade": "Enter my farm and gather Timber and Stone.",
	"upgrade": "Tap Washington Square to upgrade your farm.",
	"sell_for_coins": "Tap Washington Square to sell carrots and eggs.",
	"earn_coins": "Enter my farm and grow carrots to sell.",
}

## The step to teach for `farm` (ParcelFarm.normalize) at server time `now_ms`: a TIPS key, or "".
static func step(farm: Dictionary, now_ms: int) -> String:
	if farm.is_empty(): return ""
	var bag: Dictionary = farm.get("bag", {})
	var crops: Dictionary = farm.get("crops", {})
	# A ripe carrot comes first (Harvest), also with another carrot already in the bag; a dry one asks for the well
	# or for water.
	var ripe := false
	var dry := false
	for key: String in crops:
		ripe = ripe or int(crops[key].get("ripe_at", 0)) <= now_ms
		dry = dry or ParcelFarm.is_dry(crops[key])
	if ripe: return "harvest"
	if dry:
		if not ParcelFarm.wells(ParcelFarm.rules(), farm).is_empty():
			return "water_pail" if int(farm.get("pail_water", 0)) > 0 else "water"
		if int(bag.get(WELL_BLUEPRINT, 0)) > 0: return "well"
	return step_past_water(farm, now_ms)

## The step `step` teaches once no ripe or dry carrot asks first (C-151): the phone's task list (C-107) has no row for
## the well and the water, so it reads its rows from `stage`, which this follows.
static func step_past_water(farm: Dictionary, now_ms: int) -> String:
	if farm.is_empty(): return ""
	var bag: Dictionary = farm.get("bag", {})
	var crops: Dictionary = farm.get("crops", {})
	var rules := ParcelFarm.rules()
	match stage(farm, now_ms):
		"build": return "build" if int(bag.get(BLUEPRINT, 0)) > 0 else ""
		"sell": return "sell"
		"blueprint": return "blueprint"
		"coop":
			var blueprint := str(rules.get("buildings", {}).get(COOP, {}).get("blueprint", ""))
			return "coop" if int(bag.get(blueprint, 0)) > 0 else ""
		"feed":
			var feed := str(_livestock(rules).get("feed", ""))
			if int(bag.get(feed, 0)) > 0: return "feed"
			if feed != CROP: return ""
			# No carrot for the hens: grow one (a ripe one was asked for above), or buy seeds for it.
			if not crops.is_empty(): return ""
			if int(bag.get(SEED, 0)) <= 0:
				return "buy_seeds" if rules.get("economy", {}).get("buy_prices", {}).has(SEED) else ""
			return _sow_or_till(farm)
		"sell_egg":
			var product := str(_livestock(rules).get("product", ""))
			for d: Dictionary in farm.get("drops", []):
				if int(d.get("ready_at", 0)) <= now_ms: return "egg"
			if int(bag.get(product, 0)) > 0: return "sell_egg"
			return "egg"
		"upgrade":
			var next := ParcelFarm.next_level(rules, ParcelFarm.farm_level(farm))
			var items: Dictionary = next.get("items", {})
			for item: String in items:
				if int(bag.get(item, 0)) < int(items[item]): return "gather_upgrade"
			if int(farm.get("coins", 0)) < int(next.get("coins", 0)):
				# Short of coins (C-175#51): sell the carrots and eggs in the bag, or grow and collect some first.
				for item: String in [CROP, str(_livestock(rules).get("product", ""))]:
					if not item.is_empty() and int(bag.get(item, 0)) > 0: return "sell_for_coins"
				return "earn_coins"
			return "upgrade"
		"harvest":
			for key: String in crops:
				if int(crops[key].get("ripe_at", 0)) <= now_ms: return "harvest"
			return ""
		"sow", "till":
			if int(bag.get(SEED, 0)) <= 0: return ""
			return _sow_or_till(farm)
	return ""

## The milestone the save has reached, in the order of the phone's task rows (ParcelTasks.TASKS): build, till, sow,
## harvest, sell (the first carrot), blueprint, coop, feed, sell_egg (the first egg), upgrade; "" once every one is
## done (or before the save is read). Read from the save alone, so a parcel reopened halfway is at the same one; only
## the first egg cannot be told from a later one (ParcelTasks keeps what the device saw). Rules without the coop
## blueprint, the coop or farm levels skip those milestones; an upgraded farm has nothing left but feeding a coop never fed.
static func stage(farm: Dictionary, _now_ms: int) -> String:
	if farm.is_empty(): return ""
	var bag: Dictionary = farm.get("bag", {})
	var rules := ParcelFarm.rules()
	if int(farm.get("sales", 0)) > 0:
		if rules.get("economy", {}).get("blueprints", {}).has(COOP) and not farm.get("blueprints_claimed", {}).has(COOP):
			return "blueprint"
		var level := ParcelFarm.farm_level(farm)
		if not _livestock(rules).is_empty():
			if not ParcelFarm.buildings_of(farm).any(func(b: Dictionary): return str(b.get("type", "")) == COOP): return "coop"
			if int(farm.get("drop_seq", 0)) <= 0: return "feed"
			var product := str(_livestock(rules).get("product", ""))
			if level <= 1 and (not (farm.get("drops", []) as Array).is_empty() or int(bag.get(product, 0)) > 0): return "sell_egg"
		if level <= 1 and not ParcelFarm.next_level(rules, level).is_empty(): return "upgrade"
		return ""
	if int(bag.get(CROP, 0)) > 0: return "sell"
	if not farm.get("house") is Dictionary: return "build"
	if not (farm.get("crops", {}) as Dictionary).is_empty(): return "harvest"
	return "sow" if not (farm.get("tilled", []) as Array).is_empty() else "till"

static func _sow_or_till(farm: Dictionary) -> String:
	var crops: Dictionary = farm.get("crops", {})
	for key in farm.get("tilled", []):
		if not crops.has(key): return "sow"
	return "till"

## The coop's livestock rule (C-154: feed, product, …), {} when the rules have no coop.
static func _livestock(rules: Dictionary) -> Dictionary:
	var coop = rules.get("buildings", {}).get(COOP)
	if not coop is Dictionary: return {}
	return coop.get("livestock", {}) if coop.get("livestock") is Dictionary else {}

static func text(key: String) -> String:
	return str(TIPS.get(key, ""))

## The map's line for a step, or "" for the steps taught on the parcel itself.
static func map_text(key: String) -> String:
	return str(MAP_TIPS.get(key, ""))
