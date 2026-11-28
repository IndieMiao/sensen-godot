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
## Timber and Stone, sell farm goods if the upgrade's coins are short, and upgrade the farm at Scott's; nothing once
## the farm is past Lv1 (and its coop fed). `stage` is that milestone (the
## phone's task rows, ParcelTasks), `step` what to do next for it. The new copy is for PM to finalise (C-45).
## C-190 (0.4.6 run-through) goes on past the upgrade with 0.4.6's content: deliver a first request at the Request Board
## (C-191), buy and build the barn (C-192: Lv2, coins, Timber and Stone), feed its cows while the sheep pen's blueprint
## waits on its requests, Lv3 and coins (C-182), build the pen and feed its sheep (Wild Herb from the yard's flowers).
## Wool once sold leaves no trace in the save, so feeding the sheep comes back as a step after it; the parcel passes
## `finished` once this device saw every row done (ParcelTasks), which drops it. Copy as PM finalised it on C-190#29 (C-45).

const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const BLUEPRINT := "blueprint_cottage"
const SEED := "seed_carrot"
const CROP := "crop_carrot"
## The economy's blueprint the Carpenter gives (C-58 `economy.blueprints`); also the coop's building type (C-154).
const COOP := "coop"
## C-190: 0.4.6's blueprints, also their building types (C-192, C-182).
const BARN := "barn"
const SHEEP_PEN := "sheep_pen"
const WELL_BLUEPRINT := "blueprint_well"
const TIPS := {
	"build": "Tap Build Cottage to place your first home.",
	"till": "Pick a spot in your yard and press Till.",
	"sow": "Press Sow to plant Carrot Seeds in your soil.",
	"well": "Tap Build Well to place your well.",
	"water": "Fill your pail at the well, then press Water on your seeds.",
	"water_pail": "Press Water on your seeds.",
	"harvest": "Your carrot is ripe. Press Harvest!",
	"sell": "Head back to the map and tap Washington Square to sell your carrot.",
	"blueprint": "Head back to the map and tap Washington Square for a coop blueprint.",
	"coop": "Tap Build Coop to place your coop.",
	"feed": "Walk up to the feeder in your coop and press Feed.",
	"buy_seeds": "Head back to the map and tap Washington Square to buy Carrot Seeds.",
	"egg": "Your hen lays an egg soon. Walk over to pick it up.",
	"sell_egg": "Head back to the map and tap Washington Square to sell your egg.",
	"gather_upgrade": "Gather Timber from trees and Stone from rocks for your farm upgrade.",
	"upgrade": "Head back to the map and tap Washington Square. Scott upgrades your farm.",
	"sell_for_coins": "Need more coins to upgrade. Sell farm goods at Washington Square.",
	"earn_coins": "Need more coins to upgrade. Grow carrots to sell.",
	"request": "Tap Washington Square on the map and deliver a request at the Request Board.",
	"barn_coins": "Save up coins for the Barn Blueprint. Deliver requests and sell at Washington Square.",
	"barn_blueprint": "Head back to the map and tap Washington Square. Scott sells the Barn Blueprint.",
	"gather_barn": "Gather Timber from trees and Stone from rocks for your barn.",
	"barn": "Tap Build Barn to place your barn.",
	"feed_cows": "Walk up to the trough in your barn and press Feed.",
	"pen_requests": "Deliver more requests at the Request Board to unlock the Sheep Pen.",
	"pen_coins": "Save up coins for the Sheep Pen Blueprint. Deliver requests and sell at Washington Square.",
	"pen_blueprint": "Head back to the map and tap Washington Square. Scott sells the Sheep Pen Blueprint.",
	"gather_pen": "Gather Timber from trees and Stone from rocks for your sheep pen.",
	"sheep_pen": "Tap Build Sheep Pen to place your sheep pen.",
	"gather_herbs": "Gather Wild Herb from the flowers around your yard to feed your sheep.",
	"feed_sheep": "Walk up to the feeder in your sheep pen and press Feed.",
}
## The map's line for the steps done off the parcel (and gathering, done back on it).
const MAP_TIPS := {
	"sell": "Tap Washington Square to sell your carrot.",
	"blueprint": "Tap Washington Square to get your coop blueprint.",
	"buy_seeds": "Tap Washington Square to buy Carrot Seeds.",
	"sell_egg": "Tap Washington Square to sell your egg.",
	"gather_upgrade": "Enter my farm and gather Timber and Stone.",
	"upgrade": "Tap Washington Square to upgrade your farm.",
	"sell_for_coins": "Tap Washington Square to sell farm goods.",
	"earn_coins": "Enter my farm and grow carrots to sell.",
	"request": "Tap Washington Square to deliver a request at the Request Board.",
	"barn_coins": "Tap Washington Square to deliver requests and sell.",
	"barn_blueprint": "Tap Washington Square to buy the Barn Blueprint.",
	"gather_barn": "Enter my farm and gather Timber and Stone.",
	"pen_requests": "Tap Washington Square to deliver requests at the Request Board.",
	"pen_coins": "Tap Washington Square to deliver requests and sell.",
	"pen_blueprint": "Tap Washington Square to buy the Sheep Pen Blueprint.",
	"gather_pen": "Enter my farm and gather Timber and Stone.",
}

