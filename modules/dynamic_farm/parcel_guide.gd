extends RefCounted
## The first visit's next step on one's own parcel, read from the save alone, so a parcel reopened halfway picks up at
## the same step. 0.4.2 (C-35): place the cottage, till, sow, harvest. 0.4.3 (C-61) goes on from the first carrot:
## sell it at the Market, gather round the yard, sell what was gathered, then take the Coop Blueprint from the
## Carpenter; nothing once that blueprint is claimed. The parcel shows the step as the main farm's TipCard (UiTipCard);
## the community map says where to go for the steps done off the parcel (`map_text`).
## The 0.4.3 copy is for PM to finalise (C-45 / Q-61; docs/plans/C-61.md); English only, as the parcel's UI. C-115: the
## map's Market and Carpenter buttons became the Washington Square pin (Jasmine and Scott in its room; C-115#30), so the lines name it.

const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Gather = preload("res://modules/dynamic_farm/parcel_gather.gd")
const BLUEPRINT := "blueprint_cottage"
const SEED := "seed_carrot"
const CROP := "crop_carrot"
## The economy's blueprint the Carpenter gives (C-58 `economy.blueprints`).
const COOP := "coop"
const TIPS := {
	"build": "Tap Build Cottage to place your first home.",
	"till": "Pick a spot in your yard and press Till.",
	"sow": "Press Sow to plant Carrot Seeds in your soil.",
	"harvest": "Your carrot is ripe. Press Harvest!",
	"sell": "Head back to the map and tap Washington Square to sell your carrot.",
	"gather": "Walk up to a tree, flower or rock and press Gather.",
	"sell_gathered": "Head back to the map and tap Washington Square to sell what you gathered.",
	"blueprint": "Head back to the map and tap Washington Square for a coop blueprint.",
}
## The map's line for the steps done off the parcel (and gathering, done back on it).
const MAP_TIPS := {
	"sell": "Tap Washington Square to sell your carrot.",
	"gather": "Enter my farm and gather from trees, flowers and rocks.",
	"sell_gathered": "Tap Washington Square to sell what you gathered.",
	"blueprint": "Tap Washington Square to get your coop blueprint.",
}

## The step to teach for `farm` (ParcelFarm.normalize) at server time `now_ms`: a TIPS key, or "".
static func step(farm: Dictionary, now_ms: int) -> String:
	if farm.is_empty() or farm.get("blueprints_claimed", {}).has(COOP): return ""
	var bag: Dictionary = farm.get("bag", {})
	if int(farm.get("sales", 0)) > 0:
		if _holds_gathered(bag): return "sell_gathered"
		if farm.get("gathered", {}).is_empty() and not Gather.rules().is_empty(): return "gather"
		return "blueprint" if ParcelFarm.rules().get("economy", {}).get("blueprints", {}).has(COOP) else ""
	if int(bag.get(CROP, 0)) > 0: return "sell"
	if not farm.get("house") is Dictionary:
		return "build" if int(bag.get(BLUEPRINT, 0)) > 0 else ""
	var crops: Dictionary = farm.get("crops", {})
	if not crops.is_empty():
		for key: String in crops:
			if int(crops[key].get("ripe_at", 0)) <= now_ms: return "harvest"
		return ""
	if int(bag.get(SEED, 0)) <= 0: return ""
	for key in farm.get("tilled", []):
		if not crops.has(key): return "sow"
	return "till"

## Whether the bag holds something gathered round the yard that the Market buys.
static func _holds_gathered(bag: Dictionary) -> bool:
	var prices: Dictionary = ParcelFarm.rules().get("economy", {}).get("sell_prices", {})
	for source: Dictionary in Gather.rules().get("sources", {}).values():
		if prices.has(source.item) and int(bag.get(source.item, 0)) > 0: return true
	return false

static func text(key: String) -> String:
	return str(TIPS.get(key, ""))

## The map's line for a step, or "" for the steps taught on the parcel itself.
static func map_text(key: String) -> String:
	return str(MAP_TIPS.get(key, ""))
