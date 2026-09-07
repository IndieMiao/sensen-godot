extends GdUnitTestSuite
## B2：会话列表（渲染、@handle 发起单聊、点会话压栈）与聊天页（历史升序、已读、发送幂等、实时事件、撤回、错误文案）。

class NavRecorder extends RefCounted:
	var calls: Array = []
	func go(route: String, args: Dictionary) -> void:
		calls.append({"route": route, "args": args})

var session: AuthSession
var im_t: FakeTransport
var profile_t: FakeTransport
var nav: NavRecorder

func before_test() -> void:
	session = AuthSession.new()
	session.complete_sign_in("uid-1", "id-1", "rt-1", 3600, "password", "a@b.co")
	session.set_server_user("me-1")
	im_t = FakeTransport.new([])
	profile_t = FakeTransport.new([])
	nav = NavRecorder.new()

func after_test() -> void:
	if FileAccess.file_exists(AuthSession.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AuthSession.PATH))

func _im_api() -> ImApi:
	return ImApi.new(ApiClient.new("https://example.test/v1", im_t.callable()))

func _list_page() -> Control:
	var p := (load(AppRoutes.tab_scene("im")) as PackedScene).instantiate()
	p.auth = session
	p.im = _im_api()
	p.profile = ProfileApi.new(ApiClient.new("https://example.test/v1", profile_t.callable()))
	p.navigate = nav.go
	add_child(auto_free(p))
	return p

func _conv(id: String, name: String, unread := 0, last_text := "") -> Dictionary:
	return {"id": id, "kind": "dm", "title": null, "peer": {"user_id": "u-%s" % id, "display_name": name, "handle": null, "avatar": null},
		"member_count": 2, "last_seq": 3, "last_read_seq": 3 - unread, "unread": unread,
		"last_message": {} if last_text.is_empty() else {"id": "m9", "seq": 3, "sender_id": "u-x", "kind": "text", "body": {"text": last_text}, "created_at": 0, "deleted": false},
		"last_message_at": 0, "created_at": 0}

func _chat_page(c: Dictionary) -> Control:
	var p := (load(AppRoutes.CHAT) as PackedScene).instantiate()
	p.auth = session
	p.im = _im_api()
	p.setup({"conversation": c})
	add_child(auto_free(p))
	return p

func _msg(id: String, seq: int, sender: String, text: String) -> Dictionary:
	return {"id": id, "conversation_id": "c1", "seq": seq, "sender_id": sender, "client_id": id, "kind": "text", "body": {"text": text}, "created_at": seq * 1000, "deleted": false}

func test_list_renders_conversations_with_unread_and_preview() -> void:
	im_t.responses = [{"status": 200, "json": {"items": [_conv("c1", "Ali", 2, "hey"), _conv("c2", "Bob")]}}]
	var p := _list_page()
	assert_bool(await p.refresh()).is_true()
	assert_bool(str(im_t.requests[0].url).ends_with("/v1/im/conversations")).is_true()
	assert_int(p.list.get_child_count()).is_equal(2)
	var first: Button = p.list.get_child(0)
	assert_str(first.name).is_equal("Conv_c1")
	assert_str(first.text).is_equal("Ali  (2)\nhey")
	assert_str((p.list.get_child(1) as Button).text).is_equal("Bob\nNo messages yet")
	first.pressed.emit()
	assert_int(nav.calls.size()).is_equal(1)
	assert_str(nav.calls[0].route).is_equal(AppRoutes.CHAT)
	assert_str(nav.calls[0].args.conversation.id).is_equal("c1")

func test_start_chat_by_handle_looks_up_profile_then_opens_dm() -> void:
	profile_t.responses = [{"status": 200, "json": {"user_id": "u-9", "display_name": "Nine"}}]
	im_t.responses = [{"status": 201, "json": _conv("c9", "Nine")}]
	var p := _list_page()
	p.handle_edit.text = " @Nine "
	assert_bool(await p.start_chat()).is_true()
	assert_bool(str(profile_t.requests[0].url).ends_with("/v1/users/%40nine/profile")).is_true()
	assert_that(im_t.requests[0].body).is_equal({"user_id": "u-9"})
	assert_str(nav.calls[0].args.conversation.id).is_equal("c9")
	assert_str(p.handle_edit.text).is_empty()
	# FakeTransport 的游标不会因重新赋值 responses 而回退：追加而不是替换。
	profile_t.responses.append({"status": 404, "json": {"code": "NOT_FOUND"}})
	p.handle_edit.text = "ghost"
	assert_bool(await p.start_chat()).is_false()
	assert_bool(p.status.text.contains("No one")).is_true()

func test_list_hints_for_dev_session_and_unreachable_server() -> void:
	session.sign_out()
	session.complete_sign_in("dev-local", "dev-token", "", 3600, "dev", "dev@local")
	var p := _list_page()
	assert_bool(await p.refresh()).is_false()
	assert_int(im_t.requests.size()).is_equal(0)
	assert_bool(p.status.text.contains("Sign in")).is_true()
	session.sign_out()
	session.complete_sign_in("uid-1", "id-1", "rt-1", 3600, "password", "a@b.co")
	im_t.responses = [{"error": "timeout"}]
	var q := _list_page()
	assert_bool(await q.refresh()).is_false()
	assert_bool(q.status.text.contains("connection")).is_true()

