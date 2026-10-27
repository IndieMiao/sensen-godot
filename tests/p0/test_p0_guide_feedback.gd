extends GdUnitTestSuite

const Feedback := preload("res://modules/p0/p0_guide_feedback.gd")
const CATCH := {kind = "catch", result = "landed", fish = "fish_crucian", rarity = 1}
const RESEND := {kind = "guide", action = "resend", item = "seed_quick_radish", qty = 2, bagged = 2, left = 1}
const STORE := "user://test_p0_guide_feedback_quick.json"
const TIPS := "user://test_p0_guide_feedback_tips.json"

func after_test() -> void:
	for path in [STORE, TIPS]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _goal(have: int, need := 2, recover: Variant = null, seq := 10) -> Dictionary:
	return {seq = seq, home = {set = {pond = "own-town~pond_1"}}, guide = {
		step = "t_fish" if recover == null else "t_soup", recover = recover, progress = {have = have, need = need},
		row = {line = "Copy may change without changing the goal", go = "own-town~pond_1"}, end = null}}

func test_last_main_fish_keeps_2_of_2_when_server_has_already_skipped_to_soup() -> void:
	var before := _goal(1)
	var after := {seq = 11, guide = {step = "t_soup", recover = null, progress = {have = 0, need = 1}, row = {go = "home"}}}
	var f := Feedback.new()
	assert_str(str(f.take(before, after, [CATCH]).fish.text)).is_equal("Catch 2 fish 2/2")
	assert_dict(f.take(before, after, [CATCH]).fish).is_empty()   # retry of the same settlement
	assert_dict(f.take(after, after, []).fish).is_empty()       # polling or reconnect does not manufacture a float
	assert_int(before.guide.progress.have).is_equal(1)          # presentation never advances the server snapshot

func test_main_and_recover_progress_use_the_server_count_when_still_on_that_goal() -> void:
	assert_str(str(Feedback.fish_progress(_goal(0), _goal(1, 2, null, 11), [CATCH]).text)).is_equal("Catch 2 fish 1/2")
	assert_str(str(Feedback.fish_progress(_goal(0, 2, "r_fish_2"), _goal(1, 2, "r_fish_2", 11), [CATCH]).text)).is_equal("Catch 2 fish 1/2")
	assert_dict(Feedback.fish_progress(_goal(0, 1, "r_fish_1"), _goal(0, 1, "r_fish_1", 11), [CATCH])).is_empty()

func test_server_step_event_preserves_completion_when_an_earlier_catch_reply_was_lost() -> void:
	var after := {guide = {step = "t_soup", row = {go = "home"}, progress = {have = 0, need = 1}}}
	var events := [CATCH, {kind = "guide", action = "step", from = "t_fish", to = "t_meal"}]
	assert_str(str(Feedback.fish_progress(_goal(0), after, events).text)).is_equal("Catch 2 fish 2/2")

func test_refresh_before_a_lost_reel_reply_keeps_its_goal_but_a_new_cast_drops_it() -> void:
	var f := Feedback.new()
	var before := _goal(0, 1, "r_fish_1")
	var after := {seq = 11, guide = {step = "t_soup", recover = null, row = {go = "home"}}}
	f.sent({type = "reel", outcome = "landed"}, before)
	assert_dict(f.take(before, after, []).fish).is_empty()
	f.sent({type = "reel", outcome = "landed"}, after)   # retry after the refresh: don't erase the original goal
	assert_str(str(f.take(after, after, [CATCH]).fish.text)).is_equal("Catch 1 fish 1/1")
	f.sent({type = "reel", outcome = "landed"}, before)
	f.sent({type = "cast"}, after)
	assert_dict(f.take(after, after.merged({seq = 12}, true), [CATCH]).fish).is_empty()

func test_last_recover_fish_uses_the_old_need_when_recover_clears_or_changes() -> void:
	var after := {guide = {step = "t_soup", recover = "r_radish_sow", progress = null, row = {go = "home"}}}
	assert_str(str(Feedback.fish_progress(_goal(0, 1, "r_fish_1"), after, [CATCH]).text)).is_equal("Catch 1 fish 1/1")
	assert_str(str(Feedback.fish_progress(_goal(1, 2, "r_fish_2"), after, [CATCH]).text)).is_equal("Catch 2 fish 2/2")

