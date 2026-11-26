extends UiDrawer
## The Request Board at the Washington Square Travel Post (C-191): P0's system board (the Home Stall's Stall Board page,
## FARM-6 / BOARD-READY / SHORT / DONE, E-11; the request sheets BOARD-1 / BOARD-3 / BOARD-DROPPED of p0_board_request.gd)
## rebuilt from the same kit pieces for the parcel's own save; the P0 board is not touched. Pages, one at a time:
##   list     `Request Board` + Close · the page facts (`Requests today 2/6`, `Next request 7h 59m` while a slot refills,
##            `Bonus today 20/100` once any was paid) · one UiBoardCard per request: Track (accept) while open and
##            short, Deliver once the bag holds enough (tracked or not, as P0's q(48)), the gap on the key otherwise
##            (LOCK-10: `Need 1 more Carrot`; `Requests today 6/6` at the day's cap). The title › opens its sheet.
##   request  BOARD-1: the request's title, state and what to bring where · its NEED-TILE · Delivery · the other slot's
##            wait · `Drop request ›` (tracked only: an open one swaps itself after 72 h) · Back to the list.
##   drop     BOARD-3: what dropping does, `Next request after drop 8h`, the items stay in the bag; Drop request
##            (destructive) / Keep tracking.
##   dropped  BOARD-DROPPED once the server took it: Dropped, `Next request 8h`, Close back to the list.
## A delivery's slot shows its new request at once (refilled on delivery); the coins float up from where its key was.
## Numbers are the rules' (`requests`, assets/farm/data/dynamic_farm.json) and the save's board (ParcelFarm); keys only
## report (`command_requested`), the town sends them. The clock is the server's (`now_ms`, from the town).

signal command_requested(command: Dictionary)
## A slot's refill time came while the drawer is open: the town reads the save again (the server draws the request).
signal refill_due

const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const ParcelItems = preload("res://modules/dynamic_farm/parcel_items.gd")
const HEIGHT := 560.0
const _GAP := 8.0
## Player-visible copy after P0's board (appendix B.9; BOARD-1 / 3 / DROPPED) for PM to finalise (C-45). Titles by
## template: P0's Fresh Greens and Timber Run (req_sys_crop_basic, req_sys_material_wood); the stone and egg requests
## are new.
const COPY := {"title": "Request Board", "loading": "…", "unreachable": "Could not reach your farm.", "retry": "Retry",
	"open": "Open", "tracked": "Tracked", "ready": "Ready to deliver", "track": "Track", "deliver": "Deliver",
	"short": "Need %d more %s", "cap": "Requests today %d/%d", "coins": "%d coins", "coins_later": "%d coins · Bonus resets in %s",
	"today": "Requests today", "next": "Next request", "bonus": "Bonus today", "empty": "No requests",
	"effect": "Bring the required %s to the Request Board.", "delivery": "Delivery", "slot": "%s board slot",
	"available": "Available in", "drop": "Drop request", "back": "Back", "drop_effect": "Dropping removes tracking and delays the next request.",
	"after_drop": "Next request after drop", "stay": "Your %s stay in your bag.", "keep": "Keep tracking", "dropped": "Dropped",
	"remain": "Your %s remain in your bag.", "close": "Close", "float": "+%d coins"}
const TITLES := {"fresh_greens": "Fresh Greens", "timber_run": "Timber Run", "stone_order": "Stone Order", "egg_basket": "Egg Basket"}
const SLOT_NAMES := ["First", "Second", "Third", "Fourth"]

var farm := {}
## Server time now, in ms (the town keeps the offset from the last answer).
var now_ms: Callable = func() -> int: return int(Time.get_unix_time_from_system() * 1000.0)
## "list", "request", "drop", "dropped".
var page := "list"
## The request the request / drop / dropped pages are about: its card data and, once dropped, what it was.
var focus := {}
var title: Label
var page_box: VBoxContainer
## Request id → its UiBoardCard on the list (tests and the coins float read them).
var cards := {}
var _fact_values: Array[Label] = []
var _key := 0
var _due := -1
var _tick := 0.0

