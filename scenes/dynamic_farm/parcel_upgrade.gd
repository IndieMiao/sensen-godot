extends UiDrawer
## Scott's farm upgrade sheet (C-152): the main farm's HOME-1 (p0_home_panel.gd, Figma 482:152) rebuilt from the same
## kit pieces for the parcel's own save; the P0 sheet is not touched. Top to bottom: `Farm Lv1 → Lv2` · Needs (NEED-TILEs:
## each material the next level takes, then Coins) · What changes (Max Energy, and Wells on a level that adds one) · the
## Upgrade key with the first gap on it (LOCK-10: `Need 2 more Timber`, materials before coins as the server refuses) ·
## Close. At the top level: `Farm Lv5`, `Highest level for now`, no key.
## Numbers are the rules' (`farm_levels`, `energy.per_level`, assets/farm/data/dynamic_farm.json); the key only reports
## (`upgrade_requested`), the town sends `upgrade_farm`.

signal upgrade_requested

const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const ParcelItems = preload("res://modules/dynamic_farm/parcel_items.gd")
const HEIGHT := 440.0
const TOP_HEIGHT := 200.0
const WELL := "well"
## Player-visible copy after P0's HOME-1, as PM finalised it on SEN-C-152#29 (C-45): no footer line under the key.
const COPY := {"title": "Farm Lv%d → Lv%d", "top": "Farm Lv%d", "top_line": "Highest level for now", "needs": "Needs",
	"changes": "What changes", "energy": "Max Energy %d", "wells": "Wells %d", "now": "now %d", "upgrade": "Upgrade",
	"short": "Need %d more %s", "coins": "Need %d more coins", "close": "Close"}

var farm := {}
var title: Label
var subtitle: Label
var needs: VBoxContainer
var changes: VBoxContainer
var button: UiCommandButton
var _tiles: HFlowContainer
var _rows: VBoxContainer

func _init(farm_: Dictionary) -> void:
	super(HEIGHT)
	pad = 16.0
	title = UiKit.label("", UiTokens.STYLE_C14_XB)
	title.name = "Title"
	body.add_child(title)
	subtitle = UiKit.label(COPY.top_line, UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
	body.add_child(subtitle)
	needs = VBoxContainer.new()
	needs.name = "Needs"
	needs.add_theme_constant_override(&"separation", 10)
	_gap(needs, 4.0)
	needs.add_child(UiKit.label(COPY.needs, UiTokens.STYLE_C12_XB))
	_tiles = UiNeedTile.group([])
	needs.add_child(_tiles)
	body.add_child(needs)
	changes = VBoxContainer.new()
	changes.name = "Changes"
	changes.add_theme_constant_override(&"separation", 6)
	_gap(changes, 12.0)
	changes.add_child(UiKit.label(COPY.changes, UiTokens.STYLE_C12_XB))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override(&"separation", 6)
	changes.add_child(_rows)
	body.add_child(changes)
	var room := Control.new()
	room.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(room)
	button = UiCommandButton.new(COPY.upgrade)
	button.name = "Upgrade"
	button.sends = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.activated.connect(func(): upgrade_requested.emit())
	body.add_child(button)
	_gap(body, 6.0)
	var close := UiDismissButton.new(COPY.close)
	close.name = "Close"
	close.pressed.connect(func(): close_requested.emit())
	body.add_child(close)
	refresh(farm_)

## A toast sits over the key (q(16)), or at the foot at the top level.
func action_area() -> Control: return button if button != null and button.is_visible_in_tree() else null

## What the sheet shows for a farm (pure; tests read it): {title, top, tiles: [{id, name, have, need}],
## changes: [{icon, text, note}], reason}. `reason` is the first gap, "" when the upgrade can go.
static func model(rules: Dictionary, farm_: Dictionary) -> Dictionary:
	var level := ParcelFarm.farm_level(farm_)
	var next := ParcelFarm.next_level(rules, level)
	if next.is_empty(): return {"title": COPY.top % level, "top": true, "tiles": [], "changes": [], "reason": ""}
	var bag: Dictionary = farm_.get("bag", {})
	var tiles: Array = []
	for item: String in next.items:
		tiles.append({"id": item, "name": ParcelItems.name_of(item), "have": int(bag.get(item, 0)), "need": int(next.items[item])})
	tiles.append({"id": "coins", "name": "Coins", "have": int(farm_.get("coins", 0)), "need": int(next.coins)})
	var reason := ""
	for t: Dictionary in tiles:
		if int(t.have) >= int(t.need): continue
		var short := int(t.need) - int(t.have)
		reason = COPY.coins % short if t.id == "coins" else COPY.short % [short, str(t.name)]
		break
	var probe := farm_.duplicate()
	probe.level = int(next.level)
	var out_changes: Array = [{"icon": "energy", "text": COPY.energy % ParcelFarm.max_energy(rules, probe),
		"note": COPY.now % ParcelFarm.max_energy(rules, farm_)}]
	if rules.buildings.has(WELL):
		var wells_now := ParcelFarm.building_max(rules, WELL, level)
		var wells_next := ParcelFarm.building_max(rules, WELL, int(next.level))
		if wells_next > wells_now:
			out_changes.append({"icon": "water", "text": COPY.wells % wells_next, "note": COPY.now % wells_now})
	return {"title": COPY.title % [level, int(next.level)], "top": false, "tiles": tiles, "changes": out_changes, "reason": reason}

## New farm from the store: the tiles, the rows and the key follow it.
func refresh(farm_: Dictionary) -> void:
	farm = farm_
	var m := model(ParcelFarm.rules(), farm)
	title.text = str(m.title)
	subtitle.visible = bool(m.top)
	needs.visible = not bool(m.top)
	changes.visible = not bool(m.top)
	button.visible = not bool(m.top)
	height = TOP_HEIGHT if bool(m.top) else HEIGHT
	for c in _tiles.get_children():
		_tiles.remove_child(c)
		c.queue_free()
	for t: Dictionary in m.tiles:
		var icon := UiArt.COIN if t.id == "coins" else ParcelItems.icon_of(str(t.id))
		var tile := UiNeedTile.new(str(t.name), int(t.have), int(t.need), UiNeedTile.Size.L, icon)
		tile.name = "Need_%s" % t.id
		_tiles.add_child(tile)
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for c: Dictionary in m.changes: _rows.add_child(_change_row(c))
	button.reason = str(m.reason)

## One What changes row, as HOME-1's: icon 16 · what (fills) · the value it replaces.
static func _change_row(c: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.custom_minimum_size = Vector2(0, 25)
	var icon := UiKit.icon(P0Logic.icon(str(c.icon)), 16)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var text := UiKit.label(str(c.text), UiTokens.STYLE_C12_XB)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(text)
	var note := UiKit.label(str(c.note), UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY)
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(note)
	return row

func _gap(parent: Control, h: float) -> void:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size.y = h
	parent.add_child(c)
