extends GdUnitTestSuite
## SGODOT-235 B3: the mine's cards on the new shells — ElevatorPanel (MINE-P0-6; E3 in 355 b1). The farm spots' MAT-3
## sheet left with v4q(4) ①.

const Fx := preload("res://tests/p0/fixtures/mine_b1_view.gd")

const STORE := "user://test_p0_material_cards.json"

var ui: P0Ui

func _view() -> Dictionary:
	return {
		"energy": {"value": 200, "max": 200, "next_in": null, "regen_ms": 240000},
		"names": {"clay": "Clay"}, "bag": {"capacity": 25, "free": 25, "slots": []}, "plots": [], "coins": 40, "skills": {},
		"rest": {"used": 0, "limit": 1, "resets_in": 3600000}, "homestead": {"level": 1},
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