func _init(farm_: Dictionary = {}) -> void:
	super(HEIGHT)
	var head := HBoxContainer.new()
	title = UiKit.label(COPY.title, UiTokens.STYLE_C14_XB)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var close := UiCloseButton.new()
	close.name = "Close"
	close.pressed.connect(func(): close_requested.emit())
	head.add_child(close)
	body.add_child(head)
	var gap := Control.new()
	gap.custom_minimum_size.y = _GAP
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(gap)
	var scroll := TouchScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	page_box = VBoxContainer.new()
	page_box.name = "Page"
	page_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_box.add_theme_constant_override(&"separation", int(_GAP))
	scroll.add_child(page_box)
	refresh(farm_)

# ---------------------------------------------------------------- what the board shows (pure; tests read it)

## The list page for a farm at `now`: {facts: [[label, value]], cards: [UiBoardCard data + cmd], due: the soonest refill
## time of an empty slot still ahead (-1 for none)}.
static func model(rules: Dictionary, farm_: Dictionary, now: int) -> Dictionary:
	var q: Dictionary = rules.get("requests", {})
	if q.is_empty(): return {"facts": [], "cards": [], "due": -1}
	var board: Dictionary = farm_.get("board", ParcelFarm.empty_board())
	var today := ParcelFarm.board_today(rules, farm_, now)
	var facts: Array = [[COPY.today, "%d/%d" % [int(today.done), int(q.daily_max)]]]
	var due := -1
	for sl: Dictionary in board.get("slots", []):
		if sl.req == null and int(sl.refill_at) > now: due = int(sl.refill_at) if due < 0 else mini(due, int(sl.refill_at))
	if due > 0: facts.append([COPY.next, P0Logic.span(float(due - now))])
	if int(today.bonus) > 0: facts.append([COPY.bonus, "%d/%d" % [int(today.bonus), int(q.daily_bonus_max)]])
	var out: Array = []
	for sl: Dictionary in board.get("slots", []):
		if sl.req != null: out.append(card(rules, farm_, sl.req, now))
	return {"facts": facts, "cards": out, "due": due}

## One request as UiBoardCard data, plus `cmd` (the command its key sends, {} when it is a gap) and `slot`-free fields
## the sheets read (`noun`, `item`).
static func card(rules: Dictionary, farm_: Dictionary, r: Dictionary, now: int) -> Dictionary:
	var q: Dictionary = rules.requests
	var item := str(r.item)
	var qty := int(r.qty)
	var have := int(farm_.get("bag", {}).get(item, 0))
	var ready := have >= qty
	var tracked := str(r.status) == "accepted"
	var name := ParcelItems.name_of(item)
	var d := {"id": int(r.id), "title": title_of(r), "info": true, "item": item, "noun": noun_of(item),
		"status": COPY.ready if ready else (COPY.tracked if tracked else COPY.open),
		"facts": ["%d %s" % [qty, P0Logic.plural(name) if qty > 1 else name]], "reward": reward_line(rules, farm_, r, now),
		"needs": [{"id": item, "name": name, "have": have, "need": qty, "icon": ParcelItems.icon_of(item)}],
		"command": COPY.deliver if ready or tracked else COPY.track, "reason": "", "cmd": {}, "done": false}
	var today := ParcelFarm.board_today(rules, farm_, now)
	if ready and int(today.done) >= int(q.daily_max): d.reason = COPY.cap % [int(today.done), int(q.daily_max)]
	elif ready: d.cmd = {"type": "deliver_request", "request": int(r.id)}
	elif tracked: d.reason = COPY.short % [qty - have, P0Logic.plural(name) if qty - have > 1 else name]
	else: d.cmd = {"type": "accept_request", "request": int(r.id)}
	return d

