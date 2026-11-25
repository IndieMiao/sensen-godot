extends SceneTree
## Generates the UI kit theme from design tokens (SGODOT-211, WP7-A §4; v3 since C-105):
##   docs/design/tokens/tokens-v2.json
##   + docs/design/tokens/tokens-v3.json ->  assets/ui/gensen_theme.tres
##                                          assets/ui/fonts/nunito_w400|700|800.tres
##                                          modules/ui/kit/ui_tokens.gd
## Run after every token export:  godot --headless --path . --script tools/ui/gen_theme.gd
## Components never hard-code values; they read UiTokens and the theme variations named here.

const UiStyleBoxScript := preload("res://modules/ui/kit/ui_style_box.gd")
const TOKENS := "res://docs/design/tokens/tokens-v2.json"
## UI v3 (C-84 D-177, owner Q-121): read on top of v2. v2 names listed in ALIASES now hold the v3 value (kept one
## version, docs/design/ui-v3-2026-11-24 §2.6 / §7.2); every v3 token is also emitted under its own path name
## (COLOR_SURFACE_PAPER, RADIUS_LG, SPACE_S4, SIZE_PANEL_W, MOTION_DURATION_BASE_MS …). A v3 name that meets a v2
## name of another meaning (a v2 layout this card keeps) gets a `_V3` suffix: SIZE_HUD_AVATAR_V3, and the v3 float
## colours (bright, for outlined text over the scene: COLOR_FLOAT_COINS_V3), apart from the v2 floats' cream pills.
const TOKENS_V3 := "res://docs/design/tokens/tokens-v3.json"
const ALIASES := {
	"color": {"surface": "surface/paper", "surfaceRaised": "surface/raised", "text": "text/primary",
		"secondary": "text/secondary", "muted": "text/muted", "primary": "action/primary",
		"primaryPressed": "action/primaryPressed", "primaryTint": "action/primaryTint", "disabled": "action/disabled",
		"disabledInk": "action/disabledInk", "danger": "action/danger", "scrimModal": "scrim/modal",
		"scrimDrawer": "scrim/drawer", "unreadBadge": "badge/unread", "energyBonus": "hud/energyBonus"},
	"radius": {"card": "lg", "sheet": "xl", "bagDrawerTop": "xl", "counterDrawerTop": "xl", "cell": "md",
		"hudChip": "md", "pinMenu": "lg", "chip": "pill", "pill": "pill"},
}
## Values the v3 spec states outside its token table, and inks derived from its rules (C-105, on the card):
## - primaryInk: text in the action colour on paper / tint. S-3 keeps lime for fills; lime text is 1.9:1 on paper,
##   so the v2 green-text uses read this darker lime, 4.9:1 (§2.1's 4.5:1 rule).
## - scrim: the v2 base scrim colour now the v3 scrim's (#17150F), with its v2 opacity tokens; scrimModal opacity 0.60.
## - onAction outline: §2.1 exception (Q-121 item 1), white ExtraBold on lime with a 1.5 #3F5A12 @0.5 outline.
## - secondaryEdge: C-B2 secondary button's 1.5 outline #CFCBBE; close glyph C-P4 #555550.
const DERIVED := {"primaryInk": "#4A7318", "scrim": "#17150F", "onActionOutline": "#3F5A1280",
	"secondaryEdge": "#CFCBBE", "closeGlyph": "#555550"}
const ON_ACTION_OUTLINE := 3     # Label outline_size: 1.5 px on each side of the glyph
const FLOAT_OUTLINE := 4         # C-W5 float text: 2 px outline
const THEME_OUT := "res://assets/ui/gensen_theme.tres"
const TOKENS_OUT := "res://modules/ui/kit/ui_tokens.gd"
const FONT_OUT := "res://assets/ui/fonts/nunito_w%d.tres"

## Theme variations beyond the text styles. Order is the order they appear in UiTokens.
const BUTTONS := ["CmdPrimary", "CmdSecondary", "CmdDestructive", "CmdDangerSecondary", "CmdBlocked",
	"CmdPrimaryCompact", "CmdSecondaryCompact", "CmdDestructiveCompact", "CmdDangerSecondaryCompact", "CmdBlockedCompact",
	"NavRow", "NavCompact", "Dismiss", "CloseRound", "FilterChip", "SegmentTab", "CtaBar", "GlassRound"]
const PANELS := ["Sheet", "InfoSheet", "Card", "HudChip", "ToastPanel", "Badge",
	"Glass", "GlassStrong", "ModalPanel", "NpcCard", "TagPill", "PanelHeader"]
