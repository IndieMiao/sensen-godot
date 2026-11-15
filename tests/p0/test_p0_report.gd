extends GdUnitTestSuite
## Real HUD→drawer→P0VoiceRoom.report with a controllable HTTP seam, no services/real reports.
const Drawer := preload("res://scenes/p0/account/p0_acc_report.gd")
const Room := preload("res://modules/p0/p0_voice_room.gd")
const FakeVoice := preload("res://tests/p0/test_p0_voice_room.gd").FakeVoice
var ui: P0Ui
var room: P0VoiceRoom
var online: P0Online
var session: P0Session
var http: Reply

class Reply extends Node:
	signal answer(body: Dictionary)
	var calls: Array = []
	func request(method: int, path: String, body: Dictionary) -> Dictionary:
		calls.append({"method": method, "path": path, "body": body.duplicate()})
		return await answer
	func finish(result := "sent") -> void:
		answer.emit({"ok": result != "failed", "json": {"already": result == "already"}})

func before_test() -> void:
	session = auto_free(P0Session.new())   # no _ready/network; the production identity signal still runs
	session.player_id = "reporter-A"
	session.accounts = true
	session.identity_ready = true
	online = auto_free(P0Online.new())
	online.transport = func(_m): pass
	online.outpost = "sf_pond"
	online.room = 1
	online.epoch = 1
	online.self_id = 1
	online.members = {1: {"player": "self", "name": "Me"}, 4: {"player": "target-a", "name": "Home"}}
	room = auto_free(Room.new())
	room.voice = auto_free(FakeVoice.new())
	room.setup(session, online, "pond")
	room.available = true
	room.age = "ok"
	http = auto_free(Reply.new())
	room.request = http.request
	ui = auto_free(P0Ui.new())
	ui.quick_store = "user://test_report_bar_%d.json" % OS.get_process_id()
	ui.player_of = func() -> String: return session.player_id
	add_child(ui)
	await await_idle_frame()
	ui.root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ui.root.size = Vector2(360, 800)
	ui.set_surface("busy")
	ui.set_voice_room(room)

func after_test() -> void:
	if FileAccess.file_exists(ui.quick_store): DirAccess.remove_absolute(ProjectSettings.globalize_path(ui.quick_store))

func _open() -> UiDrawer:
	ui.open_people()
	ui._people.report_pressed.emit(4)
	return ui._report_flow.drawer

func _send(d, reason := "harassment") -> void:
	d.choose(reason)
	d.submit.activated.emit()

func test_opening_never_sends_and_all_five_rows_map_to_server_enums() -> void:
	var d = _open()
	assert_array(d.choices.keys()).is_equal(["offensive_name", "harassment", "offensive_voice", "cheating", "other"])
	assert_str(d.submit.label).is_equal("Choose a reason")
	assert_bool(d.submit.disabled).is_true()
	assert_array(http.calls).is_empty()
	for id in d.choices:
		assert_float(d.choices[id].custom_minimum_size.y).is_equal(52.0)
		_send(d, id)
		assert_dict(http.calls.back().body).is_equal({"peer": 4, "reason": id})
		http.finish("failed")
		assert_str(d.selected).is_equal(id)

func test_non_voice_reports_remain_and_voice_depends_on_local_offer_not_target_mic() -> void:
	room.available = false
	var d = _open()
	assert_int(d.choices.size()).is_equal(4)
	assert_bool(d.choices.has("offensive_voice")).is_false()
	assert_float(d.height).is_equal(380.0)
	d.close.pressed.emit()
	room.available = true
	d = _open()
	assert_bool(d.choices.has("offensive_voice")).is_true()   # target has never spoken
	_send(d, "offensive_voice")
	http.finish()

func test_pending_swallows_repeated_back_scrim_close_and_submit_and_restores_on_failure() -> void:
	var d = _open()
	_send(d)
	assert_bool(d.busy).is_true()
	assert_int(d.submit.phase).is_equal(CommandLifecycle.State.PENDING)
	d.choose("cheating")
	d.close.pressed.emit()
	assert_bool(ui.close_top_layer()).is_true()
	assert_bool(ui.close_top_layer()).is_true()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	ui._modal_veil.gui_input.emit(click)
	d.submit.activated.emit()
	d._begin(Vector2(100, 10), null)
	assert_bool(d._pressing).is_false()
	assert_int(http.calls.size()).is_equal(1)
	assert_str(d.selected).is_equal("harassment")
	assert_str(ui.modal_kind).is_equal("report")
	http.finish("failed")
	assert_bool(d.busy).is_false()
	assert_bool(d.close.disabled).is_false()
	assert_str(ui._sys.message).is_equal("Didn't go through · try again")
	assert_bool(ui._sys.visible).is_true()
	_send(d, "cheating")
	http.finish("already")
	assert_str(ui.toast_text()).is_equal("You already reported this")
	assert_str(ui.modal_kind).is_empty()

func test_success_and_already_cache_handles_across_rooms_but_not_reused_peers() -> void:
	var d = _open()
	_send(d)
	http.finish()
	assert_str(ui.toast_text()).is_equal("Report sent")
	online.members.erase(4)
	online.members[7] = {"player": "target-a", "name": "Renamed"}
	online.room = 2
	online.epoch = 2
	ui.open_people()
	ui._people.report_pressed.emit(7)
	assert_str(ui.modal_kind).is_equal("people")
	assert_str(ui.toast_text()).is_equal("You already reported this")
	assert_int(http.calls.size()).is_equal(1)
	online.members[4] = {"player": "target-b", "name": "Home"}
	ui._report(4)
	assert_str(ui.modal_kind).is_equal("report")
	_send(ui._report_flow.drawer)
	http.finish("already")
	assert_str(ui.toast_text()).is_equal("You already reported this")

