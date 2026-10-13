class_name P0FishDex
extends UiDrawer
## FISH-6 Fish-dex (SGODOT-233; 482:171 R1, 不知火舞 / 安其拉 2026-10-08). In the drawer, top to bottom:
##   heading     `Fish-dex` and Close (Compact/Navigation)
##   (no tab row in P0: Fish-dex is the only page until a read-only Cookbook exists; Crop-dex is not P0 —
##   不知火舞 233 walkthrough)
##   milestone   on surfaceRaised: NeedTile M count `Kinds 3/8` (LOCK-10) beside the next Fish-dex reward
##               (`Next at 10 kinds` / `+30 Energy`) when this season can reach it, else the rod's reach only
##   sections    one per rarity: its name, then rows of six fish cells — InventoryCell 52 over the name (9 Bold,
##               secondary). Caught: the fish and `×N`; not caught: UNCOLLECTED (1405:92952, the silhouette at
##               35 %). A fish caught since the dex was last opened rings once in color/new (1699:102396).
## A cell tap emits cell_pressed; the P0 UI opens the gate card for a silhouette held back by level or rod (q(57)),
## else the fish card. Everything comes from the server view (dex_data is pure and tested).
## P1 (§6.9.1–6.9.2, 不知火舞 on 283, q row by 李白): from Fishing Lv8 a silhouette says where to go under its name
## (`River · night · Lv9`); the next reward names its coins too (`+30 Energy · +100 coins`); `Fish-dex complete` (20
## kinds) puts a small badge right of the heading.

signal cell_pressed(fish_id: String)
signal close_pressed

const HEIGHT := 532.0        # 482:171: the drawer from y 268 of 800
const COLS := 6
const _GAP := 4.0            # Fish-dex content: 4 between rows, cells 4 apart
const _NAME_GAP := 2.0       # Fish cell: the name 2 under the cell
const _NAME_H := 23.0        # two lines of 9 Bold
const _HEADING_H := 28.0
const _MILESTONE_H := 77.0   # 安其拉 1699:102375: 40 → 77 with the NeedTile M
const _MILESTONE_PAD := Vector2(8.0, 4.0)
const _MILESTONE_TEXT_X := 100.0
const _SILHOUETTE := "fish_unknown"
const _BADGE := 22.0   # the Fish-dex badge right of the heading (283 FISH-6-COMPLETE)
const _BADGE_GAP := 6.0
## From this Fishing level a silhouette says where to go (§6.9.1 路标; 不知火舞 on 283).
const SIGNPOST_LEVEL := 8
## Only a fish that bites at one time alone says it: the others are only likelier then (不知火舞 on 283).
const _ONLY_AT := {"night_only": "night", "dawn_dusk_only": "dawn & dusk"}
const FishWorld := preload("res://modules/p0/p0_fish_world.gd")

var cells := {}   # fish id -> UiItemCell
var _fresh: Array = []

## `fresh`: fish caught since the dex was last opened; they ring once after the drawer is up.
func _init(view: Dictionary = {}, fresh: Array = []) -> void:
	super(HEIGHT)
	_fresh = fresh
	var d := dex_data(view)
	# Collection heading (482:171): 28 high; Close's 44 touch row overhangs it by 8 above and below.
	var heading := Control.new()
	heading.custom_minimum_size.y = _HEADING_H
	var title := UiKit.label("Fish-dex", UiTokens.STYLE_C14_XB)
	title.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(title)
	if str(d.badge) != "":   # Fish-dex complete: its badge right of the heading (283 FISH-6-COMPLETE, 安其拉's mark)
		var badge := TextureRect.new()
		badge.name = "DexBadge"
		badge.texture = badge_icon()
		badge.tooltip_text = str(d.badge)
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.custom_minimum_size = Vector2.ONE * _BADGE
		badge.size = badge.custom_minimum_size
		badge.position = Vector2(title.get_minimum_size().x + _BADGE_GAP, (_HEADING_H - _BADGE) * 0.5)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heading.add_child(badge)
	var close := UiNavButton.new("Close", true)
	close.chevron = false   # Compact/Navigation `Close`: nowhere to go, no ›
	close.pressed.connect(func(): close_pressed.emit())
	heading.add_child(close)
	close.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	close.offset_top = (_HEADING_H - UiTokens.SIZE_TOUCH) * 0.5
	close.offset_bottom = -close.offset_top
	close.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	body.add_child(heading)
	body.add_child(_spacer(_GAP))
	body.add_child(_milestone(d))
	var scroll := TouchScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", int(_GAP))
	scroll.add_child(col)
	for sec in d.sections:
		col.add_child(UiKit.label(str(sec.name), UiTokens.STYLE_C10_XB))
		var grid := GridContainer.new()
		grid.columns = COLS
		grid.add_theme_constant_override(&"h_separation", int(_GAP))
		grid.add_theme_constant_override(&"v_separation", int(_GAP))
		for f in sec.fish: grid.add_child(_fish_cell(f))
		col.add_child(grid)
	body.add_child(_spacer(_GAP))
	body.add_child(scroll)