## v3 type scale (§2.2) as Label variations: path -> [variation, weight]. `body` is regular and bold.
const TYPE_STYLES := {"display": ["TypeDisplay", "extrabold"], "title": ["TypeTitle", "extrabold"],
	"headline": ["TypeHeadline", "extrabold"], "body": ["TypeBody", "regular"], "bodyBold": ["TypeBodyBold", "bold"],
	"button": ["TypeButton", "extrabold"], "label": ["TypeLabel", "bold"], "hudNumber": ["TypeHudNumber", "extrabold"],
	"caption": ["TypeCaption", "bold"], "micro": ["TypeMicro", "extrabold"]}
## White text variations for dark glass, tags and the action colour: base style -> variation; *OnAction ones carry
## the §2.1 outline, TypeFloat the C-W5 float outline.
const ON_DARK := {"label": "TypeLabelOnDark", "hudNumber": "TypeHudNumberOnDark", "caption": "TypeCaptionOnDark",
	"micro": "TypeMicroOnDark", "button": "TypeButtonOnAction", "headline": "TypeHeadlineOnAction"}

var t: Dictionary
var t3: Dictionary
var fonts := {}

func _init() -> void:
	t = load_tokens()
	t3 = load_tokens_v3()
	_apply_aliases()
	_build_fonts()
	var theme := build_theme()
	var err := ResourceSaver.save(theme, THEME_OUT)
	if err != OK: push_error("gen_theme: cannot save theme (%d)" % err); quit(1); return
	var f := FileAccess.open(TOKENS_OUT, FileAccess.WRITE)
	f.store_string(tokens_source())
	f.close()
	print("gen_theme: wrote %s, %s and 3 font variations from %s %s + %s %s" % [THEME_OUT, TOKENS_OUT, TOKENS,
		t.meta.version, TOKENS_V3, t3.meta.version])
	quit()

static func load_tokens() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(TOKENS))
	assert(data is Dictionary and int(data.meta.schema) == 2, "tokens-v2.json missing or wrong schema")
	return data

static func load_tokens_v3() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(TOKENS_V3))
	assert(data is Dictionary and int(data.meta.schema) == 3, "tokens-v3.json missing or wrong schema")
	return data

func _apply_aliases() -> void:
	apply_aliases(t, t3)

## The v2 keys in ALIASES take their v3 values; the scrim base colour and the modal scrim opacity follow v3.
static func apply_aliases(v2: Dictionary, v3: Dictionary) -> Dictionary:
	for k in ALIASES.color: v2.color[k] = String(v3.color[ALIASES.color[k]].value)
	for k in ALIASES.radius: v2.radius[k] = v3.radius[ALIASES.radius[k]].value
	v2.color["scrim"] = DERIVED.scrim
	v2.opacity["scrimModal"] = snappedf(Color.html(v3.color["scrim/modal"].value).a, 0.01)
	return v2

## tokens-v2 as UiTokens holds it: the v2 names with the v3 aliases applied.
static func merged_tokens() -> Dictionary:
	return apply_aliases(load_tokens(), load_tokens_v3())

func c(key: String) -> Color: return Color.html(t.color[key])
## A v3 colour, by its path ("surface/paper").
func c3(key: String) -> Color: return Color.html(t3.color[key].value)
func r3(key: String) -> float: return float(t3.radius[key].value)
func s3(key: String) -> float: return float(t3.size[key].value)
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
	_type_v3(th)
	_buttons(th)
	_panels(th)
	return th

## v3 type scale (§2.2) and its white variants (§2.1).
func _type_v3(th: Theme) -> void:
	var styles: Dictionary = t3.font.styles.duplicate()
	styles["bodyBold"] = styles.body
	for path in TYPE_STYLES:
		var st: Dictionary = styles[path]
		_type_variation(th, TYPE_STYLES[path][0], TYPE_STYLES[path][1], st, c("text"))
	for path in ON_DARK:
		var name: String = ON_DARK[path]
		_type_variation(th, name, TYPE_STYLES[path][1], styles[path], c3("text/onDark"))
		if name.ends_with("OnAction"): _outline(th, name, Color.html(DERIVED.onActionOutline), ON_ACTION_OUTLINE)
	# C-W5: the float's number at the 14 step, ExtraBold, white with a 2 px float/outline.
	_type_variation(th, "TypeFloat", "extrabold", {"size": 14, "lineHeight": styles.hudNumber.lineHeight}, c3("float/default"))
	_outline(th, "TypeFloat", c3("float/outline"), FLOAT_OUTLINE)

