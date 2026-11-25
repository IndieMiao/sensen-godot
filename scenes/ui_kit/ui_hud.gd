class_name UiHud
extends Control
## Two-row HUD (SGODOT-222; Gensen Refactor/HUD 1143:103373, LOCK-06). Stands alone: add it under any
## full-rect Control (P0 world, map); it anchors itself at the top (x 8, y 16 + safe_top, 344 wide). Only the
## chips take touches.
##   Row 1: avatar with the two-colour skill ring (→ Profile) · Energy chip (number, bar, +1 in m:ss / Full /
##          bonus) · optional Buff chip (icon + remaining) · the priest's buffs, each an icon in a countdown ring over
##          its time (q(300), BuffRing below) · coins · bell with the red unread count.
##   Row 2: Today icon (list-checks in a 32 x 24 pill, 44 hit area; a red dot at its top-right when the Today panel
##          has something new to do now, q(107) / SGODOT-271) · location chip `City · Space` with the player's ACTUAL
##          place in the rest of the row (never Map; foreign city adds `· Day Pass 23h`; the space is truncated first).
## Energy colour is never by percentage (user 2026-10-07): Normal / Full / Bonus green bar with an ink number
## (Bonus adds a light-green over-cap segment), Low amber only when Energy is short of the next action,
## Empty red at 0. There is no separate Map / Passport button: the location chip is the way to the map.
## Data in: apply(state) with any of the keys below; P0Logic.hud_state(view, ctx) builds it for P0.

signal avatar_pressed
signal energy_pressed
signal inbox_pressed
signal today_pressed
signal place_pressed

enum Energy { NORMAL, LOW, EMPTY, FULL, BONUS }
enum PlaceKind { HOME, FOREIGN, SECOND_HOME }

const ICON_ENERGY := preload("res://assets/p0/icons/energy.svg")
const ICON_COIN := preload("res://assets/p0/icons/coin.svg")
const ICON_BELL := preload("res://assets/p0/icons/bell.svg")
const ICON_HOME := preload("res://assets/p0/icons/home.svg")
const ICON_FOREIGN := preload("res://assets/p0/icons/showmap.svg")
const ICON_TODAY := preload("res://assets/ui/icons/game/list-checks.svg")
const PORTRAIT := preload("res://assets/ui/kit_images/player_portrait.png")

# Positions inside the HUD main (one main's layout, not shared tokens):
const _ROW1_Y := 1.0              # row 1 controls are 44 high; the 42 Energy chip box sits at y 2
const _ROW1_X := -1.0             # the 44 skill ring starts 1 px left of the HUD box
const _ROW2_Y := 52.0             # row 2 chips (24) at y 52
const _AVATAR_GAP := 2            # ring → Energy chip
const _BUFF_GAP := 5              # Energy chip → Buff chip
const _INBOX_GAP := 7             # coins → bell
const _CHIP_PAD := 8              # chips: left padding
const _CHIP_PAD_END := 6          # chips: right padding before the chevron
const _CAPSULE_PAD := 7           # coins capsule padding, icon gap 4
const _ENERGY_PAD := Vector2(8, 2)   # Figma 8 / 3 with 2 px gaps; Godot line boxes are taller, so 2 / 1 keeps 42
const _ENERGY_GAP := 1
const _ICON_ENERGY := 12
const _ICON_COIN := 13
const _ICON_BELL := 18
const _SKILL_GAP := 4.0           # degrees each skill half stops short of 12 and 6 o'clock
const _ICON_BUFF := 14
# The priest's buffs (q(300) ⑨, 不知火舞's spec v1.1 §3): a 28 circle on the surface colour, its 16 icon inside, a
# 2.5 arc for the time left from 12 o'clock clockwise on NEED-TILE's light track; under it the time in a caption pill
# (16 high, radius 8, 4 in, 1 px border, C10 XB primary) whose top covers the circle's bottom 4 px — 40 high, centred
# in the 44 row. Two side by side, centres 40 apart; the left pill starts _BUFF_GAP after the Energy chip.
const _BUFF_RING := 28.0
const _BUFF_RING_ICON := 16
const _BUFF_RING_STROKE := 2.5
const _BUFF_PITCH := 40.0
const _BUFF_PILL_H := 16.0
const _BUFF_PILL_OVER := 4.0
const _BUFF_PILL_PAD := 4
const _ICON_PLACE := 11
const _ICON_TODAY := 14
const _DOT := 8.0                 # the Today icon's red dot: the unread dot of UiSegmentTab / UiInboxRow
const _DOT_OVER := 2.0            # past the pill's right and top edges by 2, as the bell's badge sits out
const _BADGE_OVER := Vector2(2, 8)   # unread badge: past the bell's right edge by 2, above its top by 8

