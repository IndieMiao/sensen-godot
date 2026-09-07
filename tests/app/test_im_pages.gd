extends GdUnitTestSuite
## B2：会话列表（渲染、@handle 发起单聊、点会话压栈）与聊天页（历史升序、已读、发送幂等、实时事件、撤回、错误文案）。

const ChatScript := preload("res://scenes/app/pages/chat_page.gd")

class NavRecorder extends RefCounted:
	var calls: Array = []
	var left := 0
	func go(route: String, args: Dictionary) -> void:
		calls.append({"route": route, "args": args})
	func leave() -> void:
		left += 1

var session: AuthSession
var im_t: FakeTransport
var profile_t: FakeTransport
var safety_t: FakeTransport
var nav: NavRecorder

func before_test() -> void:
	session = AuthSession.new()
	session.complete_sign_in("uid-1", "id-1", "rt-1", 3600, "password", "a@b.co")
	session.set_server_user("me-1")
	im_t = FakeTransport.new([])
	profile_t = FakeTransport.new([])
	safety_t = FakeTransport.new([])
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
	p.profile = ProfileApi.new(ApiClient.new("https://example.test/v1", profile_t.callable()))
	p.safety = SafetyApi.new(ApiClient.new("https://example.test/v1", safety_t.callable()))
	p.leave_handler = nav.leave
	p.setup({"conversation": c})
	add_child(auto_free(p))
	return p

func _group(id: String, title: String) -> Dictionary:
	return {"id": id, "kind": "group", "title": title, "peer": null, "member_count": 3, "peer_read_seq": null,
		"last_seq": 2, "last_read_seq": 0, "unread": 2, "last_message": {}, "last_message_at": 0, "created_at": 0}

func _member(user_id: String, name: String, read_seq: int) -> Dictionary:
	return {"user_id": user_id, "display_name": name, "handle": name.to_lower(), "avatar": null, "joined_at": 0, "last_read_seq": read_seq}

