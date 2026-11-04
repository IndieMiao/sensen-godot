extends RefCounted
## A keeper's local request card (q(272), 不知火舞 378 091a3ae9 / 77524b0e): the resident's request card (UiRequestCard,
## LOCK-18 unchanged) with a keeper's content — `Pond Catch`, `Wen · Tackle Keeper · local request`, the keeper's line,
## Bring tiles, Reward in coins only (q(262) when the day's bonus is short), Deliver to `Wen · Xuhui Tackle Shop` (` ·
## Shanghai` away). A tracked one adds `Drop request ›` (BOARD-3 / BOARD-DROPPED with the local sentence, Close back to
## where the card was opened); a keeper holding 2 or more for the player adds `Bo's other requests · 2 ›`, the card
## turning to the next in the greeting key's order (Deliver > Request > the gap), round to the first, the count kept.
## Opened from the keeper's greeting key, Today (away too) or a pin. Preloaded, no class_name.

const P0Locals := preload("res://modules/p0/p0_locals.gd")
const PinReason := preload("res://modules/p0/p0_pin_reason.gd")

## The card for `id`; `back` where Not now (and the drop flow's Close) go. `ring`: the keeper's requests the card pages
## through (fixed when the first card opens, so the count stays); none away from the city.
static func open(ui: P0Ui, id: String, back: Callable, ring: Array = []) -> void:
	var r := P0Locals.find(ui.view, id)
	if r.is_empty():
		back.call()
		return
	if ring.is_empty() and bool(r.get("here", false)):
		ring = P0Locals.of_keeper(ui.view, str(r.place)).map(func(x): return str(x.id))
	var data := card_data(ui.view, r)
	var links: Array = []
	var tracked := str(r.get("status", "")) == "accepted"
	if tracked: links.append("Drop request")
	if ring.size() >= 2: links.append("%s's other requests · %d" % [str(r.get("giver", "")), ring.size() - 1])
	data["links"] = links
	data["break_dots"] = true   # Deliver to breaks after a ` · ` (· Shanghai away)
	var cmd := {}
	if not tracked and str(data.get("reason", "")) == "": cmd = {"type": "accept", "request": id}
	elif bool(r.get("ready", false)): cmd = {"type": "deliver", "request": id}   # away too: the server's wrong_place toasts where (⑦)
	data["sends"] = not cmd.is_empty()
	var card := UiRequestCard.new(data)
	card.name = "LocalRequestCard"
	card.theme = UiKit.theme()
	card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	card.offset_left = UiTokens.SIZE_QUICK_BAR_X
	card.offset_right = -UiTokens.SIZE_QUICK_BAR_X
	card.offset_bottom = -ui.bottom_pad()
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.action_pressed.connect(func():
		ui.close_modal()
		if not cmd.is_empty(): ui.command.emit(cmd))
	card.unavailable_pressed.connect(func(reason: String): ui.toast_error(P0Logic.blocked_toast(reason)))
	card.dismissed.connect(func(): back.call())
	card.link_pressed.connect(func(i: int):
		if str(links[i]) == "Drop request":
			P0BoardRequest.confirm_local_drop(ui, {"id": id, "title": str(r.title), "noun": P0Board._noun(ui.view, r),
				"item": str(data.get("item", ""))}, func(): open(ui, id, back, ring), back)
		else:   # the keeper's next request, round to the first
			open(ui, str(ring[(ring.find(id) + 1) % ring.size()]), back, ring))
	ui._open_modal(card, 0.0, true)
	ui.modal_kind = "local_request"
	ui._modal_back = back

## UiRequestCard data for one local request (no links, no command).
static func card_data(view: Dictionary, r: Dictionary) -> Dictionary:
	var items: Array = r.get("items", [])
	var item := str(items[0]) if items.size() == 1 else ""
	var icon := item if item != "" else (str(r.icon) if r.get("icon", null) != null else "board")
	var need := {"name": PinReason._need_name(view, str(r.get("kind", "")), items, r.get("rarity", null)),
		"have": int(r.get("have", 0)), "need": int(r.get("qty", 1)), "icon": P0Logic.icon(icon)}
	var styles: Array = r.get("style", []) if r.get("style", null) is Array else []
	if not styles.is_empty() and items.is_empty(): need.name = "%s dish" % " or ".join(styles)
	# the items drawn by name, each its own tile (不知火舞 378: a Market Basket's three crops, not `Any crop`)
	var needs: Array = [need] if items.size() <= 1 else items.map(func(i): return {"name": P0Logic.item_name(view, str(i)),
		"have": int(r.get("have", 0)), "need": int(r.get("qty", 1)), "icon": P0Logic.icon(str(i))})
	var tracked := str(r.get("status", "")) == "accepted"
	# LOCK-10: a tracked one still short shows its gap on the button, here or away (不知火舞 on 378: no new line away)
	var reason := P0Locals.gap_text(view, r) if tracked and not bool(r.get("ready", false)) else ""
	if not tracked: reason = P0Logic.track_full_reason(view)   # spec ③: tracking 25 already, `Accept · Requests 25/25`
	var data := {"portrait": P0Locals.portrait(r),
		"title": str(r.get("title", "")), "who": P0Locals.who(r), "line": P0Locals.line(r), "needs": needs,
		"deliver_to": P0Locals.deliver_to(r), "action": "Deliver" if tracked else "Accept", "reason": reason, "item": item}
	data.merge(rewards(view, r))
	return data

## Reward: coins only — the floor and the completion bonus, less what the day's bonus cap leaves out (q(262)'s note).
static func rewards(view: Dictionary, r: Dictionary) -> Dictionary:
	var coins := int(r.get("coins", 0))
	var bonus := int(r.get("bonus", 0))
	var note := ""
	var quota: Dictionary = view.get("quotas", {}).get("request_bonus", {})
	if not quota.is_empty():
		var left := maxi(0, int(quota.get("cap", 0)) - int(quota.get("used", 0)))
		if left < bonus:
			coins -= bonus - left
			note = "Bonus resets in %s" % P0Logic.span(float(quota.get("resets_in", 0)))
	return {"reward": "%d coins" % coins, "bonus_note": note}
