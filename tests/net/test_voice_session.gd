extends GdUnitTestSuite

class Backend extends RefCounted:
	signal voice_event(raw: String)
	var calls: Array = []
	func request_permission(id: String): calls.append(["permission", id])
	func connect_voice(id: String, _url: String, _token: String): calls.append(["connect", id])
	func renew_lease(id: String, milliseconds: int): calls.append(["renew", id, milliseconds])
	func disconnect_voice(id: String): calls.append(["disconnect", id])
	func set_microphone(id: String, value: bool): calls.append(["microphone", id, value])
	func set_listening(id: String, value: bool): calls.append(["listening", id, value])

func _fixture(responses: Array) -> Array:
	var backend := Backend.new()
	var voice := PartyVoiceSession.new()
	add_child(auto_free(voice))
	voice.set_process(false)
	voice.set_backend(backend)
	var transport := FakeTransport.new(responses)
	var client := ApiClient.new("https://example.test/v1", transport.callable())
	client.token = "fixture-token"
	var session := FarmSession.new(client)
	return [voice, backend, session, transport]

func _grant(room := "room-1", lease := "lease-1234") -> Dictionary:
	return {"status": 200, "json": {"url": "wss://example.test", "token": "ephemeral-token", "room": room,
		"party_id": "party-1", "lease_id": lease, "capacity": 8, "lease_ms": 20000}}

func _event(voice: PartyVoiceSession, kind: String, extra := {}) -> void:
	voice._on_native_event(JSON.stringify({"event": kind, "session": voice._native_id}.merged(extra)))

func test_permission_denial_does_not_request_voice_credentials() -> void:
	var f := _fixture([])
	f[0].join(f[2])
	_event(f[0], "permission", {"granted": false})
	assert_bool(f[0].active()).is_false()
	assert_str(f[0].error).is_equal("MICROPHONE_DENIED")
	assert_array(f[3].requests).is_empty()

func test_join_is_muted_and_old_native_events_cannot_change_new_session() -> void:
	var f := _fixture([_grant()])
	f[0].join(f[2])
	var permission_id: String = f[0]._native_id
	_event(f[0], "permission", {"granted": true})
	await get_tree().process_frame
	assert_str(f[0].state).is_equal("connecting")
	assert_bool(f[0].microphone).is_false()
	f[0]._on_native_event(JSON.stringify({"event": "connected", "session": permission_id, "microphone": true}))
	assert_bool(f[0].microphone).is_false()
	_event(f[0], "connected", {"microphone": false, "participants": [{"id": "peer"}]})
	assert_str(f[0].state).is_equal("connected")
	f[0].set_microphone(true)
	assert_that(f[1].calls[-1][0]).is_equal("microphone")

func test_background_and_membership_change_stop_native_media() -> void:
	var f := _fixture([_grant(), {"status": 200, "json": {"ok": true}}])
	f[0].join(f[2]); _event(f[0], "permission", {"granted": true})
	await get_tree().process_frame
	_event(f[0], "connected")
	f[0].invalidate_membership()
	assert_str(f[0]._native_id).is_empty()
	assert_bool(f[0].active()).is_true()
	f[0]._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_bool(f[0].active()).is_false()
	assert_str(f[0].state).is_equal("idle")

func test_expired_backend_lease_stops_media_before_retry() -> void:
	var f := _fixture([_grant()])
	f[0].join(f[2]); _event(f[0], "permission", {"granted": true})
	await get_tree().process_frame
	_event(f[0], "connected")
	f[0]._lease_deadline = 0
	f[0]._heartbeat_at = Time.get_ticks_msec() + 100000
	f[0]._process(0)
	assert_str(f[0]._native_id).is_empty()
	assert_str(f[0].state).is_equal("reconnecting")
	assert_that(f[1].calls[-1][0]).is_equal("disconnect")

func test_grants_require_room_identity_capacity_and_bounded_lease() -> void:
	var valid: Dictionary = _grant().json
	assert_bool(PartyVoiceSession._valid_grant(valid)).is_true()
	for change in [{"url": "file:///tmp/no"}, {"capacity": 300}, {"lease_ms": 0}, {"party_id": ""}]:
		assert_bool(PartyVoiceSession._valid_grant(valid.merged(change, true))).is_false()

func test_automatic_room_rejoin_preserves_user_audio_choice_but_leave_resets_it() -> void:
	var f := _fixture([_grant(), _grant("room-2"), {"status": 200, "json": {"ok": true}}])
	f[0].join(f[2]); _event(f[0], "permission", {"granted": true})
	await get_tree().process_frame
	_event(f[0], "connected")
	f[0].set_microphone(true); f[0].set_listening(false)
	f[0].invalidate_membership()
	f[0]._process(0)
	await get_tree().process_frame
	_event(f[0], "connected")
	assert_that(f[1].calls[-2]).is_equal(["microphone", f[0]._native_id, true])
	assert_that(f[1].calls[-1]).is_equal(["listening", f[0]._native_id, false])
	f[0].leave()
	assert_bool(f[0]._desired_microphone).is_false()
	assert_bool(f[0]._desired_listening).is_true()

func test_cancelled_permission_event_cannot_start_microphone_or_join() -> void:
	var f := _fixture([])
	f[0].join(f[2])
	var cancelled: String = f[0]._native_id
	f[0].leave()
	f[0]._on_native_event(JSON.stringify({"event": "permission", "session": cancelled, "granted": true}))
	assert_bool(f[0].active()).is_false()
	assert_array(f[3].requests).is_empty()
