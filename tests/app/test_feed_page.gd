extends GdUnitTestSuite
## feed 页：拉时间线渲染卡片、点赞切换、纯文字发布（幂等键在重试间不变）、Dev 会话不联网。

var session: AuthSession
var feed_t: FakeTransport
var safety_t: FakeTransport

func before_test() -> void:
	session = AuthSession.new()
	feed_t = FakeTransport.new([])
	safety_t = FakeTransport.new([])
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
	p.safety = SafetyApi.new(ApiClient.new("https://example.test/v1", safety_t.callable()))
	add_child(auto_free(p))
	return p

func _post(id: String, text: String, liked := false, likes := 0, author := "u-a") -> Dictionary:
	return {"id": id, "author": {"user_id": author, "display_name": "Ali", "handle": "ali", "avatar": null},
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

## E1：非本人的卡片有举报 / 拉黑；本人的没有。举报走原因菜单；拉黑确认后本地立刻撤掉该作者的卡片。
func test_report_and_block_entries_only_on_other_peoples_posts() -> void:
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	session.set_server_user("me-1")
	feed_t.responses = [{"status": 200, "json": {"items": [_post("p1", "theirs"), _post("p2", "mine", false, 0, "me-1")], "next_cursor": null}}]
	var p := _page()
	await p.refresh()
	assert_bool(p.list.get_child(0).find_child("Report", true, false) != null).is_true()
	assert_bool(p.list.get_child(0).find_child("Block", true, false) != null).is_true()
	assert_bool(p.list.get_child(1).find_child("Report", true, false) == null).is_true()
	assert_bool(p.list.get_child(1).find_child("Block", true, false) == null).is_true()
	assert_int(p.report_menu.item_count).is_equal(8)
	assert_str(p.report_menu.get_item_text(6)).is_equal("Child safety")

func test_report_sends_reason_from_menu_and_thanks() -> void:
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	feed_t.responses = [{"status": 200, "json": {"items": [_post("p1", "x")], "next_cursor": null}}]
	safety_t.responses = [{"status": 201, "json": {"id": "r1", "created": true, "auto_hidden": false}}, {"error": "timeout"}]
	var p := _page()
	await p.refresh()
	p.open_report_menu("p1", "u-a")
	await p._on_report_reason(1)
	assert_that(safety_t.requests[0].body).is_equal({"target_type": "post", "target_id": "p1", "reason": "harassment"})
	assert_bool(p.status.text.contains("received your report")).is_true()
	assert_bool(await p.report_post("p1", "spam")).is_false()
	assert_bool(p.status.text.contains("connection")).is_true()

func test_block_removes_authors_cards_locally() -> void:
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	feed_t.responses = [{"status": 200, "json": {"items": [_post("p1", "a1"), _post("p2", "b1", false, 0, "u-b"), _post("p3", "a2")], "next_cursor": null}}]
	safety_t.responses = [{"status": 200, "json": {"ok": true, "created": true}}]
	var p := _page()
	await p.refresh()
	p.open_block_confirm("p1", "u-a")
	await p._on_block_confirmed()
	assert_str(safety_t.requests[0].method).is_equal("PUT")
	assert_bool(str(safety_t.requests[0].url).ends_with("/v1/users/u-a/block")).is_true()
	assert_int(p.list.get_child_count()).is_equal(1)
	assert_str(p.list.get_child(0).name).is_equal("Post_p2")
	assert_bool(p.status.text.contains("Blocked")).is_true()

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

func test_publish_with_attached_photos_uploads_then_posts_and_renders_thumbnails() -> void:
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	var a := _png_file("f1", 30, 30)
	var b := _png_file("f2", 30, 15)
	var post := _post("p9", "", false, 0, "u1")
	post["images"] = [{"key": "u/u1/20260907/k1.jpg", "w": 30, "h": 30}, {"key": "u/u1/20260907/k2.jpg", "w": 30, "h": 15}]
	feed_t.responses = [{"status": 200, "json": {"items": [], "next_cursor": null}}, {"status": 201, "json": post}]
	var box := {"puts": []}
	var p := _page()
	p.uploads = _upload_api([_presigned("u/u1/20260907/k1.jpg"), _presigned("u/u1/20260907/k2.jpg")], box)
	p.picker = _picker_of([a, b])
	p.images = _serving(box)
	await p.refresh()
	assert_bool(await p.publish()).is_false() # 没字也没图
	assert_bool(await p.pick_photos()).is_true()
	assert_str(p.attached_label.text).is_equal("2 photos attached")
	assert_bool(p.attached_label.visible).is_true()
	assert_bool(await p.publish()).is_true() # 只有图也能发
	assert_int(box.puts.size()).is_equal(2)
	var body: Dictionary = feed_t.requests[1].body
	assert_int(body.images.size()).is_equal(2)
	assert_str(str(body.images[0].key)).is_equal("u/u1/20260907/k1.jpg")
	assert_int(int(body.images[1].h)).is_equal(15)
	assert_int(p.attached.size()).is_equal(0)
	assert_bool(p.attached_label.visible).is_false()
	var card: PanelContainer = p.list.get_child(0)
	var strip := card.find_child("Pictures", true, false)
	assert_object(strip).is_not_null()
	assert_int(strip.get_child_count()).is_equal(2)
	assert_bool((card.find_child("Text", true, false) as Label).visible).is_false()
	var pic := strip.get_child(0).get_child(0) as PictureView
	for i in 60:
		if pic.loaded:
			break
		await get_tree().process_frame
	assert_bool(pic.loaded).is_true()
	assert_int(int(pic.custom_minimum_size.x)).is_equal(48)