func _type_variation(th: Theme, name: String, weight: String, st: Dictionary, ink: Color) -> void:
	th.set_type_variation(name, "Label")
	th.set_font("font", name, fonts[weight])
	th.set_font_size("font_size", name, int(st.size))
	th.set_color("font_color", name, ink)
	th.set_constant("line_spacing", name, _line_spacing(st))

func _outline(th: Theme, name: String, color: Color, size_: int) -> void:
	th.set_color("font_outline_color", name, color)
	th.set_constant("outline_size", name, size_)

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
	# v3 (C-B1–C-B4): lime primary and the danger key carry white ExtraBold with the §2.1 outline; the secondary is
	# raised white with the 1.5 C-B2 edge and ink text, pressed to paper.
	var kinds := {
		"Primary": [c("primary"), Color.TRANSPARENT, c3("text/onDark")],
		"Secondary": [c3("surface/raised"), Color.html(DERIVED.secondaryEdge), c("text")],
		"Destructive": [c("danger"), Color.TRANSPARENT, c3("text/onDark")],
		"DangerSecondary": [c3("surface/raised"), c("danger"), c("danger")],
		"Blocked": [c("disabled"), Color.TRANSPARENT, c("secondary")],
	}
	var pressed_fill := {"Primary": c("primaryPressed"), "Secondary": c3("surface/paper")}
	var outlined := ["Primary", "Destructive"]
	for k in kinds:
		var bg: Color = kinds[k][0]
		var edge: Color = kinds[k][1]
		var ink: Color = kinds[k][2]
		var w := (float(t.stroke.selectedCell) if k == "Secondary" else stroke) if edge.a > 0.0 else 0.0
		for compact in [false, true]:
			var radius := r("compactCommand") if compact else pill
			var mk := func(fill: Color, line: Color) -> StyleBox:
				# Compact keys pad 14 a side (space.keyCompact, BARTER-2 2570:132291), the full-size ones the page's 16
				var b := _margins(_box(fill, radius, line, w), float(t.space.keyCompact if compact else t.space.page), 0.0)
				if compact: b.visual_height = s("commandCompact")
				return b
			_button(th, "Cmd%s%s" % [k, "Compact" if compact else ""],
				mk.call(bg, edge), mk.call(pressed_fill.get(k, bg.darkened(0.12)), edge.darkened(0.12)),
				mk.call(c("disabled"), Color.TRANSPARENT),
				"C12XB" if compact else "ButtonXB15", ink, ink, c("disabledInk"))
			if k in outlined:
				_outline(th, "Cmd%s%s" % [k, "Compact" if compact else ""], Color.html(DERIVED.onActionOutline), ON_ACTION_OUTLINE)
	var flat := func(pad_v: float) -> StyleBox: return _margins(_box(Color.TRANSPARENT, 0.0), 0.0, pad_v)
	var tint := c("primaryTint")
	var flat_pressed := func(pad_v: float) -> StyleBox: return _margins(_box(tint, r("card")), 0.0, pad_v)
	var nav_pad := (s("navigationRow") - float(t.font.styles.ButtonB15.size) * float(t.font.styles.ButtonB15.lineHeight)) * 0.5
	_button(th, "NavRow", flat.call(nav_pad), flat_pressed.call(nav_pad), flat.call(nav_pad), "ButtonB15", c("info"), c("info"), c("disabledInk"))
	# Compact/Navigation 633:41276: Bold 12 in color/info (`Gift ›`, `Sort · Type`, `Today's meal ›`).
	_button(th, "NavCompact", flat.call(0.0), flat_pressed.call(0.0), flat.call(0.0), "C12B", c("info"), c("info"), c("disabledInk"))
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
	# Toggle buttons: "pressed" is the selected look. Compact/Filter selected (2026-10-08, 安其拉 on 225): primary
	# tint with a primary outline and primary ink, never the command green.
	var chip_on := func() -> StyleBox:
		var b := _margins(_box(c("primaryTint"), r("chip"), c("primary"), stroke), float(t.space.row), 0.0)
		b.visual_height = s("filterChip")
		return b
	_button(th, "FilterChip", chip.call(c("surface")), chip_on.call(), chip.call(c("disabled")),
		"C11B", c("secondary"), Color.html(DERIVED.primaryInk), c("disabledInk"))
	# SegmentedTabs 1225:83884 (LOCK-13): segments sit on a border-coloured track (UiSegmentTab draws it); the
	# selected one is white with a primary outline (radius 14), never the command green. Labels are UiSegmentTab's.
	var seg_r := 14.0   # SegmentedTabs segment radius (WP1b, not exported yet)
	_button(th, "SegmentTab", _margins(_box(Color.TRANSPARENT, seg_r), float(t.space.within), 0.0),
		_margins(_box(c("surfaceRaised"), seg_r, c("primary"), stroke), float(t.space.within), 0.0),
		_margins(_box(Color.TRANSPARENT, seg_r), float(t.space.within), 0.0), "C12B", c("secondary"), Color.html(DERIVED.primaryInk), c("disabledInk"))
	# v3 C-N6: the NPC card's full-width action bar, 48 high, square top and the card's lg bottom corners. Without an
	# action it shows its reason and stays still (the caller disables it), still lime.
	var lg := r3("lg")
	var cta := func(fill: Color) -> StyleBox:
		var b := _margins(_box(fill, 0.0), float(t.space.page), 0.0)
		b.corner_radius = Vector4(0, 0, lg, lg)
		return b
	_button(th, "CtaBar", cta.call(c("primary")), cta.call(c("primaryPressed")), cta.call(c("primary")), "ButtonXB15",
		c3("text/onDark"), c3("text/onDark"), c3("text/onDark"))
	_outline(th, "CtaBar", Color.html(DERIVED.onActionOutline), ON_ACTION_OUTLINE)
	th.set_constant("h_separation", "CtaBar", int(t3.space.s4.value))
	# v3 C-R1: a 36 glass disc in the 44 hit area; pressed raises the glass from 0.62 to 0.75 (fillStrong is 0.78).
	var glass_pad := (float(t.size.close) - s3("hud/sideButton")) * 0.5
	var disc := func(fill: Color) -> StyleBox:
		var b: StyleBox = _box(fill, s3("hud/sideButton") * 0.5)
		b.inset = Vector4(glass_pad, glass_pad, glass_pad, glass_pad)
		return _margins(b, glass_pad, glass_pad)
	var glass_pressed := c3("glass/fill")
	glass_pressed.a = 0.75
	_button(th, "GlassRound", disc.call(c3("glass/fill")), disc.call(glass_pressed), disc.call(c3("glass/fill")),
		"ButtonXB15", c3("text/onDark"), c3("text/onDark"), c3("text/onDarkMuted"))

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
	# v3 (§4): glass under the scene's capsules (S-2, no edge, no shadow); paper panels with the e2 shadow; the tag pill;
	# the panel's header band (only its top corners round).
	var pill := r3("pill")
	_panel(th, "Glass", _margins(_box(c3("glass/fill"), pill), float(t3.space.s5.value), 0.0))
	_panel(th, "GlassStrong", _margins(_box(c3("glass/fillStrong"), r3("md")), float(t3.space.s4.value), 0.0))
	_panel(th, "ModalPanel", _shadow(_box(c3("surface/paper"), r3("xl")), "e2"))
	_panel(th, "NpcCard", _shadow(_box(c3("surface/paper"), r3("lg")), "e2"))
	_panel(th, "TagPill", _margins(_box(c3("surface/tag"), pill), float(t3.space.s5.value), 0.0))
	var header := _box(c3("surface/header"), 0.0)
	header.corner_radius = Vector4(r3("xl"), r3("xl"), 0, 0)
	_panel(th, "PanelHeader", header)

