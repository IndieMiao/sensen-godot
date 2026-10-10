class_name P0SkillsDrawer
extends UiDrawer
## SKILL-1 Skills (SGODOT-233; 482:167 rows, §4.8.4 / §4.8.7 P0 note; 不知火舞 233, 10-08). In a drawer:
##   heading       `Skills` and Close
##   a row a track Farming / Fishing / Cooking: the name (12 ExtraBold), `Level 4` (10 Bold), `Next: Corn, Cabbage and
##                 Sow Again` (what this build's content opens next, else `Next: Lv5 · 88 XP to go`; `Top level` at the cap), the
##                 XP NeedTile M (count, `XP 412/500`) and `View milestones ›`, which unfolds the track's levels with
##                 something new this season here: reached ✓, the next one `N XP to go`, the rest a lock
##   First times   NeedTile M counts: Crops n/8 · Fish n/7 · Dishes n/14 (this season's denominators)
## No Today +XP and no Full XP now in P0. Display only: the rows guide nowhere (LOCK-08).

signal close_pressed

const HEIGHT := 600.0
const TRACKS := ["farming", "fishing", "cooking"]
const _ICONS := {"farming": "hoe", "fishing": "rod", "cooking": "pot"}
const _HEADING_H := 28.0
const _ROW_GAP := 3.0        # Compact/Information row: lines 3 apart
const _TRACK_GAP := 8.0      # Legacy sheet content: rows 8 apart
const _MILESTONE_GAP := 6.0
const _MARK := 14.0
const CHECK := preload("res://assets/ui/kit_icons/check.svg")
const LOCK := preload("res://assets/ui/kit_icons/lock_closed.svg")

var milestones := {}   # track -> VBoxContainer (the unfolding list)
var toggles := {}      # track -> UiNavButton

func _init(view: Dictionary = {}) -> void:
	super(HEIGHT)
	var heading := Control.new()
	heading.custom_minimum_size.y = _HEADING_H
	var title := UiKit.label("Skills", UiTokens.STYLE_C14_XB)
	title.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(title)
	var close := UiNavButton.new("Close", true)
	close.chevron = false
	close.pressed.connect(func(): close_pressed.emit())
	heading.add_child(close)
	close.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	close.offset_top = (_HEADING_H - UiTokens.SIZE_TOUCH) * 0.5
	close.offset_bottom = -close.offset_top
	close.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	body.add_child(heading)
	var scroll := TouchScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", int(_TRACK_GAP))
	scroll.add_child(col)
	var d := skills_data(view)
	for t in d.tracks: col.add_child(_track_row(t))
	col.add_child(UiKit.label("First times", UiTokens.STYLE_C12_XB))
	var tiles: Array = []
	for f in d.firsts:
		var tile := UiNeedTile.new(str(f.name), int(f.have), maxi(1, int(f.need)), UiNeedTile.Size.M, P0Logic.icon(str(f.icon)), true)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tiles.append(tile)
	col.add_child(UiNeedTile.group(tiles))
	body.add_child(scroll)

