extends GdUnitTestSuite
## q(107) / SGODOT-271, as the A 包 spec has it (①, ③ v3; LOCK-06): the Today chip is an icon with a red dot. It lights
## for a row this device has not seen that hands a request in (`Upgrade to Homestead` is Pip's), a new guide step, the
## first session's Catch / Deliver / Cook it, or a request Pip has just given (`pip:` keys) — never for a request still
## short, a ticked row or one short of Energy; crops, the stove and the rest are not in Today at all. Opening Today sees
## them all; a key that leaves the rows is forgotten, so the same thing coming back lights it again — except Pip's,
## seen once for good. Kept with the teaching tips, on the device.

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

## A request to hand in lights it by its own key; the field's rows (Harvest, Water) are not in Today.
func test_a_delivery_lights_it_and_the_fields_rows_are_gone() -> void:
	var v := _kai(_view())
	v["plots"] = [{"state": "ready", "crop": "crop_radish"}, {"state": "sown", "crop": "crop_radish"}]
	v["cooking"] = {"stove": {"dish": "dish_grilled_crucian", "ready_in": 0}}
	assert_int(P0Logic.today_rows(v).size()).is_equal(1)
	assert_array(_dots(v)).is_equal(["deliver:" + KAI])

## Never: a request still short, the free stove with fish in the bag, a countdown, the nearest level.
func test_a_short_request_does_not_light_it() -> void:
	var v := _kai(_view(), false)
	v.bag.slots = [{"id": "fish_crucian", "qty": 2}]
	v["plots"] = [{"state": "growing", "crop": "crop_radish", "ready_in": 3600000}]
	assert_int(P0Logic.today_rows(v).size()).is_equal(1)   # Old Kai's, short: no `Cook with`, no countdown
	assert_array(_dots(v)).is_empty()

## The first session (an account the new guide never ran): Catch the tutorial fish lights it — no `Sow your first plot`
## row any more; Deliver lights it again by its own key once the creel holds them.
func test_the_first_sessions_rows() -> void:
	var v := _view()
	v.erase("firsts")
	v["stall"] = {"board": {"requests": [{"id": P0Guide.TUTORIAL, "title": "Pond Catch", "item": "fish_crucian", "qty": 2,
		"have": 0, "status": "accepted"}]}}
	assert_array(_dots(v)).is_equal(["catch:" + P0Guide.TUTORIAL])
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

## Something new to hand in lights it again; seen, the same thing gone and back (the fish eaten, caught again) is new too.
func test_a_new_key_and_one_that_comes_back_light_it_again() -> void:
	var v := _kai(_view())
	var ui := await _ui(v)
	ui.open_today()
	ui.close_modal()
	var more := v.duplicate(true)
	more["boards"] = {"stall": {"slots": [{"id": "crate", "title": "Crate", "kind": "crop", "items": ["crop_radish"], "have": 2,
		"qty": 2, "ready": true, "status": "accepted"}]}}
	ui.set_view(more)
	assert_bool(ui.hud.today_dot_shown()).is_true()   # the crate is new; the delivery was seen
	ui.open_today()
	ui.close_modal()
	ui.set_view(_kai(more.duplicate(true), false))   # the fish eaten: Old Kai's hand-in row leaves
	assert_bool(ui.hud.today_dot_shown()).is_false()
	ui.set_view(more)                                  # caught again: ready to hand in once more
	assert_bool(ui.hud.today_dot_shown()).is_true()

## Spec ③ v3: Pip's Homestead request lights once, the first time — not again when its row leaves for Upgrade (a hand-in,
## its own dot) and the next level's gap row comes back.
func test_pips_homestead_request_lights_once_for_good() -> void:
	var v := _view()
	v["homestead"] = {"level": 1, "next": {"level": 2, "coins": {"need": 80, "have": 120}, "skills": [],
		"materials": [{"id": "wood", "name": "Timber", "need": 6, "have": 0}], "can_upgrade": false}}
	var ui := await _ui(v)
	assert_bool(ui.hud.today_dot_shown()).is_true()   # Pip's new request
	ui.open_today()
	ui.close_modal()
	var ready := v.duplicate(true)
	ready.homestead.next.materials[0].have = 6
	ready.homestead.next.can_upgrade = true
	ui.set_view(ready)
	assert_bool(ui.hud.today_dot_shown()).is_true()   # `Upgrade to Homestead Lv2`: a hand-in
	ui.open_today()
	ui.close_modal()
	var next := v.duplicate(true)
	next.homestead = {"level": 2, "next": {"level": 3, "coins": {"need": 80, "have": 120}, "skills": [],
		"materials": [{"id": "wood", "name": "Timber", "need": 8, "have": 0}], "can_upgrade": false}}
	ui.set_view(next)
	assert_bool(ui.hud.today_dot_shown()).is_false()  # the next level's request: seen once for good

