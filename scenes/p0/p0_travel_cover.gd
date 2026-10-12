class_name P0TravelCover
extends CanvasLayer
## The cross-city flight's cover (q(147), SGODOT-299; 不知火舞 on 299 31c4ceb5): over the map and the HUD while the camera
## flies, so the map, its pins and the HUD's keys take nothing. A cream pill 8 px under the HUD's second row names the
## city ahead (14 Bold) over its distance rolling from 0 to the real km (q(132): `1,758 km`); under it `Tap to skip`
## (11, secondary) once the take-off's first 0.5 s are past — a tap anywhere then asks to land (skip_requested), the
## press that sent Fly is not taken for one.

signal skip_requested

const P0Travel := preload("res://modules/p0/p0_travel.gd")

## Above P0Ui's layer (10): the HUD's keys sit under it.
const LAYER := 11

var title: Label
var distance: Label
var hint: Label
var pill: PanelContainer
var _km := 0
var _skippable := false

func _init() -> void:
	name = "P0TravelCover"
	layer = LAYER
	var shield := Control.new()
	shield.name = "Shield"
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shield.gui_input.connect(_on_input)
	add_child(shield)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_theme_constant_override("separation", 6)
	column.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	shield.add_child(column)
	pill = PanelContainer.new()
	pill.name = "Pill"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var box := StyleBoxFlat.new()
	box.bg_color = UiTokens.COLOR_SURFACE
	box.set_corner_radius_all(UiTokens.RADIUS_PILL)
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	box.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
	box.shadow_size = 8
	pill.add_theme_stylebox_override("panel", box)
	column.add_child(pill)
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 0)
	pill.add_child(lines)
	title = GameUi.label("", 14, UiTokens.COLOR_TEXT)
	title.name = "City"
	title.add_theme_font_override("font", load(UiTokens.FONT_BOLD_PATH))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.add_child(title)
	distance = GameUi.label("", 12, UiTokens.COLOR_SECONDARY)
	distance.name = "Distance"
	distance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.add_child(distance)
	hint = GameUi.label("Tap to skip", 11, UiTokens.COLOR_SECONDARY)
	hint.name = "Hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate.a = 0.0
	column.add_child(hint)

## The city ahead, its distance and where the pill hangs (px from the top: 8 under the HUD's second row).
func open(city: String, km: int, top: float) -> void:
	_km = maxi(0, km)
	title.text = city
	(get_node("Shield/Column") as Control).offset_top = top
	show_progress(0.0)

## t: the flight's seconds so far. The distance rolls up with the take-off and the flight (in place before landing);
## the hint and skipping come in after the take-off's first 0.5 s.
func show_progress(t: float) -> void:
	var p := clampf(t / (P0TravelFlight.UP_S + P0TravelFlight.FLY_S), 0.0, 1.0)
	distance.text = "%s km" % P0Travel.grouped(roundi(_km * (1.0 - (1.0 - p) * (1.0 - p))))
	_skippable = t >= P0TravelFlight.UP_S
	hint.modulate.a = 1.0 if _skippable else 0.0

func skippable() -> bool:
	return _skippable

func _on_input(e: InputEvent) -> void:
	var released := (e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed) \
		or (e is InputEventMouseButton and not (e as InputEventMouseButton).pressed)
	if released and _skippable: skip_requested.emit()