func _ready() -> void:
	super()
	if _fresh.is_empty(): return
	# After the slide-up, the newly caught fish ring once (MOTION_NEW_UNLOCK_FLASH_MS).
	get_tree().create_timer(UiKit.secs(UiTokens.MOTION_DRAWER_MS) if animate else 0.0).timeout.connect(func():
		for id in _fresh:
			if cells.has(id) and is_instance_valid(cells[id]): (cells[id] as UiItemCell).flash())

## What the dex shows, from the view (pure): {got, total, next: [line, reward] , sections: [{name, fish: [{id, name,
## caught, icon}]}]}. Sections follow rarity (Common → Legendary) and skip a rarity with no fish this season.
static func dex_data(view: Dictionary) -> Dictionary:
	var dex: Array = view.get("fishing", {}).get("dex", [])
	var got := dex.filter(func(f): return int(f.get("caught", 0)) > 0).size()
	var signposts := int(view.get("skills", {}).get("fishing", {}).get("level", 1)) >= SIGNPOST_LEVEL
	var sections := []
	for r in [1, 2, 3, 4]:
		var fish := []
		for f in dex:
			if int(f.get("rarity", 1)) != r: continue
			var n := int(f.get("caught", 0))
			fish.append({id = str(f.id), name = P0Logic.item_name(view, str(f.id)), caught = n,
				icon = str(f.id) if n > 0 else _SILHOUETTE,
				hint = signpost(FishWorld._fish(str(f.id))) if signposts and n <= 0 else ""})
		if not fish.is_empty(): sections.append({name = P0Logic.rarity_name(view, r), fish = fish})
	return {got = got, total = dex.size(), next = _next_line(view, got, dex.size()), sections = sections,
		badge = badge_for(got)}

## Where an uncaught fish is (from Lv8): its first water, the one time it bites at if it bites at one alone, its level —
## `River · night · Lv9`, `Pond · Lv5`; no weather (a day's, and the Bite Board's to say). "" for an unknown fish.
static func signpost(f: Dictionary) -> String:
	if f.is_empty(): return ""
	var parts := PackedStringArray()
	var where: Array = f.get("where", [])
	if not where.is_empty(): parts.append(str(where[0]).capitalize())
	var t = f.get("time", null)
	if t is String and _ONLY_AT.has(t): parts.append(str(_ONLY_AT[t]))
	parts.append("Lv%d" % int(f.get("level", 1)))
	return " · ".join(parts)

## The badge a reached Fish-dex milestone gives (content fishing.dex_milestones: `Fish-dex complete` at 20), else "".
static func badge_for(got: int) -> String:
	var badge := ""
	for m in P0Logic.content().get("fishing", {}).get("dex_milestones", []):
		if got >= int(m.get("kinds", 0)) and str(m.get("badge", "")) != "": badge = str(m.badge)
	return badge

## The Fish-dex badge (安其拉's mark, 283 badge_fishdex): the heading's, the profile's Fish tile's, the complete banner's.
static func badge_icon() -> Texture2D: return GameUi.icon("i-badge-fishdex")

## What the whole Fish-dex gave (the milestone row once complete, 283 FISH-6-COMPLETE): `+50 Energy · +300 coins · Badge`.
static func complete_gifts() -> String:
	var gifts := PackedStringArray()
	for m in P0Logic.content().get("fishing", {}).get("dex_milestones", []):
		if str(m.get("badge", "")) == "": continue
		var kinds := int(m.get("kinds", 0))
		for r in P0Logic.content().get("rewards", {}).get("fishdex", []):
			if int(r[0]) == kinds and int(r[1]) > 0: gifts.append("+%d Energy" % int(r[1]))
		if int(m.get("coins", 0)) > 0: gifts.append("+%d coins" % int(m.coins))
		gifts.append("Badge")
	return " · ".join(gifts)

