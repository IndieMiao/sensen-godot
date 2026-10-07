class_name UiNeedSource
extends PanelContainer
## NeedSource (SGODOT-222; Gensen Refactor/NeedSource 1092:77266, LOCK-10 / LOCK-08): shown only after a
## UiNeedTile is tapped, anchored just above it. One line of source + `Show ›`. Show only moves the camera
## or highlights the place; it never walks the player, never opens a panel and never acts. Emits `show_pressed`.

signal show_pressed

const _PAD := Vector4(14, 6, 6, 6)   # NeedSource main: padding left / top / right / bottom
const _GAP := 10

var text := "": set = set_text

var _label: Label
var _show: UiCommandButton

## can_show false hides Show when there is nothing to point the camera at (e.g. a place on the map).
func _init(text_: String = "", can_show := true) -> void:
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_PILL, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	add_theme_stylebox_override(&"panel", box.with_margins(_PAD.x, _PAD.y, _PAD.z, _PAD.w))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", _GAP)
	add_child(row)
	_label = UiKit.label("", UiTokens.STYLE_BODY_B14)
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_label)
	_show = UiCommandButton.new("Show ›", UiCommandButton.Kind.SECONDARY, true)
	_show.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_show.activated.connect(func(): show_pressed.emit())
	_show.visible = can_show
	row.add_child(_show)
	text = text_

func set_text(v: String) -> void:
	text = v
	if _label != null: _label.text = v

## Pops a source line just above `anchor` (global rect) inside `host`; a tap anywhere else closes it.
## Returns the popup layer (free it to close); `on_show` runs after Show, then the popup closes.
static func popup(host: Control, anchor: Rect2, source: String, on_show: Callable = Callable()) -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and not e.pressed: layer.queue_free())
	host.add_child(layer)
	var pill := UiNeedSource.new(source, on_show.is_valid())
	pill.custom_minimum_size.x = UiTokens.SIZE_TOAST_W
	layer.add_child(pill)
	pill.show_pressed.connect(func():
		if on_show.is_valid(): on_show.call()
		layer.queue_free())
	var place := func() -> void:
		var area := host.get_global_rect()
		var w := minf(pill.get_combined_minimum_size().x, area.size.x - UiTokens.SPACE_PAGE * 2.0)
		var h := pill.get_combined_minimum_size().y
		var x := clampf(anchor.get_center().x - w * 0.5, area.position.x + UiTokens.SPACE_PAGE, area.end.x - UiTokens.SPACE_PAGE - w)
		var y := maxf(area.position.y, anchor.position.y - h - UiTokens.SPACE_WITHIN)
		pill.global_position = Vector2(x, y)
		pill.size = Vector2(w, h)
	place.call_deferred()
	return layer
