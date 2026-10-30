extends GdUnitTestSuite
## SGODOT-260 Q3 PR-2: the runtime sets the view when something it shows can have changed — a new server view, a
## drawer, the world, the bar's action or pick, offline, any input — and otherwise at least every quarter second (every
## countdown's second within it), not every frame. And the first tap after opening a board is never lost (350cdc12).

const STORE := "user://test_p0_view_throttle.json"

func _view() -> Dictionary:
	return {
		"energy": {"value": 150, "max": 200, "next_in": null, "regen_ms": 240000}, "coins": 200,
		"bag": {"capacity": 25, "slots": [{"id": "fish_crucian", "qty": 4}]},
		"names": {"fish_crucian": "Pond Crucian"},
		"plots": [{"id": 0, "state": "growing", "crop": "crop_radish", "ready_in": 600}],
		"quotas": {"sys_requests": {"used": 4, "cap": 6}, "request_bonus": {"used": 0, "cap": 100}},
		"shops": {"market": {"buy": [], "sell": []}, "homestead": {"buy": [], "sell": []}},
		"keepers": {"market": {"greet": "board", "board_open": 2, "board_templates": []}},
		"boards": {"market": {"slots": [
			{"id": "m1", "title": "Dusk Haul", "kind": "fish", "items": [], "rarity": 2, "icon": "fish_crucian", "qty": 4,
				"have": 4, "ready": true, "coins": 36, "status": "open"}]},
			"stall": {"slots": [{"empty": true, "held": true}]}},
	}

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func _runtime() -> P0Runtime:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	add_child(rt)
	await get_tree().process_frame
	rt.session.view = _view()
	rt.session.set("_received_ms", Time.get_ticks_msec())
	for i in 3: await get_tree().process_frame
	return rt

func _click(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = at
	e.global_position = at
	e.pressed = down
	get_viewport().push_input(e, true)

func test_the_view_is_due_on_what_the_ui_shows_and_at_least_every_quarter_second() -> void:
	var ui: P0Ui = auto_free(P0Ui.new())
	ui.quick_store = STORE
	add_child(ui)
	var sv := _view()
	assert_bool(ui.view_wanted(sv, 1000)).is_true()    # the first
	assert_bool(ui.view_wanted(sv, 1010)).is_false()   # nothing changed: skipped
	assert_bool(ui.view_wanted(sv, 1249)).is_false()
	assert_bool(ui.view_wanted(sv, 1260)).is_true()    # a quarter second on: due (countdowns, what moves unsaid)
	assert_bool(ui.view_wanted(_view(), 1270)).is_true()   # a new server view
	sv = _view()
	ui.view_wanted(sv, 1280)
	for change in [func(): ui.modal_kind = "bag", func(): ui.surface = "pond", func(): ui.bar_mode = "fish",
			func(): ui.space = "pond", func(): ui.selected_seed = "seed_radish", func(): ui.selected_bait = "bait_worm"]:
		change.call()
		assert_bool(ui.view_wanted(sv, 1290)).is_true()
		assert_bool(ui.view_wanted(sv, 1291)).is_false()
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	ui._input(tap)   # any input: due on the next frame
	assert_bool(ui.view_wanted(sv, 1292)).is_true()
	assert_bool(ui.view_wanted(sv, 1293)).is_false()

func test_the_runtime_does_not_set_the_view_every_frame() -> void:
	var rt := await _runtime()
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	var shown: Dictionary = rt.ui.view
	for i in 3: await get_tree().process_frame   # a projection a frame, the UI's view unchanged
	if Time.get_ticks_msec() - int(rt.ui._shown_ms) < P0Ui.VIEW_FLOOR_MS:
		assert_bool(is_same(rt.ui.view, shown)).is_true()
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	assert_bool(is_same(rt.ui.view, shown)).is_false()   # within a quarter second it follows the clock

func test_a_crop_ripening_reaches_the_ui_within_a_second() -> void:
	var rt := await _runtime()
	assert_str(str(rt.ui.view.plots[0].state)).is_equal("growing")
	await get_tree().create_timer(1.0).timeout
	await get_tree().process_frame
	assert_str(str(rt.ui.view.plots[0].state)).is_equal("ready")   # 600 ms to go: ready on the UI within the second

## 350cdc12 (蒙恬 rc0): the first tap after opening a board was released on a rebuilt button and lost. Pressed, held
## past a quarter-second refresh and another input's, released: Deliver is sent.
func test_the_first_tap_after_opening_a_board_is_not_lost() -> void:
	var rt := await _runtime()
	var sent := []
	rt.ui.command.connect(func(c): sent.append(c))
	rt.ui.open_counter("market", {"section": "board"})
	await get_tree().create_timer(0.6).timeout   # the drawer settled where it stays
	await get_tree().process_frame
	var rows: Array = rt.ui._counter.board.get_children().filter(func(c): return c is UiBoardCard and c.visible)
	var button: Control = (rows[0] as UiBoardCard).command_button()
	var at := button.get_global_rect().get_center()
	_click(at, true)
	await get_tree().create_timer(0.3).timeout   # held over a quarter-second refresh
	await get_tree().process_frame
	assert_object((rows[0] as UiBoardCard).command_button()).is_same(button)
	assert_bool(button.get_global_rect().has_point(at)).is_true()
	_click(at, false)
	await await_idle_frame()
	assert_array(sent.map(func(c): return [str(c.get("type", "")), str(c.get("request", ""))])).contains([["deliver", "m1"]])

## Today's own gate lets the runtime's quarter-second view through even when its clock read came a millisecond short
## (哪吒 on #576: two 250 ms gates on two clock reads left Today up to half a second late).
func test_todays_rows_follow_the_quarter_second_view() -> void:
	var ui: P0Ui = auto_free(P0Ui.new())
	ui.quick_store = STORE
	add_child(ui)
	var v := _view()
	v.guide = {"step": "t_fish", "row": {"line": "Catch 2 fish", "icon": "fish", "go": ""}, "progress": {"have": 0, "need": 2}}
	ui.set_view(v)
	await await_idle_frame()
	ui.open_today()
	var line: Label = ui._today_panel._list.get_child(0).find_child("Line", true, false)
	var next := v.duplicate(true)
	next.guide.progress.have = 1
	ui._today_refresh_ms = Time.get_ticks_msec() - (P0Ui.VIEW_FLOOR_MS - 1)   # the view's quarter second, its clock a ms apart
	ui.set_view(next)
	assert_str(str(line.get_meta("sentence"))).is_equal("Catch 2 fish · 1/2")
