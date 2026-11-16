extends GdUnitTestSuite
const Ban := preload("res://modules/p0/p0_voice_ban.gd")
const Room := preload("res://modules/p0/p0_voice_room.gd")
const Identity := preload("res://modules/p0/p0_identity.gd")
const FakeVoice := preload("res://tests/p0/test_p0_voice_room.gd").FakeVoice
const DIR := "user://test_voice_ban_identity/"
var old_locale := ""

class Deferred extends RefCounted:
	signal replied(result: Dictionary)
	func wait() -> Dictionary: return await replied

class SessionProbe extends P0Session:
	func _ready() -> void: pass

func before_test() -> void:
	old_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")

func after_test() -> void:
	TranslationServer.set_locale(old_locale)
	var d := DirAccess.open(DIR)
	if d:
		for name in d.get_files(): d.remove(name)

func _session() -> P0Session:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var s: P0Session = auto_free(SessionProbe.new())
	s.identity = Identity.new(DIR)
	s.accounts = true
	s.player_id = "p0-voice-ban-unit"
	s.identity.player = s.player_id
	s.identity.token = "ab".repeat(32)
	s.identity_ready = true
	s.transport = func(_m, _p, _b, _c): pass
	add_child(s)
	s.set_process(false)
	return s

func _room(session: P0Session = null) -> Room:
	var online: P0Online = auto_free(P0Online.new())
	var room: Room = auto_free(Room.new())
	room.voice = auto_free(FakeVoice.new())
	room.setup(session, online, "tea")
	return room

func test_missing_malformed_and_explicit_null_are_different() -> void:
	var b := Ban.new()
	assert_int(b.kind).is_equal(Ban.UNKNOWN)
	for value in [{}, {"until": ""}, {"until": 123}, {"until": "2026-11-20"}, {"until": "2026-11-20T08:00:00+00:00"},
			{"until": "2026-02-30T08:00:00.000Z"}]:
		assert_bool(b.take(value)).is_false()
		assert_int(b.kind).is_equal(Ban.UNKNOWN)
	assert_bool(b.take(null)).is_true()
	assert_int(b.kind).is_equal(Ban.CLEAR)
	assert_bool(b.blocked).is_false()
	assert_bool(b.take({"until": null})).is_true()
	assert_int(b.kind).is_equal(Ban.PERMANENT)
	assert_str(b.message(0)).is_equal("Voice chat is off for you.")
	assert_bool(b.take({})).is_false()
	assert_bool(b.blocked and b.stale).is_true()   # a malformed new response does not clear a trusted ban

func test_expiry_uses_the_whole_utc_instant_but_shows_local_calendar_date() -> void:
	var b := Ban.new()
	assert_bool(b.take({"until": "2026-11-20T18:00:00.123Z"})).is_true()
	assert_str(b.message(0, 480)).is_equal("Voice chat is off for you until Nov 21.")
	assert_str(b.message(0, -300)).is_equal("Voice chat is off for you until Nov 20.")
	assert_bool(b.expired(b.until_ms - 1)).is_false()
	assert_bool(b.expired(b.until_ms)).is_true()
	assert_str(b.message(b.until_ms)).is_empty()   # no expired date claimed to be a current ban
	assert_bool(b.blocked).is_true()             # local time cannot declare server punishment lifted

func test_status_unknown_does_not_hide_offered_or_invent_permanent() -> void:
	var room := _room()
	room.request = func(_m, _p, _b): return {"ok": true, "json": {"available": true, "age": "ok"}}
	await room.fetch_status()
	assert_bool(room.offered()).is_true()
	assert_int(room.ban.kind).is_equal(Ban.UNKNOWN)
	assert_bool(room.mic_blocked()).is_true()
	assert_str(room.ban_message()).is_empty()
	var notices := []
	room.notice.connect(func(text, failed): notices.append([text, failed]))
	await room.toggle_mic()
	assert_array(notices).is_equal([["Didn't go through · try again", true]])
	assert_bool(room.voice.calls.any(func(c): return c[0] == "join_with")).is_false()

func test_failed_refresh_does_not_grant_new_voice_but_a_live_mic_can_still_be_switched_off() -> void:
	var room := _room()
	room.request = func(_m, _p, _b): return {"ok": true, "json": {"available": true, "age": "ok", "ban": null}}
	await room.fetch_status()
	room.request = func(_m, _p, _b): return {"ok": false, "json": {}}
	await room.fetch_status()
	assert_bool(room.offered() and room.mic_blocked()).is_true()
	room.voice.is_active = true
	room.voice.microphone = true
	await room.toggle_mic()
	assert_bool(room.voice.microphone).is_false()

