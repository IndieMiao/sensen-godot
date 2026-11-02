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

## P0's rooms and ponds (2026-11-02): join_with takes the caller's grant request; the grant names `self` (the hub's peer
## id) and `blocked` instead of a party; per person, Mute is this phone's volume and Block never subscribes, both set
## again on every connect; an older plugin without per_participant is never asked for either.
class PeopleBackend extends Backend:
	var per := true
	func capabilities() -> String: return JSON.stringify({"protocol": 1, "supported": true, "per_participant": per,
		"publish_permissions": per})
	func set_participant_volume(id: String, who: String, v: float): calls.append(["volume", id, who, v])
	func set_participant_subscribed(id: String, who: String, on: bool): calls.append(["subscribed", id, who, on])
	func set_publish_allowed(id: String, who: String, on: bool): calls.append(["publish", id, who, on])

func _p0_grant(blocked := ["7"]) -> Dictionary:
	return {"url": "wss://example.test", "token": "ephemeral-token", "room": "p0-dev-sh_tea_1-1", "lease_id": "lease-p0-1",
		"capacity": 30, "lease_ms": 20000, "self": 3, "blocked": blocked}

func _p0_fixture(per := true, grant := {}) -> Array:
	var backend := PeopleBackend.new()
	backend.per = per
	var voice := PartyVoiceSession.new()
	add_child(auto_free(voice))
	voice.set_process(false)
	voice.set_backend(backend)
	var asked: Array = []
	var g := grant if not grant.is_empty() else _p0_grant()
	var request := func(action: String, body: Dictionary) -> Dictionary:
		asked.append([action, body])
		return {"ok": true, "json": g if action == "join" else {"ok": true, "room": g.room, "lease_ms": 20000}}
	return [voice, backend, request, asked]

func test_p0_join_with_asks_its_own_request_and_keeps_self_and_blocked() -> void:
	var f := _p0_fixture()
	f[0].join_with(f[2])
	_event(f[0], "permission", {"granted": true})
	await get_tree().process_frame
	assert_str(f[3][0][0]).is_equal("join")
	assert_str(f[0].peer_self).is_equal("3")
	assert_array(f[0].blocked).is_equal(["7"])
	assert_int(f[0].capacity).is_equal(30)
	assert_bool(f[1].calls.any(func(c): return c[0] == "connect")).is_true()
	_event(f[0], "connected", {"participants": [{"id": "3", "local": true}, {"id": "7"}]})
	assert_bool(f[1].calls.has(["subscribed", f[0]._native_id, "7", false])).is_true()   # blocked from the grant on
	f[0].set_muted("5", true)
	assert_bool(f[1].calls.has(["volume", f[0]._native_id, "5", 0.0])).is_true()
	assert_bool(f[0].is_muted("5")).is_true()
	f[0].set_blocked(["5"])   # the hub's voice_blocks: 7 let go, 5 blocked
	assert_bool(f[1].calls.has(["subscribed", f[0]._native_id, "7", true])).is_true()
	assert_bool(f[1].calls.has(["subscribed", f[0]._native_id, "5", false])).is_true()
	f[0].leave()
	assert_str(f[0].peer_self).is_equal("")
	assert_array(f[0].blocked).is_empty()
	assert_bool(f[0].is_muted("5")).is_false()
	await get_tree().process_frame
	assert_str(f[3][-1][0]).is_equal("leave")

func test_p0_mutes_and_blocks_go_again_onto_a_reconnected_room() -> void:
	var f := _p0_fixture()
	f[0].join_with(f[2]); _event(f[0], "permission", {"granted": true})
	await get_tree().process_frame
	_event(f[0], "connected")
	f[0].set_muted("5", true)
	f[1].calls.clear()
	f[0]._native_id = "native-2"   # a fresh native room after a reconnect
	_event(f[0], "connected")
	assert_bool(f[1].calls.has(["subscribed", "native-2", "7", false])).is_true()
	assert_bool(f[1].calls.has(["volume", "native-2", "5", 0.0])).is_true()

func test_p0_an_older_plugin_is_never_asked_per_person() -> void:
	var f := _p0_fixture(false)
	f[0].join_with(f[2]); _event(f[0], "permission", {"granted": true})
	await get_tree().process_frame
	_event(f[0], "connected")
	f[0].set_muted("5", true)
	f[0].set_blocked(["5"])
	assert_bool(f[0].per_participant()).is_false()
	assert_bool(f[1].calls.any(func(c): return c[0] in ["volume", "subscribed"])).is_false()

func test_p0_grant_needs_self_not_a_party_and_allows_a_big_room() -> void:
	var g := _p0_grant()
	assert_bool(PartyVoiceSession._valid_grant(g, true)).is_true()
	assert_bool(PartyVoiceSession._valid_grant(g)).is_false()   # Journey's still needs its party and at most 8
	var no_self := g.duplicate(); no_self.erase("self")
	assert_bool(PartyVoiceSession._valid_grant(no_self, true)).is_false()
	var too_big := g.duplicate(); too_big["capacity"] = 65
	assert_bool(PartyVoiceSession._valid_grant(too_big, true)).is_false()
	var bad_blocked := g.duplicate(); bad_blocked["blocked"] = "7"
	assert_bool(PartyVoiceSession._valid_grant(bad_blocked, true)).is_false()
	var party: Dictionary = _grant().json
	assert_bool(PartyVoiceSession._valid_grant(party)).is_true()