## The v3 elevation (§2.3): StyleBoxFlat shadow size ≈ blur ÷ 2, offset y = the drop.
func _shadow(b: StyleBox, level: String) -> StyleBox:
	var e: Dictionary = t3.elevation[level]
	if e.color == null: return b
	b.shadow_color = Color.html(e.color)
	b.shadow_size = float(e.blur) * 0.5
	b.shadow_offset = Vector2(0, float(e.offsetY))
	return b

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
	L.append("## GENERATED by tools/ui/gen_theme.gd from docs/design/tokens/tokens-v2.json + tokens-v3.json. Do not edit by")
	L.append("## hand: edit the JSON (v2: tools/ui/export_tokens_figma.js; v3: docs/design/ui-v3-2026-11-24), then run the generator.")
	L.append("## v2 names kept one version; those in gen_theme ALIASES hold the v3 value (C-105).")
	L.append("## Values marked in PENDING are provisional until the R1 design revisions (WP1a / WP1b) are accepted.")
	L.append("")
	L.append('const VERSION := "%s"' % t3.meta.version)
	L.append('const STATUS := "confirmed"')
	L.append('const VERSION_V2 := "%s"' % t.meta.version)
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
	_v3_source(L)
	L.append("")
	L.append("# Theme variations (set Control.theme_type_variation to one of these).")
	for k in t.font.styles: L.append('const STYLE_%s := &"%s"' % [const_name(k), k])
	for k in TYPE_STYLES: L.append('const STYLE_%s := &"%s"' % [const_name(TYPE_STYLES[k][0]), TYPE_STYLES[k][0]])
	for k in ON_DARK: L.append('const STYLE_%s := &"%s"' % [const_name(ON_DARK[k]), ON_DARK[k]])
	L.append('const STYLE_TYPE_FLOAT := &"TypeFloat"')
	for k in BUTTONS: L.append('const BUTTON_%s := &"%s"' % [const_name(k), k])
	for k in PANELS: L.append('const PANEL_%s := &"%s"' % [const_name(k), k])
	L.append("")
	L.append("const PENDING := {")
	for k in t.meta.pending: L.append('\t"%s": "%s",' % [k, t.meta.pending[k]])
	L.append("}")
	return "\n".join(L) + "\n"