func test_chat_loads_history_ascending_marks_read_and_titles_by_peer() -> void:
	im_t.responses = [
		{"status": 200, "json": {"items": [_msg("m3", 3, "u-x", "third"), _msg("m2", 2, "me-1", "second"), _msg("m1", 1, "u-x", "first")]}},
		{"status": 200, "json": {"ok": true, "last_read_seq": 3}},
	]
	var c := _conv("c1", "Ali", 3, "third")
	var p := _chat_page(c)
	assert_str(p.title_label.text).is_equal("Ali")
	assert_bool(await p.load_history()).is_true()
	assert_bool(str(im_t.requests[0].url).ends_with("/v1/im/conversations/c1/messages?limit=30")).is_true()
	assert_int(p.list.get_child_count()).is_equal(3)
	assert_str(p.list.get_child(0).name).is_equal("Msg_m1")
	assert_str(p.list.get_child(2).name).is_equal("Msg_m3")
	assert_str((p.list.get_child(1).find_child("Text", true, false) as Label).text).is_equal("second")
	assert_str(im_t.requests[1].method).is_equal("POST")
	assert_bool(str(im_t.requests[1].url).ends_with("/v1/im/conversations/c1/read")).is_true()
	assert_int(int(im_t.requests[1].body.seq)).is_equal(3)

func test_chat_send_keeps_client_id_across_retry_and_appends_on_success() -> void:
	im_t.responses = [
		{"status": 200, "json": {"items": []}},
		{"error": "timeout"},
		{"status": 201, "json": _msg("m5", 5, "me-1", "hello")},
	]
	var p := _chat_page(_conv("c1", "Ali"))
	await p.load_history()
	p.composer.text = " hello "
	assert_bool(await p.send()).is_false()
	assert_bool(p.status.text.contains("connection")).is_true()
	var cid := str(im_t.requests[1].body.client_id)
	assert_bool(cid.is_empty()).is_false()
	assert_str(p.composer.text).is_equal(" hello ") # 失败保留文字
	assert_bool(await p.send()).is_true()
	assert_str(im_t.requests[2].body.client_id).is_equal(cid)
	assert_str(im_t.requests[2].body.text).is_equal("hello")
	assert_str(p.composer.text).is_empty()
	assert_str(p.pending_client_id).is_empty()
	assert_str(p.list.get_child(0).name).is_equal("Msg_m5")
	assert_str(p.status.text).is_empty()

func test_chat_live_events_append_dedupe_and_mark_deleted_only_for_this_conversation() -> void:
	im_t.responses = [{"status": 200, "json": {"items": [_msg("m1", 1, "u-x", "first")]}}, {"status": 200, "json": {"ok": true, "last_read_seq": 1}}, {"status": 200, "json": {"ok": true, "last_read_seq": 2}}]
	var p := _chat_page(_conv("c1", "Ali"))
	await p.load_history()
	p._on_im_event({"type": "message", "seq": 9, "conversation_id": "c1", "message_id": "m2", "message_seq": 2, "sender_id": "u-x", "kind": "text", "body": {"text": "second"}, "created_at": 2000})
	p._on_im_event({"type": "message", "seq": 10, "conversation_id": "c1", "message_id": "m2", "message_seq": 2, "sender_id": "u-x", "kind": "text", "body": {"text": "second"}, "created_at": 2000})
	p._on_im_event({"type": "message", "seq": 11, "conversation_id": "OTHER", "message_id": "m3", "message_seq": 1, "sender_id": "u-x", "kind": "text", "body": {"text": "elsewhere"}, "created_at": 3000})
	assert_int(p.list.get_child_count()).is_equal(2)
	assert_str(p.list.get_child(1).name).is_equal("Msg_m2")
	p._on_im_event({"type": "message_deleted", "seq": 12, "conversation_id": "c1", "message_id": "m1", "message_seq": 1})
	assert_str((p.list.get_child(0).find_child("Text", true, false) as Label).text).is_equal("Message deleted")

func test_chat_explains_greeting_limit_block_and_moderation() -> void:
	var p := _chat_page(_conv("c1", "Ali"))
	assert_str(p.describe_error({"code": "GREETING_LIMIT"})).contains("one message")
	assert_str(p.describe_error({"code": "BLOCKED"})).contains("can't message")
	assert_str(p.describe_error({"code": "MODERATION_REJECTED"})).contains("content rules")
	assert_str(p.bubble_text({"kind": "image", "body": {"key": "k", "text": "cap"}})).is_equal("[Photo] cap")
	assert_str(p.bubble_text({"kind": "text", "body": {"text": "x"}, "deleted": true})).is_equal("Message deleted")
	assert_str(p.title_for({"kind": "group", "title": "Team"})).is_equal("Team")
