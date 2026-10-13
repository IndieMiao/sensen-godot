class_name UiNeedTile
extends BaseButton
## NEED-TILE (SGODOT-222; Gensen Refactor/NeedTile 1090:78003, LOCK-10): every have / need (materials, coins,
## skill totals, stamps) is an icon inside a ring plus one line `Name have/need`.
##   met    have ≥ need: full green ring, ink number (a surplus is written as is, 5/4)
##   short  have < need: amber arc + amber have number, warm core
##   count  usage or collection counts (Meals 100/300, Fish-dex 12/20): green partial arc, ink number
## The ring is have ÷ need rounded DOWN to 10 % and capped at 100 %, like the main's Progress variants.
## L 64 (panels) · M 48 (cards, recipes) · S 36 (list rows, hint cards, the HUD Energy panel). Put tiles in
## UiNeedTile.group() (wrap layout), never a fixed grid. Tapping emits `pressed`; the host shows a
## UiNeedSource (one line + Show, guide only). The gap itself goes on the button (UiCommandButton.reason).

enum Size { L, M, S }
enum State { MET, SHORT, COUNT }

const _LABEL_GAP := {Size.L: 6, Size.M: 5, Size.S: 4}   # ring → label gap in each main
const _NAME_GAP := 3                                    # "Name" → "have/need"

var size_class: Size = Size.L
var icon: Texture2D: set = set_icon
var item_name := "": set = set_item_name
var have := 0: set = set_have
var need := 1: set = set_need
## Usage / collection count (green partial arc) instead of a requirement.
var counting := false: set = set_counting

var _ring: _Ring
var _icon: TextureRect
var _name: Label
var _have: Label
var _need: Label

func _init(name_: String = "", have_ := 0, need_ := 1, size_: Size = Size.L, icon_: Texture2D = null, counting_ := false) -> void:
	size_class = size_
	focus_mode = Control.FOCUS_NONE
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override(&"separation", _LABEL_GAP[size_class])
	add_child(col)
	_ring = _Ring.new()
	_ring.tile = self
	var side := ring_side()
	_ring.custom_minimum_size = Vector2(side, side)
	_ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_ring)
	var glyph := icon_side()
	_icon = UiKit.icon(null, glyph)
	_icon.position = Vector2(side - glyph, side - glyph) * 0.5
	_icon.size = Vector2(glyph, glyph)
	_ring.add_child(_icon)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	line.add_theme_constant_override(&"separation", _NAME_GAP)
	col.add_child(line)
	var small := size_class == Size.S
	_name = UiKit.label("", UiTokens.STYLE_C11_XB if small else UiTokens.STYLE_CAPTION_XB12)
	line.add_child(_name)
	var count := HBoxContainer.new()
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.add_theme_constant_override(&"separation", 0)
	line.add_child(count)
	_have = UiKit.label("", UiTokens.STYLE_C11_XB if small else UiTokens.STYLE_CAPTION_XB12)
	_need = UiKit.label("", UiTokens.STYLE_C11_B if small else UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	count.add_child(_have)
	count.add_child(_need)
	item_name = name_
	have = have_
	need = need_
	icon = icon_
	counting = counting_
	resized.connect(func(): col.size = size)

func set_icon(v: Texture2D) -> void: icon = v; _refresh()
func set_item_name(v: String) -> void: item_name = v; _refresh()
func set_have(v: int) -> void: have = v; _refresh()
func set_need(v: int) -> void: need = v; _refresh()
func set_counting(v: bool) -> void: counting = v; _refresh()

func state() -> State:
	if counting: return State.COUNT
	return State.MET if have >= need else State.SHORT

## Ring fill 0..1: have ÷ need rounded down to 10 % (the main's Progress steps); met is always full.
func progress() -> float:
	if state() == State.MET: return 1.0
	if need <= 0: return 1.0
	return minf(1.0, floorf(float(have) * 10.0 / float(need)) / 10.0)

## A small mark on the ring's top-right (the Fish-dex badge on the profile's Fish tile, 283 PROFILE-1-DEX): `side`
## square, its centre `inset` left of and below the ring's top-right corner. Returns it.
func add_corner(tex: Texture2D, side: float, inset := Vector2(2, 8)) -> TextureRect:
	var r := UiKit.icon(tex, side)
	r.name = "Corner"
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size = Vector2(side, side)
	r.position = Vector2(ring_side() - inset.x - side * 0.5, inset.y - side * 0.5)
	_ring.add_child(r)
	return r

func ring_side() -> float:
	return float({Size.L: UiTokens.SIZE_NEED_TILE_RING_L, Size.M: UiTokens.SIZE_NEED_TILE_RING_M,
		Size.S: UiTokens.SIZE_NEED_TILE_RING_S}[size_class])

func ring_stroke() -> float:
	return float({Size.L: UiTokens.SIZE_NEED_TILE_STROKE_L, Size.M: UiTokens.SIZE_NEED_TILE_STROKE_M,
		Size.S: UiTokens.SIZE_NEED_TILE_STROKE_S}[size_class])

func icon_side() -> float:
	return float({Size.L: UiTokens.SIZE_NEED_TILE_ICON_L, Size.M: UiTokens.SIZE_NEED_TILE_ICON_M,
		Size.S: UiTokens.SIZE_NEED_TILE_ICON_S}[size_class])

## Tiles of one group in a wrap layout (gap 10 across, 12 down), so long labels never collide.
static func group(tiles: Array) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", int(UiTokens.SIZE_NEED_TILE_GAP_X))
	flow.add_theme_constant_override(&"v_separation", int(UiTokens.SIZE_NEED_TILE_GAP_Y))
	for t in tiles: flow.add_child(t)
	return flow

func _get_minimum_size() -> Vector2:
	if _ring == null: return Vector2.ZERO
	var content := (get_child(0) as Control).get_combined_minimum_size()
	return Vector2(maxf(content.x, UiTokens.SIZE_TOUCH), maxf(content.y, UiTokens.SIZE_TOUCH))

func _refresh() -> void:
	if _ring == null: return
	_icon.texture = icon
	_name.text = item_name
	_have.text = str(have)
	_need.text = "/%d" % need
	_have.add_theme_color_override(&"font_color", UiTokens.COLOR_WARNING if state() == State.SHORT else UiTokens.COLOR_TEXT)
	_ring.queue_redraw()
	update_minimum_size()

class _Ring extends Control:
	var tile: UiNeedTile

	func _draw() -> void:
		var side := tile.ring_side()
		var t := tile.ring_stroke()
		var c := Vector2(side, side) * 0.5
		var r := side * 0.5
		var short := tile.state() == UiNeedTile.State.SHORT
		draw_arc(c, r - t * 0.5, 0.0, TAU, 64, UiTokens.COLOR_BORDER, t, true)
		var p := tile.progress()
		if p > 0.0:
			draw_arc(c, r - t * 0.5, -PI * 0.5, -PI * 0.5 + TAU * p, maxi(8, int(64 * p)),
				UiTokens.COLOR_AMBER if short else UiTokens.COLOR_PRIMARY, t, true)
		draw_circle(c, r - t, UiTokens.COLOR_WARM if short else UiTokens.COLOR_TILE_CORE, true, -1.0, true)