func test_limited_and_permanent_keep_the_entry_and_emit_only_existing_toast() -> void:
	var room := _room()
	var value := {"until": "2099-11-20T08:00:00.000Z"}
	room.request = func(_m, _p, _b): return {"ok": true, "json": {"available": true, "age": "ok", "ban": value}}
	var notices := []
	room.notice.connect(func(text, failed): notices.append([text, failed]))
	await room.fetch_status()
	assert_bool(room.offered() and room.mic_blocked()).is_true()
	await room.toggle_mic()
	assert_bool(notices[0][0].begins_with("Voice chat is off for you until ")).is_true()
	assert_bool(notices[0][1]).is_false()
	value.until = null
	await room.fetch_status()
	await room.toggle_mic()
	assert_array(notices[1]).is_equal(["Voice chat is off for you.", false])
	assert_bool(room.voice.calls.any(func(c): return c[0] == "join_with")).is_false()

func test_status_replies_cannot_reverse_order_or_erase_a_new_join_refusal() -> void:
	var room := _room()
	var first := Deferred.new()
	var second := Deferred.new()
	var n := [0]
	room.request = func(_m, _p, _b):
		n[0] += 1
		if n[0] == 1: return await first.wait()
		return await second.wait()
	room.fetch_status()
	room.fetch_status()
	second.replied.emit({"ok": true, "json": {"available": true, "age": "ok", "ban": {"until": null}}})
	first.replied.emit({"ok": true, "json": {"available": true, "age": "ok", "ban": null}})
	assert_int(room.ban.kind).is_equal(Ban.PERMANENT)
	var old_status := Deferred.new()
	room.request = func(_m, path, _b):
		if path.ends_with("status"): return await old_status.wait()
		return {"ok": false, "json": {"code": "VOICE_BANNED", "until": "2099-11-20T08:00:00.000Z"}}
	room.fetch_status()
	await room._call(HTTPClient.METHOD_POST, "heartbeat", {})
	old_status.replied.emit({"ok": true, "json": {"available": true, "age": "ok", "ban": null}})
	assert_int(room.ban.kind).is_equal(Ban.LIMITED)

func test_old_account_refusal_is_dropped_before_it_can_log_out_the_new_login() -> void:
	var s := _session()
	var room := _room(s)
	var delayed := Deferred.new()
	room.request = func(_m, _p, _b): return await delayed.wait()
	var states := []
	s.account_state.connect(func(kind, _detail): states.append(kind))
	room.fetch_status()
	# Same player, same token text: the login lifetime still differs.
	s._retire_context()
	delayed.replied.emit({"ok": false, "status": 401, "json": {"code": "account_deleted"}})
	assert_array(states).is_empty()
	assert_str(s.identity.token).is_equal("ab".repeat(32))
	assert_bool(s.identity_ready).is_true()
	assert_int(room.ban.kind).is_equal(Ban.UNKNOWN)

func test_old_heartbeat_ban_cannot_replace_a_newer_clear_status() -> void:
	var room := _room()
	var heartbeat := Deferred.new()
	room.request = func(_m, path, _body):
		if path.ends_with("heartbeat"): return await heartbeat.wait()
		return {"ok": true, "json": {"available": true, "age": "ok", "ban": null}}
	room._call(HTTPClient.METHOD_POST, "heartbeat", {})
	await room.fetch_status()
	heartbeat.replied.emit({"ok": false, "json": {"code": "VOICE_BANNED", "until": null}})
	assert_int(room.ban.kind).is_equal(Ban.CLEAR)
	assert_bool(room.mic_blocked()).is_false()

func test_older_status_refusal_cannot_override_a_newer_status_in_the_same_login() -> void:
	var s := _session()
	var room := _room(s)
	var old := Deferred.new()
	var current := Deferred.new()
	var n := [0]
	room.request = func(_m, _p, _b):
		n[0] += 1
		if n[0] == 1: return await old.wait()
		return await current.wait()
	room.fetch_status()
	room.fetch_status()
	current.replied.emit({"ok": true, "json": {"available": true, "age": "ok", "ban": null}})
	old.replied.emit({"ok": false, "status": 403, "json": {"code": "suspended", "until": null}})
	assert_bool(s.identity_ready).is_true()
	assert_int(room.ban.kind).is_equal(Ban.CLEAR)

