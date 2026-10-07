@tool
class_name UiStyleBox
extends StyleBox
## Flat rounded box with two things StyleBoxFlat cannot do (SGODOT-211):
## - `visual_height` / `inset`: draw the visible box smaller than the control, so a 34 px pill keeps a
##   44 px hit area however tall its container makes it;
## - `dashed`: dashed outline for empty / ghost slots (gameplay plan §10.3.1 "浅虚线幽灵格").
## Solid boxes delegate to an internal StyleBoxFlat; widths and radii round to whole pixels there.

@export var bg_color := Color.TRANSPARENT:
	set(v): bg_color = v; _dirty()
@export var border_color := Color.TRANSPARENT:
	set(v): border_color = v; _dirty()
@export var border_width := 0.0:
	set(v): border_width = v; _dirty()
## Per-corner radius: top-left, top-right, bottom-right, bottom-left.
@export var corner_radius := Vector4.ZERO:
	set(v): corner_radius = v; _dirty()
## Visible box inset from the control rect: left, top, right, bottom.
@export var inset := Vector4.ZERO:
	set(v): inset = v; _dirty()
## When > 0 the visible box is at most this tall, centred vertically (applied after `inset`).
@export var visual_height := 0.0:
	set(v): visual_height = v; _dirty()
@export var dashed := false:
	set(v): dashed = v; _dirty()
@export var dash := 4.0:
	set(v): dash = v; _dirty()
@export var gap := 3.0:
	set(v): gap = v; _dirty()
## Drop shadow (e.g. a lifted quick slot: COLOR_LIFT_SHADOW, SIZE_LIFT_SHADOW_RADIUS, SIZE_LIFT_SHADOW_OFFSET_Y).
@export var shadow_color := Color.TRANSPARENT:
	set(v): shadow_color = v; _dirty()
@export var shadow_size := 0.0:
	set(v): shadow_size = v; _dirty()
@export var shadow_offset := Vector2.ZERO:
	set(v): shadow_offset = v; _dirty()

var _flat: StyleBoxFlat

static func make(bg: Color, radius: float, border := Color.TRANSPARENT, width := 0.0) -> UiStyleBox:
	var b := UiStyleBox.new()
	b.bg_color = bg
	b.corner_radius = Vector4(radius, radius, radius, radius)
	b.border_color = border
	b.border_width = width
	return b

func with_inset(left: float, top: float, right: float, bottom: float) -> UiStyleBox:
	inset = Vector4(left, top, right, bottom)
	return self

func with_margins(left: float, top: float, right: float, bottom: float) -> UiStyleBox:
	content_margin_left = left
	content_margin_top = top
	content_margin_right = right
	content_margin_bottom = bottom
	return self

func visible_rect(rect: Rect2) -> Rect2:
	var r := Rect2(rect.position + Vector2(inset.x, inset.y),
		rect.size - Vector2(inset.x + inset.z, inset.y + inset.w))
	if visual_height > 0.0 and r.size.y > visual_height:
		r.position.y += (r.size.y - visual_height) * 0.5
		r.size.y = visual_height
	return r

func _dirty() -> void:
	_flat = null
	emit_changed()

func _ensure_flat() -> StyleBoxFlat:
	if _flat != null: return _flat
	_flat = StyleBoxFlat.new()
	_flat.bg_color = bg_color
	_flat.anti_aliasing = true
	_flat.corner_detail = 8
	_flat.corner_radius_top_left = roundi(corner_radius.x)
	_flat.corner_radius_top_right = roundi(corner_radius.y)
	_flat.corner_radius_bottom_right = roundi(corner_radius.z)
	_flat.corner_radius_bottom_left = roundi(corner_radius.w)
	if not dashed and border_width > 0.0 and border_color.a > 0.0:
		var w := maxi(1, roundi(border_width))
		_flat.border_color = border_color
		_flat.set_border_width_all(w)
	if shadow_color.a > 0.0 and shadow_size > 0.0:
		_flat.shadow_color = shadow_color
		_flat.shadow_size = roundi(shadow_size)
		_flat.shadow_offset = shadow_offset
	return _flat

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var r := visible_rect(rect)
	if r.size.x <= 0.0 or r.size.y <= 0.0: return
	if bg_color.a > 0.0 or (not dashed and border_width > 0.0) or shadow_color.a > 0.0:
		_ensure_flat().draw(to_canvas_item, r)
	if dashed and border_width > 0.0 and border_color.a > 0.0:
		_draw_dashes(to_canvas_item, r)

## Points along the rounded outline, inset by half the stroke so it stays inside the box.
func outline_points(r: Rect2) -> PackedVector2Array:
	var h := border_width * 0.5
	var box := r.grow(-h)
	var limit := minf(box.size.x, box.size.y) * 0.5
	var rad := [minf(corner_radius.x, limit), minf(corner_radius.y, limit), minf(corner_radius.z, limit), minf(corner_radius.w, limit)]
	var corners := [
		[box.position + Vector2(rad[0], rad[0]), PI, rad[0]],
		[Vector2(box.end.x - rad[1], box.position.y + rad[1]), PI * 1.5, rad[1]],
		[box.end - Vector2(rad[2], rad[2]), 0.0, rad[2]],
		[Vector2(box.position.x + rad[3], box.end.y - rad[3]), PI * 0.5, rad[3]],
	]
	var pts := PackedVector2Array()
	for c in corners:
		var steps := 8 if c[2] > 0.0 else 0
		for i in steps + 1:
			var a: float = c[1] + (PI * 0.5) * (float(i) / maxf(1.0, steps))
			pts.append(c[0] + Vector2(cos(a), sin(a)) * c[2])
	pts.append(pts[0])
	return pts

func _draw_dashes(ci: RID, r: Rect2) -> void:
	var pts := outline_points(r)
	var on := true
	var left := dash
	var seg := PackedVector2Array([pts[0]])
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var len := a.distance_to(b)
		var t := 0.0
		while len - t > left:
			t += left
			var p := a.lerp(b, t / len)
			if on:
				seg.append(p)
				RenderingServer.canvas_item_add_polyline(ci, seg, [border_color], border_width, true)
			seg = PackedVector2Array([p])
			on = not on
			left = dash if on else gap
		left -= len - t
		if on: seg.append(b)
		else: seg = PackedVector2Array([b])
	if on and seg.size() > 1:
		RenderingServer.canvas_item_add_polyline(ci, seg, [border_color], border_width, true)
