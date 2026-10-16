extends VBoxContainer
## The Passport's Postcards page (PASS-POSTCARDS 2627:134311; q(171) ⑥, 不知火舞 on 284): `Postcards · 3/11`, then
## a cell per resident, three to a row, in the residents table's order (P0Kindred.postcards):
##   earned    surfaceRaised, a 1 px border: the PostcardStamp (their face, or their initial), the name (C12 XB, line 16)
##             and their Kindred line in curly quotes (Bold Italic 10, line 13, secondary; the frame's values), uncut
##   unearned  no fill, a dashed border: the grey stamp and `Kindred · ?` (C12 B, secondary)
## Every cell is as tall as the longest Kindred line of the residents on the page needs (3 lines in P1), earned or not,
## so the grid never shifts as postcards come (不知火舞 on 284). Read-only: a cell does nothing. Built from the view (refresh follows it).
## Preloaded, no class_name (a new global class needs an editor import).

const Kindred := preload("res://modules/p0/p0_kindred.gd")
const Stamp := preload("res://scenes/p0/panels/p0_postcard_stamp.gd")
const COLS := 3
const GAP := 6.0
const _PAD := Vector4(8, 12, 8, 12)   # left, top, right, bottom
const _STACK := 4                      # stamp → name → line
const _RADIUS := 12

var view := {}
var model := {}
var grid: GridContainer
var _count: Label
var _key := 0

func _init(view_: Dictionary = {}) -> void:
	name = "Postcards"
	add_theme_constant_override(&"separation", 8)
	_count = UiKit.label("", UiTokens.STYLE_C12_XB)
	_count.name = "Count"
	add_child(_count)
	grid = GridContainer.new()
	grid.name = "Grid"
	grid.columns = COLS
	grid.add_theme_constant_override(&"h_separation", int(GAP))
	grid.add_theme_constant_override(&"v_separation", int(GAP))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.resized.connect(_fit)   # the cells' width is known once the page is laid out
	add_child(grid)
	refresh(view_)

## Follows the view; rebuilds only when the page's content changed.
func refresh(v: Dictionary) -> void:
	view = v
	model = Kindred.postcards(view)
	var key := hash(model)
	if key == _key: return
	_key = key
	_count.text = str(model.count)
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	for cell in model.cells: grid.add_child(_cell(cell))
	_fit.call_deferred()

## Every cell to the height the longest Kindred line needs at the cells' width (the page's residents, earned or not). Run
## again whenever the grid's width changes; the cells keep the width the grid gives them.
func _fit() -> void:
	if not is_inside_tree() or grid.get_child_count() == 0: return
	var w := (grid.size.x - GAP * (COLS - 1)) / COLS
	if w <= 0.0: return
	var text_w := w - _PAD.x - _PAD.z
	# measured as the cells' own labels lay out (their theme sizes and line spacing): hidden probes styled the same way,
	# the line one wrapping at the cells' text width
	var probe := _line_label("x")
	var name_probe := _name_label("x")
	probe.visible = false
	name_probe.visible = false
	add_child(probe)
	add_child(name_probe)
	probe.size = Vector2(text_w, 0)
	var name_h := name_probe.get_minimum_size().y
	var tallest := 0.0
	for c in model.cells:   # the residents on the page (q(193)): Mira's line joins with her in P2
		probe.text = quoted(str(P0Logic.content().residents[c.id].get("lines", {}).get("Kindred", "")))
		tallest = maxf(tallest, probe.get_minimum_size().y)
	remove_child(probe)
	remove_child(name_probe)
	probe.free()
	name_probe.free()
	var h := _PAD.y + Stamp.PASSPORT.y + _STACK + name_h + _STACK + tallest + _PAD.w
	for c in grid.get_children(): (c as Control).custom_minimum_size.y = ceilf(h)

## A cell's name: ExtraBold 12, line 16 (PASS-POSTCARDS).
static func _name_label(text: String) -> Label:
	var l := UiKit.label(text, UiTokens.STYLE_C12_XB)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

## A cell's Kindred line: Bold Italic 10, line 13, secondary, wrapping (PASS-POSTCARDS; 不知火舞 on 284).
static func _line_label(text: String) -> Label:
	var l := UiKit.label(text, UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override(&"font", UiKit.bold_italic())
	return l

## `“Best friend on the whole route. Don't tell the pigeons.”`
static func quoted(line: String) -> String:
	return "“%s”" % line if line != "" else ""

func _cell(c: Dictionary) -> PanelContainer:
	var earned := bool(c.earned)
	var cell := PanelContainer.new()
	cell.name = "Cell_" + str(c.id)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, _RADIUS, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT) if earned \
		else UiStyleBox.make(Color.TRANSPARENT, _RADIUS)
	cell.add_theme_stylebox_override(&"panel", box.with_margins(_PAD.x, _PAD.y, _PAD.z, _PAD.w))
	if not earned: cell.draw.connect(func(): _dash(cell))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override(&"separation", _STACK)
	var stamp: Control = Stamp.new(str(c.id), earned, Stamp.PASSPORT)
	stamp.name = "Stamp"
	stamp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(stamp)
	if earned:
		var who := _name_label(str(c.name))
		who.name = "Name"
		col.add_child(who)
		var line := _line_label(quoted(str(c.text)))
		line.name = "Line"
		col.add_child(line)
	else:
		var unknown := UiKit.label("Kindred · ?", UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
		unknown.name = "Unknown"
		unknown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(unknown)
	cell.add_child(col)
	return cell

## An unearned cell's dashed border (color/border, 1 px, dashes 4 / gaps 3), drawn round its rounded rect.
static func _dash(cell: Control) -> void:
	var r := Rect2(Vector2(0.5, 0.5), cell.size - Vector2.ONE)
	var rad := float(_RADIUS)
	var path := PackedVector2Array()
	var corners := [[Vector2(r.end.x - rad, r.position.y + rad), -PI / 2], [Vector2(r.end.x - rad, r.end.y - rad), 0.0],
		[Vector2(r.position.x + rad, r.end.y - rad), PI / 2], [Vector2(r.position.x + rad, r.position.y + rad), PI]]
	for k in corners:
		for i in 7: path.append((k[0] as Vector2) + Vector2.from_angle(float(k[1]) + PI / 2 * i / 6.0) * rad)
	path.append(path[0])
	var on := true
	var left := 4.0
	for i in path.size() - 1:
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var seg := a.distance_to(b)
		var t := 0.0
		while t < seg:
			var step := minf(left, seg - t)
			if on: cell.draw_line(a.lerp(b, t / seg), a.lerp(b, (t + step) / seg), UiTokens.COLOR_BORDER, 1.0, true)
			t += step
			left -= step
			if left <= 0.0:
				on = not on
				left = 4.0 if on else 3.0