## `37 coins`: the floor price × count and the bonus; once today's bonus left is short of it, what delivering pays now
## and when the bonus is back (P0Board.reward_line).
static func reward_line(rules: Dictionary, farm_: Dictionary, r: Dictionary, now: int) -> String:
	var q: Dictionary = rules.requests
	var base := ParcelFarm.floor_price(rules, str(r.item)) * int(r.qty)
	var bonus := int(r.bonus)
	var left := maxi(0, int(q.daily_bonus_max) - int(ParcelFarm.board_today(rules, farm_, now).bonus))
	if left >= bonus: return COPY.coins % (base + bonus)
	return COPY.coins_later % [base + left, P0Logic.span(float(ParcelFarm.next_rollover(rules, now) - now))]

static func title_of(r: Dictionary) -> String:
	return str(TITLES.get(str(r.template), ParcelItems.name_of(str(r.item))))

## What the sheets call the items (P0Board._noun): crops; a material or the eggs by their own name.
static func noun_of(item: String) -> String:
	if item.begins_with("crop_"): return "crops"
	var name := ParcelItems.name_of(item)
	return (P0Logic.plural(name) if item == "egg" else name).to_lower()

# ---------------------------------------------------------------- drawing

## New farm from the store: the open page follows it (a request gone from the board leaves its sheet for the list;
## the dropped page stays until Close).
func refresh(farm_: Dictionary) -> void:
	farm = farm_
	if page in ["request", "drop"] and ParcelFarm.request_slot(farm, int(focus.get("id", 0))).is_empty(): page = "list"
	_draw_page(true)

## The page's line while the farm is being read or could not be (`…`, or the failure with Retry).
func show_status(line: String, retry := Callable()) -> void:
	_clear()
	page_box.add_child(UiKit.label(line, UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY))
	if retry.is_valid():
		var again := UiCommandButton.new(COPY.retry, UiCommandButton.Kind.SECONDARY)
		again.name = "Retry"
		again.activated.connect(retry)
		page_box.add_child(again)

func open_request(id: int) -> void:
	page = "request"
	focus = {"id": id}
	_draw_page(true)

func confirm_drop() -> void:
	page = "drop"
	_draw_page(true)

## BOARD-DROPPED for the request just dropped (the town calls it on the server's answer).
func dropped() -> void:
	page = "dropped"
	_draw_page(true)

func back_to_list() -> void:
	page = "list"
	focus = {}
	_draw_page(true)

## The coins of a delivery float up from where its key was (BOARD-DONE: no result card).
func float_coins(coins: int, at: Vector2) -> void:
	if coins <= 0 or not is_inside_tree(): return
	var f := UiFloatText.new(COPY.float % coins, UiFloatText.Tone.COINS, UiArt.COIN)
	f.theme = UiKit.theme()
	get_parent().add_child(f)
	f.play(at - (get_parent() as Control).global_position if get_parent() is Control else at)

## Where request `id`'s key is on screen (Vector2.INF when it is not on the list).
func key_point(id: int) -> Vector2:
	var c: UiBoardCard = cards.get(id)
	return c.command_button().get_global_rect().get_center() if c != null and is_instance_valid(c) and c.is_visible_in_tree() else Vector2.INF

func _process(dt: float) -> void:
	_tick += dt
	if _tick < 1.0: return
	_tick = 0.0
	if page == "list" and not farm.is_empty(): _draw_page(false)
	if _due > 0 and int(now_ms.call()) >= _due:
		_due = -1
		refill_due.emit()

## The open page from the farm. The list is rebuilt only when its rows change (a pressed key keeps its node); the
## countdown updates in place.
func _draw_page(force: bool) -> void:
	if farm.is_empty(): return
	var rules := ParcelFarm.rules()
	var now: int = now_ms.call()
	match page:
		"list":
			var m := model(rules, farm, now)
			_due = int(m.due)
			var key := [m.cards, m.facts.map(func(f): return f[0])].hash()
			if not force and key == _key and _fact_values.size() == m.facts.size():
				for i in m.facts.size(): _fact_values[i].text = str(m.facts[i][1])
				return
			_key = key
			_clear()
			_list(m)
		"request": _request_page(rules, now)
		"drop": _drop_page(rules)
		"dropped": _dropped_page(rules)

func _clear() -> void:
	_key = 0
	cards = {}
	_fact_values = []
	for c in page_box.get_children():
		page_box.remove_child(c)
		c.queue_free()

