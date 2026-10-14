class_name P0MaterialCards
extends RefCounted
## SGODOT-231 cards for the mine and the gathering spots, on the new shells (SGODOT-235 B3): the ElevatorPanel above the
## elevator key (MINE-P0-6, LOCK-21), and bottom Sheets with a Close 44 above them (UiDrawer, as the workbench and the
## resident profile) for the New run confirmation (MINE-P0-7) and a spot that opens later (MAT-3); the mouth itself
## answers with its EntryCard, at 2/2 too (MINE-GATE-EXPRESS-3 / -4: the P0 "The mine" sheet MINE-P0-1 / P0-8 is gone). Sheet content follows the frames: ObjectHeader, Fact rows, then the fixed
## decision area (Cost, a note, one command, Dismiss). Copy and states come from P0MaterialLogic; these functions only
## lay them out and route taps back to the caller.

const ELEVATOR_RIGHT := 12.0     # MINE-P0-6: the panel at x 68, w 280 (right edge 12 in from the screen) …
const ELEVATOR_BOTTOM := 347.0   # … its bottom at y 453 of 800, above the elevator key
const SHEET_GAP := 8             # Sheet content: ObjectHeader / Fact / rows 8 apart
const VIEW_HOMESTEAD := "View homestead"   # MAT-3 NavigationRow (the row draws its own ›)
const HomePanel := preload("res://scenes/p0/home/p0_home_panel.gd")
const DECISION_GAP := 12         # the fixed decision area starts 12 below the content (Cost at y 12)
const ELEVATOR_KINDS := {"here": UiElevatorPanel.State.HERE, "free": UiElevatorPanel.State.FREE,
	"cost": UiElevatorPanel.State.COST, "locked": UiElevatorPanel.State.LOCKED, "short": UiElevatorPanel.State.SHORT,
	"express": UiElevatorPanel.State.EXPRESS}

## MINE-P0-6: ElevatorPanel `Elevator · stops this run`, one row per stop (Here / Free / 2 Energy / Clear Floor 1 first /
## Need 2 Energy). No scrim (the frame keeps the scene, key and bar in view); a tap outside or Back closes it. `pick`
## gets the row's cmd (mine_leave, mine_floor, energy_card); a locked row toasts its reason (LOCK-10).
static func open_elevator(ui: P0Ui, view: Dictionary, here: int, pick: Callable) -> UiElevatorPanel:
	var rows := P0MaterialLogic.elevator_rows(view, here)
	var panel := UiElevatorPanel.new(P0MaterialLogic.ELEVATOR_TITLE, rows.map(func(r: Dictionary) -> Dictionary:
		return {"floor": r.name, "value": r.state, "state": ELEVATOR_KINDS.get(str(r.kind), UiElevatorPanel.State.LOCKED)}))
	panel.theme = UiKit.theme()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -ELEVATOR_RIGHT
	panel.offset_bottom = -ELEVATOR_BOTTOM
	panel.offset_left = panel.offset_right - UiElevatorPanel.WIDTH
	panel.offset_top = panel.offset_bottom
	panel.row_pressed.connect(func(i: int):
		var cmd: Dictionary = rows[i].cmd
		if not cmd.is_empty(): pick.call(cmd))
	panel.unavailable_pressed.connect(func(i: int): ui.toast(str(rows[i].label)))
	ui._open_modal(panel, 0.0, false)
	ui.modal_kind = "elevator"
	return panel

