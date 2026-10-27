extends RefCounted
## SGODOT-341 C3: presentation only. Confirmed catch/resend events drive feedback; polling the view never pays it.
## q(215) §14.3 / q(217): the last fish can already have moved the server past the goal in the same reply.

const RESEND_LINE := "Out of radishes? Here, two more quick ones."
var _last_seq := -1
var _pending_fish: Dictionary = {}

## A network recovery can read the advanced view before retrying a lost reel reply. Retain that command's goal;
## a new cast discards it, so a later unrelated catch cannot inherit an old recovery target.
func sent(cmd: Dictionary, view: Dictionary) -> void:
	if str(cmd.get("type", "")) == "cast": _pending_fish = {}
	if str(cmd.get("type", "")) == "reel" and str(cmd.get("outcome", "")) == "landed" \
		and _pending_fish.is_empty() and not fish_goal(view).is_empty():
		_pending_fish = view.duplicate(true)

## One runtime belongs to one account. A retried command can return the same seq/events; say them only once.
## Empty refreshes do not consume seq: the command's events may still be on their way.
func take(before: Dictionary, after: Dictionary, events: Array) -> Dictionary:
	var out := {fish = {}, resends = [], fresh = false}
	if events.is_empty(): return out
	var seq := int(after.get("seq", -1))
	if seq >= 0 and seq <= _last_seq: return out
	if seq >= 0: _last_seq = seq
	out.fresh = true
	out.fish = fish_progress(_pending_fish if not _pending_fish.is_empty() else before, after, events)
	if events.any(func(e): return str(e.get("kind", "")) == "catch"): _pending_fish = {}
	for ev in events:
		if str(ev.get("kind", "")) != "guide" or str(ev.get("action", "")) != "resend": continue
		var id := str(ev.get("item", ""))
		if id == "" or int(ev.get("qty", 0)) <= 0: continue
		out.resends.append({item = id, bagged = clampi(int(ev.get("bagged", 0)), 0, int(ev.qty)), line = RESEND_LINE, affinity = []})
	return out

## A structured pond target, never a guess from English row.line, the fish icon or bundled step ids.
static func fish_goal(view: Dictionary) -> Dictionary:
	var g := P0Guide.guide_shown(view)
	var p = g.get("progress")
	var row = g.get("row")
	if not p is Dictionary or not row is Dictionary or int(p.get("need", 0)) <= 0: return {}
	var go := P0Guide.guide_go(view, str(row.get("go", "")) if row.get("go") != null else "")
	if not go.begins_with("pond:"): return {}
	return {step = str(g.get("step", "")), recover = str(g.get("recover", "")), go = go,
		have = maxi(0, int(p.get("have", 0))), need = int(p.need)}

static func fish_progress(before: Dictionary, after: Dictionary, events: Array) -> Dictionary:
	var goal := fish_goal(before)
	if goal.is_empty(): return {}
	var landed := events.filter(func(e): return str(e.get("kind", "")) == "catch" and str(e.get("result", "")) == "landed").size()
	if landed == 0 or int(goal.have) >= int(goal.need): return {}
	# A timeout cuts guidance off; it must not invent a completed goal just because a fish landed on that reply.
	if str(after.get("guide", {}).get("end", "")) in ["timeout", "legacy"]: return {}
	var next := fish_goal(after)
	var have := mini(int(goal.need), int(goal.have) + landed)
	var recover = before.get("guide", {}).get("recover")
	if not next.is_empty() and next.step == goal.step and next.recover == goal.recover:
		have = mini(int(goal.need), int(next.have))   # recover counts held cookable fish, not every fish event
	elif (recover == null or str(recover) == "") and events.any(func(e):
		return str(e.get("kind", "")) == "guide" and str(e.get("action", "")) == "step" and str(e.get("from", "")) == goal.step):
		have = int(goal.need)   # server-confirmed completion, even if an earlier catch reply was lost
	if have <= int(goal.have): return {}
	return {kind = "request", key = "guide_fish", text = "Catch %d fish %d/%d" % [int(goal.need), have, int(goal.need)],
		tone = UiFloatText.Tone.ITEM}