## A Fish-dex milestone's moment (§6.9.2; 不知火舞 on 283), {} for another id.
##   10 kinds  a RewardMoment Milestone {event, item_name, icon, strip}: `Fish-dex 10/20` · the kind that made it ·
##             `+30 Energy · +100 coins`
##   20 kinds  a full MomentBanner {banner, kind, icon, title, subtitle, rewards, seconds} (283 DEX-COMPLETE): the badge,
##             `Fish-dex complete` · `20/20`, pills `+50 Energy` (bolt) `+300 coins` (coin) `Badge` (the badge), ≤ 3 s, no button
static func milestone_card(view: Dictionary, id: String, fish: String, energy: int, coins: int, badge: String) -> Dictionary:
	if not id.begins_with("fishdex_"): return {}
	var n := int(id.trim_prefix("fishdex_"))
	var total: int = (view.get("fishing", {}).get("dex", []) as Array).size()
	if badge != "":
		var pills: Array = []
		if energy > 0: pills.append({text = "+%d Energy" % energy, tone = UiFloatText.Tone.ENERGY_GAIN, icon = P0Logic.icon("energy")})
		if coins > 0: pills.append({text = "+%d coins" % coins, tone = UiFloatText.Tone.COINS, icon = P0Logic.icon("coin")})
		pills.append({text = "Badge", tone = UiFloatText.Tone.ITEM, icon = badge_icon()})
		return {banner = true, kind = "complete", icon = badge_icon(), title = badge, subtitle = "%d/%d" % [n, total], rewards = pills,
			seconds = 3.0}
	var gifts := PackedStringArray()
	if energy > 0: gifts.append("+%d Energy" % energy)
	if coins > 0: gifts.append("+%d coins" % coins)
	return {event = "Fish-dex %d/%d" % [n, total], item_name = P0Logic.item_name(view, fish) if fish != "" else "",
		icon = fish if fish != "" else "fish_crucian", strip = " · ".join(gifts)}

## A milestone's coins (content fishing.dex_milestones, P1), 0 when none.
static func _milestone_coins(kinds: int) -> int:
	for m in P0Logic.content().get("fishing", {}).get("dex_milestones", []):
		if int(m.get("kinds", 0)) == kinds: return int(m.get("coins", 0))
	return 0

## The next Fish-dex reward (content rewards.fishdex [[kinds, Energy]]) when this season's fish can reach it;
## otherwise only the rod's reach, which is what holds the rest back (P0's eight fish never reach 10 kinds; no
## "N more to find", the NeedTile already says it — 不知火舞 233 walkthrough).
static func _next_line(view: Dictionary, got: int, total: int) -> Array:
	if total > 0 and got >= total and badge_for(got) != "": return [badge_for(got), complete_gifts()]   # all found: the badge and what it gave
	for m in P0Logic.content().get("rewards", {}).get("fishdex", []):
		if int(m[0]) > got and int(m[0]) <= total:
			var coins := _milestone_coins(int(m[0]))   # P1: the coins with it (§6.9.2)
			return ["Next at %d kinds" % int(m[0]), "+%d Energy" % int(m[1]) + (" · +%d coins" % coins if coins > 0 else "")]
	var f: Dictionary = view.get("fishing", {})
	return ["%s lands up to %s fish" % [str(f.get("rod", "Starter Rod")), P0Logic.rarity_name(view, int(f.get("rod_reach", 2)))], ""]

func _milestone(d: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size.y = _MILESTONE_H
	card.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, UiTokens.RADIUS_INVENTORY_CELL)
		.with_margins(_MILESTONE_PAD.x, _MILESTONE_PAD.y, _MILESTONE_PAD.x, _MILESTONE_PAD.y))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 0)
	card.add_child(row)
	var tile := UiNeedTile.new("Kinds", int(d.got), maxi(1, int(d.total)), UiNeedTile.Size.M, P0Logic.icon("fish_crucian"), true)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tile)
	row.add_child(_spacer(0.0, _MILESTONE_TEXT_X - _MILESTONE_PAD.x - tile.get_combined_minimum_size().x))
	var text := VBoxContainer.new()
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override(&"separation", 5)
	text.add_child(UiKit.label(str(d.next[0]), UiTokens.STYLE_C11_XB))
	var reward := UiKit.label(str(d.next[1]), UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	reward.visible = reward.text != ""
	text.add_child(reward)
	row.add_child(text)
	return card

func _fish_cell(f: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", int(_NAME_GAP))
	var cell := UiItemCell.new(UiItemCell.Density.INVENTORY)
	cell.icon = P0Logic.icon(str(f.icon))
	if int(f.caught) > 0:
		cell.quantity = "×%d" % int(f.caught)
	else:
		cell.state = UiItemCell.State.UNCOLLECTED
	var id := str(f.id)
	cell.tapped.connect(func(): cell_pressed.emit(id))
	cells[id] = cell
	box.add_child(cell)
	var name := UiKit.label(str(f.name), UiTokens.STYLE_C9_B, UiTokens.COLOR_SECONDARY)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.max_lines_visible = 2
	name.custom_minimum_size = Vector2(UiTokens.SIZE_INVENTORY_CELL, _NAME_H)
	box.add_child(name)
	if str(f.get("hint", "")) != "":   # Lv8: where to go, under the silhouette's name (安其拉's frame to come)
		var hint := UiKit.label(str(f.hint), UiTokens.STYLE_C9_B, UiTokens.COLOR_MUTED)
		hint.name = "Signpost"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.max_lines_visible = 3   # `Coast · dawn & dusk · Lv1` takes three in a 52 cell; never cut
		hint.custom_minimum_size.x = UiTokens.SIZE_INVENTORY_CELL
		box.add_child(hint)
	return box

static func _spacer(h: float, w := 0.0) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(w, h)
	return c
