class_name UiItemCell
extends Control
## One item cell, four densities (SGODOT-212; WP7-C F-05 "one item_cell, density picks the Figma main"):
##   INVENTORY  Compact/InventoryCell 633:41278  52×52  icon, quantity pill, rarity dot             (LOCK-12)
##   QUICK      Compact/QuickSlot 633:41279      52×68  icon + name + quantity only, pin state     (LOCK-04 / 05)
##   KITCHEN    Compact/Kitchen/Cell 655:58506   52×58  icon, state label, selected / cooked mark  (LOCK-20);
##              `kitchen_state` adds the main's Cookbook / Experiment states (hidden … notForCooking)
##   GEAR       Compact/GearSlot 663:61299       52×88  role above, equipment name below           (LOCK-13)
## Data in (the fields below), signals out. Each cell runs its own GestureArbiter (QUICK: SLOT mode, others:
## CELL mode, WP7-B F-04 §3 / §4), so a touch is exactly one outcome: `tapped` only for the arbiter's tap;
## everything else (lift, long_press, drag_start / drag_move / drop, swipe_up, cancel) goes out
## through `gesture` for the quick bar / bag drawer, which then sets `state` / `pinned`. mouse_filter is
## PASS, so a TouchScrollContainer still takes vertical drags (CELL mode answers them with cancel).
## Hosts outside a scroll container (the quick bar) need a STOP backing control, or the touch also reaches
## _unhandled_input (the map's tap handling, for one).
## DROP_TARGET and ZERO exist on the QuickSlot main only, LIFTED on QuickSlot and InventoryCell (State=lifted 1641:34159:
## the default look with the QuickSlot lift shadow); other densities draw them as DEFAULT.
## GHOST (QuickSlot State=ghost 1415:94114, A-08) is an empty slot showing what the action can use: dashed like
## EMPTY, the family icon at 35 %, a one-word family name in secondary ink (`title`), no count, never pinned.
## Other densities draw it as EMPTY.

signal tapped
## A GestureArbiter outcome other than tap, e.g. {kind = &"lift", pos}; `pos` is in global coordinates. Pinning is the
## quick bar's drop on its Pin zone (LOCK-05 v1.11), never a cell outcome.
signal gesture(outcome: Dictionary)

enum Density { INVENTORY, QUICK, KITCHEN, GEAR }
## UNCOLLECTED (InventoryCell 1405:92952, Fish-dex): the default surface with the icon dimmed to 35 %, no quantity, no
## rarity dot — a silhouette not caught yet. InventoryCell only (the other mains draw it as DEFAULT).
enum State { DEFAULT, SELECTED, EMPTY, LIFTED, DROP_TARGET, ZERO, GHOST, UNCOLLECTED }
## Compact/Kitchen/Cell states beyond default / selected / empty (WP1b B1-02; inPot / notForCooking 223):
##   HIDDEN       unknown page: grey dish silhouette + ingredient family dots, never the real dish art
##   CLUED        unknown page with a known slot: the silhouette and the family row with that slot lit
##   (both draw one dot per slot from `families`, a lit slot from `clues`; `might_have` adds State=mightHave's ring)
##   TASTED       known, not cooked yet: half-colour icon + `Try it` tag centred at the bottom (primary; SGODOT-256 ⑨,
##                q(92)); the tag goes after the first cook. The word Tasted is not shown to the player.
##   MASTERED     gold star at the bottom right (Cooked ×10); no quantity
## Kitchen cells carry no check mark (⑨: Show mark retired; can cook is the Can cook chip, the order and the button).
##   LOCKED       3-slot page before Cooking Lv4: silhouette + `Lv4` lock tag (text from `status`, else Lv4)
##   IN_POT       Experiment: in the pot (selected stroke, icon raised); `In pot` only once none is left (no quantity),
##                otherwise the remaining quantity (COOK-2b / P0-2 instances: Show state off while ×N shows)
##   NOT_FOR_COOKING  Experiment: the icon at 25 %, `Not for cooking`; it cannot go in the pot
enum KitchenState { DEFAULT, HIDDEN, CLUED, TASTED, MASTERED, LOCKED, IN_POT, NOT_FOR_COOKING }

const RARITY_COLORS := [UiTokens.COLOR_RARITY_COMMON, UiTokens.COLOR_RARITY_FINE, UiTokens.COLOR_RARITY_RARE,
	UiTokens.COLOR_RARITY_LEGENDARY]
const PIN_GLYPH := preload("res://assets/ui/kit_icons/pin.svg")
const STAR_GLYPH := preload("res://assets/ui/kit_icons/star.svg")
const LOCK_GLYPH := preload("res://assets/ui/kit_icons/lock.svg")
const SILHOUETTE := preload("res://assets/ui/kit_icons/kitchen/dish_silhouette.svg")
## Ingredient families (plan §7.3.1: W water, F field, O orchard, S seasoning): the dot colours color/family/* and the
## one-colour icons of a slot lit by a family clue, i-fam-fish / produce / fruit / seasoning (Figma 1727:102700 /
## 102705 / 102710 / 102717; 不知火舞 and 安其拉, SGODOT-226 33725b5e).
const FAMILY_COLORS := {"W": UiTokens.COLOR_FAMILY_WATER, "F": UiTokens.COLOR_FAMILY_FIELD, "O": UiTokens.COLOR_FAMILY_ORCHARD,
	"S": UiTokens.COLOR_FAMILY_SEASONING}
const FAMILY_ICONS := {"W": preload("res://assets/ui/kit_icons/kitchen/fam_fish.svg"),
	"F": preload("res://assets/ui/kit_icons/kitchen/fam_produce.svg"), "O": preload("res://assets/ui/kit_icons/kitchen/fam_fruit.svg"),
	"S": preload("res://assets/ui/kit_icons/kitchen/fam_seasoning.svg")}
const HOME_GLYPH := preload("res://assets/ui/kit_icons/home.svg")

