class_name UiTagPill
extends PanelContainer
## UI v3 tag pill (C-P3 / C-N3, C-105): 28 high, `surface/tag` pill, `type/label` white, 12 in on each side and a
## 6 px tail on its left pointing back at the hero object or the portrait. `Bag`, `Market · Jasmine`. Display only.

const _TAIL := 6.0

var text := "": set = set_text
var _label: Label

func _init(text_ := "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = UiTokens.PANEL_TAG_PILL
	custom_minimum_size.y = UiTokens.SIZE_TAG_H
	_label = UiKit.label("", UiTokens.STYLE_TYPE_LABEL_ON_DARK)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	text = text_

func set_text(v: String) -> void:
	text = v
	if _label != null: _label.text = v

func label() -> Label: return _label

func _draw() -> void:
	var y := size.y * 0.5
	draw_colored_polygon(PackedVector2Array([Vector2(_TAIL, y - _TAIL), Vector2(-_TAIL * 0.5, y + _TAIL * 0.5),
		Vector2(_TAIL, y + _TAIL * 0.5)]), UiTokens.COLOR_SURFACE_TAG)