## MINE-P0-7: from the EntryCard's New run · 2 Energy. ObjectHeader `The mine` / `New run`, the runs fact, then Cost
## `New run · 2 Energy`, `Your stored materials stay yours.`, Command/destructive `Start new run` (sends mine_new_run)
## and Dismiss `Keep current run` (closes).
static func open_new_run(ui: P0Ui, view: Dictionary, send: Callable) -> UiDrawer:
	var sheet := P0MaterialLogic.new_run_sheet(view)
	var d := _sheet(ui)
	d.body.add_child(UiObjectHeader.new({"title": sheet.title, "state": sheet.subtitle}))
	for f in sheet.facts: d.body.add_child(UiFactRow.new(str(f[0]), str(f[1])))
	_decision_gap(d)
	d.body.add_child(UiFactRow.new(str(sheet.cost[0]), str(sheet.cost[1]), UiFactRow.Kind.COST))
	var note := UiKit.label(str(sheet.note), UiTokens.STYLE_BODY_B14)   # body/Bold 14 (MINE-P0-7)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.body.add_child(note)
	var go := UiCommandButton.new(str(sheet.confirm.label), UiCommandButton.Kind.DESTRUCTIVE)
	var cmd: Dictionary = sheet.confirm.cmd
	go.activated.connect(func():
		ui.close_modal()
		send.call(cmd))
	d.body.add_child(go)
	var keep := UiDismissButton.new(str(sheet.keep))
	keep.pressed.connect(ui.close_modal)
	d.body.add_child(keep)
	_show(ui, d, "new_run")
	return d

## MAT-3: a spot that opens later (Clay Bank before Homestead Lv2): ObjectHeader `Clay Bank` / `Locked` / what it
## gives, the `Unlock · Homestead Lv2` fact and NavigationRow `View homestead ›`, which opens the HOME-1 upgrade sheet
## (a panel only: no jump, the camera stays, LOCK-08); Back from it returns to this sheet. The frame's `Details ›` row is left out: P0 has no details page
## (不知火舞 on 235).
static func open_locked_spot(ui: P0Ui, view: Dictionary, spot_id: String) -> UiDrawer:
	var sheet := P0MaterialLogic.locked_spot_sheet(view, spot_id)
	if sheet.is_empty(): return null
	var d := _sheet(ui)
	d.body.add_child(UiObjectHeader.new({"title": sheet.title, "state": sheet.subtitle, "effect": sheet.line}))
	for f in sheet.facts: d.body.add_child(UiFactRow.new(str(f[0]), str(f[1])))
	var home := UiNavButton.new(VIEW_HOMESTEAD)
	# P0Ui.open_home_panel decides "at home" (space_here, as the Profile's farm card does; 后裔 on #150) and sets the
	# way back: Back from HOME-1 returns here (苏烈 on #102).
	home.pressed.connect(func(): ui.open_home_panel(func(): open_locked_spot(ui, ui.view, spot_id)))
	d.body.add_child(home)
	_show(ui, d, "locked_spot")
	return d

## A bottom Sheet like the workbench's: page padding 16, the UI kit theme, the bottom safe inset, swipe-down closes.
static func _sheet(ui: P0Ui) -> UiDrawer:
	var d := UiDrawer.new(0.0)
	d.pad = UiTokens.SPACE_PAGE
	d.theme = UiKit.theme()
	d.safe_bottom = ui.safe_bottom()
	d.body.add_theme_constant_override(&"separation", SHEET_GAP)
	d.close_requested.connect(ui.close_modal)
	return d

## The fixed decision area sits 12 below the content (SHEET_GAP + 4).
static func _decision_gap(d: UiDrawer) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = DECISION_GAP - SHEET_GAP
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.body.add_child(gap)

## Open the sheet with the drawer scrim and a Close 44 six above its top, 16 in (RES-PIP / B2-06), and keep its height
## fitted to the content. Wrapped lines only know their width once the sheet is laid out, so the first fit is too tall
## (taller than the screen); the content's minimum size changes when they wrap, and the sheet refits then. A fit timed
## for "the next frame" was not enough: a second tap reopening the sheet in the next frame's input got its fit before
## its layout and stayed full screen (SGODOT-256 ①, int10c).
static func _show(ui: P0Ui, d: UiDrawer, kind: String) -> void:
	ui._open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	ui._close_above(d, P0Ui._CLOSE_ABOVE_SHEET, UiTokens.SPACE_PAGE)
	ui.modal_kind = kind
	d.body.minimum_size_changed.connect(func(): fit(d))
	fit(d)

## The sheet's height: its content plus the padding above and below (the safe inset is added by the drawer).
static func fit(d: UiDrawer) -> void:
	d.height = d.body.get_combined_minimum_size().y + d.pad * 2.0

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