func test_submit_resolves_same_handle_to_new_peer_and_never_reports_a_replacement() -> void:
	var d = _open()
	online.members[7] = online.members[4]
	online.members[4] = {"player": "target-b", "name": "Home"}
	_send(d)
	assert_int(http.calls[0].body.peer).is_equal(7)
	http.finish("failed")
	online.members.erase(7)
	_send(d)
	assert_int(http.calls.size()).is_equal(1)
	assert_bool(d.busy).is_false()
	assert_str(d.selected).is_equal("harassment")

func test_room_changed_before_submit_and_voice_no_longer_offered_do_not_send() -> void:
	var d = _open()
	room.available = false
	_send(d, "offensive_voice")
	assert_array(http.calls).is_empty()
	online.room += 1
	_send(d, "harassment")
	assert_array(http.calls).is_empty()
	assert_bool(d.busy).is_false()

func test_logout_clears_cache_and_late_response_cannot_close_new_accounts_drawer() -> void:
	var d = _open()
	_send(d)
	session.identity_ready = false
	assert_str(ui.modal_kind).is_empty()
	session.player_id = "reporter-B"
	session.identity_ready = true
	var next = _open()
	http.finish()
	assert_str(ui.modal_kind).is_equal("report")
	assert_object(ui._report_flow.drawer).is_same(next)
	assert_str(ui.toast_text()).is_empty()
	_send(next)
	http.finish()
	assert_str(ui.toast_text()).is_equal("Report sent")
	session.identity_ready = false
	session.identity_ready = true   # same player, new login: cleared too
	assert_object(_open()).is_not_null()
	assert_str(ui.modal_kind).is_equal("report")

func test_timeout_keeps_selection_and_late_result_does_not_turn_failure_into_success() -> void:
	var d = _open()
	_send(d)
	ui._report_flow._timeout.timeout.emit()
	assert_bool(d.busy).is_false()
	assert_str(d.selected).is_equal("harassment")
	http.finish()
	assert_str(ui.modal_kind).is_equal("report")
	assert_str(ui.toast_text()).is_empty()
	_send(d)
	http.finish("already")
	assert_str(ui.toast_text()).is_equal("You already reported this")

func test_a_forced_new_layer_and_system_gate_are_not_closed_by_report_response() -> void:
	var d = _open()
	_send(d)
	ui.open_people()
	await await_idle_frame()
	assert_object(ui._report_flow._timeout).is_null()
	http.finish()
	assert_str(ui.modal_kind).is_equal("people")
	assert_str(ui.toast_text()).is_empty()
	d = _open()
	_send(d)
	ui.show_account_state("suspended")
	http.finish()
	assert_object(ui._screen).is_not_null()
	assert_str(ui.toast_text()).is_empty()

func test_normal_close_back_and_scrim_do_not_submit_or_leave_a_cached_target() -> void:
	var d = _open()
	d.choose("other")
	d.close.pressed.emit()
	assert_str(ui.modal_kind).is_empty()
	d = _open()
	assert_str(d.selected).is_empty()
	assert_bool(ui.close_top_layer()).is_true()
	assert_str(ui.modal_kind).is_empty()
	d = _open()
	ui.back_modal()
	assert_str(ui.modal_kind).is_empty()
	assert_array(http.calls).is_empty()

func test_names_are_never_translated_and_only_name_is_trimmed_in_both_sentences() -> void:
	online.members[4].name = "WWWWWWWWWWWWWWWW"
	var d = _open()
	await await_idle_frame()
	d._names()
	assert_int(d.title.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	assert_int(d.privacy.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	assert_str(d.title.text).starts_with("Report ")
	assert_str(d.title.text).ends_with("…")
	assert_str(d.privacy.text).starts_with("Reports are private. ")
	assert_str(d.privacy.text).ends_with(" won't know it was you.")

func test_chinese_sentence_translates_but_home_as_player_name_does_not() -> void:
	var kept = Localization.p0_translation
	var locale := TranslationServer.get_locale()
	var t = preload("res://modules/ui/localization.gd").P0Translation.new()
	t.set_table({"Report %s": "举报 %s", "Home": "家园", "Reports are private. %s won't know it was you.": "举报是保密的，%s 不会知道是你举报的。"})
	Localization.p0_translation = t
	TranslationServer.set_locale("zh_CN")
	var d = _open()
	await await_idle_frame()
	d._names()
	assert_str(d.title.text).is_equal("举报 Home")
	assert_str(d.privacy.text).contains("Home")
	assert_str(d.privacy.text).not_contains("家园")
	Localization.p0_translation = kept
	TranslationServer.set_locale(locale)

func test_reentering_with_a_new_voice_room_keeps_confirmed_handle_in_same_login() -> void:
	var d = _open()
	_send(d)
	http.finish()
	ui.set_voice_room(null)
	var other: P0VoiceRoom = auto_free(Room.new())
	other.voice = room.voice
	other.request = http.request
	other.setup(session, online, "pond")
	ui.set_voice_room(other)
	ui.open_people()
	ui._report(4)
	assert_str(ui.modal_kind).is_equal("people")
	assert_str(ui.toast_text()).is_equal("You already reported this")
	assert_int(http.calls.size()).is_equal(1)
