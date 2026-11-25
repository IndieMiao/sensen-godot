extends RefCounted
## The in-game phone's task list (C-107, design C-85 ⑧): the first-visit guide's steps (ParcelGuide) as rows in order,
## read from the save (and, for one row, how far this device saw it get: `done_count`), so a parcel reopened halfway
## shows the same rows done. GET STARTED is the parcel's first
## four steps (C-35), TOWN what comes after the first carrot (C-61): selling to Jasmine, gathering round the yard,
## selling what was gathered and Scott's coop blueprint. No new step, reward or number: a row is done once the guide has
## moved past it. English only, as the parcel's UI.

const Guide = preload("res://modules/dynamic_farm/parcel_guide.gd")

const GET_STARTED := "GET STARTED"
const TOWN := "TOWN"
## In the guide's order. Titles of the design's rows (C-85 ⑧-B); the two gathering rows follow C-61's steps.
const TASKS := [
	{"key": "build", "group": GET_STARTED, "title": "Build Cottage"},
	{"key": "till", "group": GET_STARTED, "title": "Till your yard"},
	{"key": "sow", "group": GET_STARTED, "title": "Sow Carrot Seeds"},
	{"key": "harvest", "group": GET_STARTED, "title": "Harvest a carrot"},
	{"key": "sell", "group": TOWN, "title": "Sell to Jasmine"},
	{"key": "gather", "group": TOWN, "title": "Gather in your yard"},
	{"key": "sell_gathered", "group": TOWN, "title": "Sell what you gathered"},
	{"key": "blueprint", "group": TOWN, "title": "Take Scott's blueprint"},
]

static func keys() -> Array:
	return TASKS.map(func(t: Dictionary): return t.key)

## How many rows are done, in order (0 … TASKS.size()); the row at that index is the current one. Where the guide has
## no step to teach just now, the save still says how far the player got: a carrot growing waits on Harvest, a parcel
## that has sold waits on the blueprint (rules without one: it stays open), the coop blueprint ends the list.
## `reached` is the rows this device last counted done on the parcel: gathering again after selling what was
## gathered sends the guide back to Sell what you gathered, which the save cannot tell from a first gathering, so a
## parcel that already got past it keeps the row done.
static func done_count(farm: Dictionary, now_ms: int, reached := 0) -> int:
	if farm.is_empty(): return 0
	if farm.get("blueprints_claimed", {}).has(Guide.COOP): return TASKS.size()
	var order := keys()
	var step := Guide.step(farm, now_ms)
	if step == "sell_gathered" and reached > order.find(step): return order.find("blueprint")
	if not step.is_empty(): return order.find(step)
	if int(farm.get("sales", 0)) > 0: return order.find("blueprint")
	if not farm.get("house") is Dictionary: return 0
	if not (farm.get("crops", {}) as Dictionary).is_empty(): return order.find("harvest")
	return order.find("sow") if not (farm.get("tilled", []) as Array).is_empty() else order.find("till")

## The rows for `farm`: [{key, group, title, state: "done" | "current" | "todo"}].
static func rows(farm: Dictionary, now_ms: int, reached := 0) -> Array:
	var done := done_count(farm, now_ms, reached)
	var out := []
	for i in TASKS.size():
		var row: Dictionary = TASKS[i].duplicate()
		row.state = "done" if i < done else "current" if i == done else "todo"
		out.append(row)
	return out

## The current row's key, "" once every row is done (or before the save is read).
static func current(farm: Dictionary, now_ms: int, reached := 0) -> String:
	if farm.is_empty(): return ""
	var done := done_count(farm, now_ms, reached)
	return str(TASKS[done].key) if done < TASKS.size() else ""

static func title(key: String) -> String:
	for t: Dictionary in TASKS:
		if t.key == key: return str(t.title)
	return ""
