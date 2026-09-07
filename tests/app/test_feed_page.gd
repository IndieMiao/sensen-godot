extends GdUnitTestSuite
## feed 页：拉时间线渲染卡片、点赞切换、纯文字发布（幂等键在重试间不变）、Dev 会话不联网。

var session: AuthSession
var feed_t: FakeTransport

func before_test() -> void:
	session = AuthSession.new()
	feed_t = FakeTransport.new([])
	_clear_auth()

func after_test() -> void:
	_clear_auth()

func _clear_auth() -> void:
	if FileAccess.file_exists(AuthSession.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AuthSession.PATH))

func _page() -> Control:
	var p := (load(AppRoutes.tab_scene("feed")) as PackedScene).instantiate()
	p.auth = session
	p.feed = FeedApi.new(ApiClient.new("https://example.test/v1", feed_t.callable()))
	add_child(auto_free(p))
	return p

func _post(id: String, text: String, liked := false, likes := 0) -> Dictionary:
	return {"id": id, "author": {"user_id": "u-a", "display_name": "Ali", "handle": "ali", "avatar": null},
		"text": text, "images": [], "like_count": likes, "comment_count": 2, "liked": liked, "created_at": 0}

func test_refresh_renders_timeline_cards_and_more_button() -> void:
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	feed_t.responses = [{"status": 200, "json": {"items": [_post("p1", "first"), _post("p2", "second", true, 3)], "next_cursor": "c2"}}]
	var p := _page()
	assert_bool(await p.refresh()).is_true()
	assert_bool(str(feed_t.requests[0].url).ends_with("/v1/feed?limit=20")).is_true()
	assert_int(p.list.get_child_count()).is_equal(2)
	var first: PanelContainer = p.list.get_child(0)
	assert_str(first.name).is_equal("Post_p1")
	assert_bool((first.find_child("Author", true, false) as Label).text.begins_with("Ali @ali · ")).is_true()
	assert_str((first.find_child("Text", true, false) as Label).text).is_equal("first")
	assert_str((first.find_child("Like", true, false) as Button).text).is_equal("Like 0")
	assert_str((p.list.get_child(1).find_child("Like", true, false) as Button).text).is_equal("Liked 3")
	assert_str((first.find_child("Meta", true, false) as Label).text).is_equal("2 comments")
	assert_bool(p.more_button.visible).is_true()
	assert_str(p.status.text).is_empty()

func test_like_toggles_send_put_then_delete_and_update_count() -> void:
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	feed_t.responses = [
		{"status": 200, "json": {"items": [_post("p1", "x")], "next_cursor": null}},
		{"status": 200, "json": {"ok": true, "liked": true, "like_count": 1}},
		{"status": 200, "json": {"ok": true, "liked": false, "like_count": 0}},
	]
	var p := _page()
	await p.refresh()
	await p.toggle_like("p1")
	assert_str(feed_t.requests[1].method).is_equal("PUT")
	assert_bool(str(feed_t.requests[1].url).ends_with("/v1/posts/p1/like")).is_true()
	assert_str((p.list.get_child(0).find_child("Like", true, false) as Button).text).is_equal("Liked 1")
	await p.toggle_like("p1")
	assert_str(feed_t.requests[2].method).is_equal("DELETE")
	assert_str((p.list.get_child(0).find_child("Like", true, false) as Button).text).is_equal("Like 0")
	assert_bool(p.more_button.visible).is_false()

func test_publish_keeps_idempotency_key_across_retry_then_prepends() -> void:
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	feed_t.responses = [
		{"status": 200, "json": {"items": [_post("p1", "old")], "next_cursor": null}},
		{"error": "timeout"},
		{"status": 201, "json": _post("p2", "hello")},
	]
	var p := _page()
	await p.refresh()
	p.composer.text = "  hello  "
	assert_bool(await p.publish()).is_false()
	assert_bool(p.status.text.contains("connection")).is_true()
	var key := str(feed_t.requests[1].body.idempotency_key)
	assert_bool(key.is_empty()).is_false()
	assert_str(feed_t.requests[1].body.text).is_equal("hello")
	assert_bool(await p.publish()).is_true()
	assert_str(feed_t.requests[2].body.idempotency_key).is_equal(key)
	assert_str(p.composer.text).is_empty()
	assert_str(p.pending_key).is_empty()
	assert_int(p.list.get_child_count()).is_equal(2)
	assert_str(p.list.get_child(0).name).is_equal("Post_p2")
	assert_str(p.status.text).is_equal("Posted.")
	p.composer.text = "   "
	assert_bool(await p.publish()).is_false()
	assert_int(feed_t.requests.size()).is_equal(3)

func test_dev_session_and_unreachable_server_show_hints_without_crashing() -> void:
	session.complete_sign_in("dev-local", "dev-token", "", 3600, "dev", "dev@local")
	var p := _page()
	assert_bool(await p.refresh()).is_false()
	assert_int(feed_t.requests.size()).is_equal(0)
	assert_bool(p.status.text.contains("Follow people")).is_true()
	session.sign_out()
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	feed_t.responses = [{"error": "timeout"}]
	var q := _page()
	assert_bool(await q.refresh()).is_false()
	assert_bool(q.status.text.contains("Can't load")).is_true()

func test_age_text_buckets() -> void:
	var p := _page()
	var now := 1_000_000_000_000
	assert_str(p.age_text(now, now - 30_000)).is_equal("just now")
	assert_str(p.age_text(now, now - 5 * 60_000)).is_equal("5m ago")
	assert_str(p.age_text(now, now - 3 * 3_600_000)).is_equal("3h ago")
	assert_str(p.age_text(now, now - 2 * 86_400_000)).is_equal("2d ago")
	assert_str(p.age_text(now, now + 99_000)).is_equal("just now")
