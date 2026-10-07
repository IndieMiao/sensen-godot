extends SceneTree
## Generates the P0 UI kit theme from design tokens (SGODOT-211, WP7-A §4):
##   docs/design/tokens/tokens-v2.json  ->  assets/ui/gensen_theme.tres
##                                          assets/ui/fonts/nunito_w400|700|800.tres
##                                          modules/ui/kit/ui_tokens.gd
## Run after every token export:  godot --headless --path . --script tools/ui/gen_theme.gd
## Components never hard-code values; they read UiTokens and the theme variations named here.

const UiStyleBoxScript := preload("res://modules/ui/kit/ui_style_box.gd")
const TOKENS := "res://docs/design/tokens/tokens-v2.json"
const THEME_OUT := "res://assets/ui/gensen_theme.tres"
const TOKENS_OUT := "res://modules/ui/kit/ui_tokens.gd"
const FONT_OUT := "res://assets/ui/fonts/nunito_w%d.tres"

## Theme variations beyond the text styles. Order is the order they appear in UiTokens.
const BUTTONS := ["CmdPrimary", "CmdSecondary", "CmdDestructive", "CmdDangerSecondary", "CmdBlocked",
	"CmdPrimaryCompact", "CmdSecondaryCompact", "CmdDestructiveCompact", "CmdDangerSecondaryCompact", "CmdBlockedCompact",
	"NavRow", "NavCompact", "Dismiss", "CloseRound", "FilterChip", "SegmentTab"]
const PANELS := ["Sheet", "InfoSheet", "Card", "HudChip", "ToastPanel", "Badge"]

var t: Dictionary
var fonts := {}

func _init() -> void:
	t = load_tokens()
	_build_fonts()
	var theme := build_theme()
	var err := ResourceSaver.save(theme, THEME_OUT)
	if err != OK: push_error("gen_theme: cannot save theme (%d)" % err); quit(1); return
	var f := FileAccess.open(TOKENS_OUT, FileAccess.WRITE)
	f.store_string(tokens_source())
	f.close()
	print("gen_theme: wrote %s, %s and 3 font variations from %s %s" % [THEME_OUT, TOKENS_OUT, TOKENS, t.meta.version])
	quit()

static func load_tokens() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(TOKENS))
	assert(data is Dictionary and int(data.meta.schema) == 2, "tokens-v2.json missing or wrong schema")
	return data

func c(key: String) -> Color: return Color.html(t.color[key])
func s(key: String) -> float: return float(t.size[key])
func r(key: String) -> float: return float(t.radius[key])

func _build_fonts() -> void:
	var base: FontFile = load(t.font.file)
	for w in t.font.weights:
		var weight := int(t.font.weights[w])
		var fv := FontVariation.new()
		fv.base_font = base
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		var path := FONT_OUT % weight
		ResourceSaver.save(fv, path)
		fonts[w] = load(path)

func build_theme() -> Theme:
	var th := Theme.new()
	th.default_font = fonts.regular
	th.default_font_size = int(t.font.styles.BodyR14.size)
	th.set_color("font_color", "Label", c("text"))
	th.set_constant("line_spacing", "Label", _line_spacing(t.font.styles.BodyR14))
	for name in t.font.styles:
		var st: Dictionary = t.font.styles[name]
		th.set_type_variation(name, "Label")
		th.set_font("font", name, fonts[st.weight])
		th.set_font_size("font_size", name, int(st.size))
		th.set_color("font_color", name, c("text"))
		th.set_constant("line_spacing", name, _line_spacing(st))
	_buttons(th)
	_panels(th)
	return th

func _line_spacing(st: Dictionary) -> int:
	return roundi(float(st.size) * (float(st.lineHeight) - float(t.font.naturalLineHeight)))

func _box(bg: Color, radius: float, border := Color.TRANSPARENT, width := 0.0) -> StyleBox:
	var b: StyleBox = UiStyleBoxScript.new()
	b.bg_color = bg
	b.corner_radius = Vector4(radius, radius, radius, radius)
	b.border_color = border
	b.border_width = width
	return b

func _button(th: Theme, name: String, normal: StyleBox, pressed: StyleBox, disabled: StyleBox,
		font: String, ink: Color, ink_pressed: Color, ink_disabled: Color) -> void:
	th.set_type_variation(name, "Button")
	th.set_stylebox("normal", name, normal)
	th.set_stylebox("hover", name, normal)
	th.set_stylebox("pressed", name, pressed)
	th.set_stylebox("hover_pressed", name, pressed)
	th.set_stylebox("disabled", name, disabled)
	th.set_stylebox("focus", name, StyleBoxEmpty.new())
	var st: Dictionary = t.font.styles[font]
	th.set_font("font", name, fonts[st.weight])
	th.set_font_size("font_size", name, int(st.size))
	th.set_color("font_color", name, ink)
	th.set_color("font_hover_color", name, ink)
	th.set_color("font_focus_color", name, ink)
	th.set_color("font_pressed_color", name, ink_pressed)
	th.set_color("font_hover_pressed_color", name, ink_pressed)
	th.set_color("font_disabled_color", name, ink_disabled)
	th.set_constant("h_separation", name, int(t.space.within))