## What the page shows (pure): {tracks: [{key, name, level, next, xp, need, milestones: [{line, mark, fact}]}],
## firsts: [{name, have, need, icon}]}. mark: "done" / "next" / "locked".
static func skills_data(view: Dictionary) -> Dictionary:
	var tracks: Array = []
	for key in TRACKS:
		var s: Dictionary = view.get("skills", {}).get(key, {})
		var lv := int(s.get("level", 1))
		var xp := int(s.get("xp", 0))
		var th: Array = P0Logic.content().get("skills", {}).get(key, [])
		var top := lv >= th.size()
		var need := xp if top else int(th[lv])
		var next := "Top level"
		if not top:
			var opens := P0Logic.level_unlocks(view, key, lv + 1)
			next = ("Next: " + P0Logic.and_list(opens)) if not opens.is_empty() else "Next: Lv%d · %d XP to go" % [lv + 1, maxi(0, need - xp)]
		var rows: Array = []
		for l in range(2, th.size() + 1):
			var opens := P0Logic.level_unlocks(view, key, l)
			if opens.is_empty(): continue   # only levels with something new this season (§4.8.7)
			var mark := "done" if l <= lv else ("next" if l == lv + 1 else "locked")
			rows.append({line = "Lv%d · %s" % [l, ", ".join(opens)], mark = mark,
				fact = ("%d XP to go" % maxi(0, int(th[l - 1]) - xp)) if mark == "next" else ""})
		tracks.append({key = key, name = key.capitalize(), level = lv, next = next, xp = xp, need = need, milestones = rows})
	var firsts: Array = view.get("firsts", [])
	# Fish first-caught n/20 (李白 on #214, §4.8 / SKILL-1): the whole fish table, Coast's and the regional ones too —
	# collecting them is what travel is for.
	var fish: Array = P0Logic.content().get("fish", [])
	var caught := (view.get("fishing", {}).get("dex", []) as Array).filter(func(f):
		return int(f.get("caught", 0)) > 0 and fish.any(func(c): return str(c.id) == str(f.id))).size()
	var pages: Array = (view.get("cooking", {}).get("cookbook", []) as Array).filter(func(p): return bool(p.get("p0", false)))
	return {tracks = tracks, firsts = [
		{name = "Crops", have = firsts.filter(func(f): return str(f).begins_with("harvest:")).size(),
			need = (P0Logic.content().get("crops", []) as Array).size(), icon = "crop_radish"},
		{name = "Fish", have = caught, need = fish.size(), icon = "fish_crucian"},
		{name = "Dishes", have = pages.filter(func(p): return bool(p.get("cooked", false))).size(),
			need = pages.size() if not pages.is_empty() else (P0Logic.content().get("cooking", {}).get("recipes", []) as Array).size(),
			icon = "dish_grilled_crucian"}]}

func _track_row(t: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", int(_ROW_GAP))
	col.add_child(UiKit.label(str(t.name), UiTokens.STYLE_C12_XB))
	col.add_child(UiKit.label("Level %d" % int(t.level), UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY))
	var next := UiKit.label(str(t.next), UiTokens.STYLE_C11_B)
	next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(next)
	var tile := UiNeedTile.new("XP", int(t.xp), maxi(1, int(t.need)), UiNeedTile.Size.M, P0Logic.icon(str(_ICONS.get(t.key, "xp"))), true)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(tile)
	var list := VBoxContainer.new()
	list.add_theme_constant_override(&"separation", int(_MILESTONE_GAP))
	list.visible = false
	for m in t.milestones: list.add_child(_milestone(m))
	var key := str(t.key)
	if not t.milestones.is_empty():
		var toggle := UiNavButton.new("View milestones", true)
		toggle.pressed.connect(func(): unfold(key, not list.visible))
		col.add_child(toggle)
		toggles[key] = toggle
	col.add_child(list)
	milestones[key] = list
	return col

## Unfolds (or folds) a track's milestones in place.
func unfold(key: String, open: bool) -> void:
	if not milestones.has(key): return
	(milestones[key] as Control).visible = open
	if toggles.has(key):
		(toggles[key] as UiNavButton).label = "Hide milestones" if open else "View milestones"
		(toggles[key] as UiNavButton).chevron = not open

func _milestone(m: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	var mark := UiKit.icon(CHECK if str(m.mark) == "done" else (LOCK if str(m.mark) == "locked" else null), _MARK)
	mark.self_modulate = UiTokens.COLOR_PRIMARY if str(m.mark) == "done" else UiTokens.COLOR_SECONDARY
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	var line := UiKit.label(str(m.line), UiTokens.STYLE_C11_B, UiTokens.COLOR_TEXT if str(m.mark) != "locked" else UiTokens.COLOR_SECONDARY)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(line)
	if str(m.fact) != "": row.add_child(UiKit.label(str(m.fact), UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY))
	return row