## The step to teach for `farm` (ParcelFarm.normalize) at server time `now_ms`: a TIPS key, or "". `finished`: this
## device saw every task row done, so a milestone the save shows again (feeding the sheep once its wool was sold) is not.
static func step(farm: Dictionary, now_ms: int, finished := false) -> String:
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
	if finished and stage(farm, now_ms) == "feed_sheep": return ""
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
		"upgrade": return _upgrade_step(farm, rules)
		"request": return "request"
		"barn":
			# Coins first, then Scott's blueprint, then its Timber and Stone and the Build Barn key.
			match _blueprint_state(farm, rules, BARN):
				"bag": return "gather_barn" if _short_of_materials(farm, rules, BARN) else "barn"
				"level": return _upgrade_step(farm, rules)
				"coins": return "barn_coins"
				"buy": return "barn_blueprint"
			return ""
		"sheep_pen":
			# The pen's blueprint in the bag: its Timber and Stone and Build Sheep Pen. Before that, cows left unfed while the
			# pen waits on requests, Lv3 and coins come first (their milk sells and fills requests); a cow with milk still to
			# give or on the ground leaves this to the pen.
			var pen := _blueprint_state(farm, rules, SHEEP_PEN)
			if pen == "bag": return "gather_pen" if _short_of_materials(farm, rules, SHEEP_PEN) else "sheep_pen"
			var cows := _livestock(rules, BARN)
			var barn := _building(farm, BARN)
			if not barn.is_empty() and ParcelFarm.drops_in(farm, int(barn.get("id", 0))).is_empty() \
					and int(bag.get(str(cows.get("feed", "")), 0)) >= int(cows.get("feed_amount", 1)):
				return "feed_cows"
			match pen:
				"requests": return "pen_requests"
				"level": return _upgrade_step(farm, rules)
				"coins": return "pen_coins"
				"buy": return "pen_blueprint"
			return ""
		"feed_sheep":
			var sheep := _livestock(rules, SHEEP_PEN)
			return "feed_sheep" if int(bag.get(str(sheep.get("feed", "")), 0)) >= int(sheep.get("feed_amount", 1)) else "gather_herbs"
		"harvest":
			for key: String in crops:
				if int(crops[key].get("ripe_at", 0)) <= now_ms: return "harvest"
			return ""
		"sow", "till":
			if int(bag.get(SEED, 0)) <= 0: return ""
			return _sow_or_till(farm)
	return ""

## The milestone the save has reached, in the order of the phone's task rows (ParcelTasks.TASKS): build, till, sow,
## harvest, sell (the first carrot), blueprint, coop, feed, sell_egg (the first egg), upgrade, then 0.4.6's request (the
## first delivered), barn, sheep_pen, feed_sheep (no wool from it yet); "" once every one is done (or before the save is
## read). Read from the save alone, so a parcel reopened halfway is at the same one; only the first egg and the first wool
## cannot be told from later ones (ParcelTasks keeps what the device saw). Rules without the coop blueprint, the coop,
## farm levels, the Request Board, the barn or the sheep pen skip those milestones.
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
		return _stage_past_upgrade(farm, rules)
	if int(bag.get(CROP, 0)) > 0: return "sell"
	if not farm.get("house") is Dictionary: return "build"
	if not (farm.get("crops", {}) as Dictionary).is_empty(): return "harvest"
	return "sow" if not (farm.get("tilled", []) as Array).is_empty() else "till"

static func _sow_or_till(farm: Dictionary) -> String:
	var crops: Dictionary = farm.get("crops", {})
	for key in farm.get("tilled", []):
		if not crops.has(key): return "sow"
	return "till"