func _list(m: Dictionary) -> void:
	for f in m.facts:
		var row := UiBoardCard.fact_row(str(f[0]), str(f[1]))
		page_box.add_child(row)
		_fact_values.append(row.get_child(1) as Label)
	if m.cards.is_empty():
		page_box.add_child(UiKit.label(COPY.empty, UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY))
	for d: Dictionary in m.cards:
		var c := UiBoardCard.new()
		c.name = "Request_%d" % int(d.id)
		c.show_request(d)
		var cmd: Dictionary = d.cmd
		var id := int(d.id)
		c.command_pressed.connect(func(): if not cmd.is_empty(): command_requested.emit(cmd))
		c.info_pressed.connect(func(): open_request(id))
		page_box.add_child(c)
		cards[id] = c

func _request_page(rules: Dictionary, now: int) -> void:
	var sl := ParcelFarm.request_slot(farm, int(focus.get("id", 0)))
	if sl.is_empty():
		back_to_list()
		return
	var d := card(rules, farm, sl.req, now)
	focus = d
	_clear()
	page_box.add_child(UiObjectHeader.new({title = d.title, state = d.status, effect = COPY.effect % str(d.noun)}))
	var tiles: Array = []
	for n: Dictionary in d.needs: tiles.append(UiNeedTile.new(str(n.name), int(n.have), int(n.need), UiNeedTile.Size.S, n.icon))
	page_box.add_child(UiNeedTile.group(tiles))
	page_box.add_child(UiFactRow.new(COPY.delivery, str(d.reward)))
	var slots: Array = farm.board.slots
	for j in slots.size():
		var other: Dictionary = slots[j]
		if other.req == null and int(other.refill_at) > now:
			page_box.add_child(UiItemRow.new({icon = P0Logic.icon("clock"), title = COPY.next,
				effect = COPY.slot % SLOT_NAMES[mini(j, SLOT_NAMES.size() - 1)]}))
			page_box.add_child(UiFactRow.new(COPY.available, P0Logic.span(float(int(other.refill_at) - now))))
			break
	if str(sl.req.status) == "accepted":
		var drop := UiNavButton.new(COPY.drop)
		drop.name = "DropRequest"
		drop.pressed.connect(confirm_drop)
		page_box.add_child(drop)
	_dismiss(COPY.back, back_to_list)

func _drop_page(rules: Dictionary) -> void:
	_clear()
	page_box.add_child(UiObjectHeader.new({title = focus.get("title", ""), state = COPY.drop, effect = COPY.drop_effect}))
	page_box.add_child(UiFactRow.new(COPY.after_drop, _drop_wait(rules)))
	var stay := UiKit.label(COPY.stay % str(focus.get("noun", "items")), UiTokens.STYLE_BODY_XB14)
	stay.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page_box.add_child(stay)
	var drop := UiCommandButton.new(COPY.drop, UiCommandButton.Kind.DESTRUCTIVE)
	drop.name = "Drop"
	drop.sends = true
	var id := int(focus.get("id", 0))
	drop.activated.connect(func(): command_requested.emit({"type": "drop_request", "request": id}))
	page_box.add_child(drop)
	_dismiss(COPY.keep, func(): open_request(id))

func _dropped_page(rules: Dictionary) -> void:
	_clear()
	page_box.add_child(UiObjectHeader.new({title = focus.get("title", ""), state = COPY.dropped,
		effect = COPY.remain % str(focus.get("noun", "items"))}))
	page_box.add_child(UiFactRow.new(COPY.next, _drop_wait(rules)))
	_dismiss(COPY.close, back_to_list)

## The wait after dropping (`requests.drop_refill_seconds`, BOARD-3 `8h`).
static func _drop_wait(rules: Dictionary) -> String:
	return P0Logic.span(float(int(rules.get("requests", {}).get("drop_refill_seconds", 0)) * 1000))

func _dismiss(label: String, on_press: Callable) -> void:
	var b := UiDismissButton.new(label)
	b.name = "Dismiss"
	b.pressed.connect(on_press)
	page_box.add_child(b)
