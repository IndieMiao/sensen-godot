extends UiDrawer
## Scott's farm upgrade sheet (C-152): the main farm's HOME-1 (p0_home_panel.gd, Figma 482:152) rebuilt from the same
## kit pieces for the parcel's own save; the P0 sheet is not touched. Top to bottom: `Farm Lv1 → Lv2` · Needs (NEED-TILEs:
## each material the next level takes, then Coins) · What changes (Max Energy, and Wells on a level that adds one) · the
## Upgrade key with the first gap on it (LOCK-10: `Need 2 more Timber`, materials before coins as the server refuses) ·
## Close. At the top level: `Farm Lv5`, `Highest level for now`, no key.
## Numbers are the rules' (`farm_levels`, `energy.per_level`, assets/farm/data/dynamic_farm.json); the key only reports
## (`upgrade_requested`), the town sends `upgrade_farm`.
## C-186 (C-185 §3.4 / MS-17): while an upgrade is out the sheet holds its level (`hold`); on success hand_in() plays the
## three needs going in, the town shows the level-up card, and release() fades the next level in (120). A tap on the grey
## key shakes it and flashes the first short need's ring (MS-02); its toast is the town's, only when it differs from the key.

signal upgrade_requested

const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const ParcelItems = preload("res://modules/dynamic_farm/parcel_items.gd")
const HEIGHT := 440.0
const TOP_HEIGHT := 200.0
const WELL := "well"
## Player-visible copy after P0's HOME-1, as PM finalised it on SEN-C-152#29 (C-45): no footer line under the key.
const COPY := {"title": "Farm Lv%d → Lv%d", "top": "Farm Lv%d", "top_line": "Highest level for now", "needs": "Needs",
	"changes": "What changes", "energy": "Max Energy %d", "wells": "Wells %d", "now": "now %d", "upgrade": "Upgrade",
	"short": "Need %d more %s", "coins": "Need %d more coins", "close": "Close",
	# C-186 level-up card rows (C-185 fig-06: `Max Energy  200 → 210`, `Wells  1 → 2`), the gift row `+1 Well Blueprint`.
	"energy_label": "Max Energy", "wells_label": "Wells", "change": "%d → %d", "gift": "+%d %s"}

var farm := {}
var title: Label
var subtitle: Label
var needs: VBoxContainer
var changes: VBoxContainer
var button: UiCommandButton
var _tiles: HFlowContainer
var _rows: VBoxContainer
## C-186: an upgrade is out; refresh() keeps the farm but leaves the level drawn until release().
var hold := false

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
	button.unavailable_pressed.connect(func(_r: String): refuse())
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
	var energy_now := ParcelFarm.max_energy(rules, farm_)
	var energy_next := ParcelFarm.max_energy(rules, probe)
	var out_changes: Array = [{"icon": "energy", "text": COPY.energy % energy_next, "note": COPY.now % energy_now,
		"label": COPY.energy_label, "from": energy_now, "to": energy_next}]
	if rules.buildings.has(WELL):
		var wells_now := ParcelFarm.building_max(rules, WELL, level)
		var wells_next := ParcelFarm.building_max(rules, WELL, int(next.level))
		if wells_next > wells_now:
			out_changes.append({"icon": "water", "text": COPY.wells % wells_next, "note": COPY.now % wells_now,
				"label": COPY.wells_label, "from": wells_now, "to": wells_next})
	return {"title": COPY.title % [level, int(next.level)], "top": false, "tiles": tiles, "changes": out_changes, "reason": reason}

## New farm from the store: the tiles, the rows and the key follow it.
func refresh(farm_: Dictionary) -> void:
	farm = farm_
	if hold: return
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

## The level-up card's rows for an upgrade from `farm_` (C-185 fig-06): each change `label  from → to` with its icon, then
## the level's gift (`+1 Well Blueprint`, its item icon), from the rules only.
static func level_rows(rules: Dictionary, farm_: Dictionary) -> Array:
	var m := model(rules, farm_)
	var out: Array = []
	for c: Dictionary in m.changes:
		out.append({"icon": P0Logic.icon(str(c.icon)), "label": str(c.get("label", "")),
			"value": COPY.change % [int(c.get("from", 0)), int(c.get("to", 0))]})
	return out

## MS-17: the needs go in left to right, `motion/stagger/reward` (60) apart, each ring and icon shrinking to 0.6 and fading
## (cubic in) within 200; all in ≤ 320. Awaitable; at once when reduced or nothing is drawn.
func hand_in() -> void:
	var tiles: Array = []
	if _tiles != null: tiles = _tiles.get_children()
	if UiMotion.reduced or tiles.is_empty() or not is_inside_tree(): return
	var last: Tween = null
	var i := 0
	for t in tiles:
		var tile := t as Control
		tile.pivot_offset = tile.size * 0.5
		var tw := UiMotion.tween(tile, UiTokens.MOTION_EASING_EXIT)
		tw.tween_interval(UiKit.secs(UiTokens.MOTION_STAGGER_MS_REWARD * mini(i, 2)))
		var ms := minf(UiTokens.MOTION_DURATION_BASE_MS, UiTokens.MOTION_DURATION_EMPHASIS_MS - UiTokens.MOTION_STAGGER_MS_REWARD * mini(i, 2))
		tw.tween_property(tile, ^"scale", Vector2.ONE * UiTokens.MOTION_SCALE_FLY_END, UiKit.secs(ms))
		tw.parallel().tween_property(tile, ^"modulate:a", 0.0, UiKit.secs(ms))
		last = tw
		i += 1
	if last != null: await last.finished

## The upgrade went through and its card closed: the next level, faded in over 120.
func release() -> void:
	hold = false
	refresh(farm)
	if UiMotion.reduced or not is_inside_tree(): return
	body.modulate.a = 0.0
	UiMotion.tween(body, UiTokens.MOTION_EASING_STANDARD).tween_property(body, ^"modulate:a", 1.0, UiKit.secs(UiTokens.MOTION_DURATION_FAST_MS))

## MS-02: the grey key shakes and the first short need's ring flashes `action/danger` (120).
func refuse() -> void:
	UiMotion.shake(button)
	for t in _tiles.get_children():
		var tile := t as UiNeedTile
		if tile == null or tile.state() != UiNeedTile.State.SHORT: continue
		tile.modulate = UiTokens.COLOR_ACTION_DANGER
		var tw := UiMotion.tween(tile, UiTokens.MOTION_EASING_LINEAR)
		tw.tween_interval(UiKit.secs(UiTokens.MOTION_DURATION_FAST_MS))
		tw.tween_callback(func(): tile.modulate = Color.WHITE)
		break

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
