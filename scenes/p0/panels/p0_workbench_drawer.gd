class_name P0WorkbenchDrawer
extends UiDrawer
## The workbench drawer (SGODOT-231, B2-06 seven states; page 14 row 45, frames 1434:126236 …): a 630 Sheet with
## `Workbench`, `Uses Farm Storage first, then your bag`, a Tools | Supplies switch (P0 has no Facilities tab,
## q(31); P1 adds it when the view lists it, SGODOT-241) and one BlueprintCard per recipe. Everything shown comes from P0MaterialLogic.workbench_model over the
## server view; the drawer only reports back:
##   command_requested(cmd)            Craft / Equip
##   unavailable_requested(reason)     a grey button (LOCK-10: Need 1 more Copper Ore, No room · free a slot first …)
##   source_requested(tile, item_id)   a tapped NEED-TILE: the owner pops NeedSource above it (Show only moves the
##                                     camera, LOCK-08)
## A craft that stays here (Torch, Compost) floats `+2 Torch` on its card (TORCH-DONE, float_on); the Copper
## Pickaxe's Moment belongs to the owner.
## Tapping a card's item icon shows the shared InfoSheet (P0ItemInfo context &"workbench", read only) docked under the
## tabs, as the bag docks it above its grid; the same icon again, another tab or a closed drawer folds it.

signal command_requested(cmd: Dictionary)
signal unavailable_requested(reason: String)
signal source_requested(tile: Control, item_id: String)
signal tab_changed(tab: String)

const HEIGHT := 630.0         # B2-06: the Sheet's top at y 170 of 800
const TABS := ["tools", "supplies", "facilities"]   # Facilities from P1 (SGODOT-241), shown when the view lists it
const _TAB_LABELS := {"tools": "Tools", "supplies": "Supplies", "facilities": "Facilities"}
const _GAP := 10              # Workbench content: gap 10
const _TITLE_SIZE := 22       # title 22 ExtraBold: Title XB20 one step up (UiTokens.PENDING "blueprintCard", as P0HomePanel._big)
const _KINDS := {"primary": UiBlueprintCard.Kind.PRIMARY, "secondary": UiBlueprintCard.Kind.SECONDARY}

var view := {}
var tab := "tools"
var _tabs: UiSegmentTab
var _shown_tabs: Array = []   # the view's workbench.tabs this drawer knows (P0 servers: Tools | Supplies)
var sheet: UiInfoSheet
var _scroll: TouchScrollContainer
var _list: VBoxContainer
var _cards := {}              # recipe id -> UiBlueprintCard
var _models := {}             # recipe id -> its card in P0MaterialLogic.workbench_model (the buttons read cmd here)
var _key := 0                 # hash of what the cards show; refresh() skips a view that changes none of it

func _init(view_: Dictionary = {}, tab_ := "tools") -> void:
	super(HEIGHT)
	pad = UiTokens.SPACE_PAGE
	body.add_theme_constant_override(&"separation", _GAP)
	var title := UiKit.label("Workbench", UiTokens.STYLE_TITLE_XB20)
	title.add_theme_font_size_override(&"font_size", _TITLE_SIZE)
	body.add_child(title)
	body.add_child(UiKit.label("Uses Farm Storage first, then your bag", UiTokens.STYLE_C13_B, UiTokens.COLOR_SECONDARY))
	_shown_tabs = (view_.get("workbench", {}).get("tabs", ["tools", "supplies"]) as Array).filter(func(t): return t in TABS)
	if _shown_tabs.is_empty(): _shown_tabs = ["tools", "supplies"]
	tab = tab_ if tab_ in _shown_tabs else "tools"
	_tabs = UiSegmentTab.new(_shown_tabs.map(func(t): return {label = _TAB_LABELS[t]}), _shown_tabs.find(tab))
	_tabs.changed.connect(func(i: int):
		tab = _shown_tabs[i]
		sheet.close()
		_key = 0
		refresh(view)
		tab_changed.emit(tab))
	body.add_child(_tabs)
	sheet = UiInfoSheet.new()
	sheet.rules = func(id: String, ctx: StringName, o: Dictionary) -> Dictionary: return P0ItemInfo.spec(view, id, ctx, o)
	sheet.visible = false
	body.add_child(sheet)
	_scroll = TouchScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", _GAP)
	_scroll.add_child(_list)
	refresh(view_)

## Follows the view (the P0 UI calls this every frame while the drawer is open). Cards update in place, so a craft's
## float can sit on its card in the same frame; they are rebuilt only when the tab's recipes change.
func refresh(v: Dictionary) -> void:
	view = v
	var model := P0MaterialLogic.workbench_model(view, tab)
	var key := hash([tab, model])
	if key == _key: return
	_key = key
	if sheet.is_open(): sheet.refresh()   # Equipped, In Gear, ×N follow the view
	var ids: Array = model.map(func(m): return str(m.id))
	if ids != _cards.keys():
		for c in _list.get_children(): c.queue_free()
		_cards.clear()
		for id in ids: _cards[id] = _new_card(id)
	for m in model:
		_models[str(m.id)] = m
		(_cards[str(m.id)] as UiBlueprintCard).set_data(_card_data(m))

func _new_card(id: String) -> UiBlueprintCard:
	var card := UiBlueprintCard.new()
	card.pressed.connect(func():
		var cmd: Dictionary = _models.get(id, {}).get("button", {}).get("cmd", {})
		if not cmd.is_empty(): command_requested.emit(cmd))
	card.unavailable_pressed.connect(func(r: String): unavailable_requested.emit(r))
	card.icon_pressed.connect(func(): show_info(str(_models.get(id, {}).get("item", ""))))
	card.material_pressed.connect(func(i: int, tile: UiNeedTile):
		var cost: Array = _models.get(id, {}).get("cost", [])
		if i < cost.size(): source_requested.emit(tile, str(cost[i].id)))
	_list.add_child(card)
	return card

static func _card_data(m: Dictionary) -> Dictionary:
	var b: Dictionary = m.button
	return {
		"icon": P0Logic.icon(str(m.item)), "name": m.name, "effect": m.effect, "yield": m.yield, "have": m.have,
		"materials": (m.cost as Array).map(func(c): return {"icon": P0Logic.icon(str(c.id)), "name": c.name, "have": c.have, "need": c.need}),
		"button": {"label": b.label, "kind": _KINDS.get(str(b.kind), UiBlueprintCard.Kind.UNAVAILABLE), "toast": str(b.get("toast", ""))},
	}

func card(recipe_id: String) -> UiBlueprintCard: return _cards.get(recipe_id)

## The item's InfoSheet under the tabs; the same item again folds it.
func show_info(item_id: String) -> void:
	if item_id == "": return
	if sheet.is_open() and sheet.item_id() == item_id:
		sheet.close()
		return
	sheet.open(item_id, &"workbench")

## TORCH-DONE: `+2 Torch` (FloatText Tone=Item, Hug) starts at the right end of the card's materials row and rises;
## the drawer stays open and the counts on the card follow the view.
func float_on(recipe_id: String, text: String, icon: Texture2D = null) -> UiFloatText:
	var c: UiBlueprintCard = _cards.get(recipe_id)
	if c == null: return null
	var ft := UiFloatText.new(text, UiFloatText.Tone.ITEM, icon)
	ft.top_level = true
	add_child(ft)
	ft.set_text(text)   # lays out in the tree, so shown_size() is known
	var row := c.materials_rect()
	ft.play(Vector2(row.end.x - ft.shown_size().x * 0.5, row.end.y))
	return ft
