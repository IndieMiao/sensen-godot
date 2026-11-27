extends RefCounted
## The in-game phone's task list (C-107, design C-85 ⑧): the first-visit guide's milestones (ParcelGuide.stage) as rows
## in order, read from the save (and, for one row, how far this device saw it get: `done_count`), so a parcel reopened
## halfway shows the same rows done. GET STARTED is the parcel's first four steps (C-35), TOWN the first sale to
## Jasmine and Scott's coop blueprint (C-61). C-175 (0.4.5): C-61's two gathering rows gave way to YOUR FARM, 0.4.5's
## content after the blueprint: build the coop, feed a hen, sell an egg, upgrade the farm (gathering is part of that
## last one). No new step, reward or number: a row is done once the guide has moved past it. English only, as the
## parcel's UI; the new rows' copy is for PM to finalise (C-45). C-190 (0.4.6) adds REQUESTS & ANIMALS: the first
## delivered request, the barn, the sheep pen and feeding its sheep.

const Guide = preload("res://modules/dynamic_farm/parcel_guide.gd")

const GET_STARTED := "GET STARTED"
const TOWN := "TOWN"
const YOUR_FARM := "YOUR FARM"
const ANIMALS := "REQUESTS & ANIMALS"
## In the guide's order. Titles of the design's rows (C-85 ⑧-B); C-175's four rows follow its milestones.
const TASKS := [
	{"key": "build", "group": GET_STARTED, "title": "Build Cottage"},
	{"key": "till", "group": GET_STARTED, "title": "Till your yard"},
	{"key": "sow", "group": GET_STARTED, "title": "Sow Carrot Seeds"},
	{"key": "harvest", "group": GET_STARTED, "title": "Harvest a carrot"},
	{"key": "sell", "group": TOWN, "title": "Sell to Jasmine"},
	{"key": "blueprint", "group": TOWN, "title": "Take Scott's blueprint"},
	{"key": "coop", "group": YOUR_FARM, "title": "Build the Coop"},
	{"key": "feed", "group": YOUR_FARM, "title": "Feed a hen"},
	{"key": "sell_egg", "group": YOUR_FARM, "title": "Sell an egg"},
	{"key": "upgrade", "group": YOUR_FARM, "title": "Upgrade your farm"},
	{"key": "request", "group": ANIMALS, "title": "Deliver a request"},
	{"key": "barn", "group": ANIMALS, "title": "Build the Barn"},
	{"key": "sheep_pen", "group": ANIMALS, "title": "Build the Sheep Pen"},
	{"key": "feed_sheep", "group": ANIMALS, "title": "Feed the sheep"},
]

static func keys() -> Array:
	return TASKS.map(func(t: Dictionary): return t.key)

## How many rows are done, in order (0 … TASKS.size()); the row at that index is the current one: the guide's
## milestone (ParcelGuide.stage; a carrot growing or sown dry waits on Harvest, a hen still to lay waits on Sell an egg).
## `reached` is the rows this device last counted done on the parcel: feeding again after selling the first egg sends
## the milestone back to Sell an egg, which the save cannot tell from the first egg, so a parcel that already got past
## it keeps the row done. Feeding the sheep (C-190) is the same once their wool is sold.
static func done_count(farm: Dictionary, now_ms: int, reached := 0) -> int:
	if farm.is_empty(): return 0
	var order := keys()
	var stage := Guide.stage(farm, now_ms)
	if stage.is_empty(): return TASKS.size()
	if stage == "sell_egg" and reached > order.find(stage): return order.find("upgrade")
	if stage == "feed_sheep" and reached > order.find(stage): return TASKS.size()
	return order.find(stage)

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