# Positions inside the fixed-size mains (layout of one main, not shared tokens):
const _CELL_ICON_TOP := 10.0      # InventoryCell: 27 px icon at y 10 of 52
const _KITCHEN_ICON_TOP := 8.0    # Kitchen/Cell: icon at y 8
const _PILL_INSET := 3.0          # quantity pill 24×13 at (25, 36) of 52×52
const _DOT_INSET := 5.0           # rarity dot at (5, 5); Kitchen/Cell has it at (4, 4)
const _KITCHEN_DOT_INSET := 4.0
const _KITCHEN_LABEL_TOP := 31.0  # "Cell state label" 52×25 at y 31, radius 5, text 13 high at y 1
const _KITCHEN_LABEL_H := 25.0
const _KITCHEN_LABEL_RADIUS := 5.0
const _KITCHEN_SILHOUETTE := Rect2(10.4, 9.4, 30, 22)   # hidden / clued / locked
const _KITCHEN_FAMILY_TOP := 37.4   # Ingredient family dots: centred, top at y 38 of the main; dots 5, 3 apart,
const _KITCHEN_FAMILY_DOT := 5.0     # a lit slot 10 (the row is then 10 high and the dots sit on its middle)
const _KITCHEN_FAMILY_GAP := 3.0
const _KITCHEN_FAMILY_ICON := 10.0
const _KITCHEN_GLOW_SPREAD := 2.0    # State=mightHave 1726:32864: ring outside the cell, 0 offset, blur 4, spread 2,
const _KITCHEN_GLOW_BLUR := 4.0      # color/new at 50 %, still
const _KITCHEN_GLOW_ALPHA := 0.5
const _KITCHEN_STAR := Rect2(36.4, 36.4, 12, 12)       # State=mastered 1228:105954 (C28, 226 f5523358): bottom right,
const _KITCHEN_STAR_GLYPH := 7.7
const _KITCHEN_TAG := Vector2(1.4, 1.4)                 # Lv4 lock tag: 3 px side padding, radius 5
const _KITCHEN_TAG_PAD := 3.0
const _KITCHEN_TAG_RADIUS := 5.0
const _KITCHEN_TAG_GLYPH := 8.0
const _KITCHEN_RACK_STROKE := 0.6                        # Rack tag (Show rack, 226 e8e5617a): surface, 0.6 border
const _KITCHEN_CHIP_ROW := Vector2(36, 15)              # Try it row 1919:32860: y 36, 15 high, the tag centred in it;
const _KITCHEN_CHIP_PAD := 4.0                          # surface-raised tag, 1 px border, 4 px side padding, radius 6
const _KITCHEN_CHIP_RADIUS := 6.0
const _KITCHEN_TASTED_ALPHA := 0.5                      # "half colour"
const _KITCHEN_RAISED_ICON_TOP := 1.5                   # inPot / notForCooking: icon at y 1.5 / 2.4
const _KITCHEN_IN_POT_LABEL := Vector2(20, 16)          # `In pot` band: y 20, 16 high, no fill
const _KITCHEN_NFC_LABEL := Vector2(25, 25)             # `Not for / cooking`: y 25, two lines
const _KITCHEN_NFC_ALPHA := 0.25
const _STORED_AT := Vector2(4, 38)   # InventoryCell: Icon/i-home 11×11 at (4, 38) on storage stacks (BAG-2-2)
const _STORED_ICON := 11.0
## Gift Clues (Fishing Lv7, q(167); 不知火舞 302 b308ee14): a resident met likes this dish — a solid 14 px ♥ 4 in from
## the top-right corner, StatusBadge Gift's coral, no ring and no number; one look whoever and however much.
const _LIKED_ICON := 14.0
const _LIKED_INSET := 4.0
const HEART_GLYPH := preload("res://assets/p0/icons/heart.svg")   # solid #E07A5F, the HP bar's heart
## The gift drawer's mark (RESIDENT-GIFT 1216:83527; 不知火舞 on 302 b308ee14): what giving this dish adds, a 17 px pill
## centred 2 above the cell — `♥ +3` green on the primary tint when the dish is one this resident loves or likes
## (gain_hit; 不知火舞 on 283: by the hit, not the number), any other `♥ +2` / `♥ +1` grey ink on white, `−2` (the Mystery
## Dish, no ♥) on the grey keys' fill; ExtraBold 10, padding 5 / 1, radius 8, a 1 px edgeStrong outline (Figma's unbound #D1CCC2, 不知火舞: the nearest token); kept while selected.
const GAIN_H := 17.0
const GAIN_GAP := 2.0
const _GAIN_OUTLINE := UiTokens.COLOR_EDGE_STRONG
const _QUICK_PAD := 4.0           # QuickSlot "Slot surface" padding
const _QUICK_NAME_H := 22.0       # two-line name block, then the 12 px quantity line
const _QUICK_QTY_H := 12.0
const _GEAR_ROLE_H := 11.0        # GearSlot: role 11 high, slot at y 16, name at y 71 (16 high)
const _GEAR_SLOT_TOP := 16.0
const _GEAR_NAME_TOP := 71.0
const _GEAR_NAME_H := 23.0       # two lines of 9 / 125 % (WP1b: names wrap, never truncate; they may hang below 88)