## Today opened with other rows given is not Today's own: the dot stays.
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

## Nothing to hand in (crops growing, watering — not in Today): no dot from the start.
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

## A 包 spec ①: the first dish's `Cook it` row (an account the guide never ran) is not a request, so it is not in Today and
## lights nothing, cookable or not (it was #201's: 奕星 / 李白).
func test_cook_it_is_not_in_today() -> void:
	var v := _view()
	v.erase("firsts")
	v["plots"] = [{"state": "growing", "crop": "crop_radish", "ready_in": 3600000}]
	v["req_done"] = [P0Guide.TUTORIAL]
	v["cooking"] = {"cookbook": [{"id": "dish_grilled_crucian", "name": "Grilled Crucian", "known": true, "cooked": false,
		"can_cook": true}]}
	assert_bool(P0Logic.today_rows(v).any(func(r): return str(r.line).begins_with("Cook it"))).is_false()
	assert_array(_dots(v)).is_empty()

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

## 341: a panel left open over a passive expiry switches to the new authoritative row; Show follows that row.
func test_open_guide_today_refreshes_copy_progress_and_show_target() -> void:
	var v := _view()
	v.home = {"set": {"market": "gn-1850147~market0", "pond": "gn-1850147~pond0"}}
	v.guide = {"step": "t_fish", "row": {"line": "Catch 2 fish · Willow Pond", "icon": "fish", "go": "gn-1850147~pond0"},
		"progress": {"have": 0, "need": 2}}
	var ui := await _ui(v)
	ui.open_today()
	await await_idle_frame()
	var panel := ui._today_panel
	var first := panel._list.get_child(0)
	var pill := first.find_children("*", "UiShowPill", true, false)[0]
	var changed := v.duplicate(true)
	changed.guide.progress.have = 1
	ui.set_view(changed)
	ui._refresh_today()
	assert_bool(is_instance_valid(pill)).is_true()   # text updates do not drop the held Show pill
	assert_str(str(first.find_child("Line", true, false).get_meta("sentence"))).is_equal("Catch 2 fish · 1/2 · Willow Pond")
	changed.guide = {"step": "t_nadia_1", "row": {"line": "Bring Nadia 1 Radish · Riverside Market", "icon": "crop_radish", "go": "gn-1850147~market0"}}
	var shown := []
	ui.show_on_map.connect(func(go): shown.append(go))
	ui.set_view(changed)
	ui._refresh_today()
	assert_object(ui._today_panel).is_same(panel)
	assert_str(str(ui._today_rows[0].line)).is_equal("Bring Nadia 1 Radish · Riverside Market")
	panel.show_pressed.emit(0)
	assert_array(shown).is_equal(["outpost:gn-1850147~market0"])
	assert_str(ui.modal_kind).is_empty()

func test_open_today_projects_at_most_four_times_a_second() -> void:
	var v := _view()
	v.guide = {"step": "t_fish", "row": {"line": "Catch 2 fish", "icon": "fish", "go": ""}, "progress": {"have": 0, "need": 2}}
	var ui := await _ui(v)
	ui.open_today()
	var line: Label = ui._today_panel._list.get_child(0).find_child("Line", true, false)
	var next := v.duplicate(true)
	next.guide.progress.have = 1
	ui.set_view(next)
	assert_str(str(line.get_meta("sentence"))).is_equal("Catch 2 fish · 0/2")
	ui._today_refresh_ms -= 250
	ui.set_view(next)
	assert_str(str(line.get_meta("sentence"))).is_equal("Catch 2 fish · 1/2")