## Merged state; apply() only replaces the keys it is given.
var data := {
	energy = 0, energy_max = 200, regen = "Full", next_cost = 0,
	skills = {farming = 0.0, fishing = 0.0},
	coins = 0, unread = 0, buff = {}, buffs = [], today_dot = false,
	place = {city = "", space = "", kind = PlaceKind.HOME, day_pass = "", helping = false},
}
var safe_top := 0.0: set = set_safe_top
## Hide the coins / bell corner while a world docks its own close button there (P0 fishing).
var show_balances := true: set = set_show_balances

var _frame: Control
var _ring: _SkillRing
var _energy_chip: _Chip
var _energy_value: Label
var _energy_tween: Tween
var _energy_shown := -1.0
var _energy_track: _Track
var _energy_regen: Label
var _buff: PanelContainer
var _buff_icon: TextureRect
var _buff_left: Label
var _buff_rings: _BuffRings
var _coins: Label
var _balances: HBoxContainer
var _inbox: _Chip
var _badge: PanelContainer
var _badge_count: Label
var _today_chip: _Chip
var _today_dot: Panel
var _row2: HBoxContainer
var _place_chip: _Chip
var _place_icon: TextureRect
var _place_city: Label
var _place_space: Label
var _place_suffix: Label
var _place_names: HBoxContainer

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_bottom = UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.position = Vector2(UiTokens.SIZE_HUD_X, UiTokens.SIZE_HUD_TOP)
	_frame.size = Vector2(UiTokens.SIZE_HUD_W, UiTokens.SIZE_HUD_H)
	add_child(_frame)
	# Row 2 first: its 44 hit areas overlap row 1 by a few px and row 1 should win there.
	_build_row2()
	_build_row1()
	_refresh()

func set_safe_top(v: float) -> void:
	safe_top = v
	if _frame != null:
		_frame.position.y = UiTokens.SIZE_HUD_TOP + v
		offset_bottom = UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + v

func apply(state: Dictionary) -> void:
	if state.has("energy") and int(state.energy) != int(data.energy) and _energy_shown >= 0.0:
		if _energy_tween != null and _energy_tween.is_valid(): _energy_tween.kill()
		_energy_shown = -1.0   # a newer authoritative value supersedes an unfinished count
	for k in state:
		if k == "place" or k == "skills":
			var merged: Dictionary = (data[k] as Dictionary).duplicate()
			merged.merge(state[k], true)
			data[k] = merged
		else:
			data[k] = state[k]
	_refresh()

## q(247): the upgrade's confirmed gain rolls in the existing number, never in a second floating reward.
## State and action availability remain authoritative; only the displayed number interpolates.
func roll_energy_from(from: int) -> void:
	if from >= int(data.energy) or not is_inside_tree(): return
	if _energy_tween != null and _energy_tween.is_valid(): _energy_tween.kill()
	_energy_shown = float(from)
	_refresh()
	_energy_tween = create_tween()
	_energy_tween.tween_method(func(value: float):
		_energy_shown = value
		_energy_value.text = "%d/%d" % [roundi(value), int(data.energy_max)], float(from), float(data.energy),
		UiKit.secs(UiTokens.MOTION_QUICK_BAR_REFILL_MS))   # existing number-roll duration (also used by the table coins)
	_energy_tween.tween_callback(func():
		_energy_shown = -1.0
		_refresh())