var density: Density
var state: State = State.DEFAULT: set = set_state
var icon: Texture2D: set = set_icon
## Item name: the two-line QuickSlot name or the GearSlot equipment name. Unused by INVENTORY / KITCHEN.
var title := "": set = set_title
## Count as shown, e.g. "×24"; "" hides it. QUICK shows a plain line, INVENTORY / KITCHEN a pill.
var quantity := "": set = set_quantity
## 0 = no dot, 1–4 = Common / Fine / Rare / Legendary (INVENTORY and KITCHEN).
var rarity := 0: set = set_rarity
## LOCK-05 pin: warm fill, amber strip inside the top edge, amber pin badge over the top centre (QUICK).
var pinned := false: set = set_pinned
## GearSlot role above the slot, e.g. "Fishing".
var role := "": set = set_role
## Kitchen state label over the lower part of the cell, e.g. "Shop"; "" hides it.
var status := "": set = set_status
## KITCHEN only; DEFAULT keeps the plain behaviour above (status label).
var kitchen_state: KitchenState = KitchenState.DEFAULT: set = set_kitchen_state
## KITCHEN only: a seasoning held on the Spice Rack (Show rack): a `Rack` tag top-left where the Lv4 lock sits, and
## no rarity dot (q(46); An Qi La, 226 e8e5617a). The quantity is the stored count. In the pot it keeps the tag
## (COOK-2b-RACK): taking it out returns it to the rack.
var rack := false: set = set_rack
## INVENTORY: the stack is in Farm Storage, not the bag — a small house at the bottom left (BAG-2-2).
var stored := false: set = set_stored
## INVENTORY: a resident met likes this dish (Gift Clues, Fishing Lv7): the ♥ at the top right.
var liked := false: set = set_liked
## INVENTORY, the gift drawer: what giving this dish adds (int; null hides the mark), drawn over the cell.
var gain = null: set = set_gain
## The gift drawer: the dish is one this resident loves or likes — its mark is green.
var gain_hit := false: set = set_gain_hit
## KITCHEN unknown pages: each slot's family, e.g. ["W", "S"] — one dot per slot in its colour (FAMILY_COLORS).
var families: Array = []: set = set_families
## KITCHEN unknown pages: per slot, the clue that lit it — the ingredient's own icon, or family_icon() when the clue
## is a family ("Any Common fish") — or null. Never the dish art (§7.2.7: 线索点亮为具体原料).
var clues: Array = []: set = set_clues
## KITCHEN: "You might have what it takes" (§7.5.1, server `maybe`): the page's families can all be filled from what
## the stove reaches. Kitchen/Cell State=mightHave (1726:32864) is the hidden look with this ring; a clued page keeps
## its lit slot under it.
var might_have := false: set = set_might_have

## Milliseconds for the arbiter; tests inject a fake clock.
var clock := Callable(Time, &"get_ticks_msec")

var _arbiter: GestureArbiter
var _surface: Panel
var _icon: TextureRect
var _name: Label
var _qty: Label
var _pill: Panel
var _dot: Panel
var _role: Label
var _status: Panel
var _strip: Panel
var _new_ring: Panel   # QuickSlot State=new (1663:101150): the color/new ring of a first-time item
var _badge: Panel
var _silhouette: TextureRect
var _family: HBoxContainer
var _glow: Panel
var _star: Panel
var _tag: PanelContainer
var _rack_tag: PanelContainer
var _tag_label: Label
var _chip: HBoxContainer
var _chip_label: Label
var _home: TextureRect
var _liked: TextureRect
var _gain: PanelContainer
var _gain_label: Label

func _init(d: Density = Density.INVENTORY) -> void:
	density = d
	mouse_filter = Control.MOUSE_FILTER_PASS
	_arbiter = GestureArbiter.new(GestureArbiter.Mode.SLOT if d == Density.QUICK else GestureArbiter.Mode.CELL)
	set_process(false)
	match density:
		Density.INVENTORY: custom_minimum_size = Vector2(UiTokens.SIZE_INVENTORY_CELL, UiTokens.SIZE_INVENTORY_CELL)
		Density.QUICK: custom_minimum_size = Vector2(UiTokens.SIZE_QUICK_SLOT_W, UiTokens.SIZE_QUICK_SLOT_H)
		Density.KITCHEN: custom_minimum_size = Vector2(UiTokens.SIZE_KITCHEN_CELL_W, UiTokens.SIZE_KITCHEN_CELL_H)
		Density.GEAR: custom_minimum_size = Vector2(UiTokens.SIZE_GEAR_SLOT_W, UiTokens.SIZE_GEAR_SLOT_H)
	_surface = _box(self)
	match density:
		Density.QUICK: _build_quick()
		Density.GEAR: _build_gear()
		_: _build_cell()
	_refresh()

func set_state(v: State) -> void: state = v; _refresh()
func set_icon(v: Texture2D) -> void: icon = v; _refresh()
func set_title(v: String) -> void: title = v; _refresh()
func set_quantity(v: String) -> void: quantity = v; _refresh()
func set_rarity(v: int) -> void: rarity = v; _refresh()
func set_pinned(v: bool) -> void: pinned = v; _refresh()
func set_role(v: String) -> void: role = v; _refresh()
func set_status(v: String) -> void: status = v; _refresh()
func set_kitchen_state(v: KitchenState) -> void: kitchen_state = v; _refresh()
func set_rack(v: bool) -> void: rack = v; _refresh()
func set_stored(v: bool) -> void: stored = v; _refresh()
func set_liked(v: bool) -> void: liked = v; _refresh()
func set_gain(v) -> void: gain = v; _refresh()
func set_gain_hit(v: bool) -> void: gain_hit = v; _refresh()
func set_families(v: Array) -> void:
	if v == families: return   # a grid refresh sets them on every cell
	families = v
	_build_family()
	_refresh()
func set_clues(v: Array) -> void:
	if v == clues: return
	clues = v
	_build_family()
	_refresh()
func set_might_have(v: bool) -> void: might_have = v; _refresh()

static func family_icon(family: String) -> Texture2D: return FAMILY_ICONS.get(family, null)

func _gui_input(event: InputEvent) -> void:
	_emit(_arbiter.feed(event, clock.call()))
	set_process(_arbiter.is_active())
	# A lifted or dragged cell keeps its touch: the scroll container behind it must not take the drag (the bag's
	# way onto the quick bar, SGODOT-225 / BAR-DRAG-9). Before the lift a vertical drag still scrolls the grid.
	if _arbiter.is_lifted() or _arbiter.is_dragging(): accept_event()

## Long presses fire on time alone, so tick while a finger is down.
func _process(_delta: float) -> void:
	_emit(_arbiter.tick(clock.call()))
	if not _arbiter.is_active(): set_process(false)

func _notification(what: int) -> void:
	# A scroll container took over the drag: this touch is no longer the cell's.
	if what == NOTIFICATION_SCROLL_BEGIN and _arbiter.is_active():
		_arbiter.reset()
		set_process(false)
		gesture.emit({kind = &"cancel"})

func _emit(outcomes: Array) -> void:
	for o: Dictionary in outcomes:
		if o.kind == &"tap":
			tapped.emit()
			continue
		var g := o.duplicate()
		if g.has("pos"): g.pos = get_global_transform() * (g.pos as Vector2)
		gesture.emit(g)