func _margins(b: StyleBox, h: float, v: float) -> StyleBox:
	b.content_margin_left = h
	b.content_margin_right = h
	b.content_margin_top = v
	b.content_margin_bottom = v
	return b

func _margins4(b: StyleBox, left: float, top: float, right: float, bottom: float) -> StyleBox:
	b.content_margin_left = left
	b.content_margin_top = top
	b.content_margin_right = right
	b.content_margin_bottom = bottom
	return b

func _buttons(th: Theme) -> void:
	var stroke := float(t.stroke.default)
	var pill := r("pill")
	# kind: [bg, border, ink]. Pressed uses the Figma primary-pressed fill where it exists, otherwise a
	# darkened fill. Blocked is CommandButton Kind=unavailable (still tappable, explains why); the real
	# disabled state (e.g. offline) is the neutral grey with disabledInk.
	var kinds := {
		"Primary": [c("primary"), Color.TRANSPARENT, c("surfaceRaised")],
		"Secondary": [c("surface"), c("primary"), c("primary")],
		"Destructive": [c("danger"), Color.TRANSPARENT, c("surfaceRaised")],
		"DangerSecondary": [c("surface"), c("danger"), c("danger")],
		"Blocked": [c("disabled"), Color.TRANSPARENT, c("secondary")],
	}
	var pressed_fill := {"Primary": c("primaryPressed")}
	for k in kinds:
		var bg: Color = kinds[k][0]
		var edge: Color = kinds[k][1]
		var ink: Color = kinds[k][2]
		var w := stroke if edge.a > 0.0 else 0.0
		for compact in [false, true]:
			var radius := r("compactCommand") if compact else pill
			var mk := func(fill: Color, line: Color) -> StyleBox:
				var b := _margins(_box(fill, radius, line, w), float(t.space.page), 0.0)
				if compact: b.visual_height = s("commandCompact")
				return b
			_button(th, "Cmd%s%s" % [k, "Compact" if compact else ""],
				mk.call(bg, edge), mk.call(pressed_fill.get(k, bg.darkened(0.12)), edge.darkened(0.12)),
				mk.call(c("disabled"), Color.TRANSPARENT),
				"C12XB" if compact else "ButtonXB15", ink, ink, c("disabledInk"))
	var flat := func(pad_v: float) -> StyleBox: return _margins(_box(Color.TRANSPARENT, 0.0), 0.0, pad_v)
	var tint := c("primaryTint")
	var flat_pressed := func(pad_v: float) -> StyleBox: return _margins(_box(tint, r("card")), 0.0, pad_v)
	var nav_pad := (s("navigationRow") - float(t.font.styles.ButtonB15.size) * float(t.font.styles.ButtonB15.lineHeight)) * 0.5
	_button(th, "NavRow", flat.call(nav_pad), flat_pressed.call(nav_pad), flat.call(nav_pad), "ButtonB15", c("info"), c("info"), c("disabledInk"))
	_button(th, "NavCompact", flat.call(0.0), flat_pressed.call(0.0), flat.call(0.0), "C12B", c("primary"), c("primary"), c("disabledInk"))
	_button(th, "Dismiss", flat.call(0.0), flat_pressed.call(0.0), flat.call(0.0), "ButtonB15", c("secondary"), c("secondary"), c("disabledInk"))
	var icon_pad := (s("close") - s("closeIcon")) * 0.5
	var close_box := func(fill: Color, line: Color) -> StyleBox:
		return _margins(_box(fill, s("close") * 0.5, line, stroke), icon_pad, icon_pad)
	_button(th, "CloseRound", close_box.call(c("surface"), c("border")), close_box.call(c("surface").darkened(0.08), c("border")),
		close_box.call(c("disabled"), Color.TRANSPARENT), "ButtonB15", c("text"), c("text"), c("disabledInk"))
	var chip := func(fill: Color) -> StyleBox:
		var b := _margins(_box(fill, r("chip")), float(t.space.row), 0.0)
		b.visual_height = s("filterChip")
		return b
	# Toggle buttons: "pressed" is the selected look.
	_button(th, "FilterChip", chip.call(c("surface")), chip.call(c("primary")), chip.call(c("disabled")),
		"C11B", c("secondary"), c("surface"), c("disabledInk"))
	# SegmentTab selected style is provisional: LOCK-13 forbids the command green for mode switches (WP1b).
	var seg := func(fill: Color, line: Color) -> StyleBox: return _margins(_box(fill, pill, line, stroke), float(t.space.row), 0.0)
	_button(th, "SegmentTab", seg.call(c("surface"), c("border")), seg.call(c("primaryTint"), c("primary")),
		seg.call(c("disabled"), Color.TRANSPARENT), "BodyB14", c("secondary"), c("primary"), c("disabledInk"))

