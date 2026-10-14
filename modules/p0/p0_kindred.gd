extends RefCounted
## Kindred's two gifts on the client (q(171), SGODOT-284; 不知火舞's frames KINDRED-PIP 2620:134209, PASS-POSTCARDS
## 2627:134311, PostcardStamp 2615:134287). The server gives them once, the first time a resident reaches Kindred
## (event `kindred` {resident, postcard, title} after its affinity event; view.residents[id].kindred {postcard, text,
## title, at} from then on). Here:
##   card       the arrival's RewardMoment Milestone: `Kindred · Pip`, the resident's stamp, `Postcard from Pip`, the
##              strip `New title · Pip's Best Friend` (a heart before it), no pills.
##   postcards  the Passport's Postcards page: `Postcards · 3/12` and a cell per resident in the residents table's order
##              (not by when it came) — earned: the stamp, the name, the Kindred line in quotes; not yet: a grey
##              silhouette and `Kindred · ?`.
## Pure and static. Preloaded, no class_name (a new global class needs an editor import).

## A resident's name from the content table ("" for an unknown id).
static func resident_name(id: String) -> String:
	return str(P0Logic.content().get("residents", {}).get(id, {}).get("name", ""))

## The arrival card's fields from the `kindred` event: {resident, event, item_name, strip}. The postcard's and the
## title's names are the server's (content affinity.kindred); a resident's name stands in for an older server.
static func card(_view: Dictionary, ev: Dictionary) -> Dictionary:
	var id := str(ev.get("resident", ""))
	var who := resident_name(id)
	var postcard := str(ev.get("postcard", ""))
	var title := str(ev.get("title", ""))
	return {resident = id, event = "Kindred · %s" % who,
		item_name = postcard if postcard != "" else "Postcard from %s" % who,
		strip = "New title · %s" % (title if title != "" else "%s's Best Friend" % who)}

## The Postcards page: {count: `Postcards · 3/12`, cells: [{id, name, text, earned}]} — every resident of the table in its
## order, the denominator the residents there are (12 now). An earned cell's text is its Kindred line (the view's, as the
## server gave it), uncut; an unearned one names no one.
static func postcards(view: Dictionary) -> Dictionary:
	var table: Dictionary = P0Logic.content().get("residents", {})
	var mine: Dictionary = view.get("residents", {}) if view.get("residents", {}) is Dictionary else {}
	var cells: Array = []
	var got := 0
	for id in table:
		var k = mine.get(id, {}).get("kindred", null) if mine.get(id, {}) is Dictionary else null
		var earned: bool = k is Dictionary
		if earned: got += 1
		var line := str(k.get("text", "")) if earned else ""
		if earned and line == "": line = str(table[id].get("lines", {}).get("Kindred", ""))
		cells.append({id = str(id), name = str(table[id].get("name", "")) if earned else "", text = line, earned = earned})
	return {count = "Postcards · %d/%d" % [got, table.size()], cells = cells}

## A resident's initial for a stamp without its portrait yet (不知火舞 on 284: earned stamps never wear the grey
## silhouette, which is how an unearned one looks).
static func initial(id: String) -> String:
	return resident_name(id).left(1).to_upper()
