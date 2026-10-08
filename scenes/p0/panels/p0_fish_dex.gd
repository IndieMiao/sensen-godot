class_name P0FishDex
extends UiDrawer
## FISH-6 Fish-dex (SGODOT-233; 482:171 R1, 不知火舞 / 安其拉 2026-10-08). In the drawer, top to bottom:
##   heading     `Fish-dex` and Close (Compact/Navigation)
##   tabs        Compact/Filter: Fish-dex | Cookbook (P0 has no Crop-dex); Cookbook asks the host (tab_pressed)
##   milestone   on surfaceRaised: NeedTile M count `Kinds 3/8` (LOCK-10) and the next Fish-dex reward
##               (`Next at 10 kinds` / `+30 Energy`), or the rod's reach when no reward is reachable this season
##   sections    one per rarity: its name, then rows of six fish cells — InventoryCell 52 over the name (9 Bold,
##               secondary). Caught: the fish and `×N`; not caught: UNCOLLECTED (1405:92952, the silhouette at
##               35 %). A fish caught since the dex was last opened rings once in color/new (1699:102396).
## A cell tap emits cell_pressed; the P0 UI opens the gate card for a silhouette held back by level or rod (q(57)),
## else the fish card. Everything comes from the server view (dex_data is pure and tested).

signal cell_pressed(fish_id: String)
signal tab_pressed(tab: String)
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
	body.add_child(UiFilterChip.row(PackedStringArray(["Fish-dex", "Cookbook"]), 0, func(i: int):
		if i == 1: tab_pressed.emit("cookbook")))
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
	var sections := []
	for r in [1, 2, 3, 4]:
		var fish := []
		for f in dex:
			if int(f.get("rarity", 1)) != r: continue
			var n := int(f.get("caught", 0))
			fish.append({id = str(f.id), name = P0Logic.item_name(view, str(f.id)), caught = n,
				icon = str(f.id) if n > 0 else _SILHOUETTE})
		if not fish.is_empty(): sections.append({name = P0Logic.rarity_name(view, r), fish = fish})
	return {got = got, total = dex.size(), next = _next_line(view, got, dex.size()), sections = sections}

## The next Fish-dex reward (content rewards.fishdex [[kinds, Energy]]) when this season's fish can reach it;
## otherwise the rod's reach, which is what holds the rest back.
static func _next_line(view: Dictionary, got: int, total: int) -> Array:
	for m in P0Logic.content().get("rewards", {}).get("fishdex", []):
		if int(m[0]) > got and int(m[0]) <= total: return ["Next at %d kinds" % int(m[0]), "+%d Energy" % int(m[1])]
	var f: Dictionary = view.get("fishing", {})
	if got >= total and total > 0: return ["All %d kinds caught" % total, ""]
	return ["%d more to find" % (total - got),
		"%s lands up to %s fish" % [str(f.get("rod", "Starter Rod")), P0Logic.rarity_name(view, int(f.get("rod_reach", 2)))]]

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
	return box

static func _spacer(h: float, w := 0.0) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(w, h)
	return c