func energy_state() -> Energy:
	return energy_state_for(int(data.energy), int(data.energy_max), int(data.next_cost))

## LOCK-06 colour rule: by what the player can do next, never by percentage.
static func energy_state_for(energy: int, energy_max: int, next_cost: int) -> Energy:
	if energy <= 0: return Energy.EMPTY
	if energy > energy_max: return Energy.BONUS
	if next_cost > 0 and energy < next_cost: return Energy.LOW
	if energy >= energy_max: return Energy.FULL
	return Energy.NORMAL

## Start / end angles (degrees, 0 = 3 o'clock, clockwise) of the two skill halves for progress 0..1.
static func skill_arcs(farming: float, fishing: float) -> Dictionary:
	var span := 180.0 - _SKILL_GAP * 2.0
	var f := floorf(clampf(farming, 0.0, 1.0) * 20.0) / 20.0
	var g := floorf(clampf(fishing, 0.0, 1.0) * 20.0) / 20.0
	return {
		farming = Vector2(-90.0 + _SKILL_GAP, -90.0 + _SKILL_GAP + span * f),
		fishing = Vector2(-90.0 - _SKILL_GAP, -90.0 - _SKILL_GAP - span * g),
	}

## The chip's third segment (LOCK-06 v1.9): `Helping` while helping on someone's farm (it wins over a pass),
## else `Day Pass 23h` while a pass runs; none once the pass has run out (its end is told by a D8 banner).
## Helping and the pass are P2 social; P0 never sets them, but the chip keeps room for either.
static func place_tail(place: Dictionary) -> String:
	if bool(place.get("helping", false)): return "Helping"
	if str(place.get("day_pass", "")) != "": return "Day Pass " + str(place.day_pass)
	return ""

## `City · Space`, plus `· Day Pass 23h` when one is running. Arrived-but-not-in-a-space reads
## `Tokyo · Arrived` (the caller passes space "Arrived").
static func place_text(place: Dictionary) -> String:
	var parts := [str(place.get("city", "")), str(place.get("space", ""))]
	var tail := place_tail(place)
	if tail != "": parts.append(tail)
	return " · ".join(parts.filter(func(p): return p != ""))

func set_show_balances(v: bool) -> void:
	show_balances = v
	if _balances == null: return
	_balances.modulate.a = 1.0 if v else 0.0   # keeps its place, so a docked close button can use balances_rect()
	_inbox.mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE

## Placement mode keeps only the first row (P1 q(23), SGODOT-241): Today and the place chip step aside.
func set_row2_shown(on: bool) -> void:
	if _row2 != null: _row2.visible = on

func energy_chip_rect() -> Rect2: return _energy_chip.visual_rect()
func balances_rect() -> Rect2: return _balances.get_global_rect()
## The Today icon's drawn 32 x 24 pill (the TipCard hangs under its bottom edge, as under the old chip's).
func today_chip_rect() -> Rect2: return _today_chip.visual_rect()

## Whether the Today icon shows its red dot.
func today_dot_shown() -> bool: return _today_dot.visible

## Pulses played on the Today icon (tests read it).
var today_pulses := 0

## The Today icon's GuidePulse, once (its focus row changed; the caller decides, P0Ui): Shape=Pill around the drawn
## pill, not its 44 px touch area.
func pulse_today() -> void:
	today_pulses += 1
	var visual := _today_chip.visual_rect()
	UiGuidePulse.play(_today_chip, Rect2(visual.position - _today_chip.global_position, visual.size), UiGuidePulse.Shape.PILL)
func place_chip_rect() -> Rect2: return _place_chip.visual_rect()

# ------------------------------------------------------------------ build

