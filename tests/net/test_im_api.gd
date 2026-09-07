extends GdUnitTestSuite
## ImApi：路径 / 方法 / 请求体 / 幂等 client_id / 分页参数。

class TokenBox extends RefCounted:
	func get_token() -> String:
		return "id-1"

var box: TokenBox

func before_test() -> void:
	box = TokenBox.new()

func _api(t: FakeTransport) -> ImApi:
	var c := ApiClient.new("https://example.test/v1", t.callable())
	c.token_provider = box.get_token
	return ImApi.new(c)

func test_conversation_routes() -> void:
	var t := FakeTransport.new([
		{"status": 201, "json": {"id": "c1", "kind": "dm", "created": true}},
		{"status": 201, "json": {"id": "g1", "kind": "group"}},
		{"status": 200, "json": {"ok": true, "added": ["u-3"]}},
		{"status": 200, "json": {"ok": true, "removed": true}},
		{"status": 200, "json": {"items": []}},
	])
	var api := _api(t)
	assert_str((await api.open_dm("u-2")).id).is_equal("c1")
	assert_str((await api.create_group("Team", ["u-2", "u-3"])).id).is_equal("g1")
	assert_that((await api.add_members("g1", ["u-3"])).added).is_equal(["u-3"])
	assert_bool((await api.leave_group("g1")).removed).is_true()
	assert_that((await api.conversations()).items).is_equal([])
	assert_that(t.requests[0].body).is_equal({"user_id": "u-2"})
	assert_bool(str(t.requests[0].url).ends_with("/v1/im/dm")).is_true()
	assert_that(t.requests[1].body).is_equal({"title": "Team", "member_ids": ["u-2", "u-3"]})
	assert_bool(str(t.requests[2].url).ends_with("/v1/im/groups/g1/members")).is_true()
	assert_str(t.requests[3].method).is_equal("DELETE")
	assert_bool(str(t.requests[3].url).ends_with("/v1/im/groups/g1/members/me")).is_true()
	assert_bool(str(t.requests[4].url).ends_with("/v1/im/conversations")).is_true()

func test_messages_send_read_delete_and_sync() -> void:
	var t := FakeTransport.new([
		{"status": 200, "json": {"items": [{"seq": 5}]}},
		{"status": 200, "json": {"items": []}},
		{"status": 201, "json": {"id": "m1", "seq": 6, "created": true}},
		{"status": 200, "json": {"id": "m1", "seq": 6, "created": false}},
		{"status": 201, "json": {"id": "m2", "kind": "image"}},
		{"status": 200, "json": {"ok": true, "last_read_seq": 6}},
		{"status": 200, "json": {"ok": true, "deleted": true}},
		{"status": 200, "json": {"events": [{"seq": 1, "type": "message"}], "latest_seq": 1}},
	])
	var api := _api(t)
	assert_int((await api.messages("c1")).items[0].seq).is_equal(5)
	await api.messages("c1", 5, 10)
	var a: Dictionary = await api.send_text("c1", "hi")
	assert_bool(a.created).is_true()
	var cid := str(t.requests[2].body.client_id)
	assert_bool(cid.is_empty()).is_false()
	assert_bool((await api.send_text("c1", "hi", cid)).created).is_false()
	assert_str(t.requests[3].body.client_id).is_equal(cid)
	assert_str((await api.send_image("c1", {"key": "u/me/1.jpg", "w": 10, "h": 10}, "cap")).kind).is_equal("image")
	assert_int((await api.mark_read("c1", 6)).last_read_seq).is_equal(6)
	assert_bool((await api.delete_message("m1")).deleted).is_true()
	var s: Dictionary = await api.sync(-5)
	assert_int(s.latest_seq).is_equal(1)
	assert_bool(str(t.requests[0].url).ends_with("/v1/im/conversations/c1/messages?limit=30")).is_true()
	assert_bool(str(t.requests[1].url).ends_with("/v1/im/conversations/c1/messages?limit=10&before_seq=5")).is_true()
	assert_that(t.requests[2].body).is_equal({"client_id": cid, "kind": "text", "text": "hi"})
	# JSON 解析回来的数字是 float：逐字段比，不整体比字典。
	assert_str(t.requests[4].body.kind).is_equal("image")
	assert_str(t.requests[4].body.image.key).is_equal("u/me/1.jpg")
	assert_int(int(t.requests[4].body.image.w)).is_equal(10)
	assert_str(t.requests[4].body.text).is_equal("cap")
	assert_int(int(t.requests[5].body.seq)).is_equal(6)
	assert_bool(str(t.requests[6].url).ends_with("/v1/im/messages/m1")).is_true()
	assert_bool(str(t.requests[7].url).ends_with("/v1/im/sync?since=0&limit=200")).is_true()


func test_members_hits_conversation_members_url() -> void:
	var t := FakeTransport.new([{"status": 200, "json": {"items": []}}])
	var api := ImApi.new(ApiClient.new("https://example.test/v1", t.callable()))
	var r: Dictionary = await api.members("c 1")
	assert_bool(r.ok).is_true()
	assert_bool(str(t.requests[0].url).ends_with("/v1/im/conversations/c%201/members")).is_true()
