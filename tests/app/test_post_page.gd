extends GdUnitTestSuite
## 动态详情：卡片 + 评论分页；发评论追加并加计数；删自己的评论；举报评论；拉黑评论作者撤掉其评论、拉黑帖子作者离开。

class NavRecorder extends RefCounted:
	var calls: Array = []
	var left := 0
	func go(route: String, args: Dictionary) -> void:
		calls.append({"route": route, "args": args})
	func leave() -> void:
		left += 1

var session: AuthSession
var feed_t: FakeTransport
var safety_t: FakeTransport
var nav: NavRecorder

func before_test() -> void:
	session = AuthSession.new()
	session.complete_sign_in("uid-1", "id-1", "rt-1", 3600, "password", "a@b.co")
	session.set_server_user("me-1")
	feed_t = FakeTransport.new([])
	safety_t = FakeTransport.new([])
	nav = NavRecorder.new()

func after_test() -> void:
	if FileAccess.file_exists(AuthSession.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AuthSession.PATH))

func _page(args: Dictionary) -> Control:
	var p := (load(AppRoutes.POST) as PackedScene).instantiate()
	p.auth = session
	p.feed = FeedApi.new(ApiClient.new("https://example.test/v1", feed_t.callable()))
	p.safety = SafetyApi.new(ApiClient.new("https://example.test/v1", safety_t.callable()))
	p.navigate = nav.go
	p.leave_handler = nav.leave
	p.setup(args)
	add_child(auto_free(p))
	return p

func _post(id: String, author := "u-a", comments := 1) -> Dictionary:
	return {"id": id, "author": {"user_id": author, "display_name": "Ali", "handle": "ali", "avatar": null},
		"text": "hello", "images": [], "like_count": 0, "comment_count": comments, "liked": false, "created_at": 0}

func _comment(id: String, author: String, text: String) -> Dictionary:
	return {"id": id, "post_id": "p1", "author": {"user_id": author, "display_name": "Bo" if author != "me-1" else "Me", "handle": null, "avatar": null}, "text": text, "created_at": 0}

func test_loads_card_and_comments_then_adds_and_deletes_own_comment() -> void:
	feed_t.responses = [
		{"status": 200, "json": {"items": [_comment("k1", "u-b", "nice"), _comment("k2", "me-1", "mine")], "next_cursor": null}},
		{"status": 201, "json": _comment("k3", "me-1", "added")},
		{"status": 200, "json": {"ok": true}},
	]
	var p := _page({"post": _post("p1", "u-a", 2)})
	assert_bool(await p.load()).is_true()
	assert_bool(str(feed_t.requests[0].url).ends_with("/v1/posts/p1/comments?limit=20")).is_true()
	assert_str(p.card.name).is_equal("Post_p1")
	assert_int(p.comment_list.get_child_count()).is_equal(2)
	var k1: Node = p.comment_list.get_child(0)
	assert_str(k1.name).is_equal("Comment_k1")
	assert_bool((k1.find_child("Author", true, false) as Label).text.begins_with("Bo · ")).is_true()
	assert_object(k1.find_child("Report", true, false)).is_not_null()
	assert_object(k1.find_child("Delete", true, false)).is_null()
	assert_object(p.comment_list.get_child(1).find_child("Delete", true, false)).is_not_null()
	p.composer.text = " added "
	assert_bool(await p.add_comment()).is_true()
	assert_that(feed_t.requests[1].body).is_equal({"text": "added"})
	assert_int(p.comment_list.get_child_count()).is_equal(3)
	assert_str((p.card.find_child("Meta", true, false) as Button).text).is_equal("3 comments")
	assert_str(p.composer.text).is_empty()
	assert_bool(await p.delete_comment("k2")).is_true()
	assert_str(feed_t.requests[2].method).is_equal("DELETE")
	assert_bool(str(feed_t.requests[2].url).ends_with("/v1/comments/k2")).is_true()
	assert_int(p.comment_list.get_child_count()).is_equal(2)
	assert_str((p.card.find_child("Meta", true, false) as Button).text).is_equal("2 comments")

func test_fetches_post_when_only_id_given_and_like_updates_card() -> void:
	feed_t.responses = [
		{"status": 200, "json": _post("p1")},
		{"status": 200, "json": {"items": [], "next_cursor": null}},
		{"status": 200, "json": {"ok": true, "liked": true, "like_count": 1}},
	]
	var p := _page({"post_id": "p1"})
	assert_bool(await p.load()).is_true()
	assert_bool(str(feed_t.requests[0].url).ends_with("/v1/posts/p1")).is_true()
	await p.toggle_like("p1")
	assert_str((p.card.find_child("Like", true, false) as Button).text).is_equal("Liked 1")

func test_report_comment_and_block_comment_author_removes_their_comments() -> void:
	feed_t.responses = [{"status": 200, "json": {"items": [_comment("k1", "u-b", "one"), _comment("k2", "u-c", "two"), _comment("k3", "u-b", "three")], "next_cursor": null}}]
	safety_t.responses = [{"status": 201, "json": {"id": "r1"}}, {"status": 200, "json": {"ok": true}}, {"status": 200, "json": {"ok": true}}]
	var p := _page({"post": _post("p1")})
	await p.load()
	(p.comment_list.get_child(0).find_child("Report", true, false) as Button).pressed.emit()
	await p._on_report_reason(1)
	assert_that(safety_t.requests[0].body).is_equal({"target_type": "comment", "target_id": "k1", "reason": "harassment"})
	(p.comment_list.get_child(0).find_child("Block", true, false) as Button).pressed.emit()
	assert_str(p.block_target).is_equal("u-b")
	await p._on_block_confirmed()
	assert_bool(str(safety_t.requests[1].url).ends_with("/v1/users/u-b/block")).is_true()
	assert_int(p.comment_list.get_child_count()).is_equal(1)
	assert_str(p.comment_list.get_child(0).name).is_equal("Comment_k2")
	assert_int(nav.left).is_equal(0)
	# 拉黑帖子作者：离开本页
	await p.block_user("u-a")
	assert_int(nav.left).is_equal(1)
