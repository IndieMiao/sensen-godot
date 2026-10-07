class_name UiProfileTopBar
extends HBoxContainer
## Profile top bar (SGODOT-225; ProfileTopBar 1233:107734, LOCK-22). One profile design only:
##   SELF   back + `Profile` + gear (Settings)
##   OTHER  back + their name + ··· (UiProfileMoreMenu: Unfollow / Block / Report, flows in WP5)
## `show_settings = false` hides the gear while P0 has no Settings page (TODO in the P0 page).
## Emits back_pressed, settings_pressed, more_pressed(anchor: Rect2, global).

signal back_pressed
signal settings_pressed
signal more_pressed(anchor: Rect2)

enum Kind { SELF, OTHER }

const _GAP := 10.0   # ProfileTopBar: back → title → right button

var kind: Kind
var title := "": set = set_title
var show_settings := true: set = set_show_settings

var _title: Label
var _right: _Round

func _init(kind_: Kind = Kind.SELF, title_ := "Profile") -> void:
	kind = kind_
	add_theme_constant_override(&"separation", int(_GAP))
	var back := _Round.new(_Round.Glyph.BACK)
	back.pressed.connect(func(): back_pressed.emit())
	add_child(back)
	# ExtraBold 17 in the main; the nearest exported style until WP1b mains are in tokens (UiTokens.PENDING "wp1b").
	_title = UiKit.label("", UiTokens.STYLE_ROW_TITLE_XB15)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_title)
	_right = _Round.new(_Round.Glyph.GEAR if kind == Kind.SELF else _Round.Glyph.MORE)
	_right.pressed.connect(func():
		if kind == Kind.SELF: settings_pressed.emit()
		else: more_pressed.emit(_right.get_global_rect()))
	add_child(_right)
	title = title_
	show_settings = show_settings

func set_title(v: String) -> void:
	title = v
	if _title != null: _title.text = v

func set_show_settings(v: bool) -> void:
	show_settings = v
	if _right != null and kind == Kind.SELF:
		_right.modulate.a = 1.0 if v else 0.0   # keeps its place so the title does not jump
		_right.mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE

func right_button() -> Button: return _right

## 44 round raised button with a drawn glyph (‹, gear, ···).
class _Round extends Button:
	enum Glyph { BACK, GEAR, MORE }
	var glyph: Glyph

	func _init(g: Glyph) -> void:
		glyph = g
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(UiTokens.SIZE_CLOSE, UiTokens.SIZE_CLOSE)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var box := UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, UiTokens.SIZE_CLOSE * 0.5, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
		for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
			add_theme_stylebox_override(st, box)

	func _draw() -> void:
		var c := size * 0.5
		var ink := UiTokens.COLOR_TEXT
		match glyph:
			Glyph.BACK:
				var w := UiTokens.STROKE_DEFAULT * 2.0   # the main's ‹ is a thin ExtraBold glyph
				draw_polyline(PackedVector2Array([c + Vector2(3, -7), c + Vector2(-4, 0), c + Vector2(3, 7)]), ink, w, true)
			Glyph.MORE:
				for dx in [-6.0, 0.0, 6.0]: draw_circle(c + Vector2(dx, 0), 2.0, ink, true, -1.0, true)
			Glyph.GEAR:
				var r := UiTokens.SIZE_CLOSE_ICON * 0.5
				var pts := PackedVector2Array()
				for i in 16:   # eight teeth
					var a := TAU * float(i) / 16.0
					pts.append(c + Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.72))
				draw_colored_polygon(pts, ink)
				draw_circle(c, r * 0.32, UiTokens.COLOR_SURFACE_RAISED, true, -1.0, true)