## P0's voice/join refusals (后裔 on #645): a final one ends the session with its code, no retry; VOICE_UNAVAILABLE
## (LiveKit's side) waits and tries again; a heartbeat's LEASE_EXPIRED joins again as Journey's VOICE_EXPIRED does.
func test_p0_final_refusals_end_and_only_voice_unavailable_retries() -> void:
	for code in ["VOICE_OFF", "NOT_IN_ROOM", "VOICE_NOT_HERE", "VOICE_ROOM_FULL", "AGE_GATE", "UNAUTHENTICATED"]:
		var voice := PartyVoiceSession.new()
		add_child(auto_free(voice))
		voice.set_process(false)
		voice.set_backend(PeopleBackend.new())
		voice.join_with(func(_a: String, _b: Dictionary) -> Dictionary: return {"ok": false, "json": {"code": code}})
		_event(voice, "permission", {"granted": true})
		await get_tree().process_frame
		assert_bool(voice.active()).override_failure_message(code).is_false()
		assert_str(voice.error).is_equal(code)
	var busy := PartyVoiceSession.new()
	add_child(auto_free(busy))
	busy.set_process(false)
	busy.set_backend(PeopleBackend.new())
	busy.join_with(func(_a: String, _b: Dictionary) -> Dictionary: return {"ok": false, "json": {"code": "VOICE_UNAVAILABLE"}})
	_event(busy, "permission", {"granted": true})
	await get_tree().process_frame
	assert_bool(busy.active()).is_true()
	assert_str(busy.state).is_equal("reconnecting")

func test_p0_lease_expired_on_a_heartbeat_joins_again() -> void:
	var f := _p0_fixture()
	f[0].join_with(f[2]); _event(f[0], "permission", {"granted": true})
	await get_tree().process_frame
	_event(f[0], "connected")
	f[0]._request = func(_a: String, _b: Dictionary) -> Dictionary: return {"ok": false, "json": {"code": "LEASE_EXPIRED"}}
	f[0]._heartbeat()
	await get_tree().process_frame
	assert_bool(f[0].active()).is_true()
	assert_str(f[0].state).is_equal("reconnecting")
	assert_str(f[0]._native_id).is_equal("")

## SGODOT-384 (周瑜 on #647): a block keeps this phone's tracks from them through LiveKit's subscription permissions, as
## well as taking none of theirs — on connect, on a new list, and allowed again once off it; an older plugin without
## publish_permissions is never asked.
func test_p0_block_keeps_our_tracks_from_them_through_livekit() -> void:
	var f := _p0_fixture()
	f[0].join_with(f[2]); _event(f[0], "permission", {"granted": true})
	await get_tree().process_frame
	_event(f[0], "connected")
	var id: String = f[0]._native_id
	assert_bool(f[1].calls.has(["publish", id, "7", false])).is_true()   # the grant's block, on connect
	f[0].set_blocked(["5"])
	assert_bool(f[1].calls.has(["publish", id, "7", true])).is_true()   # off the list: allowed again
	assert_bool(f[1].calls.has(["publish", id, "5", false])).is_true()
	var old := _p0_fixture(false)
	old[0].join_with(old[2]); _event(old[0], "permission", {"granted": true})
	await get_tree().process_frame
	_event(old[0], "connected")
	old[0].set_blocked(["5"])
	assert_bool(old[1].calls.any(func(c): return c[0] == "publish")).is_false()

## SGODOT-384 (李元芳 on 384 f25aa80d): the Android plugin is a JNISingleton, whose methods has_method never sees — a
## script-less backend is asked capabilities() outright, only a scripted test adapter has_method. (Mute and Block read
## false on phones and never reached LiveKit.)
func test_a_native_backend_is_never_judged_by_has_method() -> void:
	var voice := PartyVoiceSession.new()
	add_child(auto_free(voice))
	voice.set_process(false)
	var native := Object.new()   # no script, as the JNISingleton: has_method sees nothing it can call
	voice._backend = native
	assert_bool(voice._adapter_without("capabilities")).is_false()
	assert_bool(voice._adapter_without("set_publish_allowed")).is_false()
	native.free()
	var adapter := PeopleBackend.new()
	voice._backend = adapter
	assert_bool(voice._adapter_without("capabilities")).is_false()
	assert_bool(voice._adapter_without("no_such_method")).is_true()
	assert_bool(voice.per_participant()).is_true()
	assert_bool(voice.publish_permissions()).is_true()
	voice._backend = null

## Blocks go to the native room before the mic is turned on at a connect (SGODOT-384: a track published first could be
## taken by the blocked one before the permissions arrive).
func test_blocks_are_set_before_the_microphone_on_connect() -> void:
	var f := _p0_fixture()
	f[0].join_with(f[2])
	_event(f[0], "permission", {"granted": true})
	await get_tree().process_frame
	_event(f[0], "connected", {"participants": []})
	var order: Array = f[1].calls.map(func(c): return str(c[0])).filter(func(n): return n in ["publish", "subscribed", "microphone"])
	# both of the block's calls there, both before the mic (周瑜 on #650: a missing one finds -1 and would pass)
	assert_int(order.find("subscribed")).is_greater_equal(0)
	assert_int(order.find("publish")).is_greater_equal(0)
	assert_int(order.find("microphone")).is_greater(order.find("subscribed"))
	assert_int(order.find("microphone")).is_greater(order.find("publish"))
