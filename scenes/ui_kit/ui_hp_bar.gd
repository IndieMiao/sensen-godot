class_name UiHpBar
extends PanelContainer
## HPBar (Figma 14 · Gensen Refactor/HPBar, COMBAT-1 482:562; SGODOT-288) and EnemyHP Kind=Elite (COMBAT-ELITE
## 1228:111690): the mine's HP, shown only where it counts (mine floors 3–5, §13.3.1).
##   Kind PLAYER  card 28 high, surface, 1 px border, radius 12, padding 10 / 5: the 14 × 13 heart in its own coral
##                (HPBar 1124:79402, assets/p0/icons/heart.svg), a 120 × 10 bar (track border, fill primary) and the
##                percent (ExtraBold 12), 6 apart; under 30 % the fill and the percent turn danger.
##   Kind ELITE   card 328 × 55 under the player's: the name (ExtraBold 14) and its percent (Bold 12) on one row, a
##                302 × 12 bar under them (track ink at 12 %, fill danger); shown for the whole fight.
## Attack is not on the HUD (COMBAT-1).

enum Kind { PLAYER, ELITE }
const LOW := 0.3
const _PLAYER_BAR := Vector2(120, 10)
const _ELITE_BAR := Vector2(302, 12)
const _ELITE_W := 328.0

var kind: Kind = Kind.PLAYER
var title := "": set = set_title
var _fraction := 1.0
var _track: Panel
var _fill: Panel
var _fill_box: UiStyleBox
var _percent: Label
var _name: Label

func _init(kind_ := Kind.PLAYER) -> void:
	kind = kind_
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, 12 if kind == Kind.PLAYER else 14, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	if kind == Kind.PLAYER: box.with_margins(10, 4, 10, 4)
	else: box.with_margins(13, 9, 13, 10)
	add_theme_stylebox_override(&"panel", box)
	var bar_size := _PLAYER_BAR if kind == Kind.PLAYER else _ELITE_BAR
	_track = Panel.new()
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.custom_minimum_size = bar_size
	_track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track_ink := UiTokens.COLOR_BORDER if kind == Kind.PLAYER else Color(UiTokens.COLOR_TEXT, 0.12)   # ink at 12 %
	_track.add_theme_stylebox_override(&"panel", UiStyleBox.make(track_ink, bar_size.y * 0.5))
	_fill = Panel.new()
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_box = UiStyleBox.make(UiTokens.COLOR_PRIMARY if kind == Kind.PLAYER else UiTokens.COLOR_DANGER, bar_size.y * 0.5)
	_fill.add_theme_stylebox_override(&"panel", _fill_box)
	_track.add_child(_fill)
	_percent = UiKit.label("100%", UiTokens.STYLE_C12_XB if kind == Kind.PLAYER else UiTokens.STYLE_C12_B, UiTokens.COLOR_TEXT)
	if kind == Kind.PLAYER:
		custom_minimum_size.y = 28
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override(&"separation", 6)
		add_child(row)
		var heart := TextureRect.new()
		heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heart.texture = P0Logic.icon("heart") if ResourceLoader.exists("res://assets/p0/icons/heart.svg") else null
		heart.name = "Heart"
		heart.custom_minimum_size = Vector2(14, 13)
		heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		heart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		heart.visible = heart.texture != null   # the icon carries its own coral (#E07A5F), no tint
		row.add_child(heart)
		row.add_child(_track)
		row.add_child(_percent)
	else:
		custom_minimum_size.x = _ELITE_W
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_theme_constant_override(&"separation", 6)
		add_child(col)
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(head)
		_name = UiKit.label("", UiTokens.STYLE_C14_XB, UiTokens.COLOR_TEXT)
		_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(_name)
		head.add_child(_percent)
		col.add_child(_track)
	_track.resized.connect(_layout_fill)
	_refresh()

func set_title(v: String) -> void:
	title = v
	if _name: _name.text = v

## HP as hp of max; the percent is rounded down so it reads 0% only at 0.
func set_hp(hp: int, maximum: int) -> void:
	_fraction = clampf(float(hp) / float(maxi(1, maximum)), 0.0, 1.0)
	_refresh()

func fraction() -> float: return _fraction
func percent_text() -> String: return _percent.text
func low() -> bool: return kind == Kind.PLAYER and _fraction < LOW

func _refresh() -> void:
	_percent.text = "%d%%" % int(floor(_fraction * 100.0 + 1e-6))
	var red := low()
	if kind == Kind.PLAYER:
		_fill_box.bg_color = UiTokens.COLOR_DANGER if red else UiTokens.COLOR_PRIMARY
		_percent.add_theme_color_override(&"font_color", UiTokens.COLOR_DANGER if red else UiTokens.COLOR_TEXT)
	_layout_fill()

func _layout_fill() -> void:
	if _fill == null or _track == null: return
	var size := _track.custom_minimum_size
	_fill.position = Vector2.ZERO
	_fill.size = Vector2(maxf(0.0, size.x * _fraction), size.y)
	_fill.visible = _fraction > 0.0
