class_name UiQualityBadge
extends PanelContainer
## QualityBadge 1178:82154 (SGODOT-226): the cooking quality next to a dish name — ★ Good / ★★ Perfect on a gold
## pill. Plain shows nothing (quality 0 hides the badge). Used on dish reveal cards, Warming Cabinet rows and
## Cookbook Best. Display only.

const _PAD_X := 8.0
const _PAD_Y := 2.0
const _RADIUS := 10.0
const LABELS := ["", "★ Good", "★★ Perfect"]

## 0 Plain (hidden), 1 Good, 2 Perfect.
var quality := 1: set = set_quality

var _label: Label

func _init(quality_ := 1) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_QUALITY_GOLD, _RADIUS).with_margins(_PAD_X, _PAD_Y, _PAD_X, _PAD_Y))
	_label = UiKit.label("", UiTokens.STYLE_CAPTION_XB12)
	add_child(_label)
	quality = quality_

func set_quality(v: int) -> void:
	quality = clampi(v, 0, 2)
	if _label == null: return
	_label.text = LABELS[quality]
	visible = quality > 0