func _build_row1() -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 0)
	row.position = Vector2(_ROW1_X, _ROW1_Y)
	# The 44 bell hit area is wider than its 32 box: let it run past the HUD box so the box lines up.
	row.size = Vector2(UiTokens.SIZE_HUD_W - _ROW1_X + (UiTokens.SIZE_TOUCH - UiTokens.SIZE_INBOX) * 0.5, UiTokens.SIZE_TOUCH)
	_frame.add_child(row)
	var avatar := _Chip.new(0.0, 0.0)
	avatar.custom_minimum_size = Vector2(UiTokens.SIZE_SKILL_RING, UiTokens.SIZE_TOUCH)
	avatar.pressed.connect(func(): avatar_pressed.emit())
	_ring = _SkillRing.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	avatar.add_child(_ring)
	var portrait := UiKit.icon(PORTRAIT, UiTokens.SIZE_HUD_AVATAR)
	var inset := (UiTokens.SIZE_SKILL_RING - UiTokens.SIZE_HUD_AVATAR) * 0.5
	portrait.position = Vector2(inset, inset)
	portrait.size = Vector2(UiTokens.SIZE_HUD_AVATAR, UiTokens.SIZE_HUD_AVATAR)
	_ring.add_child(portrait)
	row.add_child(avatar)
	row.add_child(_gap(_AVATAR_GAP))
	_energy_chip = _Chip.new(UiTokens.RADIUS_HUD_CHIP, UiTokens.SIZE_ENERGY_CHIP_H)
	_energy_chip.custom_minimum_size.x = UiTokens.SIZE_ENERGY_CHIP_W
	_energy_chip.pressed.connect(func(): energy_pressed.emit())
	_energy_chip.body.add_theme_constant_override(&"margin_left", int(_ENERGY_PAD.x))
	_energy_chip.body.add_theme_constant_override(&"margin_top", int(_energy_chip.margin_y() + _ENERGY_PAD.y))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", _ENERGY_GAP)
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_energy_chip.body.add_child(col)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override(&"separation", _ENERGY_GAP)
	var bolt := UiKit.icon(ICON_ENERGY, _ICON_ENERGY)
	bolt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(bolt)
	_energy_value = UiKit.label("", UiTokens.STYLE_C14_XB)
	top.add_child(_energy_value)
	col.add_child(top)
	_energy_track = _Track.new()
	_energy_track.hud = self
	_energy_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_energy_track.custom_minimum_size = Vector2(UiTokens.SIZE_ENERGY_TRACK_W, UiTokens.SIZE_ENERGY_TRACK_H)
	_energy_track.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_energy_track)
	_energy_regen = UiKit.label("", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	col.add_child(_energy_regen)
	row.add_child(_energy_chip)
	row.add_child(_gap(_BUFF_GAP))
	_buff = _capsule()
	var bh := _buff.get_child(0) as HBoxContainer
	_buff_icon = UiKit.icon(null, _ICON_BUFF)
	_buff_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(_buff_icon)
	_buff_left = UiKit.label("", UiTokens.STYLE_C11_XB, UiTokens.COLOR_PRIMARY_INK)
	_buff_left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(_buff_left)
	row.add_child(_buff)
	_buff_rings = _BuffRings.new()
	row.add_child(_buff_rings)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_balances = HBoxContainer.new()
	_balances.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_balances.add_theme_constant_override(&"separation", 0)
	row.add_child(_balances)
	var coins := _capsule()
	var ch := coins.get_child(0) as HBoxContainer
	_coins = UiKit.label("", UiTokens.STYLE_C11_XB)
	_coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ch.add_child(_coins)
	var coin := UiKit.icon(ICON_COIN, _ICON_COIN)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ch.add_child(coin)
	_balances.add_child(coins)
	_balances.add_child(_gap(_INBOX_GAP - (UiTokens.SIZE_TOUCH - UiTokens.SIZE_INBOX) * 0.5))
	_inbox = _Chip.new(UiTokens.SIZE_INBOX * 0.5, UiTokens.SIZE_INBOX, UiTokens.SIZE_INBOX)
	_inbox.custom_minimum_size = Vector2(UiTokens.SIZE_TOUCH, UiTokens.SIZE_TOUCH)
	_inbox.pressed.connect(func(): inbox_pressed.emit())
	var bell := UiKit.icon(ICON_BELL, _ICON_BELL)
	bell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_inbox.body.add_child(bell)
	_badge = PanelContainer.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_UNREAD_BADGE, UiTokens.SIZE_UNREAD_BADGE_H * 0.5))
	_badge.custom_minimum_size = Vector2(UiTokens.SIZE_UNREAD_BADGE_W, UiTokens.SIZE_UNREAD_BADGE_H)
	var box := (UiTokens.SIZE_TOUCH - UiTokens.SIZE_INBOX) * 0.5
	_badge.position = Vector2(UiTokens.SIZE_TOUCH - box + _BADGE_OVER.x - UiTokens.SIZE_UNREAD_BADGE_W, box - _BADGE_OVER.y)
	_badge_count = UiKit.label("", UiTokens.STYLE_C10_XB, UiTokens.COLOR_SURFACE_RAISED)
	_badge_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.add_child(_badge_count)
	_inbox.add_child(_badge)
	_balances.add_child(_inbox)

