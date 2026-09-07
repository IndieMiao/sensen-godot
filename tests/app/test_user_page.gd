extends GdUnitTestSuite
## 用户主页：按 handle / id 拉资料与动态、关注切换后重拉、发消息开单聊、举报与拉黑、被拉黑时的提示。

class NavRecorder extends RefCounted:
	var calls: Array = []
	var left := 0
	func go(route: String, args: Dictionary) -> void:
		calls.append({"route": route, "args": args})
	func leave() -> void:
		left += 1

var session: AuthSession
var profile_t: FakeTransport
var feed_t: FakeTransport
var safety_t: FakeTransport
var im_t: FakeTransport
var nav: NavRecorder

func before_test() -> void:
	session = AuthSession.new()
	session.complete_sign_in("uid-1", "id-1", "rt-1", 3600, "password", "a@b.co")
	session.set_server_user("me-1")
	profile_t = FakeTransport.new([])
	feed_t = FakeTransport.new([])
	safety_t = FakeTransport.new([])
	im_t = FakeTransport.new([])
	nav = NavRecorder.new()

func after_test() -> void:
	if FileAccess.file_exists(AuthSession.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AuthSession.PATH))

func _page(args: Dictionary) -> Control:
	var p := (load(AppRoutes.USER) as PackedScene).instantiate()
	p.auth = session
	p.profile = ProfileApi.new(ApiClient.new("https://example.test/v1", profile_t.callable()))
	p.feed = FeedApi.new(ApiClient.new("https://example.test/v1", feed_t.callable()))
	p.safety = SafetyApi.new(ApiClient.new("https://example.test/v1", safety_t.callable()))
	p.im = ImApi.new(ApiClient.new("https://example.test/v1", im_t.callable()))
	p.navigate = nav.go
	p.leave_handler = nav.leave
	p.setup(args)
	add_child(auto_free(p))
	return p

func _profile(following := false, followed_by := false, with_following := true) -> Dictionary:
	var d := {"user_id": "u-a", "handle": "ali", "display_name": "Ali", "bio": "hi there", "avatar": null,
		"followers_count": 12, "following_visible": true, "relation": {"following": following, "followed_by": followed_by}}
	if with_following:
		d["following_count"] = 3
	return d

func _post(id: String, text: String) -> Dictionary:
	return {"id": id, "author": {"user_id": "u-a", "display_name": "Ali", "handle": "ali", "avatar": null},
		"text": text, "images": [], "like_count": 0, "comment_count": 0, "liked": false, "created_at": 0}

func test_loads_profile_by_handle_then_posts_and_shows_relation() -> void:
	profile_t.responses = [{"status": 200, "json": _profile(false, true)}]
	feed_t.responses = [{"status": 200, "json": {"items": [_post("p1", "one"), _post("p2", "two")], "next_cursor": "c2"}}]
	var p := _page({"handle": "@Ali"})
	assert_bool(await p.load()).is_true()
	assert_bool(str(profile_t.requests[0].url).ends_with("/v1/users/%40ali/profile")).is_true()
	assert_bool(str(feed_t.requests[0].url).ends_with("/v1/users/u-a/posts?limit=20")).is_true()
	assert_str(p.name_label.text).is_equal("Ali")
	assert_str(p.title_label.text).is_equal("Ali")
	assert_str(p.handle_label.text).is_equal("@ali")
	assert_str(p.bio_label.text).is_equal("hi there")
	assert_str(p.counts_label.text).is_equal("12 followers · 3 following · Follows you")
	assert_str(p.follow_button.text).is_equal("Follow")
	assert_bool((p.follow_button.get_parent() as Control).visible).is_true()
	assert_int(p.list.get_child_count()).is_equal(2)
	assert_str(p.list.get_child(0).name).is_equal("Post_p1")
	assert_bool(p.more_button.visible).is_true()
	# 卡片上作者是本人页面的主人：评论数按钮进详情
	(p.list.get_child(0).find_child("Meta", true, false) as Button).pressed.emit()
	assert_str(nav.calls[0].route).is_equal(AppRoutes.POST)