func _drag(to: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.position = to
	return e

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
	# 有最近消息时间就带相对时间
	var recent := _conv("c3", "Cy", 0, "yo")
	recent["last_message_at"] = int(Time.get_unix_time_from_system() * 1000.0) - 5 * 60 * 1000
	im_t.responses.append({"status": 200, "json": {"items": [recent]}})
	await p.refresh()
	assert_str((p.list.get_child(0) as Button).text).is_equal("Cy · 5m ago\nyo")

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


func test_list_creates_group_from_name_and_handles() -> void:
	profile_t.responses = [{"status": 200, "json": {"user_id": "u-a", "display_name": "Ann"}}, {"status": 200, "json": {"user_id": "u-b", "display_name": "Ben"}}]
	im_t.responses = [{"status": 201, "json": _group("g1", "Team")}]
	var p := _list_page()
	assert_bool(p.group_panel.visible).is_false()
	p.group_toggle.pressed.emit()
	assert_bool(p.group_panel.visible).is_true()
	p.group_title_edit.text = " Team "
	p.group_members_edit.text = "@Ann, ben ann"
	assert_bool(await p.create_group()).is_true()
	assert_int(profile_t.requests.size()).is_equal(2) # ann 去重
	assert_bool(str(profile_t.requests[1].url).ends_with("/v1/users/%40ben/profile")).is_true()
	assert_that(im_t.requests[0].body).is_equal({"title": "Team", "member_ids": ["u-a", "u-b"]})
	assert_str(nav.calls[0].args.conversation.id).is_equal("g1")
	assert_bool(p.group_panel.visible).is_false()
	assert_bool(await p.create_group()).is_false()
	assert_bool(p.status.text.contains("name")).is_true()
	p.group_title_edit.text = "T"
	assert_bool(await p.create_group()).is_false()
	assert_bool(p.status.text.contains("@handle")).is_true()
	profile_t.responses.append({"status": 404, "json": {"code": "NOT_FOUND"}})
	p.group_members_edit.text = "ghost"
	assert_bool(await p.create_group()).is_false()
	assert_bool(p.status.text.contains("@ghost")).is_true()
	assert_int(im_t.requests.size()).is_equal(1)

func test_chat_group_shows_sender_names_and_read_counts() -> void:
	im_t.responses = [
		{"status": 200, "json": {"items": [_msg("m2", 2, "me-1", "mine"), _msg("m1", 1, "u-a", "hi all")]}},
		{"status": 200, "json": {"items": [_member("me-1", "Me", 2), _member("u-a", "Ann", 2), _member("u-b", "Ben", 1)]}},
		{"status": 200, "json": {"ok": true, "last_read_seq": 2}},
	]
	var p := _chat_page(_group("g1", "Team"))
	assert_str(p.title_label.text).is_equal("Team")
	assert_bool(await p.load_history()).is_true()
	assert_bool(str(im_t.requests[1].url).ends_with("/v1/im/conversations/g1/members")).is_true()
	assert_str((p.bubbles["m1"].find_child("Who", true, false) as Label).text).is_equal("Ann")
	assert_object(p.bubbles["m2"].find_child("Who", true, false)).is_null()
	var receipt := p.bubbles["m2"].find_child("Receipt", true, false) as Label
	assert_bool(receipt.visible).is_true()
	assert_str(receipt.text).is_equal("Read by 1")
	im_t.responses.append({"status": 200, "json": {"items": [_member("me-1", "Me", 2), _member("u-a", "Ann", 2), _member("u-b", "Ben", 2)]}})
	assert_bool(await p.load_members()).is_true()
	assert_str(receipt.text).is_equal("Read by 2")
	im_t.responses.append({"status": 200, "json": {"items": [_member("me-1", "Me", 2), _member("u-a", "Ann", 2)]}})
	assert_bool(await p.show_members()).is_true()
	assert_bool(p.status.text.contains("Ann")).is_true()
	assert_bool(p.status.text.contains("You")).is_true()

func test_chat_group_read_events_advance_read_by_count_live() -> void:
	im_t.responses = [
		{"status": 200, "json": {"items": [_msg("m2", 2, "me-1", "mine"), _msg("m1", 1, "u-a", "hi all")]}},
		{"status": 200, "json": {"items": [_member("me-1", "Me", 2), _member("u-a", "Ann", 1), _member("u-b", "Ben", 1)]}},
		{"status": 200, "json": {"ok": true, "last_read_seq": 2}},
	]
	var p := _chat_page(_group("g1", "Team"))
	assert_bool(await p.load_history()).is_true()
	var receipt := p.bubbles["m2"].find_child("Receipt", true, false) as Label
	assert_bool(receipt.visible).is_false()
	p._on_im_event({"type": "read", "conversation_id": "g1", "user_id": "u-a", "read_seq": 2})
	assert_bool(receipt.visible).is_true()
	assert_str(receipt.text).is_equal("Read by 1")
	# 还没进成员表的人（刚被拉进群）也能计数；自己的已读不算；别的会话不影响。
	p._on_im_event({"type": "read", "conversation_id": "g1", "user_id": "u-c", "read_seq": 2})
	assert_str(receipt.text).is_equal("Read by 2")
	p._on_im_event({"type": "read", "conversation_id": "g1", "user_id": "me-1", "read_seq": 2})
	p._on_im_event({"type": "read", "conversation_id": "g2", "user_id": "u-b", "read_seq": 2})
	assert_str(receipt.text).is_equal("Read by 2")
	p._on_im_event({"type": "read", "conversation_id": "g1", "user_id": "u-b", "read_seq": 1})
	assert_str(receipt.text).is_equal("Read by 2")

func test_chat_dm_read_receipt_marks_last_read_own_message_and_follows_read_events() -> void:
	im_t.responses = [
		{"status": 200, "json": {"items": [_msg("m3", 3, "me-1", "three"), _msg("m2", 2, "u-c1", "two"), _msg("m1", 1, "me-1", "one")]}},
		{"status": 200, "json": {"ok": true, "last_read_seq": 3}},
	]
	var c := _conv("c1", "Ali", 0)
	c["peer_read_seq"] = 1
	var p := _chat_page(c)
	assert_bool(await p.load_history()).is_true()
	var r1 := p.bubbles["m1"].find_child("Receipt", true, false) as Label
	var r3 := p.bubbles["m3"].find_child("Receipt", true, false) as Label
	assert_bool(r1.visible).is_true()
	assert_str(r1.text).is_equal("Read")
	assert_bool(r3.visible).is_false()
	assert_object(p.bubbles["m2"].find_child("Receipt", true, false)).is_null()
	p._on_im_event({"type": "read", "seq": 7, "conversation_id": "c1", "user_id": "u-c1", "read_seq": 3})
	assert_bool(r1.visible).is_false()
	assert_bool(r3.visible).is_true()
	p._on_im_event({"type": "read", "seq": 8, "conversation_id": "c1", "user_id": "me-1", "read_seq": 9})
	assert_int(p.peer_read_seq).is_equal(3)
	p._on_im_event({"type": "read", "seq": 9, "conversation_id": "OTHER", "user_id": "u-c1", "read_seq": 9})
	assert_int(p.peer_read_seq).is_equal(3)

func test_chat_long_press_menu_reports_blocks_and_unsends() -> void:
	im_t.responses = [
		{"status": 200, "json": {"items": [_msg("m2", 2, "me-1", "mine"), _msg("m1", 1, "u-c1", "theirs")]}},
		{"status": 200, "json": {"ok": true, "last_read_seq": 2}},
	]
	safety_t.responses = [{"status": 201, "json": {"id": "r1", "created": true}}, {"status": 200, "json": {"ok": true}}]
	var p := _chat_page(_conv("c1", "Ali"))
	await p.load_history()
	p._press("m1", true, Vector2.ZERO)
	assert_str(p.pressed_id).is_equal("m1")
	p._press("m1", false, Vector2.ZERO)
	assert_str(p.pressed_id).is_empty()
	p._press("m1", true, Vector2.ZERO)
	p._on_bubble_input(_drag(Vector2(30, 0)), "m1") # 拖动超过阈值 = 在滚列表，取消
	assert_str(p.pressed_id).is_empty()
	p._press("m1", true, Vector2.ZERO)
	p._on_bubble_input(_drag(Vector2(3, 2)), "m1")
	assert_str(p.pressed_id).is_equal("m1")
	p.long_press.timeout.emit()
	assert_str(p.menu_target).is_equal("m1")
	assert_int(p.context_menu.item_count).is_equal(2)
	assert_str(p.context_menu.get_item_text(0)).is_equal("Report message")
	assert_str(p.context_menu.get_item_text(1)).is_equal("Block Ali")
	p._on_menu(ChatScript.MenuItem.REPORT_MESSAGE)
	await p._on_report_reason(1)
	assert_str(safety_t.requests[0].method).is_equal("POST")
	assert_that(safety_t.requests[0].body).is_equal({"target_type": "message", "target_id": "m1", "reason": "harassment"})
	assert_bool(p.status.text.contains("report")).is_true()
	p.open_page_menu()
	assert_int(p.context_menu.item_count).is_equal(3)
	p.navigate = nav.go
	p._on_menu(ChatScript.MenuItem.VIEW_PROFILE)
	assert_str(nav.calls[-1].route).is_equal(AppRoutes.USER)
	assert_str(nav.calls[-1].args.user_id).is_equal("u-c1")
	p._on_menu(ChatScript.MenuItem.REPORT_USER)
	assert_that(p.pending_report).is_equal({"type": "user", "id": "u-c1"})
	assert_bool(p.open_message_menu("m1")).is_true()
	p._on_menu(ChatScript.MenuItem.BLOCK_USER)
	assert_str(p.block_target).is_equal("u-c1")
	await p._on_block_confirmed()
	assert_str(safety_t.requests[1].method).is_equal("PUT")
	assert_bool(str(safety_t.requests[1].url).ends_with("/v1/users/u-c1/block")).is_true()
	assert_int(nav.left).is_equal(1)
	assert_bool(p.open_message_menu("m2")).is_true()
	assert_int(p.context_menu.item_count).is_equal(1)
	assert_str(p.context_menu.get_item_text(0)).is_equal("Unsend")
	im_t.responses.append({"status": 200, "json": {"ok": true, "deleted": true}})
	assert_bool(await p.unsend("m2")).is_true()
	# 这个会话 last_read_seq 已是 3，进页不会再发 read；撤回是第 2 个请求
	assert_int(im_t.requests.size()).is_equal(2)
	assert_str(im_t.requests[1].method).is_equal("DELETE")
	assert_bool(str(im_t.requests[1].url).ends_with("/v1/im/messages/m2")).is_true()
	assert_str((p.bubbles["m2"].find_child("Text", true, false) as Label).text).is_equal("Message deleted")
	assert_bool(p.open_message_menu("m2")).is_false()

func test_chat_group_menu_adds_people_and_leaves() -> void:
	im_t.responses = [
		{"status": 200, "json": {"items": []}},
		{"status": 200, "json": {"items": [_member("me-1", "Me", 0), _member("u-a", "Ann", 0)]}},
	]
	var p := _chat_page(_group("g1", "Team"))
	assert_bool(await p.load_history()).is_true()
	p.open_page_menu()
	assert_int(p.context_menu.item_count).is_equal(3)
	assert_bool(p.add_row.visible).is_false()
	p._on_menu(ChatScript.MenuItem.ADD_PEOPLE)
	assert_bool(p.add_row.visible).is_true()
	profile_t.responses = [{"status": 200, "json": {"user_id": "u-c", "display_name": "Cara"}}]
	im_t.responses.append({"status": 200, "json": {"ok": true, "added": ["u-c"]}})
	im_t.responses.append({"status": 200, "json": {"items": [_member("me-1", "Me", 0), _member("u-a", "Ann", 0), _member("u-c", "Cara", 0)]}})
	p.add_edit.text = "@Cara"
	assert_bool(await p.add_people()).is_true()
	assert_bool(str(im_t.requests[2].url).ends_with("/v1/im/groups/g1/members")).is_true()
	assert_that(im_t.requests[2].body).is_equal({"user_ids": ["u-c"]})
	assert_bool(p.add_row.visible).is_false()
	assert_str(p.name_for("u-c")).is_equal("Cara")
	im_t.responses.append({"status": 200, "json": {"ok": true, "removed": true}})
	assert_bool(await p.leave_group()).is_true()
	assert_str(im_t.requests[4].method).is_equal("DELETE")
	assert_bool(str(im_t.requests[4].url).ends_with("/v1/im/groups/g1/members/me")).is_true()
	assert_int(nav.left).is_equal(1)

const PIC_DIR := "user://qa_test_pages"

func _png_file(name: String, w: int, h: int) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PIC_DIR))
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.CORAL)
	var path := "%s/%s.png" % [PIC_DIR, name]
	img.save_png(path)
	return path

