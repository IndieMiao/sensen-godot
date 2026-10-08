class_name P0InboxDrawer
extends UiDrawer
## The Inbox drawer (C2-01, LOCK-14; INBOX-TODO 1312:90013 / INBOX-PARCELS 1312:90181 / INBOX-UPDATES 1312:90357,
## PARCEL-1…5; §12.5.2, q(79); SGODOT-234): a 630 Sheet with `Inbox`, the `3 new · 2 to do` line and the To do |
## Parcels | Updates switch (red counts on To do and Parcels, an unread dot on Updates). The bell and the farmhouse
## Mailbox open this same drawer.
##   To do     P0 has no source: `No invites right now`.
##   Parcels   `Bag 19/25 · 6 slots free`, the rule line, one InboxRow Kind=Item per parcel (soonest first), what
##             happens to unclaimed ones; the fixed `Claim all · 2 slots` (grey `Make room · 2 slots` with the bag
##             full) at the bottom; empty `No parcels`.
##   Updates   one InboxRow Kind=System per expired or returned parcel, newest first; opening it reads them all;
##             empty `No updates yet`.
## Everything comes from P0Inbox over the server view; the drawer only reports back:
##   claim_requested(cmd, from)   claim_parcel {key} or claim_parcels {keys}; `from` is the pressed button (floats)
##   read_requested(keys)         Updates opened with unread rows: read_inbox
##   refused(text)                a grey Claim pressed with the bag full: `Make room · 1 slot` (§10.4.8)
##   tab_changed(tab)

signal claim_requested(cmd: Dictionary, from: Control)
signal read_requested(keys: Array)
signal refused(text: String)
signal tab_changed(tab: String)

const HEIGHT := 630.0     # INBOX-*: the Sheet's top at y 170 of 800
const _GAP := 10          # Inbox content: gap 10
const _TITLE_SIZE := 22   # `Inbox` 22 ExtraBold, as the Workbench's title (UiTokens.PENDING "blueprintCard")

var view := {}
var tab := "parcels"
var now_ms := Callable(self, &"_now_ms")   # the Updates' `2h ago` clock (tests pin it)
var tabs: UiSegmentTab
var claim_all: UiCommandButton
var rows: Array[UiInboxRow] = []

var _sub: Label
var _scroll: TouchScrollContainer
var _page: VBoxContainer
var _key := 0
var _shape := 0   # the page's rows and lines without their times: a change rebuilds it
var _fresh := {}   # update keys unread when this visit opened Updates: their dots stay until the drawer closes

func _init(view_: Dictionary = {}, tab_ := "") -> void:
	super(HEIGHT)
	pad = UiTokens.SPACE_PAGE
	body.add_theme_constant_override(&"separation", _GAP)
	var title := UiKit.label("Inbox", UiTokens.STYLE_TITLE_XB20)
	title.add_theme_font_size_override(&"font_size", _TITLE_SIZE)
	body.add_child(title)
	_sub = UiKit.label("", UiTokens.STYLE_C13_B, UiTokens.COLOR_SECONDARY)
	body.add_child(_sub)
	view = view_
	tab = tab_ if tab_ in P0Inbox.TABS else P0Inbox.default_tab(view_)
	tabs = UiSegmentTab.new(P0Inbox.TAB_LABELS.map(func(l): return {label = l}), P0Inbox.TABS.find(tab))
	tabs.changed.connect(func(i: int): set_tab(P0Inbox.TABS[i]))
	body.add_child(tabs)
	_scroll = TouchScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override(&"separation", _GAP)
	_scroll.add_child(_page)
	claim_all = UiCommandButton.new("", UiCommandButton.Kind.PRIMARY)
	claim_all.sends = true   # claim_parcels: Offline while offline (§10.7.1)
	claim_all.activated.connect(func():
		var c := P0Inbox.claim_all(view)
		if not (c.get("keys", []) as Array).is_empty(): claim_requested.emit({"type": "claim_parcels", "keys": c.keys}, claim_all))
	body.add_child(claim_all)
	refresh(view_)

func _ready() -> void:
	super._ready()
	_read_if_updates()   # opened on Updates: after the owner has connected read_requested

static func _now_ms() -> float: return Time.get_unix_time_from_system() * 1000.0

## q(16): the toast sits above Claim all while it shows.
func action_area() -> Control: return claim_all if claim_all.is_visible_in_tree() else null