## QuickSlot pin badge pop after a pin toggle on the Pin zone (LOCK-05 v1.11): 1 → 1.3 → 1 over 300 ms.
const _PIN_POP := 1.3
const _PIN_POP_MS := 300.0
func pop_pin() -> void:
	if _badge == null or not _badge.visible: return
	_badge.pivot_offset = _badge.size * 0.5
	var t := _badge.create_tween()
	t.tween_property(_badge, ^"scale", Vector2.ONE * _PIN_POP, UiKit.secs(_PIN_POP_MS * 0.5)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_badge, ^"scale", Vector2.ONE, UiKit.secs(_PIN_POP_MS * 0.5)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

## QuickSlot State=new (1663:101150, §10.3.3 ④): a first-time item's slot rings once in color/new, in then out over
## MOTION_NEW_UNLOCK_FLASH_MS; size, place and icon stay, no badge, no buzz. QuickSlot and InventoryCell (the Fish-dex's
## newly caught fish, 1699:102396).
func flash() -> void:
	if _new_ring == null: return
	var half := UiKit.secs(UiTokens.MOTION_NEW_UNLOCK_FLASH_MS * 0.5)
	var t := _new_ring.create_tween()
	_new_ring.modulate.a = 0.0
	t.tween_property(_new_ring, ^"modulate:a", 1.0, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(_new_ring, ^"modulate:a", 0.0, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func is_flashing() -> bool: return _new_ring != null and _new_ring.modulate.a > 0.0

## The ring at its peak, held: the gallery and snapshots only (a still of State=new).
func show_new_ring() -> void:
	if _new_ring: _new_ring.modulate.a = 1.0

## The state actually drawn: the extra QuickSlot states fall back to DEFAULT (GHOST to EMPTY) on the other mains.
func drawn_state() -> State:
	if density != Density.QUICK and state in [State.DROP_TARGET, State.ZERO]: return State.DEFAULT
	if density not in [Density.QUICK, Density.INVENTORY] and state == State.LIFTED: return State.DEFAULT
	if density != Density.QUICK and state == State.GHOST: return State.EMPTY
	if density != Density.INVENTORY and state == State.UNCOLLECTED: return State.DEFAULT
	return state

# ------------------------------------------------------------------ build

static func _box(parent: Control) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p

static func _place(c: Control, anchor_x: float, x: float, y: float, w: float, h: float) -> void:
	c.anchor_left = anchor_x
	c.anchor_right = anchor_x
	c.offset_left = x
	c.offset_right = x + w
	c.offset_top = y
	c.offset_bottom = y + h

## Label centred on a band: Godot sizes a Label to the font's full line box, so the band may be shorter
## than the label; growing both ways keeps the text centred where the Figma text box sits.
## A quick slot's name style (不知火舞 B7 286 6e15f758, option B): C10, broken only between words over the slot's full
## 52; a word wider than that — `Chamomile`, `Strawberry` — sets the whole name in C9, the floor. A word wider still
## at C9 is a naming matter (李白), not a smaller size. A hyphen is a break too (`Salt-` / `Grilled`).
static func quick_name_style(title: String) -> StringName:
	if _cjk(title): return UiTokens.STYLE_C10_B   # broken by the character (中文): no word is wider than the slot
	var th := UiKit.theme()
	var font := th.get_font(&"font", UiTokens.STYLE_C10_B)
	var fs := th.get_font_size(&"font_size", UiTokens.STYLE_C10_B)
	for word in title.replace("-", "- ").split(" ", false):
		if font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > UiTokens.SIZE_QUICK_SLOT_W: return UiTokens.STYLE_C9_B
	return UiTokens.STYLE_C10_B

## A quick slot's name as shown (q(217), 不知火舞 340 c4a3b888): a name that breaks into more than two lines at its
## quick_name_style drops a last word `Seeds` / `Seed` (the seed-packet icon says it): `Quick Radish Seeds` →
## `Quick Radish`. Still more than two lines, it is set as q(197) sets it; nothing else is cut. Quick slots only (and
## the bag drawer's bar row, the same cell); the Bag's cells, the item card and Today keep the whole name.
## Under 中文 (#649 第二批 ⑤, zh-01 「小萝卜种子」 past the slot) the name is the translation, broken by the character:
## past two lines a last 「种子」 goes the same way (「小萝卜」).
static func quick_name(title: String) -> String:
	var shown := String(TranslationServer.translate(title))
	if _cjk(shown):
		if quick_lines(shown) <= 2 or not shown.ends_with(SEED_ZH): return shown
		return shown.trim_suffix(SEED_ZH)
	if quick_lines(title) <= 2: return title
	for tail in [" Seeds", " Seed"]:
		if title.ends_with(tail): return title.trim_suffix(tail)
	return title
const SEED_ZH := "种子"

## Chinese in it (CJK and up): broken by the character, as AUTOWRAP_ARBITRARY does, not between words.
static func _cjk(text: String) -> bool:
	for c in text:
		if c.unicode_at(0) >= 0x2E80: return true
	return false

## Lines a quick slot's name takes across the slot's full 52 at its style, breaking between words (and after a hyphen)
## as the label's AUTOWRAP_WORD does.
static func quick_lines(title: String) -> int:
	var style := quick_name_style(title)
	var th := UiKit.theme()
	var font := th.get_font(&"font", style)
	var fs := th.get_font_size(&"font_size", style)
	var width := float(UiTokens.SIZE_QUICK_SLOT_W)
	var lines := 0
	var line := ""
	if _cjk(title):
		for c in title:
			if line != "" and font.get_string_size(line + c, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
				lines += 1
				line = c.strip_edges()
			else: line += c
		return lines + (1 if line != "" else 0)
	for word in title.replace("-", "- ").split(" ", false):
		var joined := word if line == "" else (line + word if line.ends_with("-") else line + " " + word)
		if line != "" and font.get_string_size(joined, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
			lines += 1
			line = word
		else: line = joined
	return lines + (1 if line != "" else 0)

static func _band_label(parent: Control, style: StringName, y: float, h: float, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := UiKit.label("", style)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	l.anchor_right = 1.0
	l.offset_top = y
	l.offset_bottom = y + h
	parent.add_child(l)
	return l

func _add_icon(parent: Control, side: float, top: float) -> void:
	_icon = UiKit.icon(null, side)
	_place(_icon, 0.5, -side * 0.5, top, side, side)
	parent.add_child(_icon)

func _add_pill(parent: Control) -> void:
	_pill = _box(parent)
	_pill.anchor_left = 1.0
	_pill.anchor_right = 1.0
	_pill.anchor_top = 1.0
	_pill.anchor_bottom = 1.0
	_pill.offset_left = -_PILL_INSET - UiTokens.SIZE_QTY_PILL_W
	_pill.offset_right = -_PILL_INSET
	_pill.offset_top = -_PILL_INSET - UiTokens.SIZE_QTY_PILL_H
	_pill.offset_bottom = -_PILL_INSET
	_pill.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, UiTokens.SIZE_QTY_PILL_H * 0.5))
	_qty = _band_label(_pill, UiTokens.STYLE_C10_XB, 0.0, UiTokens.SIZE_QTY_PILL_H)

func _add_dot(parent: Control, inset: float) -> void:
	_dot = _box(parent)
	_place(_dot, 0.0, inset, inset, UiTokens.SIZE_RARITY_DOT, UiTokens.SIZE_RARITY_DOT)

## INVENTORY and KITCHEN: a square surface with icon, pill and rarity dot; KITCHEN adds label and mark.
func _build_cell() -> void:
	var side := UiTokens.SIZE_INVENTORY_CELL if density == Density.INVENTORY else UiTokens.SIZE_KITCHEN_CELL_W
	_place(_surface, 0.0, 0.0, 0.0, side, side)
	_surface.anchor_right = 1.0
	_surface.offset_right = 0.0
	var kitchen := density == Density.KITCHEN
	_add_icon(_surface, UiTokens.SIZE_INVENTORY_ICON, _KITCHEN_ICON_TOP if kitchen else _CELL_ICON_TOP)
	_add_dot(_surface, _KITCHEN_DOT_INSET if kitchen else _DOT_INSET)
	_add_pill(_surface)
	if not kitchen:
		_home = UiKit.icon(HOME_GLYPH, _STORED_ICON)   # Farm Storage stack: 11 px house at (4, 38)
		_home.self_modulate = UiTokens.COLOR_SECONDARY
		_place(_home, 0.0, _STORED_AT.x, _STORED_AT.y, _STORED_ICON, _STORED_ICON)
		_surface.add_child(_home)
		_liked = UiKit.icon(HEART_GLYPH, _LIKED_ICON)
		_liked.name = "Liked"
		_place(_liked, 1.0, -_LIKED_INSET - _LIKED_ICON, _LIKED_INSET, _LIKED_ICON, _LIKED_ICON)
		_surface.add_child(_liked)
		_gain = PanelContainer.new()
		_gain.name = "Gain"
		_gain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_gain.anchor_left = 0.5
		_gain.anchor_right = 0.5
		_gain.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_gain.offset_top = -GAIN_GAP - GAIN_H
		_gain.offset_bottom = -GAIN_GAP
		_gain_label = UiKit.label("", UiTokens.STYLE_C10_XB)
		_gain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_gain_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_gain.add_child(_gain_label)
		add_child(_gain)
		# InventoryCell State=new (1699:102396): 2 px color/new inside the cell, flashed once like the QuickSlot's.
		_new_ring = _box(_surface)
		_new_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_new_ring.add_theme_stylebox_override(&"panel", UiStyleBox.make(Color.TRANSPARENT, UiTokens.RADIUS_INVENTORY_CELL,
			UiTokens.COLOR_NEW, UiTokens.STROKE_SELECTED))
		_new_ring.modulate.a = 0.0
		return
	_status = _box(self)
	_place(_status, 0.0, 0.0, _KITCHEN_LABEL_TOP, side, _KITCHEN_LABEL_H)
	_status.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, _KITCHEN_LABEL_RADIUS))
	_name = _band_label(_status, UiTokens.STYLE_C10_B, 0.0, UiTokens.SIZE_QTY_PILL_H)
	_name.add_theme_color_override(&"font_color", UiTokens.COLOR_SECONDARY)
	_build_kitchen_extras()

## The Cookbook / Experiment marks of the Kitchen/Cell main (hidden, clued, tasted, mastered, locked).
func _build_kitchen_extras() -> void:
	_silhouette = UiKit.icon(SILHOUETTE, _KITCHEN_SILHOUETTE.size.y)
	_silhouette.self_modulate = UiTokens.COLOR_DISABLED
	_place(_silhouette, 0.0, _KITCHEN_SILHOUETTE.position.x, _KITCHEN_SILHOUETTE.position.y, _KITCHEN_SILHOUETTE.size.x, _KITCHEN_SILHOUETTE.size.y)
	_surface.add_child(_silhouette)
	_family = HBoxContainer.new()
	_family.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_family.alignment = BoxContainer.ALIGNMENT_CENTER
	_family.add_theme_constant_override(&"separation", int(_KITCHEN_FAMILY_GAP))
	_family.anchor_right = 1.0
	_family.offset_top = _KITCHEN_FAMILY_TOP
	_family.offset_bottom = _KITCHEN_FAMILY_TOP   # grows down to its tallest child: 5 with dots only, 10 with a lit slot
	_surface.add_child(_family)
	var g := _KITCHEN_GLOW_SPREAD
	_glow = _box(self)
	move_child(_glow, 0)   # under the surface: only the ring outside it shows
	_place(_glow, 0.0, -g, -g, UiTokens.SIZE_KITCHEN_CELL_W + g * 2.0, UiTokens.SIZE_KITCHEN_CELL_W + g * 2.0)
	var ring := UiStyleBox.make(Color.TRANSPARENT, UiTokens.RADIUS_INVENTORY_CELL + g)
	ring.shadow_color = UiKit.alpha(UiTokens.COLOR_NEW, _KITCHEN_GLOW_ALPHA)
	ring.shadow_size = _KITCHEN_GLOW_BLUR
	_glow.add_theme_stylebox_override(&"panel", ring)
	_star = _box(_surface)
	_place(_star, 0.0, _KITCHEN_STAR.position.x, _KITCHEN_STAR.position.y, _KITCHEN_STAR.size.x, _KITCHEN_STAR.size.y)
	_star.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_GOLD_DEEP, _KITCHEN_STAR.size.x * 0.5))   # the white star needs the deep gold
	var star := UiKit.icon(STAR_GLYPH, _KITCHEN_STAR_GLYPH)
	star.self_modulate = UiTokens.COLOR_SURFACE_RAISED
	var inset := (_KITCHEN_STAR.size.x - _KITCHEN_STAR_GLYPH) * 0.5
	_place(star, 0.0, inset, inset, _KITCHEN_STAR_GLYPH, _KITCHEN_STAR_GLYPH)
	_star.add_child(star)
	_tag = _pill_tag(UiTokens.COLOR_DISABLED, Color.TRANSPARENT, _KITCHEN_TAG_RADIUS, _KITCHEN_TAG_PAD)
	_tag.position = _KITCHEN_TAG
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 1)
	var lock := UiKit.icon(LOCK_GLYPH, _KITCHEN_TAG_GLYPH)
	lock.self_modulate = UiTokens.COLOR_SECONDARY
	lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lock)
	_tag_label = UiKit.label("", UiTokens.STYLE_C9_B, UiTokens.COLOR_SECONDARY)
	row.add_child(_tag_label)
	_tag.add_child(row)
	_surface.add_child(_tag)
	_rack_tag = PanelContainer.new()
	_rack_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rack_tag.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, _KITCHEN_TAG_RADIUS, UiTokens.COLOR_BORDER,
		_KITCHEN_RACK_STROKE).with_margins(_KITCHEN_TAG_PAD, 0.0, _KITCHEN_TAG_PAD, 0.0))
	_rack_tag.position = _KITCHEN_TAG
	_rack_tag.add_child(UiKit.label("Rack", UiTokens.STYLE_C9_B, UiTokens.COLOR_SECONDARY))
	_surface.add_child(_rack_tag)
	_chip = HBoxContainer.new()   # the row across the cell; the tag, as wide as its word, in its middle
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.alignment = BoxContainer.ALIGNMENT_CENTER
	_chip.anchor_right = 1.0
	_chip.offset_top = _KITCHEN_CHIP_ROW.x
	_chip.offset_bottom = _KITCHEN_CHIP_ROW.x + _KITCHEN_CHIP_ROW.y
	var tag := _pill_tag(UiTokens.COLOR_SURFACE_RAISED, UiTokens.COLOR_BORDER, _KITCHEN_CHIP_RADIUS, _KITCHEN_CHIP_PAD)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip_label = UiKit.label("Try it", UiTokens.STYLE_C10_B, UiTokens.COLOR_PRIMARY)
	tag.add_child(_chip_label)
	_chip.add_child(tag)
	_surface.add_child(_chip)

