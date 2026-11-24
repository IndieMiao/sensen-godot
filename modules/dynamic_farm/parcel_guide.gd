extends RefCounted
## The first visit's next step on one's own parcel (C-35, 0.4.2): place the cottage, till, sow, harvest.
## Read from the save alone, so a parcel reopened halfway picks up at the same step; nothing once the
## first carrot is in the bag (or sold). The parcel shows it as the main farm's TipCard (UiTipCard).
## Copy for the owner's approval (C-35); English only, as the parcel's UI.

const BLUEPRINT := "blueprint_cottage"
const SEED := "seed_carrot"
const CROP := "crop_carrot"
const TIPS := {
	"build": "Tap Build Cottage to place your first home.",
	"till": "Pick a spot in your yard and press Till.",
	"sow": "Press Sow to plant Carrot Seeds in your soil.",
	"harvest": "Your carrot is ripe. Press Harvest!",
}

## The step to teach for `farm` (ParcelFarm.normalize) at server time `now_ms`: a TIPS key, or "".
static func step(farm: Dictionary, now_ms: int) -> String:
	if farm.is_empty(): return ""
	var bag: Dictionary = farm.get("bag", {})
	if int(bag.get(CROP, 0)) > 0 or int(farm.get("sales", 0)) > 0: return ""
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

static func text(key: String) -> String:
	return str(TIPS.get(key, ""))