func set_tab(t: String) -> void:
	if t == tab or not t in P0Inbox.TABS: return
	tab = t
	tabs.selected = P0Inbox.TABS.find(t)
	_key = 0
	_shape = 0
	refresh(view)
	_scroll.scroll_vertical = 0
	tab_changed.emit(tab)
	_read_if_updates()

## Opening Updates marks all read (§12.5.2): the server clears them and the tab's dot goes; the rows that were new keep
## their dots for this visit, so the player still sees which ones they are.
func _read_if_updates() -> void:
	if tab != "updates" or not is_inside_tree(): return
	var keys: Array = P0Inbox.unread_updates(view).map(func(u): return str(u.key))
	for k in keys: _fresh[k] = true
	if not keys.is_empty(): read_requested.emit(keys)

## Follows the view (the P0 UI calls it every frame while the drawer is open). The page is rebuilt only when its rows
## or lines change (a claim, a new update); a minute passing only rewrites the rows' times in place.
func refresh(v: Dictionary) -> void:
	view = v
	_sub.text = P0Inbox.new_line(view)
	tabs.set_marks(0, P0Inbox.todo_count(view), false)
	tabs.set_marks(1, P0Inbox.parcels(view).size(), false)
	tabs.set_marks(2, 0, not P0Inbox.unread_updates(view).is_empty())
	var model := _page_model()
	var key := hash([tab, model])
	if key == _key: return
	_key = key
	var shape := hash([tab, (model.get("rows", []) as Array).map(func(r): return r.key), model.get("head"), model.get("rule"),
		model.get("note"), model.get("claim")])
	if shape == _shape and rows.size() == (model.get("rows", []) as Array).size():
		for i in rows.size(): rows[i].show_row(model.rows[i])
		return
	_shape = shape
	_build(model)

func _page_model() -> Dictionary:
	match tab:
		"parcels":
			return {rows = P0Inbox.parcel_rows(view), head = P0Inbox.capacity_line(view), rule = P0Inbox.rule_line(view),
				note = P0Inbox.expiry_note(view), claim = P0Inbox.claim_all(view)}
		"updates":
			# Minutes in the `ago` text only: the rows rebuild once a minute, not every frame.
			var rows_now := P0Inbox.update_rows(view, floorf(float(now_ms.call()) / 60000.0) * 60000.0)
			for r in rows_now: r.unread = bool(r.unread) or _fresh.has(str(r.key))
			return {rows = rows_now}
	return {}

func _build(model: Dictionary) -> void:
	for c in _page.get_children():
		c.hide()
		c.queue_free()
	rows.clear()
	claim_all.visible = false
	match tab:
		"todo":
			_page.add_child(_empty("No invites right now"))
		"parcels":
			if (model.rows as Array).is_empty() and int(P0Inbox.inbox(view).get("waiting", 0)) <= 0:
				_page.add_child(_empty("No parcels"))
				return
			_page.add_child(UiKit.label(str(model.head), UiTokens.STYLE_C14_XB))
			_page.add_child(_wrapped(str(model.rule), UiTokens.STYLE_C12_B))
			for r in model.rows:
				var row := UiInboxRow.new(UiInboxRow.Kind.ITEM)
				row.show_row(r)
				row.claim_pressed.connect(func(k: String): claim_requested.emit({"type": "claim_parcel", "key": k}, row.claim))
				row.claim_unavailable.connect(func(_k: String): refused.emit("Make room · 1 slot"))
				_page.add_child(row)
				rows.append(row)
			if not (model.rows as Array).is_empty(): _page.add_child(_wrapped(str(model.note), UiTokens.STYLE_C11_B))   # q(81): with parcels only
			var c: Dictionary = model.claim
			if not c.is_empty():
				claim_all.label = str(c.label)
				claim_all.reason = str(c.reason)
				claim_all.visible = true
		"updates":
			if (model.rows as Array).is_empty():
				_page.add_child(_empty("No updates yet"))
				return
			for r in model.rows:
				var row := UiInboxRow.new(UiInboxRow.Kind.SYSTEM)
				row.show_row(r)
				_page.add_child(row)
				rows.append(row)

static func _wrapped(text: String, style: StringName) -> Label:
	var l := UiKit.label(text, style, UiTokens.COLOR_SECONDARY)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func _empty(text: String) -> UiEmptyState:
	return UiEmptyState.new(text, P0Logic.icon("bell"))
