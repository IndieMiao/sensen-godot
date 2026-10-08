class_name UiPointer
extends Control
## The small downward pointer under floating cards (SGODOT-221): EntryCard 1468:94344 and PinMenu 1141:80291
## both draw a SIZE_POINTER_W × SIZE_POINTER_H triangle in the card fill with the card's border on its two
## slanted edges, overlapping the card's bottom edge by one stroke so the border reads as continuous.

var fill := UiTokens.COLOR_SURFACE: set = set_fill
var edge := UiTokens.COLOR_BORDER: set = set_edge

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(UiTokens.SIZE_POINTER_W, UiTokens.SIZE_POINTER_H)
	size = custom_minimum_size

func set_fill(v: Color) -> void: fill = v; queue_redraw()
func set_edge(v: Color) -> void: edge = v; queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	var stroke := float(UiTokens.STROKE_DEFAULT)
	# Start one stroke above the top so the card's border line is covered where the pointer joins it.
	draw_colored_polygon(PackedVector2Array([Vector2(0, -stroke), Vector2(w, -stroke), Vector2(w * 0.5, h)]), fill)
	draw_polyline(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.5, h), Vector2(w, 0)]), edge, stroke, true)