static func _ease_literal(godot: String) -> String:
	var trans := "Tween.TRANS_LINEAR"
	var ease := "Tween.EASE_IN_OUT"
	for part in godot.split("+"):
		var p := part.strip_edges()
		if p.begins_with("TRANS_"): trans = "Tween." + p
		elif p.begins_with("EASE_"): ease = "Tween." + p
	return "[%s, %s]" % [trans, ease]

## v3 tokens under their path names; a name a v2 token already holds is skipped when equal (an alias) and suffixed
## `_V3` when the v2 value is another one (a v2 layout kept, e.g. SIZE_HUD_AVATAR).
func _v3_source(L: PackedStringArray) -> void:
	var taken := {}
	for line in L:
		if line.begins_with("const "): taken[line.get_slice(" ", 1)] = line.get_slice(":= ", 1)
	var add := func(name: String, literal: String) -> void:
		if taken.has(name):
			if taken[name] == literal: return
			name += "_V3"
		taken[name] = literal
		L.append("const %s := %s" % [name, literal])
	L.append("")
	L.append("# UI v3 (docs/design/tokens/tokens-v3.json, C-84 D-177 / Q-121): colours by path, then derived inks.")
	for k in t3.color: add.call("COLOR_%s" % const_name(k), 'Color("%s")' % String(t3.color[k].value).trim_prefix("#"))
	add.call("COLOR_PRIMARY_INK", 'Color("%s")' % DERIVED.primaryInk.trim_prefix("#"))
	add.call("COLOR_ON_ACTION_OUTLINE", 'Color("%s")' % DERIVED.onActionOutline.trim_prefix("#"))
	add.call("COLOR_SECONDARY_EDGE", 'Color("%s")' % DERIVED.secondaryEdge.trim_prefix("#"))
	add.call("COLOR_CLOSE_GLYPH", 'Color("%s")' % DERIVED.closeGlyph.trim_prefix("#"))
	for group in ["radius", "space", "size"]:
		L.append("")
		L.append("# v3 %s" % group)
		for k in t3[group]: add.call("%s_%s" % [group.to_upper(), const_name(k)], _literal(t3[group][k].value))
	L.append("")
	L.append("# v3 elevation (§2.3): shadow colour, blur, drop.")
	for k in t3.elevation:
		var e: Dictionary = t3.elevation[k]
		if e.color == null: continue
		add.call("ELEVATION_%s_COLOR" % k.to_upper(), 'Color("%s")' % String(e.color).trim_prefix("#"))
		add.call("ELEVATION_%s_BLUR" % k.to_upper(), _literal(float(e.blur)))
		add.call("ELEVATION_%s_OFFSET_Y" % k.to_upper(), _literal(float(e.offsetY)))
	L.append("")
	L.append("# v3 motion (§2.5): durations in ms, easings as [Tween.TransitionType, Tween.EaseType].")
	for k in t3.motion.duration: add.call("MOTION_DURATION_%s_MS" % const_name(k), _literal(float(t3.motion.duration[k].ms)))
	for k in t3.motion.easing: add.call("MOTION_EASING_%s" % const_name(k), _ease_literal(String(t3.motion.easing[k].godot)))
	for k in t3.motion:
		if k in ["duration", "easing"]: continue
		if t3.motion[k] is Dictionary:
			for sub in t3.motion[k]: add.call("MOTION_%s_%s" % [const_name(k), const_name(sub)], _literal(float(t3.motion[k][sub])))
		else: add.call("MOTION_%s" % const_name(k), _literal(float(t3.motion[k])))
