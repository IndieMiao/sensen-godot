class_name P0MaterialCards
extends RefCounted
## SGODOT-231 cards for the mine and the gathering spots, built on P0Ui's card layer (its _center_card / _sheet until
## the stage-3 ModalStack, per Arthur) from kit parts, themed with UiKit.theme() (the card layer still carries GameUi's,
## which drew the primary Start new run white on the Android walkthrough): the elevator panel (MINE-P0-6), "The mine" sheet from tapping
## the mouth (MINE-P0-1 / P0-8), the New run confirmation (MINE-P0-7) and a locked spot (MAT-3). Copy and states come
## from P0MaterialLogic; these functions only lay them out and route taps back to the caller.

const HERE_BG := Color("e6f0de")

## MINE-P0-6: "Elevator · stops this run", one row per stop, name left and Free / Here / reason right. `pick` gets the
## row's cmd (mine_leave, mine_floor, energy_card); an unavailable row toasts its reason.
static func open_elevator(ui: P0Ui, view: Dictionary, here: int, pick: Callable) -> void:
	var v := ui._center_card(260)
	v.theme = UiKit.theme()   # kit parts (CommandButton, FactRow) keep their styles inside the P0 card layer
	v.add_child(UiKit.label(P0MaterialLogic.ELEVATOR_TITLE, UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY))
	for r in P0MaterialLogic.elevator_rows(view, here):
		var row := Button.new()
		row.focus_mode = Control.FOCUS_NONE
		row.custom_minimum_size = Vector2(0, 44)
		var is_here := str(r.state) == "Here"
		ui._style_button(row, HERE_BG if is_here else P0Ui.PAPER, P0Ui.EDGE, 10)
		var fact := UiFactRow.new(str(r.name), str(r.state))
		fact.set_anchors_preset(Control.PRESET_FULL_RECT)
		fact.offset_left = 12
		fact.offset_right = -12
		fact.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(fact)
		var cmd: Dictionary = r.cmd
		var enabled: bool = r.enabled
		var reason := str(r.label)
		row.pressed.connect(func():
			if enabled and not cmd.is_empty(): pick.call(cmd)
			elif not is_here: ui.toast(reason))
		v.add_child(row)

## MINE-P0-1 / P0-8: tapping the mouth shows what the mine is and today's runs; when no run is possible today the
## only button is the grey reason. Entering stays on the main action key (LOCK-21).
static func open_mine_sheet(ui: P0Ui, view: Dictionary) -> void:
	var sheet := P0MaterialLogic.mine_sheet(view)
	var v := ui._sheet(300, "")
	v.theme = UiKit.theme()   # kit parts (CommandButton, FactRow) keep their styles inside the P0 card layer
	v.add_child(UiObjectHeader.new({"title": sheet.title, "state": sheet.subtitle, "effect": sheet.line}))
	for f in sheet.facts: v.add_child(UiFactRow.new(str(f[0]), str(f[1])))
	var button: Dictionary = sheet.button
	if not button.is_empty():
		var b := UiCommandButton.new("", UiCommandButton.Kind.PRIMARY)
		b.reason = str(button.label)
		b.unavailable_pressed.connect(func(text: String): ui.toast(text))
		v.add_child(b)

## MINE-P0-7: from the EntryCard's New run · 2 Energy. Start new run sends mine_new_run; Keep current run closes.
static func open_new_run(ui: P0Ui, view: Dictionary, send: Callable) -> void:
	var sheet := P0MaterialLogic.new_run_sheet(view)
	var v := ui._sheet(340, "")
	v.theme = UiKit.theme()   # kit parts (CommandButton, FactRow) keep their styles inside the P0 card layer
	v.add_child(UiObjectHeader.new({"title": sheet.title, "state": sheet.subtitle}))
	for f in sheet.facts: v.add_child(UiFactRow.new(str(f[0]), str(f[1])))
	v.add_child(UiFactRow.new(str(sheet.cost[0]), str(sheet.cost[1]), UiFactRow.Kind.COST))
	v.add_child(UiKit.label(str(sheet.note), UiTokens.STYLE_BODY_R14))
	var go := UiCommandButton.new(str(sheet.confirm.label), UiCommandButton.Kind.PRIMARY)
	go.sends = true   # mine_new_run (§10.7.1 Offline)
	var cmd: Dictionary = sheet.confirm.cmd
	go.activated.connect(func():
		ui.close_modal()
		send.call(cmd))
	v.add_child(go)
	var keep := UiCommandButton.new(str(sheet.keep), UiCommandButton.Kind.SECONDARY)
	keep.activated.connect(ui.close_modal)
	v.add_child(keep)

## MAT-3: a spot that opens later (Clay Bank before Homestead Lv2).
static func open_locked_spot(ui: P0Ui, view: Dictionary, spot_id: String) -> void:
	var sheet := P0MaterialLogic.locked_spot_sheet(view, spot_id)
	if sheet.is_empty(): return
	var v := ui._sheet(260, "")
	v.theme = UiKit.theme()   # kit parts (CommandButton, FactRow) keep their styles inside the P0 card layer
	v.add_child(UiObjectHeader.new({"title": sheet.title, "state": sheet.subtitle, "effect": sheet.line}))
	for f in sheet.facts: v.add_child(UiFactRow.new(str(f[0]), str(f[1])))

