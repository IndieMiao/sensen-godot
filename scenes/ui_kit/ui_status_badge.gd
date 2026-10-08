class_name UiStatusBadge
extends Control
## StatusBadge 1132:79554 (SGODOT-221, LOCK-11; plan §16.1.3 STATE-ICONS): the round state mark that hangs over
## a facility (World, 28 px) or a resident's head (NPC, 36 px), with an optional caption pill under it (`1h 12m`).
## Fill and ring colours come from the main per state (COLOR_STATUS_<state>[_RING]); glyphs are the main's own
## vectors (assets/ui/kit_icons/status/). AVAILABLE shows the facility's icon instead (`icon`). Display only:
## facilities and residents take the tap (LOCK-07). Track it with WorldAnchor over a `badge_` / `use_` anchor.

enum Size { WORLD, NPC }
enum State { AVAILABLE, READY, COUNTDOWN, COOLING, USED_TODAY, LOCKED, INSUFFICIENT, FULL, NEW, REQUEST,
	DELIVERABLE, EVENT, GIFT, BLOCKED, SELL }

const _KEYS := ["available", "ready", "countdown", "cooling", "used_today", "locked", "insufficient", "full", "new",
	"request", "deliverable", "event", "gift", "blocked", "sell"]
const _FILL := [UiTokens.COLOR_STATUS_AVAILABLE, UiTokens.COLOR_STATUS_READY, UiTokens.COLOR_STATUS_COUNTDOWN,
	UiTokens.COLOR_STATUS_COOLING, UiTokens.COLOR_STATUS_USED_TODAY, UiTokens.COLOR_STATUS_LOCKED,
	UiTokens.COLOR_STATUS_INSUFFICIENT, UiTokens.COLOR_STATUS_FULL, UiTokens.COLOR_STATUS_NEW,
	UiTokens.COLOR_STATUS_REQUEST, UiTokens.COLOR_STATUS_DELIVERABLE, UiTokens.COLOR_STATUS_EVENT,
	UiTokens.COLOR_STATUS_GIFT, UiTokens.COLOR_STATUS_BLOCKED, UiTokens.COLOR_STATUS_SELL]
const _RING := [UiTokens.COLOR_STATUS_AVAILABLE_RING, UiTokens.COLOR_STATUS_READY_RING,
	UiTokens.COLOR_STATUS_COUNTDOWN_RING, UiTokens.COLOR_STATUS_COOLING_RING, UiTokens.COLOR_STATUS_USED_TODAY_RING,
	UiTokens.COLOR_STATUS_LOCKED_RING, UiTokens.COLOR_STATUS_INSUFFICIENT_RING, UiTokens.COLOR_STATUS_FULL_RING,
	UiTokens.COLOR_STATUS_NEW_RING, UiTokens.COLOR_STATUS_REQUEST_RING, UiTokens.COLOR_STATUS_DELIVERABLE_RING,
	UiTokens.COLOR_STATUS_EVENT_RING, UiTokens.COLOR_STATUS_GIFT_RING, UiTokens.COLOR_STATUS_BLOCKED_RING,
	UiTokens.COLOR_STATUS_SELL_RING]
## States drawn with the 2 px accent ring in the main; the rest use the 1 px hairline.
const _ACCENT := [State.AVAILABLE, State.NEW, State.REQUEST, State.DELIVERABLE, State.EVENT, State.GIFT, State.BLOCKED]
const _CAPTION_GAP := 2.0          # caption pill 18 high, 2 px under the 28 / 36 px badge
const _CAPTION_PAD := 7.0          # caption text inset 7 px

var size_kind: Size = Size.WORLD: set = set_size_kind
var state: State = State.AVAILABLE: set = set_state
## The facility icon AVAILABLE shows (the main's Icon swap).
var icon: Texture2D: set = set_icon
## Optional caption under the badge, e.g. the countdown `1h 12m`; "" hides it.
var caption := "": set = set_caption

var _badge: Panel
var _glyph: TextureRect
var _pill: PanelContainer
var _caption: Label

func _init(state_: State = State.AVAILABLE, size_: Size = Size.WORLD) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge = Panel.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_badge)
	_glyph = UiKit.icon(null, UiTokens.SIZE_STATUS_GLYPH_WORLD)
	_badge.add_child(_glyph)
	_pill = PanelContainer.new()
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CAPTION_PILL, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.with_margins(_CAPTION_PAD, 0, _CAPTION_PAD, 0)
	_pill.add_theme_stylebox_override(&"panel", box)
	_pill.custom_minimum_size.y = UiTokens.SIZE_CAPTION_PILL_H
	add_child(_pill)
	_caption = UiKit.label("", UiTokens.STYLE_C11_B)
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pill.add_child(_caption)
	_pill.minimum_size_changed.connect(_layout)
	size_kind = size_
	state = state_
	_refresh()   # the setters skip unchanged values, so the defaults still need one draw

# P0 sets these every frame: unchanged values skip the restyle.
func set_size_kind(v: Size) -> void:
	if v != size_kind: size_kind = v; _refresh()
func set_state(v: State) -> void:
	if v != state: state = v; _refresh()
func set_icon(v: Texture2D) -> void:
	if v != icon: icon = v; _refresh()
func set_caption(v: String) -> void:
	if v != caption: caption = v; _refresh()

func side() -> float: return float(UiTokens.SIZE_STATUS_BADGE_NPC if size_kind == Size.NPC else UiTokens.SIZE_STATUS_BADGE_WORLD)

func ring_width() -> float:
	return float(UiTokens.STROKE_STATUS_BADGE_NPC if state in _ACCENT else UiTokens.STROKE_DEFAULT)

func _get_minimum_size() -> Vector2:
	var s := side()
	if caption == "" or _pill == null: return Vector2(s, s)
	var p := _pill.get_combined_minimum_size()
	return Vector2(maxf(s, p.x), s + _CAPTION_GAP + p.y)

func _refresh() -> void:
	if _caption == null: return
	var s := side()
	_badge.add_theme_stylebox_override(&"panel", UiStyleBox.make(_FILL[state], s * 0.5, _RING[state], ring_width()))
	var g := UiTokens.SIZE_STATUS_GLYPH_NPC if size_kind == Size.NPC else UiTokens.SIZE_STATUS_GLYPH_WORLD
	_glyph.custom_minimum_size = Vector2(g, g)
	_glyph.size = Vector2(g, g)
	_glyph.texture = icon if state == State.AVAILABLE else load("res://assets/ui/kit_icons/status/%s.svg" % _KEYS[state])
	_caption.text = caption
	_pill.visible = caption != ""
	_layout()

func _layout() -> void:
	var s := side()
	var w := get_combined_minimum_size().x
	_badge.position = Vector2((w - s) * 0.5, 0)
	_badge.size = Vector2(s, s)
	_glyph.position = (Vector2(s, s) - _glyph.size) * 0.5
	if _pill.visible:
		_pill.size = _pill.get_combined_minimum_size()
		_pill.position = Vector2((w - _pill.size.x) * 0.5, s + _CAPTION_GAP)
	update_minimum_size()
