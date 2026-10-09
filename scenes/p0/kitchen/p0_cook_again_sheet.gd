extends Control
## COOK-P0-7 / P0-8 Cook Again (Cooking Lv2, SGODOT-226; plan §7.2.6): the last page again, over the stove with ×
## above it. Facts (Cooking time when it can, Cooks today, Cooking XP), the page's slots, NEED-TILEs, Choose recipe ›
## and Details ›, then the fixed Cook Again (the gap on the button when short, LOCK-10; nothing is taken until it
## cooks). Facts come from P0KitchenLogic.cook_again; the owner sends the command.

signal cook(cmd: Dictionary)
signal choose_recipe
signal details
signal close_requested
signal unavailable(reason: String)

const HEIGHT := 595.0          # COOK-P0-7 sheet 205 → 800
const CLOSE_GAP := 6.0
const _INSET := 4.0            # the drawer's 12 + 4 = 16 (Kitchen content x 16)
const _SLOT_GAP := 20.0          # PotSlot44 in COOK-P0-7 / P0-8 784:77585 (256 ⑤ A'): 20 apart, centred

var facts: Dictionary = {}
var safe_bottom := 0.0
var _drawer: UiDrawer
var _close: UiCloseButton

func _init(facts_: Dictionary) -> void:
	facts = facts_
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiKit.theme()

func _ready() -> void:
	_drawer = UiDrawer.new(HEIGHT)
	_drawer.safe_bottom = safe_bottom
	_drawer.close_requested.connect(func(): close_requested.emit())
	add_child(_drawer)
	var inset := MarginContainer.new()
	for side in [&"margin_left", &"margin_top", &"margin_right"]: inset.add_theme_constant_override(side, int(_INSET))
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drawer.body.add_child(inset)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", int(UiTokens.SPACE_OVERLAY_BODY))
	inset.add_child(col)
	var scroll := TouchScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", int(UiTokens.SPACE_OVERLAY_BODY))
	scroll.add_child(list)
	list.add_child(UiObjectHeader.new({title = str(facts.title), state = str(facts.state), effect = str(facts.effect)}))
	for f in facts.facts: list.add_child(UiFactRow.new(str(f[0]), str(f[1])))
	list.add_child(UiKit.label(str(facts.section), UiTokens.STYLE_ROW_TITLE_XB15))
	list.add_child(_slot_bar())
	list.add_child(UiNeedTile.group(facts.tiles.map(func(t): return UiNeedTile.new(str(t.name), int(t.have), int(t.need), UiNeedTile.Size.M, t.icon))))
	var pick := UiNavButton.new("Choose recipe")
	pick.pressed.connect(func(): choose_recipe.emit())
	list.add_child(pick)
	var info := UiNavButton.new("Details")
	info.pressed.connect(func(): details.emit())
	list.add_child(info)
	var go := UiCommandButton.new(str(facts.button))
	go.reason = str(facts.reason)
	go.sends = true   # cook again (§10.7.1 Offline)
	go.activated.connect(func(): cook.emit(facts.command))
	go.unavailable_pressed.connect(func(r): unavailable.emit(r))
	col.add_child(go)
	_close = UiCloseButton.new()
	_close.pressed.connect(func(): close_requested.emit())
	add_child(_close)
	resized.connect(_place_close)
	_place_close.call_deferred()

## The page's slots, filled with what Cook Again will use, and the locked 3rd slot before Cooking Lv4: PotSlot44 as
## under the pot (256 ⑤ A', 刘邦 on #142), icons and ×1 with no names; a tap on the lock says what opens it.
func _slot_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override(&"separation", int(_SLOT_GAP))
	var tiles: Array = facts.tiles
	for t in tiles:
		for i in int(t.need):
			var s := UiPotSlot.new(UiPotSlot.State.FILLED)
			s.icon = t.icon
			s.quantity = "×1"
			bar.add_child(s)
	if bool(facts.get("locked", false)):
		var lock := UiPotSlot.new(UiPotSlot.State.LOCKED)
		lock.locked_tapped.connect(func(): unavailable.emit(str(facts.get("lock_note", ""))))
		bar.add_child(lock)
	return bar

func _place_close() -> void:
	_close.position = Vector2(size.x - UiTokens.SPACE_PAGE - UiTokens.SIZE_CLOSE, size.y - HEIGHT - safe_bottom - CLOSE_GAP - UiTokens.SIZE_CLOSE)