# --- Workbench (B2-06) ---

const CRAFTED_REVEAL := 96.0   # PICKAXE-DONE: the tool over the card (the reveal is the caller's, RewardMoment main)
const CRAFTED_GAP := 44        # PICKAXE-DONE: reveal 200–296, card from 340 …
const CRAFTED_LIFT := 86.0     # … the pair sits 43 above the screen's middle
const BANNER_TOP := 108.0      # MomentBanner: x16 y108 w328, under the HUD
const BANNER_S := 3.0          # MomentBanner: ≤3 s, a tap skips it
const BANNER_DISC := 48.0
const BANNER_CHECK := 26.0
const CHECK := preload("res://assets/ui/kit_icons/check.svg")

## PICKAXE-DONE (1472:95235): the drawer closes, RewardMoment (Milestone) says `Crafted!` with the tool, its effect on
## the tags line and only Equip. Equip sends the command and closes; a tap outside keeps it in Gear (Equip there).
static func open_crafted(ui: P0Ui, view: Dictionary, item: String, send: Callable) -> UiRewardMoment:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -CRAFTED_LIFT
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.theme = UiKit.theme()
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", CRAFTED_GAP)
	center.add_child(col)
	var reveal := UiKit.icon(P0Logic.icon(item), CRAFTED_REVEAL)
	reveal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(reveal)
	var card := UiRewardMoment.new()
	card.show_fields({"tone": UiRewardMoment.Tone.MILESTONE, "event": "Crafted!", "icon": P0Logic.icon(item),
		"item_name": P0Logic.item_name(view, item), "rarity": 1,
		"rarity_word": str(P0MaterialLogic.EFFECTS.get(item, "")), "primary": "Equip"})
	card.primary_pressed.connect(func():
		ui.close_modal()
		send.call({"type": "equip", "item": item}))
	col.add_child(card)
	ui._open_modal(center, UiTokens.OPACITY_SCRIM_MODAL, true)
	ui.modal_kind = "card"
	return card

## GLOVES-DONE (1472:95635): MomentBanner Kind=Complete under the HUD, over the still-open drawer: green accent, check
## disc, `Gather Gloves`, `+1 at every gathering spot`, `Next Timber harvest: 7`, `Passive · no gear slot needed`.
## Gone after 3 s or on a tap.
static func gloves_banner(ui: P0Ui, view: Dictionary) -> Control:
	var m := P0MaterialLogic.gloves_moment(view)
	var card := PanelContainer.new()
	card.name = "GlovesMoment"
	card.theme = UiKit.theme()
	card.set_anchors_preset(Control.PRESET_TOP_WIDE)
	card.offset_left = UiTokens.SPACE_PAGE
	card.offset_right = -UiTokens.SPACE_PAGE
	card.offset_top = BANNER_TOP
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, 20, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.shadow_color = Color("2E3B3333")   # 0 10 28 rgba(46,59,51,0.2), as HOME-2's banner
	box.shadow_size = 14
	box.shadow_offset = Vector2(0, 10)
	card.add_theme_stylebox_override(&"panel", box.with_margins(0, 0, 0, 14))
	card.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW   # the accent follows the card's rounded top
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	card.add_child(col)
	var accent := ColorRect.new()
	accent.custom_minimum_size = Vector2(0, 6)
	accent.color = UiTokens.COLOR_PRIMARY   # Kind=Complete
	col.add_child(accent)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", UiTokens.SPACE_PAGE)
	pad.add_theme_constant_override(&"margin_right", UiTokens.SPACE_PAGE)
	pad.add_theme_constant_override(&"margin_top", 4)
	col.add_child(pad)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 12)
	pad.add_child(head)
	var disc := CenterContainer.new()
	disc.custom_minimum_size = Vector2(BANNER_DISC, BANNER_DISC)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var disc_bg := Panel.new()
	disc_bg.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, BANNER_DISC * 0.5))
	disc_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	disc.add_child(disc_bg)
	var check := UiKit.icon(CHECK, BANNER_CHECK)
	check.modulate = UiTokens.COLOR_PRIMARY
	disc.add_child(check)
	head.add_child(disc)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_theme_constant_override(&"separation", 2)
	var title := UiKit.label(str(m.title), UiTokens.STYLE_TITLE_XB20)
	title.add_theme_font_size_override(&"font_size", 22)
	titles.add_child(title)
	titles.add_child(UiKit.label(str(m.line), UiTokens.STYLE_C13_B, UiTokens.COLOR_SECONDARY))
	head.add_child(titles)
	var detail := UiKit.label(str(m.fact), UiTokens.STYLE_C13_B)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(detail)
	var tip := UiKit.label(str(m.note), UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tip)
	_pass_taps(col)
	card.gui_input.connect(func(e: InputEvent):
		if P0Ui.is_tap(e) and is_instance_valid(card): card.queue_free())
	ui.root.add_child(card)
	ui.root.get_tree().create_timer(BANNER_S).timeout.connect(func():
		if is_instance_valid(card): card.queue_free())
	return card

## Children ignore the mouse so a tap anywhere on the banner reaches the card and skips it.
static func _pass_taps(n: Node) -> void:
	if n is Control: (n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children(): _pass_taps(c)
