class_name UiBlueprintCard
extends PanelContainer
## BlueprintCard 1434:93844 (SGODOT-231 B2-06, 安其拉 · WP4): one workbench recipe per card.
##   header    icon tile (44, icon 32) · name + effect · yield (`You get 2`, Supplies only)
##   materials NEED-TILE M per cost (LOCK-10: short = amber ring and number); hidden once a tool is owned
##   footer    have (`You have 6`, Supplies only) · one Compact/Command button: Craft (primary), Equip (secondary),
##             or the reason / done state in the neutral look (`Need 1 more Copper Ore`, `No room · free a slot
##             first`, `Farming Lv3`, `Equipped`, `Owned · always on`) — those still take the tap (LOCK-10).
## The card only lays the recipe out; its owner sends the command (`pressed`), toasts a reason
## (`unavailable_pressed`) and shows a tile's source (`material_pressed`, NeedSource above the tile).

signal pressed
signal unavailable_pressed(reason: String)
signal material_pressed(index: int, tile: UiNeedTile)

enum Kind { PRIMARY, SECONDARY, UNAVAILABLE }

const _PAD_X := 14.0          # BlueprintCard main: padding 12 / 14, gap 10, radius 16 (UiTokens.PENDING "blueprintCard")
const _PAD_Y := 12.0
const _GAP := 10
const _RADIUS := 16.0
const _TILE := 44.0           # icon tile 44, icon 32
const _ICON := 32
const _TEXT_GAP := 2
const _MATERIAL_GAP := 8
const _NAME_SIZE := 16        # name 16 ExtraBold: Row Title XB15 one step up (no type token yet)

var _icon: TextureRect
var _name: Label
var _effect: Label
var _yield: Label
var _materials: HBoxContainer
var _have: Label
var button: UiCommandButton
var _tiles: Array[UiNeedTile] = []

## data: {icon, name, effect, yield, have, materials: [{icon, name, have, need}], button: {label, kind}}
func _init(data := {}) -> void:
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, _RADIUS, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	add_theme_stylebox_override(&"panel", box.with_margins(_PAD_X, _PAD_Y, _PAD_X, _PAD_Y))
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", _GAP)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", _GAP)
	col.add_child(head)
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(_TILE, _TILE)
	tile.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, _TILE * 0.5))
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(tile)
	_icon = UiKit.icon(null, _ICON)
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.add_child(_icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override(&"separation", _TEXT_GAP)
	head.add_child(text)
	_name = UiKit.label("", UiTokens.STYLE_ROW_TITLE_XB15)
	_name.add_theme_font_size_override(&"font_size", _NAME_SIZE)
	text.add_child(_name)
	_effect = UiKit.label("", UiTokens.STYLE_C13_B, UiTokens.COLOR_SECONDARY)
	_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_effect)
	_yield = UiKit.label("", UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
	head.add_child(_yield)
	_materials = HBoxContainer.new()
	_materials.add_theme_constant_override(&"separation", _MATERIAL_GAP)
	col.add_child(_materials)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override(&"separation", _MATERIAL_GAP)
	col.add_child(foot)
	_have = UiKit.label("", UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
	_have.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_have)
	button = UiCommandButton.new("", UiCommandButton.Kind.PRIMARY, true)
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.activated.connect(func(): pressed.emit())
	button.unavailable_pressed.connect(func(r: String): unavailable_pressed.emit(r))
	foot.add_child(button)
	set_data(data)

func set_data(d: Dictionary) -> void:
	_icon.texture = d.get("icon", null)
	_name.text = str(d.get("name", ""))
	_effect.text = str(d.get("effect", ""))
	_effect.visible = _effect.text != ""
	_yield.text = str(d.get("yield", ""))
	_yield.visible = _yield.text != ""
	_have.text = str(d.get("have", ""))
	for t in _tiles: t.queue_free()
	_tiles.clear()
	var mats: Array = d.get("materials", [])
	for i in mats.size():
		var m: Dictionary = mats[i]
		var t := UiNeedTile.new(str(m.get("name", "")), int(m.get("have", 0)), int(m.get("need", 1)), UiNeedTile.Size.M,
			m.get("icon", null))
		t.pressed.connect(func(): material_pressed.emit(i, t))
		_materials.add_child(t)
		_tiles.append(t)
	_materials.visible = not mats.is_empty()   # an owned tool turns its materials off (Show materials, main)
	var b: Dictionary = d.get("button", {})
	button.label = str(b.get("label", ""))
	match int(b.get("kind", Kind.PRIMARY)):
		Kind.PRIMARY:
			button.kind = UiCommandButton.Kind.PRIMARY
			button.reason = ""
		Kind.SECONDARY:
			button.kind = UiCommandButton.Kind.SECONDARY
			button.reason = ""
		_:
			button.reason = button.label   # LOCK-10: the label is the reason, the button stays tappable

func tiles() -> Array[UiNeedTile]: return _tiles

## The materials row in global coordinates (the whole inner width): a craft's FloatText starts at its right end.
## An owned tool has no row; then the card's inner area.
func materials_rect() -> Rect2:
	if _materials.visible: return _materials.get_global_rect()
	return get_global_rect().grow_individual(-_PAD_X, -_PAD_Y, -_PAD_X, -_PAD_Y)