## One 5 px dot per slot in its family colour; a slot with a clue is its 10 px icon instead, the dots centred on it.
func _build_family() -> void:
	if _family == null: return
	for c in _family.get_children(): c.free()
	for i in families.size():
		var clue = clues[i] if i < clues.size() else null
		if clue is Texture2D:
			_family.add_child(UiKit.icon(clue, _KITCHEN_FAMILY_ICON))
			continue
		var dot := _box(_family)
		dot.custom_minimum_size = Vector2(_KITCHEN_FAMILY_DOT, _KITCHEN_FAMILY_DOT)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var color: Color = FAMILY_COLORS.get(str(families[i]), UiTokens.COLOR_DISABLED)
		dot.add_theme_stylebox_override(&"panel", UiStyleBox.make(color, _KITCHEN_FAMILY_DOT * 0.5))

static func _pill_tag(bg: Color, border: Color, radius: float, pad: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiStyleBox.make(bg, radius, border, UiTokens.STROKE_DEFAULT if border.a > 0.0 else 0.0)
	p.add_theme_stylebox_override(&"panel", box.with_margins(pad, 0.0, pad, 0.0))
	return p

func _build_quick() -> void:
	_surface.anchor_right = 1.0
	var w := UiTokens.SIZE_QUICK_SLOT_W - _QUICK_PAD * 2.0
	var body := Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [&"offset_left", &"offset_top"]: body.set(side, _QUICK_PAD)
	for side in [&"offset_right", &"offset_bottom"]: body.set(side, -_QUICK_PAD)
	_surface.add_child(body)
	_add_icon(body, UiTokens.SIZE_QUICK_SLOT_ICON, 0.0)
	# The name block spans the slot's full width (the icon and the count keep the padding) and breaks only between
	# words (quick_name_style; 不知火舞 B7 286 6e15f758, option B).
	_name = _band_label(body, UiTokens.STYLE_C10_B, 0.0, _QUICK_NAME_H)
	_name.offset_left = -_QUICK_PAD
	_name.offset_right = _QUICK_PAD
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	_name.max_lines_visible = 2
	_name.custom_minimum_size.x = w + _QUICK_PAD * 2.0
	_qty = _band_label(body, UiTokens.STYLE_C10_XB, 0.0, _QUICK_QTY_H, HORIZONTAL_ALIGNMENT_RIGHT)
	_new_ring = _box(_surface)
	_new_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_new_ring.add_theme_stylebox_override(&"panel", UiStyleBox.make(Color.TRANSPARENT, UiTokens.RADIUS_CELL, UiTokens.COLOR_NEW, UiTokens.STROKE_SELECTED))
	_new_ring.modulate.a = 0.0
	_strip = _box(_surface)
	_strip.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PIN_AMBER, UiTokens.SIZE_PIN_STRIP_H * 0.5))
	var b := UiTokens.SIZE_PIN_BADGE
	_badge = _box(_surface)
	_place(_badge, 0.5, -b * 0.5, -b * 0.5, b, b)
	_badge.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PIN_AMBER, b * 0.5,
		UiTokens.COLOR_SURFACE, UiTokens.STROKE_PIN_BADGE))
	var glyph := UiKit.icon(PIN_GLYPH, UiTokens.SIZE_PIN_ICON)
	glyph.self_modulate = UiTokens.COLOR_SURFACE_RAISED
	_place(glyph, 0.5, -UiTokens.SIZE_PIN_ICON * 0.5, (b - UiTokens.SIZE_PIN_ICON) * 0.5, UiTokens.SIZE_PIN_ICON, UiTokens.SIZE_PIN_ICON)
	_badge.add_child(glyph)

