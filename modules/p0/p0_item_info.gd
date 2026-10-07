class_name P0ItemInfo
extends RefCounted
## Item detail rules for the InfoSheet (SGODOT-224; F-07 confirmed table, SGODOT-207 comment 168a4cc3, revisions 1–2;
## product wording 李白 25f3cb4c; K-3 = A, crops can't be gifted). Every condition is computed here from the server
## view; the card only draws the spec it is given.
##
## INTERFACE STUB (day 0): the contract below is what UiInfoSheet and its callers (bag drawer SGODOT-225, counter
## SGODOT-224) build on. spec() fills only the title area for now; the rule table (item_info_rules.json, keyed
## "kind/context") and its snapshot tests land in the next commits without changing these signatures.
##
## Contexts (the F-07 columns that show a detail card; cooking picks put the cell straight into the pot, no card):
##   &"bag"           bag drawer detail (LOCK-12 / 13)
##   &"gear"          Gear side slot rows (LOCK-13; rods and tools)
##   &"counter_buy"   a counter's Buy list row (LOCK-15)
##   &"counter_sell"  a counter's Sell here selection (LOCK-15)
##   &"gift"          the gift drawer, Bag side only
##
## opts (all optional):
##   place: String     "home" (own farm / farmhouse), "pond", "outpost" — at-home rules (Store, Sell at home)
##   counter: String   counter role: "homestead", "tackle", "tea", "market", "post" (same ids as open_counter)
##   qty: int          stepper count on a buy row (price column shows the total, line 2 "2 × 15 coins")
##   target: Dictionary gift recipient {kind: "resident" | "player", id} or a delivery request {request: id}
##
## Spec (Dictionary) returned by spec():
##   id, icon: Texture2D, title: String, quantity: int (0 hides ×N), info: bool (title shows ›)
##   rarity: int (0 = none), rarity_text: String, quality: int (dish ★ count), region: String
##   badge: StringName   &"" / &"locked" / &"pinned" / &"new" (one at most: Locked > Pinned > New)
##   facts: Array[String]   at most what fits 6 card rows with title and buttons (q(10) wording)
##   buttons: Array of {id: StringName, label: String, kind: StringName, payload: Dictionary}
##            kind: &"primary" (at most one per screen) / &"secondary" / &"nav" (Gift ›) / &"unavailable"
##            (label is the reason: Sell at home, Limit reached · 9h 12m, Energy full)
##   lock: {shown: bool, locked: bool}   the title-area lock icon (not a button slot)
##   quota: Dictionary   counter_sell only: {text, have, total, note} for the buy-back line; {} hides it

const CONTEXTS: Array[StringName] = [&"bag", &"gear", &"counter_buy", &"counter_sell", &"gift"]

static func spec(view: Dictionary, item_id: String, context: StringName, opts := {}) -> Dictionary:
	assert(context in CONTEXTS, "P0ItemInfo: unknown context %s" % context)
	var it := P0Logic.item(view, item_id)
	var rarity := int(it.get("rarity", 0))
	return {
		id = item_id,
		icon = P0Logic.icon(item_id),
		title = P0Logic.item_name(view, item_id),
		quantity = P0Logic.bag_count(view, item_id),
		info = true,
		rarity = rarity,
		rarity_text = P0Logic.rarity_name(view, rarity) if rarity > 0 else "",
		quality = 0,
		region = "",
		badge = &"",
		facts = [],
		buttons = [],
		lock = {shown = false, locked = false},
		quota = {},
	}