func test_refresh_failures_traps_legacy_and_timeout_never_claim_a_guide_catch() -> void:
	for events in [[], [{kind = "catch", result = "escaped"}], [{kind = "trap", fish = 2}], [{kind = "item", id = "fish_crucian", delta = 1}]]:
		assert_dict(Feedback.fish_progress(_goal(0), _goal(1), events)).is_empty()
	assert_dict(Feedback.fish_progress({guide = {step = null, end = "legacy"}}, _goal(1), [CATCH])).is_empty()
	assert_dict(Feedback.fish_progress(_goal(1), {guide = {step = null, end = "timeout"}}, [CATCH])).is_empty()
	var unrelated := _goal(0)
	unrelated.guide.row.go = "home"
	assert_dict(Feedback.fish_progress(unrelated, _goal(1), [CATCH])).is_empty()

func test_empty_refresh_does_not_consume_the_replys_feedback_and_resends_are_once() -> void:
	var f := Feedback.new()
	assert_array(f.take({}, {seq = 20}, []).resends).is_empty()
	var out: Dictionary = f.take({}, {seq = 20}, [RESEND])
	assert_array(out.resends).has_size(1)
	assert_int(out.resends[0].bagged).is_equal(2)
	assert_str(out.resends[0].line).is_equal("Out of radishes? Here, two more quick ones.")
	assert_array(f.take({}, {seq = 20}, [RESEND]).resends).is_empty()
	assert_array(f.take({}, {seq = 19}, [RESEND]).resends).is_empty()
	assert_array(f.take({}, {seq = 21}, [RESEND.merged({left = 0}, true)]).resends).has_size(1)

func test_full_and_partial_bag_only_fly_the_confirmed_bagged_amount() -> void:
	for n in [0, 1, 2]:
		var out: Dictionary = Feedback.new().take({}, {seq = 1}, [RESEND.merged({bagged = n}, true)])
		assert_int(out.resends[0].bagged).is_equal(n)
		assert_dict(out.fish).is_empty()

class Pond extends Node:
	func p0_event(ev: Dictionary, _v: Dictionary) -> bool: return str(ev.get("kind", "")) == "catch"

func _view() -> Dictionary:
	return {seq = 10, energy = {value = 140, max = 200}, coins = 180, skills = {fishing = {level = 2}},
		bag = {capacity = 25, slots = []}, names = {seed_quick_radish = "Quick Radish Seeds", fish_crucian = "Pond Crucian"},
		residents = {res_pip = {affinity = 2, stage = "New Face", stage_from = 0, next_at = 15, next_stage = "Acquainted",
			request_state = "none", request = null, chatted_today = true, gift_today = false, meal = "none", need_stage = null, next_in = null}},
		guide = {step = "t_nadia_1", recover = "r_radish_sow", pip = {here = true, bang = true, line = Feedback.RESEND_LINE}}}

func _runtime(v: Dictionary) -> P0Runtime:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	rt.ui.tips_path = TIPS
	rt.session.transport = func(_m, _p, _b, _c): pass
	add_child(rt)
	await get_tree().process_frame
	rt.set_process(false)
	rt.session.set_process(false)
	rt.session.view = v
	rt.ui.set_view(v)
	rt.ui.set_surface("farm")
	return rt

func _texts(rt: P0Runtime) -> Array:
	return rt.ui.root.get_children().filter(func(n): return n is UiFloatText and not n.is_queued_for_deletion()).map(func(n): return n.text)

func _settle(rt: P0Runtime, after: Dictionary, events: Array) -> void:
	rt.session.view = after
	rt._on_state(after, events)
	for i in 4: await get_tree().process_frame

func test_runtime_last_catch_joins_the_landing_group_once_with_no_completion_toast() -> void:
	var before := _view().merged(_goal(1), true)
	var rt := await _runtime(before)
	rt.world = auto_free(Pond.new())
	var after := _view()
	after.seq = 11
	after.guide = {step = "t_soup", recover = null, row = {go = "home"}, progress = {have = 0, need = 1}}
	await _settle(rt, after, [CATCH, {kind = "xp", skill = "fishing", amount = 5, percent = 100}])
	assert_array(_texts(rt)).is_empty()   # before the fish reaches the hand
	var parts := rt.take_catch_floats()
	assert_array(parts.map(func(p): return p.get("text", ""))).contains(["Catch 2 fish 2/2"])
	assert_array(rt.take_catch_floats()).is_empty()
	rt.ui.queue_floats(parts, Vector2(180, 300))
	await get_tree().process_frame
	assert_array(_texts(rt)).contains(["Catch 2 fish 2/2", "+5 XP"])
	assert_str(rt.catch_toast).is_empty()
	assert_str(rt.ui.toast_text()).is_empty()
	await _settle(rt, after, [CATCH])
	assert_array(rt.take_catch_floats()).is_empty()

