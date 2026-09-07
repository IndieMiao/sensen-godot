extends GdUnitTestSuite
## ProfileApi：路径 / 方法 / 请求体 / 分页 query 与统一包装。

class TokenBox extends RefCounted:
	func get_token() -> String:
		return "id-1"

var box: TokenBox

func before_test() -> void:
	box = TokenBox.new()

func _api(t: FakeTransport) -> ProfileApi:
	var c := ApiClient.new("https://example.test/v1", t.callable())
	c.token_provider = box.get_token
	return ProfileApi.new(c)

func test_me_and_update_use_profile_route_with_patch_body() -> void:
	var t := FakeTransport.new([
		{"status": 200, "json": {"display_name": "Sen", "handle": null}},
		{"status": 200, "json": {"display_name": "Sen2", "handle": "sen"}},
	])
	var api := _api(t)
	var me: Dictionary = await api.me()
	assert_bool(me.ok).is_true()
	assert_bool(me.handle == null).is_true()
	var up: Dictionary = await api.update({"display_name": "Sen2", "handle": "sen", "bio": ""})
	assert_str(up.handle).is_equal("sen")
	assert_str(t.requests[0].method).is_equal("GET")
	assert_bool(str(t.requests[0].url).ends_with("/v1/users/me/profile")).is_true()
	assert_str(t.requests[1].method).is_equal("PUT")
	assert_that(t.requests[1].body).is_equal({"display_name": "Sen2", "handle": "sen", "bio": ""})

func test_follow_routes_encode_handles_and_lists_carry_cursor() -> void:
	var t := FakeTransport.new([
		{"status": 200, "json": {"ok": true, "created": true}},
		{"status": 200, "json": {"ok": true, "removed": true}},
		{"status": 200, "json": {"items": [], "next_cursor": null}},
		{"status": 200, "json": {"items": [], "unread_count": 2, "next_cursor": null}},
		{"status": 200, "json": {"user_id": "u-2"}},
	])
	var api := _api(t)
	assert_bool((await api.follow("@Bobby")).created).is_true()
	assert_bool((await api.unfollow("u-2")).removed).is_true()
	assert_that((await api.followers("me", "abc+/=", 5)).items).is_equal([])
	assert_int((await api.new_followers()).unread_count).is_equal(2)
	assert_str((await api.get_profile("@bobby")).user_id).is_equal("u-2")
	assert_str(t.requests[0].method).is_equal("PUT")
	assert_bool(str(t.requests[0].url).ends_with("/v1/users/%40Bobby/follow")).is_true()
	assert_str(t.requests[1].method).is_equal("DELETE")
	assert_bool(str(t.requests[2].url).ends_with("/v1/users/me/followers?limit=5&cursor=abc%2B%2F%3D")).is_true()
	assert_bool(str(t.requests[3].url).ends_with("/v1/users/me/new-followers?limit=20")).is_true()
	assert_bool(str(t.requests[4].url).ends_with("/v1/users/%40bobby/profile")).is_true()

func test_errors_carry_code_and_field() -> void:
	var t := FakeTransport.new([
		{"status": 409, "json": {"code": "HANDLE_TAKEN"}},
		{"status": 400, "json": {"code": "SCHEMA", "field": "bio", "reason": "LENGTH"}},
	])
	var api := _api(t)
	var a: Dictionary = await api.update({"handle": "x"})
	assert_bool(a.ok).is_false()
	assert_str(a.code).is_equal("HANDLE_TAKEN")
	var b: Dictionary = await api.update({"bio": "x"})
	assert_str(b.code).is_equal("SCHEMA")
	assert_str(b.field).is_equal("bio")


## 一串 handle → 去重小写；批量查 id 遇到查不到的就整体失败并指出是谁。
func test_parse_handles_and_user_ids_for() -> void:
	assert_array(Array(ProfileApi.parse_handles(" @Ann, ben，ann  @Cy "))).is_equal(["ann", "ben", "cy"])
	assert_int(ProfileApi.parse_handles("").size()).is_equal(0)
	var t := FakeTransport.new([{"status": 200, "json": {"user_id": "u-a"}}, {"status": 404, "json": {"code": "NOT_FOUND"}}])
	var api := ProfileApi.new(ApiClient.new("https://example.test/v1", t.callable()))
	var r: Dictionary = await api.user_ids_for(PackedStringArray(["ann", "ghost", "cy"]))
	assert_bool(r.ok).is_false()
	assert_str(r.missing).is_equal("ghost")
	assert_int(t.requests.size()).is_equal(2) # 第一个失败就停
	t.responses.append({"status": 200, "json": {"user_id": "u-b"}})
	t.responses.append({"status": 200, "json": {"user_id": "u-b"}})
	var ok: Dictionary = await api.user_ids_for(PackedStringArray(["ben", "ben2"]))
	assert_bool(ok.ok).is_true()
	assert_that(ok.ids).is_equal(["u-b"])