func _panel(th: Theme, name: String, box: StyleBox) -> void:
	th.set_type_variation(name, "PanelContainer")
	th.set_stylebox("panel", name, box)

func _panels(th: Theme) -> void:
	var sheet_bg := c("surface")
	sheet_bg.a = float(t.opacity.sheetSurface)
	var top := r("sheet")
	for name in ["Sheet", "InfoSheet"]:
		var b := _margins(_box(sheet_bg, 0.0, c("border"), float(t.stroke.default)), s("sheetPad"), s("sheetPad"))
		b.corner_radius = Vector4(top, top, 0, 0)
		_panel(th, name, b)
	_panel(th, "Card", _margins(_box(c("surface"), r("card"), c("border"), float(t.stroke.default)), float(t.space.row), float(t.space.row)))
	_panel(th, "HudChip", _margins(_box(c("surface"), r("hudChip")), 8.0, 4.0))
	_panel(th, "ToastPanel", _margins4(_box(c("text"), r("card")), s("toastPadLeft"), s("toastPadTop"), s("toastPadRight"), s("toastPadBottom")))
	_panel(th, "Badge", _margins(_box(c("primaryTint"), s("stateBadgeH") * 0.5), 8.0, 0.0))

# ---------------------------------------------------------------- UiTokens source

## camelCase and Figma group paths to UPPER_SNAKE: "quickSlotW" -> QUICK_SLOT_W, "role/marketTint" -> ROLE_MARKET_TINT.
static func const_name(key: String) -> String:
	var re := RegEx.create_from_string("([a-z0-9])([A-Z])")
	return re.sub(key.replace("/", "_"), "$1_$2", true).to_upper()

static func _literal(v) -> String:
	if v is float and v == floorf(v): return str(int(v))
	if v is String: return '"%s"' % v
	if v is Array: return "[%s]" % ", ".join(v.map(func(x): return _literal(x)))
	return str(v)

func tokens_source() -> String:
	var L := PackedStringArray()
	L.append("class_name UiTokens")
	L.append("## GENERATED by tools/ui/gen_theme.gd from docs/design/tokens/tokens-v2.json. Do not edit by hand:")
	L.append("## re-export tokens with tools/ui/export_tokens_figma.js, then run the generator (SGODOT-211).")
	L.append("## Values marked in PENDING are provisional until the R1 design revisions (WP1a / WP1b) are accepted.")
	L.append("")
	L.append('const VERSION := "%s"' % t.meta.version)
	L.append('const STATUS := "%s"' % t.meta.status)
	L.append('const THEME_PATH := "%s"' % THEME_OUT)
	for w in t.font.weights:
		L.append('const FONT_%s_PATH := "%s"' % [w.to_upper(), FONT_OUT % int(t.font.weights[w])])
	L.append("")
	L.append("# Colours (semantic Figma variables first, then values Figma still hard-codes).")
	for k in t.color: L.append('const COLOR_%s := Color("%s")' % [const_name(k), String(t.color[k]).trim_prefix("#")])
	for group in ["opacity", "space", "radius", "stroke", "size", "dash", "motion"]:
		L.append("")
		L.append("# %s" % group.capitalize())
		for k in t[group]:
			var prefix: String = group.to_upper() + "_"
			L.append("const %s%s := %s" % [prefix, const_name(k), _literal(t[group][k])])
	L.append("")
	L.append("# Theme variations (set Control.theme_type_variation to one of these).")
	for k in t.font.styles: L.append('const STYLE_%s := &"%s"' % [const_name(k), k])
	for k in BUTTONS: L.append('const BUTTON_%s := &"%s"' % [const_name(k), k])
	for k in PANELS: L.append('const PANEL_%s := &"%s"' % [const_name(k), k])
	L.append("")
	L.append("const PENDING := {")
	for k in t.meta.pending: L.append('\t"%s": "%s",' % [k, t.meta.pending[k]])
	L.append("}")
	return "\n".join(L) + "\n"