func test_old_state_and_old_account_http_do_not_change_new_owner_or_clear_its_busy() -> void:
	var s := _session()
	var old := s.request_context()
	s._retire_context()
	s.busy = true
	s.view = {"seq": 9}
	s._finish(HTTPRequest.RESULT_SUCCESS, 401, '{"code":"unauthenticated"}'.to_utf8_buffer(), {}, old)
	assert_bool(s.busy).is_true()
	assert_dict(s.view).is_equal({"seq": 9})
	assert_str(s.identity.token).is_equal("ab".repeat(32))
	var called := []
	s.base_url = "http://127.0.0.1:1"
	s._account_request(HTTPClient.METHOD_GET, "/p0/hello", {}, func(r): called.append(r))
	var http: HTTPRequest = s.get_children().filter(func(node): return node is P0HttpRequest)[0]
	s._retire_context()
	http.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), '{"ok":true,"terms_version":"old"}'.to_utf8_buffer())
	assert_array(called).is_empty()   # before P0Identity's mutation callback

func test_expiry_schedules_one_check_and_clear_does_not_auto_start_voice() -> void:
	var room := _room()
	var clock := [Ban.parse_until("2026-11-20T08:00:00.000Z") - 1]
	room.now_ms = func(): return clock[0]
	var calls := [0]
	room.request = func(_m, _p, _b):
		calls[0] += 1
		return {"ok": true, "json": {"available": true, "age": "ok", "ban": {"until": "2026-11-20T08:00:00.000Z"}}}
	await room.fetch_status()
	clock[0] += 1
	room._next_status = 0
	room._process(0.1)
	for i in 10: room._process(0.1)
	assert_int(calls[0]).is_equal(2)
	assert_str(room.ban_message()).is_empty()
	assert_bool(room.mic_blocked()).is_true()
	room.request = func(_m, _p, _b): return {"ok": true, "json": {"available": true, "age": "ok", "ban": null}}
	await room.fetch_status()
	assert_bool(room.mic_blocked()).is_false()
	assert_bool(room.voice.calls.any(func(c): return c[0] == "join_with")).is_false()

func test_ban_final_code_never_enters_voice_reconnect_loop() -> void:
	var voice: PartyVoiceSession = auto_free(PartyVoiceSession.new())
	voice._wanted = true
	voice._failed("VOICE_BANNED")
	assert_bool(voice.active()).is_false()
	assert_str(voice.state).is_equal("idle")
	assert_str(voice.error).is_equal("VOICE_BANNED")
	voice._process(10.0)
	assert_str(voice.state).is_equal("idle")

func test_retired_voice_join_and_heartbeat_do_not_clear_new_pending_flags() -> void:
	var voice: PartyVoiceSession = auto_free(PartyVoiceSession.new())
	var old_join := Deferred.new()
	voice._request = func(_action, _body): return await old_join.wait()
	voice._wanted = true
	voice._connect_voice()
	assert_bool(voice._joining).is_true()
	voice.leave()
	voice._wanted = true
	voice._joining = true   # a new lifetime already has its own request out
	old_join.replied.emit({"ok": false, "json": {"code": "VOICE_BANNED"}})
	assert_bool(voice._wanted and voice._joining).is_true()
	var old_heartbeat := Deferred.new()
	voice._request = func(_action, _body): return await old_heartbeat.wait()
	voice._heartbeat()
	voice.leave()
	voice._wanted = true
	voice._polling = true
	old_heartbeat.replied.emit({"ok": false, "json": {"code": "VOICE_BANNED"}})
	assert_bool(voice._wanted and voice._polling).is_true()

func test_gray_mic_is_clickable_and_keeps_people_count() -> void:
	var keys = auto_free(load("res://scenes/p0/panels/p0_voice_keys.gd").new())
	add_child(keys)
	keys.show_mic(true)
	keys.set_mic(false, true)
	keys.set_count(3)
	var presses := []
	keys.mic_pressed.connect(func(): presses.append(true))
	keys.mic.pressed.emit()
	assert_bool(keys.mic.visible).is_true()
	assert_bool(keys.mic.disabled).is_false()
	assert_array(presses).is_equal([true])
	assert_str(keys.people.text).is_equal("3")
	assert_that(keys.mic.get_theme_color("icon_normal_color")).is_equal(UiTokens.COLOR_DISABLED_INK)
