extends GdUnitTestSuite
## B5 好友小卡：距离文案分档、不知道自己在哪时只说新鲜度、按钮回调带上 user_id。

func _f(lat := 31.2, lng := 121.5, updated := 0) -> Dictionary:
	return {"user_id": "u-1", "display_name": "阿甲", "handle": "jia", "avatar": null,
		"lat": lat, "lng": lng, "updated_at": updated}

## 测试进程不加载 PO，tr 回落成 msgid：这里断言英文键，翻译由 i18n 校验保证。
func test_distance_text_buckets() -> void:
	assert_str(FriendCard.distance_text(12.0)).is_equal("nearby")
	assert_str(FriendCard.distance_text(340.0)).is_equal("340 m away")
	assert_str(FriendCard.distance_text(1500.0)).is_equal("1.5 km away")
	assert_str(FriendCard.distance_text(250_000.0)).is_equal("250 km away") # 跨城不要小数

func test_distance_is_measured_from_me() -> void:
	# 纬度差 0.001° ≈ 111 m。
	var m: float = FriendCard.distance_m(_f(31.201, 121.5), 31.2, 121.5)
	assert_float(m).is_between(100.0, 125.0)

func test_meta_says_only_freshness_when_we_dont_know_where_we_are() -> void:
	var now := 1_000_000
	var meta: String = FriendCard.meta_text(_f(31.9, 121.9, now - 300_000), {"now_ms": func(): return now})
	assert_str(meta).is_equal("5m ago") # 没有 has_me：不编距离
	var with_me: String = FriendCard.meta_text(_f(31.201, 121.5, now - 300_000),
		{"now_ms": func(): return now, "has_me": true, "me_lat": 31.2, "me_lng": 121.5})
	assert_str(with_me).contains("m away")
	assert_str(with_me).contains("5m ago")

func test_buttons_call_back_with_the_user_id() -> void:
	var seen: Array = []
	var card: PanelContainer = auto_free(FriendCard.build(_f(), {
		"on_profile": func(uid: String): seen.append(["profile", uid]),
		"on_message": func(uid: String): seen.append(["message", uid]),
		"on_close": func(): seen.append(["close"]),
	}))
	assert_str((card.find_child("Who", true, false) as Label).text).is_equal("阿甲")
	for node_name in ["Profile", "Message", "Close"]:
		(card.find_child(node_name, true, false) as Button).pressed.emit()
	assert_array(seen).is_equal([["profile", "u-1"], ["message", "u-1"], ["close"]])
