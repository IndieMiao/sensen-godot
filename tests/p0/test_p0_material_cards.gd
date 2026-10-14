extends GdUnitTestSuite
## SGODOT-235 B3: the mine and gathering-spot cards on the new shells — ElevatorPanel (MINE-P0-6), and bottom Sheets
## with Close above for New run (MINE-P0-7) and a spot that opens later (MAT-3).

const STORE := "user://test_p0_material_cards.json"

var ui: P0Ui

func _floor(n: int, paid := true, cleared := false) -> Dictionary:
	return {"floor": n, "paid": paid, "cleared": cleared, "left": 0 if cleared else 6, "broken": [], "lit": false, "preview": null, "bag_ok": true}

func _view(run = null, used := 0) -> Dictionary:
	return {
		"energy": {"value": 200, "max": 200, "next_in": null, "regen_ms": 240000},
		"names": {"clay": "Clay"}, "bag": {"capacity": 25, "free": 25, "slots": []}, "plots": [], "coins": 40, "skills": {},
		"rest": {"used": 0, "limit": 1, "resets_in": 3600000}, "homestead": {"level": 1},
		"mine": {"runs": {"used": used, "limit": 2, "resets_in": 33120000}, "ended": null, "floor_energy": 2, "rock_energy": 2,
			"rocks": 6, "stone_per_rock": 1, "run": run},
		"gather": {"spots": [{"id": "spot_clay_bank", "name": "Clay Bank", "open": false, "homestead": 2, "ready": false,
			"yield": [["clay", 2]]}]},
	}

func before_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	ui = P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	ui.layer = 128
	await await_idle_frame()

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func _labels(n: Node) -> Array:
	return n.find_children("*", "Label", true, false).filter(func(l): return (l as Label).is_visible_in_tree()).map(func(l): return (l as Label).text)

func test_elevator_panel_rows_pick_or_say_why() -> void:
	ui.set_view(_view({"id": 1, "deepest": 1, "floors": [_floor(1, true, true), _floor(2, false)]}))
	var picked: Array = []
	var p := P0MaterialCards.open_elevator(ui, ui.view, 1, func(cmd): picked.append(cmd))
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("elevator")
	assert_that(p.rows.map(func(r): return r.state)).is_equal(
		[UiElevatorPanel.State.FREE, UiElevatorPanel.State.HERE, UiElevatorPanel.State.COST])
	p.row(0).pressed.emit()
	p.row(2).pressed.emit()
	assert_that(picked).is_equal([{"type": "mine_leave"}, {"type": "mine_floor", "floor": 2}])
	# A floor behind an uncleared one is grey and says why (LOCK-10).
	ui.set_view(_view({"id": 1, "deepest": 1, "floors": [_floor(1), _floor(2, false)]}))
	p = P0MaterialCards.open_elevator(ui, ui.view, 1, func(cmd): picked.append(cmd))
	assert_int(p.rows[2].state).is_equal(UiElevatorPanel.State.LOCKED)
	p.row(2).pressed.emit()
	assert_str(ui.toast_text()).is_equal("Floor 2 · Clear Floor 1 first")
	assert_int(picked.size()).is_equal(2)

func test_new_run_starts_with_the_destructive_command_or_keeps_with_dismiss() -> void:
	ui.set_view(_view({"id": 1, "deepest": 2, "floors": [_floor(1, true, true), _floor(2, true, true)]}, 1))
	var sent: Array = []
	var d := P0MaterialCards.open_new_run(ui, ui.view, func(cmd): sent.append(cmd))
	await await_idle_frame()
	assert_that(_labels(d)).contains(["The mine", "New run", "Runs today", "1/2 → 2/2", "2 Energy", "Your stored materials stay yours."])
	var go: UiCommandButton = d.find_children("*", "UiCommandButton", true, false)[0]
	assert_int(go.kind).is_equal(UiCommandButton.Kind.DESTRUCTIVE)
	assert_array(d.find_children("*", "UiDismissButton", true, false)).has_size(1)
	go.activated.emit()
	assert_that(sent).is_equal([{"type": "mine_new_run"}])
	assert_bool(ui.has_modal()).is_false()
	d = P0MaterialCards.open_new_run(ui, ui.view, func(cmd): sent.append(cmd))
	(d.find_children("*", "UiDismissButton", true, false)[0] as UiDismissButton).pressed.emit()
	assert_bool(ui.has_modal()).is_false()
	assert_int(sent.size()).is_equal(1)

func test_locked_spot_says_the_gate_and_opens_the_homestead_sheet() -> void:
	ui.set_view(_view())
	var d := P0MaterialCards.open_locked_spot(ui, ui.view, "spot_clay_bank")
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("locked_spot")
	assert_that(_labels(d)).contains(["Clay Bank", "Locked", "Unlock", "Homestead Lv2"])
	var navs: Array = d.find_children("*", "UiNavButton", true, false)
	assert_array(navs).has_size(1)   # View homestead only: no Details page in P0
	(navs[0] as UiNavButton).pressed.emit()
	assert_str(ui.modal_kind).is_equal("homestead")   # HOME-1 (a panel, no jump)
	ui.back_modal()                                   # Android Back: one layer back, to MAT-3 (苏烈 on #102)
	assert_str(ui.modal_kind).is_equal("locked_spot")
	ui.back_modal()
	assert_bool(ui.has_modal()).is_false()
	assert_object(P0MaterialCards.open_locked_spot(ui, ui.view, "spot_unknown")).is_null()