func _build_row2() -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UiTokens.SIZE_HUD_ROW2_H
	# The Today icon's 44 hit area is wider than its 32 pill: the row starts that much further left and the gap to
	# the place chip is that much shorter, so the pill sits where the row starts and 8 before the place chip (300).
	var overhang := (UiTokens.SIZE_TOUCH - UiTokens.SIZE_TODAY_ICON_W) * 0.5
	row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_HUD_ROW_GAP - overhang))
	row.position = Vector2(-_ROW1_X * 2.0 - overhang, _ROW2_Y - (UiTokens.SIZE_TOUCH - h) * 0.5)
	row.size = Vector2(UiTokens.SIZE_HUD_W + _ROW1_X * 4.0 + overhang, UiTokens.SIZE_TOUCH)
	_frame.add_child(row)
	_row2 = row
	_today_chip = _Chip.new(UiTokens.RADIUS_HUD_CHIP, h, UiTokens.SIZE_TODAY_ICON_W)
	_today_chip.custom_minimum_size = Vector2(UiTokens.SIZE_TOUCH, UiTokens.SIZE_TOUCH)
	_today_chip.pressed.connect(func(): today_pressed.emit())
	var list := UiKit.icon(ICON_TODAY, _ICON_TODAY)
	list.modulate = UiTokens.COLOR_TEXT   # the game glyph is white; the icon is ink (不知火舞 76ebeaad)
	list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	list.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_today_chip.body.add_child(list)
	_today_dot = Panel.new()
	_today_dot.name = "TodayDot"
	_today_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_today_dot.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_UNREAD_BADGE, _DOT * 0.5))
	_today_dot.size = Vector2(_DOT, _DOT)
	_today_dot.position = Vector2(overhang + UiTokens.SIZE_TODAY_ICON_W + _DOT_OVER - _DOT, _today_chip.margin_y() - _DOT_OVER)
	_today_chip.add_child(_today_dot)
	row.add_child(_today_chip)
	_place_chip = _Chip.new(UiTokens.RADIUS_HUD_CHIP, h)
	_place_chip.custom_minimum_size = Vector2(UiTokens.SIZE_TOUCH, UiTokens.SIZE_TOUCH)
	_place_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place_chip.pressed.connect(func(): place_pressed.emit())
	var ph := _chip_row(_place_chip)
	_place_icon = UiKit.icon(ICON_HOME, _ICON_PLACE)
	_place_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(_place_icon)
	var names := HBoxContainer.new()
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_theme_constant_override(&"separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place_city = UiKit.label("", UiTokens.STYLE_C10_B)
	_place_space = UiKit.label("", UiTokens.STYLE_C10_B)
	_place_space.clip_text = true
	_place_suffix = UiKit.label("", UiTokens.STYLE_C10_B)
	for l in [_place_city, _place_space, _place_suffix]: names.add_child(l)
	_place_names = names
	names.resized.connect(_fit_space)
	ph.add_child(names)
	ph.add_child(UiKit.label("›", UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY))
	row.add_child(_place_chip)

static func _gap(w: float) -> Control:
	var g := Control.new()
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.custom_minimum_size.x = w
	return g

func _chip_row(chip: _Chip) -> HBoxContainer:
	chip.body.add_theme_constant_override(&"margin_left", _CHIP_PAD)
	chip.body.add_theme_constant_override(&"margin_right", _CHIP_PAD_END)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN) - 1)
	chip.body.add_child(h)
	return h