func _build_gear() -> void:
	_role = _band_label(self, UiTokens.STYLE_C9_B, 0.0, _GEAR_ROLE_H)
	_role.add_theme_color_override(&"font_color", UiTokens.COLOR_SECONDARY)
	_place(_surface, 0.0, 0.0, _GEAR_SLOT_TOP, UiTokens.SIZE_GEAR_SLOT_W, UiTokens.SIZE_INVENTORY_CELL)
	var side := UiTokens.SIZE_INVENTORY_ICON
	_add_icon(_surface, side, (UiTokens.SIZE_INVENTORY_CELL - side) * 0.5)
	_name = _band_label(self, UiTokens.STYLE_C9_B, _GEAR_NAME_TOP, _GEAR_NAME_H)
	_name.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_name.grow_vertical = Control.GROW_DIRECTION_END
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.max_lines_visible = 2

# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if _surface == null: return
	var s := drawn_state()
	var empty := s == State.EMPTY
	_icon.texture = icon
	_icon.visible = icon != null and not empty
	match density:
		Density.QUICK: _refresh_quick(s)
		Density.GEAR:
			_surface.add_theme_stylebox_override(&"panel", _cell_box(s, UiTokens.RADIUS_INVENTORY_CELL))
			_role.text = role
			_name.text = "Empty" if empty else title   # an empty slot says only Empty (WP1b, A-08)
		_:
			_surface.add_theme_stylebox_override(&"panel", _cell_box(s, UiTokens.RADIUS_INVENTORY_CELL))
			var dim := s == State.UNCOLLECTED
			_pill.visible = quantity != "" and not empty and not dim
			_qty.text = quantity
			_dot.visible = rarity > 0 and not empty and not dim and not (density == Density.KITCHEN and rack)
			_icon.modulate.a = UiTokens.OPACITY_ZERO_ICON if dim else 1.0   # "Icon · dimmed" 35 %, as the ghost slot
			if _home != null: _home.visible = stored and not empty
			if _liked != null: _liked.visible = liked and not empty and not dim   # kept while selected
			if _gain != null: _paint_gain(empty)
			if rarity > 0:
				_dot.add_theme_stylebox_override(&"panel", UiStyleBox.make(RARITY_COLORS[clampi(rarity - 1, 0, 3)], UiTokens.SIZE_RARITY_DOT * 0.5))
			if density == Density.KITCHEN: _refresh_kitchen(s, empty)