## 把预签名 + 原始 PUT 都记在 box 里（lambda 捕获的是副本，要用引用类型带出来）。
func _upload_api(presigned: Array, box: Dictionary) -> UploadApi:
	var t := FakeTransport.new(presigned)
	var c := ApiClient.new("https://example.test/v1", t.callable())
	c.raw_transport = func(method: String, url: String, headers: PackedStringArray, bytes: PackedByteArray) -> ApiClient.Response:
		box["puts"].append({"method": method, "url": url, "headers": headers, "bytes": bytes})
		return ApiClient.Response.new(true, 200, {}, "")
	box["presign"] = t
	return UploadApi.new(c)

func _presigned(key: String) -> Dictionary:
	return {"status": 201, "json": {"key": key, "url": "http://h/v1/uploads/local/tok-%s" % key.get_file(), "method": "PUT", "headers": {"content-type": "image/jpeg"}, "expires_at": 1, "public_url": "http://h/v1/files/%s" % key}}

func _serving(box: Dictionary) -> ImageCache:
	return ImageCache.new(func(_url: String) -> ApiClient.Response:
		var r := ApiClient.Response.new(true, 200, {}, "")
		r.bytes = box["puts"][0].bytes if not box["puts"].is_empty() else PackedByteArray()
		return r)

