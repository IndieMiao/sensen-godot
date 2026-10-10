extends RefCounted
## Fish Trap on the client (SGODOT-283; plan §6.8, q(109) ⑦, 不知火舞's spec on 283): the quick bar's Set Trap key,
## the trap's EntryCard, its name strip, the pond card's fact, Today's row, the event toasts and the refusals — all from
## view.fishing.trap (server/src/p0/fish_trap.ts trapsView: traps [{place, fish, keep, next_in, fits, all_fit,
## back_fits}], slots, next_level, have, here). Pure and static: tested headless.

const ID := "trap_fish"
const NAME := "Fish Trap"

static func _t(view: Dictionary) -> Dictionary: return view.get("fishing", {}).get("trap", {})

## The player's trap at this pond, {} when none.
static func at(view: Dictionary, place: String) -> Dictionary:
	for t in _t(view).get("traps", []):
		if str(t.get("place", "")) == place: return t
	return {}

## The main key with the trap selected on the Fishing bar (q(109) ⑦, q(122)): `Set Trap`, greyed `Trap already here`
## or `Traps 1/1 · Fishing Lv8 adds 1` (`Traps 3/3` at the top).
static func set_key(view: Dictionary, place: String) -> Dictionary:
	var t := _t(view)
	var used: int = (t.get("traps", []) as Array).size()
	var slots := int(t.get("slots", 0))
	if not at(view, place).is_empty():
		return _grey("Set Trap", "Trap already here")
	if used >= slots:
		var lv = t.get("next_level", null)
		var why := "Traps %d/%d" % [used, slots] + (" · Fishing Lv%d adds 1" % int(lv) if lv != null else "")
		return _grey("Set Trap", why)
	return {"icon": ID, "verb": "Set Trap", "sub": "Free", "enabled": true, "amber": false,
		"cmd": {"type": "set_trap"}, "need": 0}

static func _grey(verb: String, why: String) -> Dictionary:
	return {"icon": ID, "verb": verb, "sub": why, "enabled": false, "amber": false, "cmd": {}, "need": 0, "toast": why}

## The trap's EntryCard (q(109) ⑦, q(122)): main `Collect 2` (empty `Empty · next in 5h 12m`, partial `Collect 1`,
## none fits `Collect · Creel full`), second `Take back` (`Take back · Collect first` when not all fit, `Bag full`
## when the trap itself does not). Buttons {label, enabled, cmd, toast}.
static func card(view: Dictionary, place: String) -> Dictionary:
	var t := at(view, place)
	if t.is_empty(): return {}
	var fish := int(t.get("fish", 0))
	var fits := int(t.get("fits", fish))
	var main := {}
	if fish == 0:
		var left = t.get("next_in", null)
		var why := "Empty · next in %s" % P0Logic.span(float(left)) if left != null else "Empty"
		main = {"label": why, "enabled": false, "cmd": {}, "toast": why}
	elif fits == 0:
		main = {"label": "Collect · Creel full", "enabled": false, "cmd": {}, "toast": "Collect · Creel full"}
	else:
		main = {"label": "Collect %d" % fits, "enabled": true, "cmd": {"type": "collect_trap"}, "toast": ""}
	var second := {"label": "Take back", "enabled": true, "cmd": {"type": "collect_trap", "take_back": true}, "toast": ""}
	if not bool(t.get("all_fit", true)):
		second = {"label": "Take back · Collect first", "enabled": false, "cmd": {}, "toast": "Take back · Collect first"}
	elif not bool(t.get("back_fits", true)):
		second = {"label": "Take back · Bag full", "enabled": false, "cmd": {}, "toast": "Bag full · free a slot first"}
	return {"title": NAME, "fact": "%d/%d" % [fish, int(t.get("keep", 3))], "main": main, "second": second}

## The trap's world prompt: `Fish Trap · 2/3`, Ready when it holds a fish.
static func prompt(view: Dictionary, place: String) -> Dictionary:
	var t := at(view, place)
	if t.is_empty(): return {}
	return {"id": ID, "icon": ID, "text": NAME, "fact": "%d/%d" % [int(t.get("fish", 0)), int(t.get("keep", 3))],
		"ready": int(t.get("fish", 0)) > 0}

## The pond card's fact row (q(109) ⑦): ["Your trap", "2/3"], [] when the player has none there.
static func pond_fact(view: Dictionary, place: String) -> Array:
	var t := at(view, place)
	return [] if t.is_empty() else ["Your trap", "%d/%d" % [int(t.get("fish", 0)), int(t.get("keep", 3))]]

## Today's row when traps are full (q(109) ⑦, q(107) red dot): `Collect 3 fish · Fern Pond`, several
## `Collect 6 fish · 2 traps`; go = the pond of the first full trap (the map shows it). {} when none is full.
static func today_row(view: Dictionary) -> Dictionary:
	var full: Array = (_t(view).get("traps", []) as Array).filter(func(t): return int(t.get("fish", 0)) >= int(t.get("keep", 3)))
	if full.is_empty(): return {}
	var n := 0
	for t in full: n += int(t.get("fish", 0))
	var places: Array = full.map(func(t): return str(t.get("place", "")))
	var where := pond_name(view, places[0]) if full.size() == 1 else "%d traps" % full.size()
	return {"line": "Collect %d fish · %s" % [n, where], "icon": ID, "go": "pond:" + places[0], "dot": "trap:" + ",".join(places)}

static func pond_name(view: Dictionary, place: String) -> String:
	var p: Dictionary = view.get("fishing", {}).get("places", {}).get(place, {})
	if p.is_empty(): p = P0Logic.content().get("fishing", {}).get("places", {}).get(place, {})
	return str(p.get("name", place))

## The toast after a trap event (q(109) ⑦): set / partial collect / taken back; "" for none.
static func event_toast(e: Dictionary) -> String:
	match str(e.get("action", "")):
		"set": return "Fish Trap set · 1 fish every 8h"
		"collected": return ("%d left in the trap" % int(e.get("left", 0))) if int(e.get("left", 0)) > 0 else ""
		"taken_back": return "Fish Trap back in your bag"
	return ""

## A refused set_trap / collect_trap in the card's words; null for anything else (the runtime's own handling).
static func refusal_text(cmd: Dictionary, code: String, detail: Dictionary):
	if not str(cmd.get("type", "")) in ["set_trap", "collect_trap"]: return null
	match code:
		"trap_here": return "Trap already here"
		"trap_slots":
			var lv = detail.get("next_level", null)
			return "Traps %d/%d" % [int(detail.get("used", 0)), int(detail.get("slots", 0))] + (" · Fishing Lv%d adds 1" % int(lv) if lv != null else "")
		"collect_first": return "Take back · Collect first"
		"creel_full": return "Collect · Creel full"
		"bag_full": return "Bag full · free a slot first"
		"no_trap": return "No Fish Trap in your bag"
		"no_trap_here", "not_at_pond": return ""
	return null
