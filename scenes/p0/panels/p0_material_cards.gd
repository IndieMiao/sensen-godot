class_name P0MaterialCards
extends RefCounted
## SGODOT-231 cards for the mine and the gathering spots, built on P0Ui's card layer (its _center_card / _sheet until
## the stage-3 ModalStack, per Arthur) from kit parts: the elevator panel (MINE-P0-6), "The mine" sheet from tapping
## the mouth (MINE-P0-1 / P0-8), the New run confirmation (MINE-P0-7) and a locked spot (MAT-3). Copy and states come
## from P0MaterialLogic; these functions only lay them out and route taps back to the caller.

const HERE_BG := Color("e6f0de")

## MINE-P0-6: "Elevator · stops this run", one row per stop, name left and Free / Here / reason right. `pick` gets the
## row's cmd (mine_leave, mine_floor, energy_card); an unavailable row toasts its reason.
static func open_elevator(ui: P0Ui, view: Dictionary, here: int, pick: Callable) -> void:
	var v := ui._center_card(260)
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
	v.add_child(UiObjectHeader.new({"title": sheet.title, "state": sheet.subtitle}))
	for f in sheet.facts: v.add_child(UiFactRow.new(str(f[0]), str(f[1])))
	v.add_child(UiFactRow.new(str(sheet.cost[0]), str(sheet.cost[1]), UiFactRow.Kind.COST))
	v.add_child(UiKit.label(str(sheet.note), UiTokens.STYLE_BODY_R14))
	var go := UiCommandButton.new(str(sheet.confirm.label), UiCommandButton.Kind.PRIMARY)
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
	v.add_child(UiObjectHeader.new({"title": sheet.title, "state": sheet.subtitle, "effect": sheet.line}))
	for f in sheet.facts: v.add_child(UiFactRow.new(str(f[0]), str(f[1])))
