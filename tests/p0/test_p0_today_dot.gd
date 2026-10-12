extends GdUnitTestSuite
## q(107) / SGODOT-271: the Today chip is an icon with a red dot. It lights for a row that can be done now and that
## this device has not seen — a request to hand in, a harvest, a dish at the stove, a new recipe or slot, the first
## session's Sow / Catch / Deliver — never for a countdown, an info row, a request still short, `N fish · the stove is
## free`, `Water N sown plots`, a ticked row or one short of Energy. Opening Today sees them all; a key that leaves
## the rows is forgotten, so the same thing coming back lights it again. Kept with the teaching tips, on the device.

const KAI := "req_res_kai_1"

## One file per process: user:// is shared by every worktree of the project (哪吒 on #199).
static func _tips() -> String: return "user://test_p0_today_dot_%d.json" % OS.get_process_id()
static func _store() -> String: return "user://test_p0_today_dot_bar_%d.json" % OS.get_process_id()

func after_test() -> void:
	for f in [_tips(), _store()]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func _view() -> Dictionary:
	return {
		"coins": 120, "energy": {"value": 150, "max": 200},
		"skills": {"farming": {"level": 2, "xp": 60}, "fishing": {"level": 4, "xp": 70}, "cooking": {"level": 2, "xp": 40}},
		"names": {"fish_crucian": "Pond Crucian", "crop_radish": "Radish", "dish_grilled_crucian": "Grilled Crucian"},
		"bag": {"capacity": 25, "slots": []},
		"firsts": ["harvest:crop_radish"],   # farmed before: no `Sow your first plot`
	}

## Old Kai's request, ready to hand in or `have` of 1.
static func _kai(v: Dictionary, ready := true) -> Dictionary:
	v["residents"] = {"res_old_kai": {"request": {"id": KAI, "kind": "fish", "rarity": 1, "have": 1 if ready else 0, "qty": 1,
		"ready": ready}, "request_state": "accepted"}}
	return v

static func _dots(v: Dictionary) -> Array: return P0Logic.today_dots(P0Logic.today_rows(v))

# ---------------------------------------------------------------- which rows light it

## A request to hand in and a harvest light it, each by its own key; watering the sown plots does not.
func test_a_delivery_and_a_harvest_light_it_watering_does_not() -> void:
	var v := _kai(_view())
	v["plots"] = [{"state": "ready", "crop": "crop_radish"}, {"state": "sown", "crop": "crop_radish"}]
	var rows := P0Logic.today_rows(v)
	assert_array(rows.map(func(r): return r.line)).contains(["Harvest 1 Radish", "Water 1 sown plot"])
	assert_array(_dots(v)).is_equal(["deliver:" + KAI, "harvest:crop_radish"])

## Several crops ready are one row, keyed by all of them: a new kind ripening is new.
func test_several_crops_ready_are_keyed_by_all_of_them() -> void:
	var v := _view()
	v["plots"] = [{"state": "ready", "crop": "crop_radish"}, {"state": "ready", "crop": "crop_lettuce"}]
	assert_array(_dots(v)).is_equal(["harvest:crop_lettuce+crop_radish"])

## A dish waiting at the stove lights it; the same dish still cooking is a countdown and does not.
func test_a_dish_ready_at_the_stove_lights_it_a_cooking_one_does_not() -> void:
	var v := _view()
	v["cooking"] = {"stove": {"dish": "dish_grilled_crucian", "ready_in": 0}}
	assert_array(_dots(v)).is_equal(["stove:dish_grilled_crucian"])
	v.cooking.stove.ready_in = 4000
	assert_array(P0Logic.today_rows(v).map(func(r): return r.line)).contains(["Grilled Crucian · 0:04 left at the stove"])
	assert_array(_dots(v)).is_empty()

## Never: a request still short, the free stove with fish in the bag, a countdown, the nearest level.
func test_progress_the_free_stove_countdowns_and_levels_do_not_light_it() -> void:
	var v := _kai(_view(), false)
	v.bag.slots = [{"id": "fish_crucian", "qty": 2}]
	v["plots"] = [{"state": "growing", "crop": "crop_radish", "ready_in": 3600000}]
	var lines := P0Logic.today_rows(v).map(func(r): return r.line)
	assert_array(lines).contains(["Cook with 2 fish", "Radishes ready in 1h"])
	assert_array(_dots(v)).is_empty()

## The first session: Catch the tutorial fish and `Sow your first plot` light it; short of Energy the sow row does not;
## Deliver lights it again by its own key once the creel holds them.
func test_the_first_sessions_rows() -> void:
	var v := _view()
	v.erase("firsts")
	v["stall"] = {"board": {"requests": [{"id": P0Guide.TUTORIAL, "title": "Pond Catch", "item": "fish_crucian", "qty": 2,
		"have": 0, "status": "accepted"}]}}
	assert_array(_dots(v)).contains_exactly_in_any_order(["sow:first", "catch:" + P0Guide.TUTORIAL])
	v.energy.value = 0
	assert_array(_dots(v)).is_equal(["catch:" + P0Guide.TUTORIAL])   # `Sow your first plot · needs 2 Energy`: short
	v.stall.board.requests[0].have = 2
	assert_array(_dots(v)).is_equal(["deliver:" + P0Guide.TUTORIAL])