## A livestock building's rule (C-154: feed, feed_amount, product, …; the coop's by default), {} when the rules have none.
static func _livestock(rules: Dictionary, type := COOP) -> Dictionary:
	var building = rules.get("buildings", {}).get(type)
	if not building is Dictionary: return {}
	return building.get("livestock", {}) if building.get("livestock") is Dictionary else {}

## C-190: 0.4.6's milestones once the farm is past Lv1 (stage): the first request, the barn, the sheep pen and its first
## wool, each skipped when the rules do not have it.
static func _stage_past_upgrade(farm: Dictionary, rules: Dictionary) -> String:
	if not (rules.get("requests", {}) as Dictionary).is_empty() and int(farm.get("requests_done", 0)) <= 0: return "request"
	for type: String in [BARN, SHEEP_PEN]:
		if _sold(rules, type) and _building(farm, type).is_empty(): return type
	var pen := _building(farm, SHEEP_PEN)
	if not pen.is_empty() and not _livestock(rules, SHEEP_PEN).is_empty():
		var wool := str(_livestock(rules, SHEEP_PEN).get("product", ""))
		if ParcelFarm.drops_in(farm, int(pen.get("id", 0))).is_empty() and int(farm.get("bag", {}).get(wool, 0)) <= 0:
			return "feed_sheep"
	return ""

## The rules build `type` from a blueprint Scott sells (economy.blueprints.<type>).
static func _sold(rules: Dictionary, type: String) -> bool:
	return rules.get("buildings", {}).get(type) is Dictionary and rules.get("economy", {}).get("blueprints", {}).has(type)

## The first building of `type` on the farm, {} when none.
static func _building(farm: Dictionary, type: String) -> Dictionary:
	for b: Dictionary in ParcelFarm.buildings_of(farm):
		if str(b.get("type", "")) == type: return b
	return {}

## Where the blueprint for `type` stands, in the order Scott's key and the server check it (C-182 parcel_town):
## "bag" (to build), "requests", "level", "coins" (what it still waits on), "buy", or "" (bought and not in the bag).
static func _blueprint_state(farm: Dictionary, rules: Dictionary, type: String) -> String:
	var item := str(rules.get("buildings", {}).get(type, {}).get("blueprint", ""))
	if int(farm.get("bag", {}).get(item, 0)) > 0: return "bag"
	if farm.get("blueprints_claimed", {}).has(type): return ""
	var rule: Dictionary = rules.get("economy", {}).get("blueprints", {}).get(type, {})
	if int(farm.get("requests_done", 0)) < int(rule.get("min_requests", 0)): return "requests"
	if ParcelFarm.farm_level(farm) < int(rule.get("min_level", 1)): return "level"
	if int(farm.get("coins", 0)) < int(rule.get("coins", 0)): return "coins"
	return "buy"

static func _short_of_materials(farm: Dictionary, rules: Dictionary, type: String) -> bool:
	var materials: Dictionary = rules.get("buildings", {}).get(type, {}).get("materials", {})
	for item: String in materials:
		if int(farm.get("bag", {}).get(item, 0)) < int(materials[item]): return true
	return false

## The next farm level's step (C-152, C-175#51): gather its Timber and Stone, sell farm goods or grow some when its
## coins are short, then upgrade at Scott's.
static func _upgrade_step(farm: Dictionary, rules: Dictionary) -> String:
	var bag: Dictionary = farm.get("bag", {})
	var next := ParcelFarm.next_level(rules, ParcelFarm.farm_level(farm))
	if next.is_empty(): return ""
	var items: Dictionary = next.get("items", {})
	for item: String in items:
		if int(bag.get(item, 0)) < int(items[item]): return "gather_upgrade"
	if int(farm.get("coins", 0)) < int(next.get("coins", 0)):
		# Short of coins (C-175#51): sell the farm goods in the bag (carrots and the eggs, milk and wool, C-190#65), or
		# grow and collect some first.
		for item: String in [CROP, str(_livestock(rules).get("product", "")), str(_livestock(rules, BARN).get("product", "")),
				str(_livestock(rules, SHEEP_PEN).get("product", ""))]:
			if not item.is_empty() and int(bag.get(item, 0)) > 0: return "sell_for_coins"
		return "earn_coins"
	return "upgrade"

static func text(key: String) -> String:
	return str(TIPS.get(key, ""))

## The map's line for a step, or "" for the steps taught on the parcel itself.
static func map_text(key: String) -> String:
	return str(MAP_TIPS.get(key, ""))
