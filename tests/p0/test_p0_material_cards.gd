extends GdUnitTestSuite
## SGODOT-235 B3: the mine and gathering-spot cards on the new shells — ElevatorPanel (MINE-P0-6; E3 in 355 b1), and
## bottom Sheets with Close above for a spot that opens later (MAT-3).

const Fx := preload("res://tests/p0/fixtures/mine_b1_view.gd")

const STORE := "user://test_p0_material_cards.json"

var ui: P0Ui

func _view() -> Dictionary:
	return {
		"energy": {"value": 200, "max": 200, "next_in": null, "regen_ms": 240000},
		"names": {"clay": "Clay"}, "bag": {"capacity": 25, "free": 25, "slots": []}, "plots": [], "coins": 40, "skills": {},
		"rest": {"used": 0, "limit": 1, "resets_in": 3600000}, "homestead": {"level": 1},
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
	ui.set_view(Fx.view(10, {"stations": [{"floor": 10, "paid": true}, {"floor": 20, "paid": false}]}))
	var picked: Array = []
	var p := P0MaterialCards.open_elevator(ui, ui.view, 10, func(cmd): picked.append(cmd))
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("elevator")
	assert_that(_labels(p)).contains(["Elevator · Ironvale Vein"])   # E3 326:181733
	assert_that(p.rows.map(func(r): return r.state)).is_equal(
		[UiElevatorPanel.State.FREE, UiElevatorPanel.State.HERE, UiElevatorPanel.State.COST])
	p.row(0).pressed.emit()
	p.row(2).pressed.emit()
	assert_that(picked).is_equal([{"type": "mine_leave"}, {"type": "mine_floor", "to": 20, "via": "elevator"}])
	# Short of Energy: amber, its press the Energy card's (picked as energy_card).
	ui.close_modal()
	ui.set_view(Fx.view(10, {"energy": 1, "stations": [{"floor": 10, "paid": true}, {"floor": 20, "paid": false}]}))
	p = P0MaterialCards.open_elevator(ui, ui.view, 10, func(cmd): picked.append(cmd))
	assert_int(p.rows[2].state).is_equal(UiElevatorPanel.State.SHORT)
	p.row(2).pressed.emit()
	assert_str(str(picked[2].type)).is_equal("energy_card")

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
