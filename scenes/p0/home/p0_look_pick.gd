class_name P0LookPick
extends UiDrawer
## LOOK-PICK (SGODOT-282; 不知火舞 49498df6 / e2d76a7c, q(24) / q(112); Figma row 63, 2199:32862): a Homestead look
## stage's two looks, a (timber) and b (stone), over the farm. After the HOME-2 banner of Lv3 / 5 / 8 / 10 (P0Runtime
## queues it behind the banner) and from HOME-1's Looks rows. A standard bottom drawer with its handle; the camera stays
## where it is, so the farmhouse is in view above it. Title `Lv5 look · Porch` (17 ExtraBold) with ✕ (44), subtitle
## `Pick one · free to change later` (13 Bold, secondary), two LookOption cards (158 wide, 12 apart, as tall as the
## taller) and the full-width main key `Use Timber Porch` following the selection.
## A card tap previews that look on the real farmhouse (P0Ui.look_previewed → the farm swaps the stage's parts with a
## 0.3 s pop and dust); only the main key writes it (set_look). Closing — ✕, a drag down, a tap outside, Back — after the
## level-up (`first`) leaves look a (q(24)), the preview going back to a; from HOME-1 it changes nothing and goes back
## to HOME-1.

const SUBTITLE := "Pick one · free to change later"
const THUMB := "res://assets/p0/looks/look_lv%d_%s.png"   # baked offline (tools/dev/look_thumbs.gd), one per stage and look
const TITLE_SIZE := 17
const GAP := 12.0

var stage := {}          # content homestead.looks entry: {id, level, name, a, b}
var first := false       # opened by the level-up: closing = look a
var current := "a"       # the look the save has (from HOME-1) — what closing goes back to
var choice := "a"
var options := {}        # "a" / "b" → UiLookOption
var use_button: UiCommandButton
var _ui: P0Ui

## Open the card for `stage_id`. first: right after the upgrade (default a, closing = a); else from HOME-1 (default the
## current look, closing changes nothing and returns to HOME-1).
static func open(ui: P0Ui, stage_id: String, first_time := false) -> P0LookPick:
	var stage_ := P0Logic.look_stage(stage_id)
	if stage_.is_empty(): return null
	var d := P0LookPick.new(0.0)
	d._ui = ui
	d.stage = stage_
	d.first = first_time
	d.current = "a" if first_time else (P0Logic.look_of(ui.view, stage_id) if P0Logic.look_of(ui.view, stage_id) != "" else "a")
	d.choice = d.current
	d.pad = UiTokens.SPACE_PAGE
	d.theme = UiKit.theme()
	d.safe_bottom = ui.safe_bottom()
	d._build()
	d.close_requested.connect(d.dismiss)
	ui._open_modal(d, 0.0, true)   # no scrim: the farmhouse above is the preview
	ui.modal_kind = "look_pick"
	ui._modal_back = d.dismiss   # Back and a tap outside close it the card's way
	d.body.minimum_size_changed.connect(func(): d.height = d.body.get_combined_minimum_size().y + d.pad * 2.0)
	d.height = d.body.get_combined_minimum_size().y + d.pad * 2.0
	return d

func _build() -> void:
	body.add_theme_constant_override(&"separation", 0)
	var head := HBoxContainer.new()
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override(&"separation", 2)
	var title := UiKit.label("Lv%d look · %s" % [int(stage.level), str(stage.name)], UiTokens.STYLE_C14_XB)
	title.add_theme_font_size_override(&"font_size", TITLE_SIZE)
	title.name = "Title"
	titles.add_child(title)
	var sub := UiKit.label(SUBTITLE, UiTokens.STYLE_C13_B, UiTokens.COLOR_SECONDARY)
	sub.name = "Subtitle"
	titles.add_child(sub)
	head.add_child(titles)
	var close := UiCloseButton.new()
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(dismiss)
	head.add_child(close)
	body.add_child(head)
	body.add_child(_gap(GAP))
	var row := HBoxContainer.new()
	row.name = "Options"
	row.add_theme_constant_override(&"separation", int(GAP))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for look in ["a", "b"]:
		var o := UiLookOption.new(str(stage.get(look, "")), thumbnail(int(stage.level), look))
		o.name = "Look_" + look
		o.picked.connect(pick.bind(look))
		row.add_child(o)
		options[look] = o
	UiLookOption.pair(options.a, options.b)
	body.add_child(row)
	body.add_child(_gap(16.0))
	use_button = UiCommandButton.new("")
	use_button.sends = true   # set_look: Offline while offline (§10.7.1)
	use_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	use_button.activated.connect(use)
	body.add_child(use_button)
	_refresh()

static func thumbnail(level: int, look: String) -> Texture2D:
	var path := THUMB % [level, look]
	return load(path) if ResourceLoader.exists(path) else null

## A card tapped: select it and preview it on the farmhouse.
func pick(look: String) -> void:
	if look == choice: return
	choice = look
	_refresh()
	_ui.look_previewed.emit(str(stage.id), look)

## The main key: write the selection, keep it on the farmhouse, close (back to HOME-1 when opened from there).
## The preview stays up until the reply's view has this look (the farm lets it go then), so nothing flickers back.
func use() -> void:
	_ui.command.emit({"type": "set_look", "stage": str(stage.id), "look": choice})
	_leave()

## ✕, a drag down, a tap outside, Back: after the level-up = look a; from HOME-1 = no change.
func dismiss() -> void:
	_ui.look_previewed.emit(str(stage.id), "")
	_leave()

func _leave() -> void:
	if first: _ui.close_modal()
	else: _ui.open_home_panel()

func _refresh() -> void:
	for look in options: (options[look] as UiLookOption).selected = look == choice
	use_button.label = "Use %s" % str(stage.get(choice, ""))

static func _gap(h: float) -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, h)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g
