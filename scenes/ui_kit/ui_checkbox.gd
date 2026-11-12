class_name UiCheckbox
extends MarginContainer
## Checkbox 9:104780 (Gensen Refactor; the first launch's consent row, SGODOT-491 / q(312) A): a 24 box, 10 off its
## line (Bold 14, text, wrapping, its top on the box's), 10 above and below — at least the 44 a finger needs, and the
## whole row is the key. Off: white, a 2 px disabled-ink edge, radius 7; on: primary filled, a white tick 16 in it.
## `links`: words of the line drawn as links in info blue (`Terms of Service`, `Privacy Policy`); a tap on one says
## which (link_pressed) and leaves the box as it was. The line and its links go through the table here, the links found
## in the line by their own Chinese (the table keeps the two together: test_p0_acc_copy); the row's own nodes are not
## translated again.

signal toggled(on: bool)
signal link_pressed(index: int)

const BOX := 24.0
const TICK := 16.0
const GAP := 10
const PAD := 10
const RADIUS := 7.0
const EDGE := 2
const TICK_ICON := preload("res://assets/ui/kit_icons/check.svg")

var checked := false: set = set_checked
var text := ""
var links: Array = []
var box: Panel
var line: RichTextLabel
var _tick: TextureRect
var _link_hit := false

func _init(text_ := "", links_: Array = []) -> void:
	text = text_
	links = links_
	name = "Checkbox"
	mouse_filter = Control.MOUSE_FILTER_STOP
	for side in ["top", "bottom"]: add_theme_constant_override("margin_" + side, PAD)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", GAP)
	add_child(row)
	box = Panel.new()
	box.name = "Box"
	box.custom_minimum_size = Vector2(BOX, BOX)
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(box)
	_tick = UiKit.icon(TICK_ICON, TICK)
	_tick.name = "Tick"
	_tick.position = Vector2.ONE * (BOX - TICK) * 0.5
	box.add_child(_tick)
	line = RichTextLabel.new()
	line.name = "Line"
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_PASS   # a link's tap is its own; the rest falls through to the row
	line.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # translated here, once
	line.add_theme_font_override(&"normal_font", UiKit.font(&"bold"))
	line.add_theme_font_size_override(&"normal_font_size", 14)
	line.add_theme_color_override(&"default_color", UiTokens.COLOR_TEXT)
	line.meta_underlined = false
	line.meta_clicked.connect(func(meta):
		_link_hit = true
		link_pressed.emit(int(meta)))
	row.add_child(line)
	_write()
	set_checked(false)

func set_checked(on: bool) -> void:
	checked = on
	if box == null: return
	var sb := UiStyleBox.make(UiTokens.COLOR_PRIMARY if on else UiTokens.COLOR_SURFACE_RAISED, RADIUS,
		UiTokens.COLOR_PRIMARY if on else UiTokens.COLOR_DISABLED_INK, EDGE)
	box.add_theme_stylebox_override(&"panel", sb)
	_tick.visible = on

## The line as the screen's language writes it, its links where their own words are in it.
func _write() -> void:
	line.clear()
	var whole := tr(text)
	var spans: Array = []   # [start, end, index], in order
	for i in links.size():
		var word := tr(str(links[i]))
		var at := whole.find(word)
		if at >= 0: spans.append([at, at + word.length(), i])
	spans.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	var from := 0
	for s in spans:
		if int(s[0]) < from: continue
		line.add_text(whole.substr(from, int(s[0]) - from))
		line.push_meta(int(s[2]))
		line.push_color(UiTokens.COLOR_INFO)
		line.add_text(whole.substr(int(s[0]), int(s[1]) - int(s[0])))
		line.pop()
		line.pop()
		from = int(s[1])
	line.add_text(whole.substr(from))

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and line != null: _write()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		accept_event()
		if _link_hit:   # the line's link took this tap
			_link_hit = false
			return
		set_checked(not checked)
		toggled.emit(checked)