## A 26 px capsule (coins, Buff) centred in the 44 row; display only.
static func _capsule() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.SIZE_HUD_CAPSULE_H * 0.5)
	box.visual_height = UiTokens.SIZE_HUD_CAPSULE_H
	p.add_theme_stylebox_override(&"panel", box.with_margins(_CAPSULE_PAD, 0, _CAPSULE_PAD, 0))
	p.custom_minimum_size.y = UiTokens.SIZE_TOUCH
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override(&"separation", int(UiTokens.SPACE_QUICK_BAR_GAP))
	p.add_child(h)
	return p

# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if _place_suffix == null: return
	var e := energy_state()
	_energy_value.text = "%d/%d" % [roundi(_energy_shown) if _energy_shown >= 0.0 else int(data.energy), int(data.energy_max)]
	var ink := UiTokens.COLOR_TEXT
	if e == Energy.LOW: ink = UiTokens.COLOR_WARNING
	elif e == Energy.EMPTY: ink = UiTokens.COLOR_DANGER
	_energy_value.add_theme_color_override(&"font_color", ink)
	_energy_regen.text = str(data.regen)
	_energy_track.queue_redraw()
	_ring.farming = clampf(float(data.skills.get("farming", 0.0)), 0.0, 1.0)
	_ring.fishing = clampf(float(data.skills.get("fishing", 0.0)), 0.0, 1.0)
	_ring.queue_redraw()
	var buff: Dictionary = data.buff
	_buff.visible = not buff.is_empty()
	_buff_icon.texture = buff.get("icon", null)
	_buff_left.text = str(buff.get("remaining", ""))
	_buff_rings.show_buffs(data.buffs)
	_coins.text = str(int(data.coins))
	var unread := int(data.unread)
	_badge.visible = unread > 0
	_badge_count.text = str(unread) if unread < 100 else "99+"
	_today_dot.visible = bool(data.today_dot)
	var place: Dictionary = data.place
	var kind := int(place.get("kind", PlaceKind.HOME))
	_place_icon.texture = ICON_FOREIGN if kind == PlaceKind.FOREIGN else ICON_HOME
	var city := str(place.get("city", ""))
	var space := str(place.get("space", ""))
	_place_city.text = city + (" · " if city != "" and space != "" else "")
	_place_space.text = space
	var tail := place_tail(place)
	_place_suffix.text = " · " + tail if tail != "" else ""
	_fit_space()