func _paint_gain(empty: bool) -> void:
	_gain.visible = gain != null and not empty
	if not _gain.visible: return
	var n := int(gain)
	var hit := gain_hit and n > 0
	var bg := UiTokens.COLOR_PRIMARY_TINT if hit else (UiTokens.COLOR_SURFACE_RAISED if n >= 0 else UiTokens.COLOR_DISABLED)
	_gain.add_theme_stylebox_override(&"panel", UiStyleBox.make(bg, 8.0, _GAIN_OUTLINE, UiTokens.STROKE_DEFAULT).with_margins(5.0, 1.0, 5.0, 1.0))
	_gain_label.add_theme_color_override(&"font_color", UiTokens.COLOR_PRIMARY if hit else UiTokens.COLOR_SECONDARY)
	_gain_label.text = ("♥ +%d" % n) if n >= 0 else ("−%d" % -n)

## Kitchen/Cell: DEFAULT keeps the plain cell (status label); the other
## kitchen states draw the main's marks and their own labels.
func _refresh_kitchen(_s: State, empty: bool) -> void:
	var k := KitchenState.DEFAULT if empty else kitchen_state
	var unknown := k in [KitchenState.HIDDEN, KitchenState.CLUED, KitchenState.LOCKED]
	_surface.modulate.a = UiTokens.OPACITY_KITCHEN_EMPTY if empty else 1.0
	var in_pot := k == KitchenState.IN_POT
	if in_pot: _surface.add_theme_stylebox_override(&"panel", _cell_box(State.SELECTED, UiTokens.RADIUS_INVENTORY_CELL))
	_icon.visible = icon != null and not empty and not unknown
	var raised := k in [KitchenState.IN_POT, KitchenState.NOT_FOR_COOKING]
	var top := _KITCHEN_RAISED_ICON_TOP if raised else _KITCHEN_ICON_TOP
	_icon.offset_top = top
	_icon.offset_bottom = top + UiTokens.SIZE_INVENTORY_ICON
	_icon.modulate.a = _KITCHEN_NFC_ALPHA if k == KitchenState.NOT_FOR_COOKING else (_KITCHEN_TASTED_ALPHA if k == KitchenState.TASTED else 1.0)
	_silhouette.visible = unknown
	_family.visible = unknown
	_glow.visible = might_have and not empty
	_star.visible = k == KitchenState.MASTERED
	_tag.visible = k == KitchenState.LOCKED
	_rack_tag.visible = rack and not empty and k in [KitchenState.DEFAULT, KitchenState.IN_POT]
	_tag_label.text = status if status != "" else "Lv4"
	_chip.visible = k == KitchenState.TASTED
	_pill.visible = _pill.visible and k in [KitchenState.DEFAULT, KitchenState.HIDDEN, KitchenState.CLUED,
		KitchenState.LOCKED, KitchenState.TASTED, KitchenState.IN_POT]   # the star has the bottom right on a mastered page
	match k:
		KitchenState.IN_POT, KitchenState.NOT_FOR_COOKING:
			var band := _KITCHEN_IN_POT_LABEL if in_pot else _KITCHEN_NFC_LABEL
			_status.visible = not in_pot or quantity == ""
			_status.offset_top = band.x
			_status.offset_bottom = band.x + band.y
			_status.self_modulate.a = 0.0   # these two labels sit on the cell without the label plate
			_name.text = "In pot" if in_pot else "Not for\ncooking"
		_:
			_status.offset_top = _KITCHEN_LABEL_TOP
			_status.offset_bottom = _KITCHEN_LABEL_TOP + _KITCHEN_LABEL_H
			_status.self_modulate.a = 1.0
			_status.visible = status != "" and not empty and k in [KitchenState.DEFAULT, KitchenState.MASTERED]
			_name.text = status
	_name.offset_bottom = _status.offset_bottom - _status.offset_top if k == KitchenState.NOT_FOR_COOKING else UiTokens.SIZE_QTY_PILL_H

