class_name DayGoals
extends RefCounted
## Chapter facts are server-owned; only D0's intermediate farming steps use the visible plots.

const PATH := "res://assets/farm/data/chapters.json"
const TITLES := ["First harvest", "A rainy day", "Share your harvest", "At the kitchen",
	"Farm visits", "Room to grow", "A garden together"]
const LABELS := {
	"farm_created": "Create your farm",
	"first_harvest": "Harvest your first crop",
	"rain_care_done": "Care for crops in the rain",
	"request_d1_bistro_lettuce_done": "Complete the bistro's lettuce request",
	"life_choice_resolved": "Choose a use for your harvest",
	"second_resident_remembers": "Share your choice with another resident",
	"first_salad_cooked": "Make your first salad together",
	"request_d3_nursery_basket_done": "Complete the nursery request",
	"visit_tutorial_completed": "Visit a farm and return",
	"engineering_first_submitted": "Contribute to the nursery basket",
	"growth_intent_set": "Choose tools or another garden bed",
	"wind_care_done": "Care for crops in the wind",
	"engineering_quota_complete": "Complete the nursery basket",
	"shared_scene_done": "Join the garden gathering",
}
static var _chapters: Array = []

static func definition(index: int) -> Dictionary:
	if _chapters.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_chapters = parsed.get("chapters", []) if parsed is Dictionary else []
	return _chapters[index] if index >= 0 and index < _chapters.size() else {}

static func chapter_state(state: Dictionary, index: int) -> Dictionary:
	var chapters = state.get("chapters", [])
	if chapters is Array and index >= 0 and index < chapters.size() and chapters[index] is Dictionary:
		return chapters[index]
	return {}

static func _confirmed(flags: Dictionary, fact: String) -> bool:
	var value = flags.get(fact, false)
	return value is bool and value

static func evaluate(state: Dictionary, cells: Dictionary) -> Array:
	if JourneyProgress.active(state): return JourneyProgress.goals(state)
	var index := int((state.get("clock", {}) as Dictionary).get("chapter_index", 0))
	var chapter := definition(index)
	if chapter.is_empty(): return []
	var current := chapter_state(state, index)
	var raw_flags = current.get("step_flags", {})
	var flags: Dictionary = raw_flags if raw_flags is Dictionary else {}
	var goals := []
	for fact in chapter.get("min_facts", []):
		goals.append({"id": str(fact), "label": str(LABELS.get(fact, L10n.text("Chapter goal"))), "done": _confirmed(flags, str(fact))})
	if index != 0: return goals
	var steps := _farming_steps(state, cells, _confirmed(flags, "first_harvest"))
	for i in steps.size():
		goals.insert(i + 1, steps[i])
	return goals

static func _farming_steps(state: Dictionary, cells: Dictionary, first_harvest: bool) -> Array:
	var xp: Dictionary = state.get("xp", {})
	var states := []
	for id in cells:
		states.append(str((cells[id] as Dictionary).get("state", "")))
	var any := func(list: Array) -> bool:
		for s in states:
			if list.has(s):
				return true
		return false
	var harvested: bool = first_harvest or (xp.get("first_harvest_crops", []) as Array).size() > 0
	# 四步生命周期：开垦 → 播种 → 浇水 → 收割。
	var tilled_any: bool = harvested or int(xp.get("tilled_total", 0)) > 0 \
		or any.call(["tilled", "sown", "growing"])
	var sown_any: bool = harvested or any.call(["sown", "growing"])
	var watered_any: bool = harvested or any.call(["growing"])
	return [
		{"id": "till", "label": L10n.text("Till a plot"), "done": tilled_any},
		{"id": "sow", "label": L10n.text("Sow a radish"), "done": sown_any},
		{"id": "water", "label": L10n.text("Water it"), "done": watered_any},
	]

static func progress(state: Dictionary, derived: Dictionary = {}, now_ms := 0) -> Dictionary:
	if JourneyProgress.active(state):
		return {"index": 0, "title": str(JourneyProgress.next_goal(state).label), "journey": true,
			"complete": JourneyProgress.unlocked(state, "garden"), "next_open_in_ms": -1, "last_chapter": true, "pending": false}
	var index := int((state.get("clock", {}) as Dictionary).get("chapter_index", 0))
	var chapter := definition(index)
	var current := chapter_state(state, index)
	var raw_flags = current.get("step_flags", {})
	var flags: Dictionary = raw_flags if raw_flags is Dictionary else {}
	var complete := str(current.get("status", "")) == "done" and not chapter.is_empty()
	for fact in chapter.get("min_facts", []):
		complete = complete and _confirmed(flags, str(fact))
	var next_at = derived.get("next_chapter_opens_at")
	var remaining := -1
	if complete and not definition(index + 1).is_empty() and int(derived.get("chapter_index", index)) == index \
			and (next_at is int or next_at is float) and next_at > 0:
		remaining = maxi(0, int(next_at) - now_ms)
	return {"index": index, "title": TITLES[index] if index >= 0 and index < TITLES.size() else L10n.text("Chapter goals"),
		"complete": complete, "next_open_in_ms": remaining, "last_chapter": not chapter.is_empty() and definition(index + 1).is_empty(),
		"pending": chapter.is_empty() or current.is_empty() or str(current.get("status", "")) == "done" and not complete}

static func done_count(goals: Array) -> int:
	var n := 0
	for g in goals:
		if bool(g.done):
			n += 1
	return n