## A ticked row never lights it.
func test_a_ticked_row_does_not_light_it() -> void:
	assert_array(P0Logic.today_dots([{"dot": "deliver:x", "state": "done"}, {"dot": "", "state": "default"}])).is_empty()

# ---------------------------------------------------------------- on screen

func _ui(v: Dictionary) -> P0Ui:
	var ui := P0Ui.new()
	ui.quick_store = _store()
	ui.tips_path = _tips()
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(v)
	ui.set_surface("farm")
	await await_idle_frame()
	return ui

## Lit on the first view; opening Today puts it out; Today stays as it was (same rows, same panel).
func test_opening_today_puts_it_out() -> void:
	var ui := await _ui(_kai(_view()))
	assert_bool(ui.hud.today_dot_shown()).is_true()
	ui.open_today()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("today")
	assert_bool(ui.hud.today_dot_shown()).is_false()
	ui.close_modal()
	await await_idle_frame()
	assert_bool(ui.hud.today_dot_shown()).is_false()

## Something new to do lights it again; seen, the same thing gone and back (the fish eaten, caught again) is new too.
func test_a_new_key_and_one_that_comes_back_light_it_again() -> void:
	var v := _kai(_view())
	var ui := await _ui(v)
	ui.open_today()
	ui.close_modal()
	var harvest := v.duplicate(true)
	harvest["plots"] = [{"state": "ready", "crop": "crop_radish"}]
	ui.set_view(harvest)
	assert_bool(ui.hud.today_dot_shown()).is_true()   # the harvest is new; the delivery was seen
	ui.open_today()
	ui.close_modal()
	ui.set_view(_kai(harvest.duplicate(true), false))   # the fish eaten: the delivery row leaves
	assert_bool(ui.hud.today_dot_shown()).is_false()
	ui.set_view(harvest)                                  # caught again: ready to hand in once more
	assert_bool(ui.hud.today_dot_shown()).is_true()

## Today opened with other rows (the Energy card's Free to do now) is not Today's own: the dot stays.
func test_today_opened_with_other_rows_leaves_it() -> void:
	var ui := await _ui(_kai(_view()))
	ui.open_today([{"line": "Browse the map", "icon": "map", "go": "map", "state": "default", "tail": "", "focus": false}])
	await await_idle_frame()
	assert_bool(ui.hud.today_dot_shown()).is_true()

## Seen on this device, it stays out after a restart (the seen keys live in the tips file, not the save).
func test_seen_keys_outlive_the_ui() -> void:
	var ui := await _ui(_kai(_view()))
	ui.open_today()
	ui.close_modal()
	ui.queue_free()
	await await_idle_frame()
	var again := await _ui(_kai(_view()))
	assert_bool(again.hud.today_dot_shown()).is_false()

## Nothing to do now (countdowns, watering): no dot from the start.
func test_nothing_to_do_now_shows_no_dot() -> void:
	var v := _view()
	v["plots"] = [{"state": "sown", "crop": "crop_radish"}, {"state": "growing", "crop": "crop_radish", "ready_in": 3600000}]
	var ui := await _ui(v)
	assert_bool(ui.hud.today_dot_shown()).is_false()

## The icon opens Today and, with Today open, closes it.
func test_the_icon_opens_today_and_closes_it() -> void:
	var ui := await _ui(_kai(_view()))
	ui.hud.today_pressed.emit()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("today")
	ui.hud.today_pressed.emit()
	await await_idle_frame()
	assert_bool(ui.has_modal()).is_false()

## 奕星 / 李白 on #201: the first dish's row lights it once the stove can make it; seen, the fish eaten (it cannot be
## cooked, the key leaves) and caught again, it lights again.
func test_cook_it_lights_again_after_the_fish_is_eaten_and_caught_again() -> void:
	var v := _view()
	v.erase("firsts")
	v["plots"] = [{"state": "growing", "crop": "crop_radish", "ready_in": 3600000}]
	v["req_done"] = [P0Guide.TUTORIAL]
	v["cooking"] = {"cookbook": [{"id": "dish_grilled_crucian", "name": "Grilled Crucian", "known": true, "cooked": false,
		"can_cook": true}]}
	assert_array(_dots(v)).is_equal(["cook:dish_grilled_crucian"])
	var ui := await _ui(v)
	assert_bool(ui.hud.today_dot_shown()).is_true()
	ui.open_today()
	ui.close_modal()
	assert_bool(ui.hud.today_dot_shown()).is_false()
	var eaten := v.duplicate(true)
	eaten.cooking.cookbook[0].can_cook = false   # the fish eaten: Cook it stays, lighting nothing
	ui.set_view(eaten)
	assert_bool(ui.hud.today_dot_shown()).is_false()
	ui.set_view(v)                                # caught again
	assert_bool(ui.hud.today_dot_shown()).is_true()

## A new account on this device (the server reset it, the app still open) starts with nothing seen: the same first
## rows light the dot again (亚瑟 on #201).
func test_a_new_account_sees_its_dot_even_on_the_same_keys() -> void:
	var v := _kai(_view())
	v["profile"] = {"since_ms": 1_700_000_000_000}
	var ui := await _ui(v)
	ui.open_today()
	ui.close_modal()
	assert_bool(ui.hud.today_dot_shown()).is_false()
	var fresh := v.duplicate(true)
	fresh.profile.since_ms = 1_800_000_000_000
	ui.set_view(fresh)
	assert_bool(ui.hud.today_dot_shown()).is_true()
