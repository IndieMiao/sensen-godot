extends GdUnitTestSuite
## B6 语音房页面：列表 / 建房 / 进房、上下麦换 token 并重连桥、房主静音、举报即本地静音、
## 没有原生桥时的只读模式。

class FakeBridge extends VoiceBridge:
	var connects: Array = []
	var mic_calls: Array = []
	var volumes: Dictionary = {}
	var disconnects := 0
	var here := true
	func available() -> bool:
		return here
	func connect_room(url: String, token: String) -> void:
		connects.append({"url": url, "token": token})
		state = State.CONNECTED
	func disconnect_room() -> void:
		disconnects += 1
		state = State.IDLE
	func set_mic(enabled: bool) -> void:
		mic_calls.append(enabled)
	func set_volume(identity: String, volume: float) -> void:
		volumes[identity] = volume

var t: FakeTransport
var safety_t: FakeTransport
var fake: FakeBridge
var session: AuthSession

func before_test() -> void:
	session = AuthSession.new()
	session.complete_sign_in("uid-1", "id-1", "rt-1", 3600, "password", "a@b.co")
	session.set_server_user("me-1")
	t = FakeTransport.new([])
	safety_t = FakeTransport.new([])
	fake = FakeBridge.new()

func after_test() -> void:
	if FileAccess.file_exists(AuthSession.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AuthSession.PATH))

func _page(with_bridge := true) -> Control:
	var p := (load(AppRoutes.VOICE_ROOM) as PackedScene).instantiate()
	p.auth = session
	p.voice = VoiceApi.new(ApiClient.new("https://example.test/v1", t.callable()))
	p.safety = SafetyApi.new(ApiClient.new("https://example.test/v1", safety_t.callable()))
	if with_bridge:
		p.bridge = fake
	add_child(auto_free(p))
	return p

func _room(id := "r1", role := "listener", muted := false, host := "u-host") -> Dictionary:
	return {
		"id": id, "title": "午后闲聊", "host_id": host, "host_name": "Ann",
		"member_count": 2, "speaker_count": 1, "closed": false,
		"members": [
			{"user_id": host, "role": "host", "muted": false, "display_name": "Ann", "handle": "ann", "avatar": null},
			{"user_id": "me-1", "role": role, "muted": muted, "display_name": "Me", "handle": "me", "avatar": null},
		],
		"me": {"user_id": "me-1", "role": role, "muted": muted, "display_name": "Me", "handle": "me", "avatar": null},
		"livekit_url": "wss://lk.test", "token": "token-%s-%s" % [role, str(muted)],
	}

func test_lists_rooms_and_joining_connects_the_bridge_with_the_server_token() -> void:
	t.responses = [
		{"status": 200, "json": {"items": [{"id": "r1", "title": "午后闲聊", "host_name": "Ann", "member_count": 3}]}},
		{"status": 200, "json": _room()},
	]
	var p := _page()
	assert_bool(await p.fetch_rooms()).is_true()
	assert_bool(str(t.requests[0].url).ends_with("/v1/voice/rooms")).is_true()
	var row := p.list.get_node("Room_r1") as Button
	assert_object(row).is_not_null()
	assert_bool(row.text.contains("午后闲聊")).is_true()
	assert_bool(await p.join("r1")).is_true()
	assert_bool(str(t.requests[1].url).ends_with("/v1/voice/rooms/r1/join")).is_true()
	assert_bool(p.room_panel.visible).is_true()
	# 用服务端给的 URL 与 token 连，不自己拼。
	assert_int(fake.connects.size()).is_equal(1)
	assert_str(str(fake.connects[0]["url"])).is_equal("wss://lk.test")
	assert_str(str(fake.connects[0]["token"])).is_equal("token-listener-false")
	assert_bool(p.can_speak()).is_false()

func test_taking_the_mic_swaps_the_token_and_reconnects() -> void:
	t.responses = [{"status": 200, "json": _room()}, {"status": 200, "json": _room("r1", "speaker")}]
	var p := _page()
	assert_bool(await p.join("r1")).is_true()
	assert_str(p.mic_button.text).is_equal("Take the mic")
	assert_bool(await p.toggle_stage()).is_true()
	assert_that(t.requests[1].body).is_equal({"on": true})
	assert_str(p.me_role()).is_equal("speaker")
	assert_bool(p.can_speak()).is_true()
	assert_str(p.mic_button.text).is_equal("Leave the mic")
	# 新 token 到手就重连，并打开麦克风。
	assert_int(fake.connects.size()).is_equal(2)
	assert_str(str(fake.connects[1]["token"])).is_equal("token-speaker-false")
	assert_array(fake.mic_calls).is_equal([true])

## 我是房主时的房间：我 + 一个听众。
func _room_as_host(other_muted := false) -> Dictionary:
	return {
		"id": "r1", "title": "午后闲聊", "host_id": "me-1", "host_name": "Me",
		"member_count": 2, "speaker_count": 1, "closed": false,
		"members": [
			{"user_id": "me-1", "role": "host", "muted": false, "display_name": "Me", "handle": "me", "avatar": null},
			{"user_id": "u-other", "role": "listener", "muted": other_muted, "display_name": "Ann", "handle": "ann", "avatar": null},
		],
		"me": {"user_id": "me-1", "role": "host", "muted": false, "display_name": "Me", "handle": "me", "avatar": null},
		"livekit_url": "wss://lk.test", "token": "token-host",
	}

