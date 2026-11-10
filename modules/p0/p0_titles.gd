extends RefCounted
## Titles (q(180), §10.6.2): view.titles {list, wearing} from the server (titles.ts) — the titles given, as stable ids in
## the fixed order, and the one worn — named here. The skills', Homestead's, Explorer's and Home Cook's names are the
## client's (P0Logic.TITLE_NAMES, P0KitchenLogic.HOME_COOK); the Cookbook milestones', Kindred's and the requests' are
## the content's. Each row also says where it came from: `Homestead Lv10`, `Cookbook 20/48`, `Mastered 10`,
## `Explorer Bronze`, `Kindred · Pip`, `Request · The Smoker's Secret`.

## Ids to their P0Logic.TITLE_NAMES key and their source line.
const _NAMED := {
	"homestead": ["title_homestead_master", "Home Lv10"],
	"level:farming": ["title_master_gardener", "Farming Lv10"],
	"level:fishing": ["title_master_angler", "Fishing Lv10"],
	"level:cooking": ["title_chef", "Cooking Lv10"],
	"explorer:100": ["title_globetrotter", "Explorer Platinum"],
	"explorer:3": ["title_wanderer", "Explorer Bronze"],
}
const HOME_COOK := "milestone:home_cook"
const ELLIPSIS := "…"

## A title's {id, name, source}; {} for an id this client cannot name (a newer server's), which is then left out.
static func info(view: Dictionary, id: String) -> Dictionary:
	if _NAMED.has(id):
		return {id = id, name = str(P0Logic.TITLE_NAMES.get(_NAMED[id][0], "")), source = str(_NAMED[id][1])}
	var c := P0Logic.content()
	var total := int(P0KitchenLogic.cooking(view).get("pages_total", 48))
	if id == HOME_COOK:
		var at := int(((c.get("rewards", {}).get("cookbook", [[8, 0]]) as Array)[0] as Array)[0])
		return {id = id, name = P0KitchenLogic.HOME_COOK, source = "Cookbook %d/%d" % [at, total]}
	if id.begins_with("milestone:"):
		for m in c.get("cooking", {}).get("milestones", []):
			if str(m.get("id", "")) != id.trim_prefix("milestone:"): continue
			var source := ("Mastered %d" % int(m.mastered)) if m.has("mastered") else "Cookbook %d/%d" % [int(m.get("discovered", 0)), total]
			return {id = id, name = str(m.get("title", "")), source = source}
		return {}
	var residents: Dictionary = c.get("residents", {})
	if id.begins_with("kindred:"):
		var who := str(residents.get(id.trim_prefix("kindred:"), {}).get("name", ""))
		if who == "": return {}
		var title := str(c.get("affinity", {}).get("kindred", {}).get("title", "{name}'s Best Friend"))
		return {id = id, name = title.replace("{name}", who), source = "Kindred · %s" % who}
	if id.begins_with("req:"):
		for r in residents.values():
			for q in r.get("requests", []):
				if str(q.get("id", "")) == id.trim_prefix("req:") and str(q.get("reward", {}).get("title", "")) != "":
					return {id = id, name = str(q.reward.title), source = "Request · %s" % str(q.get("title", ""))}
		return {}
	return {}

## The one worn: a pick just sent (`pending` {id, seq}) until the server's answer moves the view past that seq, else
## view.titles.wearing; "" with none.
static func worn(view: Dictionary, pending := {}) -> String:
	if not pending.is_empty() and int(view.get("seq", -1)) == int(pending.get("seq", -2)): return str(pending.get("id", ""))
	var w = view.get("titles", {}).get("wearing", null)
	return "" if w == null else str(w)

## The Titles drawer's rows, in the server's order (the worn one not moved up): {id, name, source, worn}.
static func rows(view: Dictionary, pending := {}) -> Array:
	var on := worn(view, pending)
	var out: Array = []
	for id in view.get("titles", {}).get("list", []):
		var t := info(view, str(id))
		if t.is_empty(): continue
		t.worn = str(id) == on
		out.append(t)
	return out

## The profile's title beside the name: the worn one's name, "" with none (then neither it nor its › shows).
static func worn_name(view: Dictionary, pending := {}) -> String:
	var on := worn(view, pending)
	return "" if on == "" else str(info(view, on).get("name", ""))

## q(180) ④: the name and the title on one line `width` wide. The name is never cut while the title can keep its first
## letter and `…`: the title gives way first (`Granny Wu's Best F…`), down to `G…`; only a name too wide even for that
## (16 W's) is cut at its end. `tail` is what follows the title (its gap and the ›), `gap` what sits between the name and
## the title; `name_w` / `title_w` measure a string in each one's own font. No title: the name alone, cut only if it
## must be. Returns {name, title}.
static func fit(name: String, title: String, width: float, gap: float, tail: float, name_w: Callable, title_w: Callable) -> Dictionary:
	if title == "": return {name = cut(name, width, name_w), title = ""}
	var room := width - float(name_w.call(name)) - gap - tail
	if float(title_w.call(title)) <= room: return {name = name, title = title}
	var least := title.left(1) + ELLIPSIS
	if float(title_w.call(least)) <= room: return {name = name, title = cut(title, room, title_w)}
	return {name = cut(name, width - gap - tail - float(title_w.call(least)), name_w), title = least}

## `text` as it fits `width`: whole, or its longest start (trailing spaces dropped) and `…`, at least one letter.
static func cut(text: String, width: float, measure: Callable) -> String:
	if float(measure.call(text)) <= width: return text
	for n in range(text.length() - 1, 0, -1):
		var t := text.left(n).strip_edges(false, true) + ELLIPSIS
		if float(measure.call(t)) <= width: return t
	return text.left(1) + ELLIPSIS
