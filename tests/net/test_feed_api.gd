extends GdUnitTestSuite
## FeedApi：路径 / 方法 / 请求体 / 幂等键。

class TokenBox extends RefCounted:
	func get_token() -> String:
		return "id-1"

var box: TokenBox

func before_test() -> void:
	box = TokenBox.new()

func _api(t: FakeTransport) -> FeedApi:
	var c := ApiClient.new("https://example.test/v1", t.callable())
	c.token_provider = box.get_token
	return FeedApi.new(c)

func test_timeline_and_posts_of_carry_paging() -> void:
	var t := FakeTransport.new([
		{"status": 200, "json": {"items": [{"id": "p1"}], "next_cursor": "c2"}},
		{"status": 200, "json": {"items": [], "next_cursor": null}},
	])
	var api := _api(t)
	var r: Dictionary = await api.timeline("c1", 10)
	assert_str(r.next_cursor).is_equal("c2")
	assert_int(r.items.size()).is_equal(1)
	await api.posts_of("@ali")
	assert_bool(str(t.requests[0].url).ends_with("/v1/feed?limit=10&cursor=c1")).is_true()
	assert_bool(str(t.requests[1].url).ends_with("/v1/users/%40ali/posts?limit=20")).is_true()

func test_create_post_generates_idempotency_key_once_and_keeps_given_one() -> void:
	var t := FakeTransport.new([
		{"status": 201, "json": {"id": "p1", "created": true}},
		{"status": 200, "json": {"id": "p1", "created": false}},
	])
	var api := _api(t)
	var a: Dictionary = await api.create_post("hi")
	assert_bool(a.created).is_true()
	var key := str(t.requests[0].body.idempotency_key)
	assert_bool(key.is_empty()).is_false()
	assert_str(t.requests[0].body.text).is_equal("hi")
	assert_bool(t.requests[0].body.has("images")).is_false()
	await api.create_post("hi", [{"key": "img/a.jpg"}], key)
	assert_str(t.requests[1].body.idempotency_key).is_equal(key)
	assert_that(t.requests[1].body.images).is_equal([{"key": "img/a.jpg"}])
	assert_str(t.requests[1].method).is_equal("POST")
	assert_bool(str(t.requests[1].url).ends_with("/v1/posts")).is_true()

func test_like_comment_and_delete_routes() -> void:
	var t := FakeTransport.new([
		{"status": 200, "json": {"liked": true, "like_count": 1}},
		{"status": 200, "json": {"liked": false, "like_count": 0}},
		{"status": 201, "json": {"id": "c1", "text": "yo"}},
		{"status": 200, "json": {"items": [], "next_cursor": null}},
		{"status": 200, "json": {"ok": true, "deleted": true}},
		{"status": 200, "json": {"ok": true, "deleted": true}},
		{"status": 404, "json": {"code": "NOT_FOUND"}},
	])
	var api := _api(t)
	assert_int((await api.like("p1")).like_count).is_equal(1)
	assert_bool((await api.unlike("p1")).liked).is_false()
	assert_str((await api.add_comment("p1", "yo")).id).is_equal("c1")
	await api.comments("p1", "", 5)
	assert_bool((await api.delete_comment("c1")).deleted).is_true()
	assert_bool((await api.delete_post("p1")).deleted).is_true()
	assert_str((await api.get_post("nope")).code).is_equal("NOT_FOUND")
	assert_str(t.requests[0].method).is_equal("PUT")
	assert_bool(str(t.requests[0].url).ends_with("/v1/posts/p1/like")).is_true()
	assert_str(t.requests[1].method).is_equal("DELETE")
	assert_that(t.requests[2].body).is_equal({"text": "yo"})
	assert_bool(str(t.requests[3].url).ends_with("/v1/posts/p1/comments?limit=5")).is_true()
	assert_bool(str(t.requests[4].url).ends_with("/v1/comments/c1")).is_true()
	assert_bool(str(t.requests[5].url).ends_with("/v1/posts/p1")).is_true()