## InventoryCell / Kitchen Cell / GearSlot surface: hairline border, 1.5 primary when selected, dashed when empty;
## a lifted InventoryCell keeps the default look under the QuickSlot lift shadow (1641:34159).
func _cell_box(s: State, radius: float) -> UiStyleBox:
	if s == State.LIFTED:
		var lifted := UiStyleBox.make(UiTokens.COLOR_SURFACE, radius, UiTokens.COLOR_BORDER, UiTokens.STROKE_CELL_HAIRLINE)
		lifted.shadow_color = UiTokens.COLOR_LIFT_SHADOW
		lifted.shadow_size = UiTokens.SIZE_LIFT_SHADOW_RADIUS
		lifted.shadow_offset = Vector2(0.0, UiTokens.SIZE_LIFT_SHADOW_OFFSET_Y)
		return lifted
	if s == State.SELECTED:
		return UiStyleBox.make(UiTokens.COLOR_SURFACE, radius, UiTokens.COLOR_PRIMARY, UiTokens.STROKE_SELECTED_CELL)
	if s == State.EMPTY:
		var bg := UiTokens.COLOR_SURFACE
		if density == Density.INVENTORY: bg = UiKit.alpha(UiTokens.COLOR_SURFACE, UiTokens.OPACITY_EMPTY_CELL)
		var dash: Array = UiTokens.DASH_KITCHEN if density == Density.KITCHEN else UiTokens.DASH_INVENTORY
		return _dashed(UiStyleBox.make(bg, radius, UiTokens.COLOR_BORDER, UiTokens.STROKE_CELL_HAIRLINE), dash)
	return UiStyleBox.make(UiTokens.COLOR_SURFACE, radius, UiTokens.COLOR_BORDER, UiTokens.STROKE_CELL_HAIRLINE)

static func _dashed(b: UiStyleBox, pattern: Array) -> UiStyleBox:
	b.dashed = true
	b.dash = pattern[0]
	b.gap = pattern[1]
	return b

func _refresh_quick(s: State) -> void:
	var rest := UiTokens.SIZE_QUICK_SLOT_H - UiTokens.SIZE_QUICK_SLOT_SURFACE_H
	var top := rest
	if s == State.SELECTED: top = rest - UiTokens.SIZE_QUICK_SLOT_LIFT
	elif s == State.LIFTED: top = rest - UiTokens.SIZE_QUICK_SLOT_LIFT_DRAG
	_surface.offset_top = top
	_surface.offset_bottom = top + UiTokens.SIZE_QUICK_SLOT_SURFACE_H
	var fill := UiTokens.COLOR_PIN_WARM if pinned else UiTokens.COLOR_SURFACE
	var box: UiStyleBox
	match s:
		State.SELECTED, State.LIFTED:
			box = UiStyleBox.make(fill, UiTokens.RADIUS_CELL, UiTokens.COLOR_PRIMARY, UiTokens.STROKE_SELECTED)
			if s == State.LIFTED:
				box.shadow_color = UiTokens.COLOR_LIFT_SHADOW
				box.shadow_size = UiTokens.SIZE_LIFT_SHADOW_RADIUS
				box.shadow_offset = Vector2(0.0, UiTokens.SIZE_LIFT_SHADOW_OFFSET_Y)
		State.EMPTY, State.GHOST:
			box = _dashed(UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CELL, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT), UiTokens.DASH_QUICK)
		State.DROP_TARGET:
			box = _dashed(UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, UiTokens.RADIUS_CELL, UiTokens.COLOR_PRIMARY, UiTokens.STROKE_SELECTED), UiTokens.DASH_DROP_TARGET)
		_:
			box = UiStyleBox.make(fill, UiTokens.RADIUS_CELL, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	_surface.add_theme_stylebox_override(&"panel", box)
	var empty := s == State.EMPTY
	var name_top := float(UiTokens.SIZE_QUICK_SLOT_ICON) if _icon.visible else 0.0
	_name.offset_top = name_top
	_name.offset_bottom = name_top + _QUICK_NAME_H
	_qty.offset_top = name_top + _QUICK_NAME_H
	_qty.offset_bottom = name_top + _QUICK_NAME_H + _QUICK_QTY_H
	_name.text = quick_name(title)
	_name.theme_type_variation = quick_name_style(_name.text)
	_name.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY if _cjk(_name.text) else TextServer.AUTOWRAP_WORD
	_name.visible = title != "" and not empty
	_qty.text = quantity
	var ghost := s == State.GHOST
	_qty.visible = quantity != "" and not empty and not ghost
	# The ghost's "Icon · dimmed" is the same 35 % as the ×0 icon (no separate token yet).
	_icon.modulate.a = UiTokens.OPACITY_ZERO_ICON if s in [State.ZERO, State.GHOST] else 1.0
	_name.add_theme_color_override(&"font_color", UiTokens.COLOR_SECONDARY if ghost else UiTokens.COLOR_TEXT)
	_qty.add_theme_color_override(&"font_color", UiTokens.COLOR_SECONDARY if s == State.ZERO else UiTokens.COLOR_TEXT)
	var show_pin := pinned and not empty and not ghost
	_strip.visible = show_pin
	_badge.visible = show_pin
	# The new ring sits inside the outline too: green outside, cyan inside when both show (1663:101150).
	var inset := 0.0 if box.border_color == UiTokens.COLOR_BORDER else float(box.border_width)
	for side in [&"offset_left", &"offset_top"]: _new_ring.set(side, inset)
	for side in [&"offset_right", &"offset_bottom"]: _new_ring.set(side, -inset)
	# The amber strip sits inside the outline, so it moves down with the 2 px selected stroke (LOCK-05).
	var w := UiTokens.SIZE_PIN_STRIP_W
	_place(_strip, 0.5, -w * 0.5, box.border_width, w, UiTokens.SIZE_PIN_STRIP_H)