func _picker_of(paths: Array) -> PhotoPicker:
	var pp := PhotoPicker.new()
	pp.max_side = 64
	pp.picker = func(_n: int) -> PackedStringArray: return PackedStringArray(paths)
	return pp

func _img_msg(id: String, seq: int, sender: String, key: String, w: int, h: int, caption := "") -> Dictionary:
	var body := {"key": key, "w": w, "h": h}
	if not caption.is_empty():
		body["text"] = caption
	return {"id": id, "conversation_id": "c1", "seq": seq, "sender_id": sender, "client_id": id, "kind": "image", "body": body, "created_at": seq * 1000, "deleted": false}

func test_chat_attach_photo_uploads_then_sends_image_and_fills_bubble() -> void:
	var png := _png_file("pick1", 40, 20)
	im_t.responses = [{"status": 200, "json": {"items": []}}, {"status": 201, "json": _img_msg("m7", 7, "me-1", "u/me-1/20260907/x.jpg", 40, 20, "cap")}]
	var box := {"puts": []}
	var p := _chat_page(_conv("c1", "Ali"))
	p.uploads = _upload_api([_presigned("u/me-1/20260907/x.jpg")], box)
	p.picker = _picker_of([png])
	p.images = _serving(box)
	await p.load_history()
	p.composer.text = " cap "
	assert_bool(await p.attach_photo()).is_true()
	assert_int(box.puts.size()).is_equal(1)
	assert_str(box.puts[0].url).is_equal("http://h/v1/uploads/local/tok-x.jpg")
	assert_bool((box.puts[0].bytes as PackedByteArray).size() > 0).is_true()
	assert_int(int(box.presign.requests[0].body.size)).is_equal((box.puts[0].bytes as PackedByteArray).size())
	var sent: Dictionary = im_t.requests[1].body
	assert_str(str(sent.kind)).is_equal("image")
	assert_str(str(sent.image.key)).is_equal("u/me-1/20260907/x.jpg")
	assert_int(int(sent.image.w)).is_equal(40)
	assert_str(str(sent.text)).is_equal("cap")
	assert_str(p.composer.text).is_empty()
	assert_bool(p.attaching).is_false()
	var pic := p.bubbles["m7"].find_child("Picture", true, false) as PictureView
	assert_object(pic).is_not_null()
	for i in 60:
		if pic.loaded:
			break
		await get_tree().process_frame
	assert_bool(pic.loaded).is_true()
	assert_int(int(pic.custom_minimum_size.x)).is_equal(48) # 40x20 只缩不放，最小 48
	assert_str((p.bubbles["m7"].find_child("Text", true, false) as Label).text).is_equal("cap")
	# 取消选图：不算失败也不报错
	p.picker = _picker_of([])
	assert_bool(await p.attach_photo()).is_false()
	assert_str(p.status.text).is_empty()
	# 撤回图片消息：图藏起来、文字换成「已撤回」
	p._on_im_event({"type": "message_deleted", "seq": 12, "conversation_id": "c1", "message_id": "m7", "message_seq": 7})
	assert_bool(pic.visible).is_false()
	assert_str((p.bubbles["m7"].find_child("Text", true, false) as Label).text).is_equal("Message deleted")