## Truncates the space first (`Tokyo · Arr… · Day Pass 23h`). Done by hand: Godot's TRIM_ELLIPSIS only adds
## "…" once 6 letters still fit, so a squeezed space read `Arr` with no ellipsis.
func _fit_space() -> void:
	var full := str((data.place as Dictionary).get("space", ""))
	var font := _place_space.get_theme_font(&"font")
	var fs := _place_space.get_theme_font_size(&"font_size")
	var room := _place_names.size.x - _place_city.get_minimum_size().x - _place_suffix.get_minimum_size().x
	var shown := full
	if full != "" and font.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		var n := full.length() - 1
		while n > 1 and font.get_string_size(full.left(n) + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room: n -= 1
		shown = full.left(n).strip_edges(false, true) + "…"
	_place_space.text = shown
	# a fixed width (never more than the room) so the names row cannot push the chip wider
	_place_space.custom_minimum_size.x = ceilf(font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)

# ------------------------------------------------------------------ parts

## A HUD chip: a 44 px hit area with a smaller drawn box (UiStyleBox.visual_height), content in `body`.
class _Chip extends BaseButton:
	var body: MarginContainer
	var _visual_h: float
	var _visual_w: float

	func _init(radius: float, visual_h: float, visual_w := 0.0) -> void:
		focus_mode = Control.FOCUS_NONE
		_visual_h = visual_h
		_visual_w = visual_w
		if visual_h > 0.0:
			var bg := Panel.new()
			bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, radius)
			box.visual_height = visual_h
			if visual_w > 0.0:
				var side := (UiTokens.SIZE_TOUCH - visual_w) * 0.5
				box.inset = Vector4(side, 0, side, 0)
			bg.add_theme_stylebox_override(&"panel", box)
			add_child(bg)
		body = MarginContainer.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if visual_h > 0.0:
			body.add_theme_constant_override(&"margin_top", int(margin_y()))
			body.add_theme_constant_override(&"margin_bottom", int(margin_y()))
		add_child(body)

	func margin_y() -> float: return maxf(0.0, (UiTokens.SIZE_TOUCH - _visual_h) * 0.5) if _visual_h > 0.0 else 0.0

	## The drawn box, centred in the hit area like UiStyleBox.visual_height draws it.
	func visual_rect() -> Rect2:
		var r := get_global_rect()
		if _visual_h > 0.0 and r.size.y > _visual_h:
			r.position.y += (r.size.y - _visual_h) * 0.5
			r.size.y = _visual_h
		if _visual_w > 0.0 and r.size.x > _visual_w:
			r.position.x += (r.size.x - _visual_w) * 0.5
			r.size.x = _visual_w
		return r

	func _get_minimum_size() -> Vector2:
		return body.get_combined_minimum_size() if body != null else Vector2.ZERO

## Avatar ring (HUD main, 197 2026-10-07): right half Farming fills clockwise from 12 o'clock, left half Fishing
## counter-clockwise from 12 o'clock; each half stops 4° short of 12 and 6 o'clock (172° to fill) and shows
## the progress within the current level floored to 5 % (full at the top level). Cooking is not on the ring.
class _SkillRing extends Control:
	var farming := 0.0
	var fishing := 0.0

	func _draw() -> void:
		var side := float(UiTokens.SIZE_SKILL_RING)
		var c := Vector2(side, size.y) * 0.5
		var t := float(UiTokens.STROKE_RING)
		var r := side * 0.5 - t * 0.5
		draw_arc(c, r, 0.0, TAU, 48, UiTokens.COLOR_BORDER, t, true)
		var arcs := UiHud.skill_arcs(farming, fishing)
		if farming > 0.0: _arc(c, r, t, arcs.farming, UiTokens.COLOR_SKILL_FARMING)
		if fishing > 0.0: _arc(c, r, t, arcs.fishing, UiTokens.COLOR_SKILL_FISHING)

	func _arc(c: Vector2, r: float, t: float, deg: Vector2, color: Color) -> void:
		draw_arc(c, r, deg_to_rad(deg.x), deg_to_rad(deg.y), 24, color, t, true)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED and get_child_count() > 0:
			var p := get_child(0) as Control
			p.position = (Vector2(UiTokens.SIZE_SKILL_RING, size.y) - p.size) * 0.5

## Energy bar: green fill (amber when Low, none at 0); Bonus draws the over-cap part in light green.
class _Track extends Control:
	var hud: UiHud

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var radius := size.y * 0.5
		draw_style_box(UiStyleBox.make(UiTokens.COLOR_BORDER, radius), rect)
		var e := hud.energy_state()
		if e == UiHud.Energy.EMPTY: return
		var mx := maxf(1.0, float(hud.data.energy_max))
		var pct := clampf(float(hud.data.energy) / mx, 0.0, 1.0)
		var fill := UiTokens.COLOR_ENERGY_HUD_FILL if e == UiHud.Energy.LOW else UiTokens.COLOR_PRIMARY
		draw_style_box(UiStyleBox.make(fill, radius), Rect2(Vector2.ZERO, Vector2(maxf(size.y, size.x * pct), size.y)))
		if e == UiHud.Energy.BONUS:
			var over := clampf((float(hud.data.energy) - mx) / mx, 0.0, 1.0)
			var w := maxf(size.y, size.x * over)
			draw_rect(Rect2(Vector2(size.x - w, 0.0), Vector2(w, size.y)), UiTokens.COLOR_ENERGY_BONUS)