func test_runtime_resend_changes_the_open_bubble_and_only_floats_actual_seeds() -> void:
	var rt := await _runtime(_view())
	assert_bool(rt.ui.open_resident("res_pip")).is_true()
	var after := _view()
	after.seq = 11
	after.bag.slots = [{id = "seed_quick_radish", qty = 2}]
	after.guide.pip.line = "They're ready!"
	await _settle(rt, after, [RESEND])
	assert_str(str(rt.ui._reply.line)).is_equal(Feedback.RESEND_LINE)
	assert_str(rt.ui.speaker()).is_equal("res_pip")
	assert_array(_texts(rt)).is_equal(["+2 Quick Radish Seeds"])
	await _settle(rt, after, [RESEND])
	assert_array(_texts(rt)).is_equal(["+2 Quick Radish Seeds"])   # never +4 on a replay
	assert_dict(rt.ui.inbox_notice_shown()).is_empty()

func test_runtime_full_bag_resend_uses_one_ordinary_notice_after_the_dialogue_closes() -> void:
	var rt := await _runtime(_view())
	rt.ui.open_resident("res_pip")
	var after := _view()
	after.seq = 11
	after.bag.slots = [{id = "fish_crucian", qty = 10}]
	var parcel := {kind = "parcel", id = "seed_quick_radish", qty = 2, key = "guide_resend:1:0", waiting = false, expires_in = 86400000}
	var events := [parcel, RESEND.merged({bagged = 0}, true)]
	await _settle(rt, after, events)
	assert_array(_texts(rt)).is_empty()
	assert_dict(rt.ui.inbox_notice_shown()).is_empty()   # dialogue stays readable
	rt.ui.close_modal()
	for i in 3: await get_tree().process_frame
	assert_dict(rt.ui.inbox_notice_shown()).is_equal({title = "Sent to Inbox", item = "Quick Radish Seeds", quantity = "×2", line = "Expires in 24h"})
	assert_int(rt.ui.root.find_children("*", "UiItemFly", true, false).size()).is_equal(0)
	rt.ui._process(3.0)
	assert_dict(rt.ui.inbox_notice_shown()).is_empty()
	await _settle(rt, after, events)
	assert_dict(rt.ui.inbox_notice_shown()).is_empty()   # a replay does not reopen the expired notice

func test_late_resend_reply_never_reopens_a_dialogue_the_player_closed() -> void:
	var rt := await _runtime(_view())
	rt.ui.open_resident("res_pip")
	rt.ui.close_modal()
	await _settle(rt, _view().merged({seq = 11}, true), [RESEND])
	assert_str(rt.ui.modal_kind).is_empty()
	assert_array(_texts(rt)).is_equal(["+2 Quick Radish Seeds"])
	var flights := rt.ui.root.get_children().filter(func(n): return n is UiItemFly)
	assert_array(flights).has_size(1)
	assert_int(flights[0].count).is_equal(2)   # visible Bag: the existing item flight carries the confirmed amount

func test_first_chat_and_resend_share_a_group_without_overlapping_pills() -> void:
	var rt := await _runtime(_view())
	rt.ui.open_resident("res_pip")
	var events := [{kind = "affinity", resident = "res_pip", delta = 2, total = 4, reason = "chat"}, RESEND]
	var after := _view().merged({seq = 11}, true)
	await _settle(rt, after, events)
	assert_array(_texts(rt)).is_equal(["+2 Quick Radish Seeds", "+2 · first chat today"])
	var pills := rt.ui.root.get_children().filter(func(n): return n is UiFloatText)
	assert_float(absf(pills[0].position.y - pills[1].position.y)).is_greater(20.0)
	await _settle(rt, after, events)
	assert_array(_texts(rt)).is_equal(["+2 Quick Radish Seeds", "+2 · first chat today"])