func test_muted_member_cannot_speak_and_host_can_mute() -> void:
	t.responses = [{"status": 200, "json": _room_as_host()}, {"status": 200, "json": _room_as_host(true)}]
	var p := _page()
	assert_bool(await p.join("r1")).is_true()
	assert_bool(p.is_host()).is_true()
	# 房主能看到别人的静音按钮，也能看到举报按钮。
	var other: Node = p.stage.get_node("Member_u-other")
	assert_object(other.find_child("Mute", true, false)).is_not_null()
	assert_object(other.find_child("Report", true, false)).is_not_null()
	assert_bool(await p.set_muted("u-other", true)).is_true()
	assert_bool(str(t.requests[1].url).contains("/v1/voice/rooms/r1/mute")).is_true()
	assert_that(t.requests[1].body).is_equal({"user_id": "u-other", "muted": true})
	var row := p.stage.get_node("Member_u-other") as Node
	assert_bool((row.find_child("Name", true, false) as Label).text.contains("Muted")).is_true()
	# 自己被静音时说不了话，按钮文案回到「上麦」。
	var q := _page()
	t.responses.append({"status": 200, "json": _room("r1", "listener", true)})
	assert_bool(await q.join("r1")).is_true()
	assert_bool(q.can_speak()).is_false()

func test_reporting_someone_mutes_them_locally_and_sends_the_report() -> void:
	t.responses = [{"status": 200, "json": _room()}]
	safety_t.responses = [{"status": 201, "json": {"ok": true}}]
	var p := _page()
	assert_bool(await p.join("r1")).is_true()
	assert_bool(await p.report("u-host", "harassment")).is_true()
	assert_float(float(fake.volumes.get("u-host", 1.0))).is_equal(0.0)
	assert_str(str(safety_t.requests[0].body.get("target_type", ""))).is_equal("user")
	assert_str(str(safety_t.requests[0].body.get("reason", ""))).is_equal("harassment")
	assert_str(p.status.text).is_equal("Thanks, we've received your report.")

func test_without_a_native_bridge_the_page_is_listen_only() -> void:
	t.responses = [{"status": 200, "json": _room()}]
	var p := _page(false)
	assert_object(p.bridge).is_null() # 桌面没有插件：工厂返回 null
	assert_bool(await p.join("r1")).is_true()
	assert_bool(p.mic_button.disabled).is_true()
	assert_str(p.status.text).is_equal("Listening only: voice isn't available on this device yet.")
	assert_bool(await p.toggle_stage()).is_false()

func test_leaving_disconnects_and_returns_to_the_list() -> void:
	t.responses = [{"status": 200, "json": _room()}, {"status": 200, "json": {"ok": true, "closed": false}},
		{"status": 200, "json": {"items": []}}]
	var p := _page()
	assert_bool(await p.join("r1")).is_true()
	assert_bool(await p.leave()).is_true()
	assert_int(fake.disconnects).is_equal(1)
	assert_bool(p.room_panel.visible).is_false()
	assert_str(p.status.text).is_equal("No rooms yet. Start one.")

func test_server_errors_are_explained() -> void:
	var p := _page()
	assert_str(p.describe_error({"code": "STAGE_FULL"})).is_equal("All mic seats are taken.")
	assert_str(p.describe_error({"code": "MUTED"})).is_equal("The host muted you.")
	assert_str(p.describe_error({"code": "VOICE_NOT_CONFIGURED"})).is_equal("Voice rooms aren't available on this server yet.")
	assert_str(p.describe_error({"code": "NOT_FOUND"})).is_equal("This room has ended.")

## 真机复查修正：进房后列表与建房行让位（否则房间信息被空列表挤到屏幕最底）；
## 房主的麦克风按钮直接禁用并说明，不再点出一句「房主始终在麦上」的报错。
func test_entering_a_room_hides_the_list_and_host_cannot_toggle_the_mic() -> void:
	t.responses = [{"status": 200, "json": _room_as_host()}]
	var p := _page()
	assert_bool(p.list_scroll.visible).is_true()
	assert_bool(p.new_room_row.visible).is_true()
	assert_bool(await p.join("r1")).is_true()
	assert_bool(p.list_scroll.visible).is_false()
	assert_bool(p.new_room_row.visible).is_false()
	assert_int(p.room_panel.size_flags_vertical).is_equal(Control.SIZE_EXPAND_FILL)
	assert_str(p.mic_button.text).is_equal("You're the host")
	assert_bool(p.mic_button.disabled).is_true()
	# 房主点上麦：什么也不发（服务端会 409，不该让用户看到报错）。
	var before := t.requests.size()
	assert_bool(await p.toggle_stage()).is_false()
	assert_int(t.requests.size()).is_equal(before)
	assert_str(p.status.text).is_empty()

func test_leaving_restores_the_list_and_create_row() -> void:
	t.responses = [{"status": 200, "json": _room()}, {"status": 200, "json": {"ok": true, "closed": false}},
		{"status": 200, "json": {"items": []}}]
	var p := _page()
	assert_bool(await p.join("r1")).is_true()
	assert_bool(p.list_scroll.visible).is_false()
	assert_bool(await p.leave()).is_true()
	assert_bool(p.list_scroll.visible).is_true()
	assert_bool(p.new_room_row.visible).is_true()