## The priest's buffs (q(300) ⑨): `buffs` [{icon, remaining "18:20", progress 0..1}], left to right; display only.
## Laid out by hand: the pills are wider than the circles and set the slots, the circles' centres 40 apart.
class _BuffRings extends Control:
	var _slots: Array = []   # [ring, icon, pill, label]

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, UiTokens.SIZE_TOUCH)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func show_buffs(buffs: Array) -> void:
		visible = not buffs.is_empty()
		while _slots.size() < buffs.size(): _slots.append(_slot())
		var top := (UiTokens.SIZE_TOUCH - (_BUFF_RING + _BUFF_PILL_H - _BUFF_PILL_OVER)) * 0.5
		var centre := 0.0
		var right := 0.0
		for i in _slots.size():
			var s: Array = _slots[i]
			var on := i < buffs.size()
			for n in s: (n as Control).visible = on
			if not on: continue
			var b: Dictionary = buffs[i]
			var ring: _BuffRing = s[0]
			ring.progress = clampf(float(b.get("progress", 0.0)), 0.0, 1.0)
			ring.queue_redraw()
			(s[1] as TextureRect).texture = b.get("icon", null)
			(s[3] as Label).text = str(b.get("remaining", ""))
			var pill: PanelContainer = s[2]
			var pw := pill.get_combined_minimum_size().x
			var half := maxf(pw, _BUFF_RING) * 0.5
			centre = half if i == 0 else centre + _BUFF_PITCH
			ring.position = Vector2(centre - _BUFF_RING * 0.5, top)
			(s[1] as Control).position = Vector2(centre - _BUFF_RING_ICON * 0.5, top + (_BUFF_RING - _BUFF_RING_ICON) * 0.5)
			pill.size = Vector2(pw, _BUFF_PILL_H)
			pill.position = Vector2(centre - pw * 0.5, top + _BUFF_RING - _BUFF_PILL_OVER)
			right = centre + half
		custom_minimum_size.x = right
		update_minimum_size()

	func _slot() -> Array:
		var ring := _BuffRing.new()
		ring.size = Vector2(_BUFF_RING, _BUFF_RING)
		add_child(ring)
		var icon := UiKit.icon(null, _BUFF_RING_ICON)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size = Vector2(_BUFF_RING_ICON, _BUFF_RING_ICON)
		add_child(icon)
		var pill := PanelContainer.new()
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, _BUFF_PILL_H * 0.5, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
		pill.add_theme_stylebox_override(&"panel", box.with_margins(_BUFF_PILL_PAD, 0, _BUFF_PILL_PAD, 0))
		pill.custom_minimum_size.y = _BUFF_PILL_H
		var label := UiKit.label("", UiTokens.STYLE_C10_XB, UiTokens.COLOR_PRIMARY_INK)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pill.add_child(label)
		add_child(pill)
		return [ring, icon, pill, label]

## One buff's circle: the surface colour, NEED-TILE's light track and its green arc for the share of time left.
class _BuffRing extends Control:
	var progress := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(_BUFF_RING, _BUFF_RING) * 0.5
		var r := _BUFF_RING * 0.5 - _BUFF_RING_STROKE * 0.5
		draw_circle(c, _BUFF_RING * 0.5, UiTokens.COLOR_SURFACE, true, -1.0, true)
		draw_arc(c, r, 0.0, TAU, 64, UiTokens.COLOR_BORDER, _BUFF_RING_STROKE, true)
		if progress > 0.0:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * progress, maxi(8, int(64 * progress)), UiTokens.COLOR_PRIMARY,
				_BUFF_RING_STROKE, true)