func test_follow_toggles_put_then_delete_and_refetches_profile() -> void:
	profile_t.responses = [
		{"status": 200, "json": _profile(false)},
		{"status": 200, "json": {"ok": true, "following": true}}, {"status": 200, "json": _profile(true)},
		{"status": 200, "json": {"ok": true, "following": false}}, {"status": 200, "json": _profile(false)},
	]
	feed_t.responses = [{"status": 200, "json": {"items": [], "next_cursor": null}}]
	var p := _page({"user_id": "u-a"})
	await p.load()
	assert_bool(await p.toggle_follow()).is_true()
	assert_str(profile_t.requests[1].method).is_equal("PUT")
	assert_bool(str(profile_t.requests[1].url).ends_with("/v1/users/u-a/follow")).is_true()
	assert_str(p.follow_button.text).is_equal("Following")
	assert_bool(await p.toggle_follow()).is_true()
	assert_str(profile_t.requests[3].method).is_equal("DELETE")
	assert_str(p.follow_button.text).is_equal("Follow")
	assert_bool(p.status.text.contains("No posts")).is_true()

func test_message_opens_dm_and_pushes_chat() -> void:
	profile_t.responses = [{"status": 200, "json": _profile()}]
	feed_t.responses = [{"status": 200, "json": {"items": [], "next_cursor": null}}]
	im_t.responses = [{"status": 200, "json": {"id": "c7", "kind": "dm", "peer": {"user_id": "u-a", "display_name": "Ali"}}}]
	var p := _page({"user_id": "u-a"})
	await p.load()
	assert_bool(await p.open_chat()).is_true()
	assert_that(im_t.requests[0].body).is_equal({"user_id": "u-a"})
	assert_str(nav.calls[-1].route).is_equal(AppRoutes.CHAT)
	assert_str(nav.calls[-1].args.conversation.id).is_equal("c7")

func test_report_and_block_hit_safety_and_block_leaves_page() -> void:
	profile_t.responses = [{"status": 200, "json": _profile()}]
	feed_t.responses = [{"status": 200, "json": {"items": [_post("p1", "x")], "next_cursor": null}}]
	safety_t.responses = [{"status": 201, "json": {"id": "r1"}}, {"status": 201, "json": {"id": "r2"}}, {"status": 200, "json": {"ok": true}}]
	var p := _page({"user_id": "u-a"})
	await p.load()
	p.open_report_menu("user", "u-a")
	await p._on_report_reason(0)
	assert_that(safety_t.requests[0].body).is_equal({"target_type": "user", "target_id": "u-a", "reason": "spam"})
	(p.list.get_child(0).find_child("Report", true, false) as Button).pressed.emit()
	await p._on_report_reason(2)
	assert_that(safety_t.requests[1].body).is_equal({"target_type": "post", "target_id": "p1", "reason": "sexual"})
	assert_bool(p.status.text.contains("report")).is_true()
	await p._on_block_confirmed()
	assert_str(safety_t.requests[2].method).is_equal("PUT")
	assert_bool(str(safety_t.requests[2].url).ends_with("/v1/users/u-a/block")).is_true()
	assert_int(nav.left).is_equal(1)

func test_blocked_or_missing_user_shows_hint_and_own_profile_hides_actions() -> void:
	profile_t.responses = [{"status": 404, "json": {"code": "NOT_FOUND"}}]
	var p := _page({"user_id": "u-x"})
	assert_bool(await p.load()).is_false()
	assert_bool(p.status.text.contains("isn't available")).is_true()
	assert_int(feed_t.requests.size()).is_equal(0)
	var me := _profile()
	me["user_id"] = "me-1"
	profile_t.responses.append({"status": 200, "json": me})
	feed_t.responses = [{"status": 200, "json": {"items": [], "next_cursor": null}}]
	var q := _page({"user_id": "me-1"})
	assert_bool(await q.load()).is_true()
	assert_bool((q.follow_button.get_parent() as Control).visible).is_false()
