extends GdUnitTestSuite
## E2：离开设备的诊断数据必须先脱敏——位置与消息正文一律不带。

func test_sensitive_keys_are_replaced_whole() -> void:
	var got: Dictionary = Scrub.payload({
		"lat": 31.2304, "lng": 121.4737, "accuracy_m": 12.0,
		"text": "见面聊", "body": {"text": "秘密"}, "caption": "图注",
		"id_token": "eyJhbGciOiJSUzI1NiIsImtpZCI6IngifQ.payload.sig",
		"conversation_id": "c1", "seq": 7,
	})
	for key in ["lat", "lng", "accuracy_m", "text", "body", "caption", "id_token"]:
		assert_str(str(got[key])).is_equal(Scrub.REDACTED)
	# 不敏感的字段原样保留：没有它们诊断信息就没用了。
	assert_str(str(got["conversation_id"])).is_equal("c1")
	assert_int(int(got["seq"])).is_equal(7)

func test_key_matching_ignores_case_and_separators() -> void:
	assert_bool(Scrub.is_sensitive_key("Lat")).is_true()
	assert_bool(Scrub.is_sensitive_key("ACCESS-TOKEN")).is_true()
	assert_bool(Scrub.is_sensitive_key("display_name")).is_true()
	assert_bool(Scrub.is_sensitive_key("user_id")).is_false()
	assert_bool(Scrub.is_sensitive_key("status")).is_false()

func test_free_text_patterns_are_masked() -> void:
	assert_str(Scrub.text("联系 qa-alice@sensen.test 谢谢")).is_equal("联系 %s 谢谢" % Scrub.REDACTED)
	assert_str(Scrub.text("Authorization: Bearer abc.def-ghi")).is_equal("Authorization: Bearer %s" % Scrub.REDACTED)
	assert_str(Scrub.text("at 31.2304,121.4737 now")).is_equal("at %s now" % Scrub.REDACTED)
	assert_str(Scrub.text("id 1234567890123")).is_equal("id %s" % Scrub.REDACTED)
	assert_str(Scrub.text("HTTP 404 NOT_FOUND")).is_equal("HTTP 404 NOT_FOUND")

func test_urls_lose_their_query() -> void:
	assert_str(Scrub.url("https://api.test/v1/feed?cursor=abc&limit=20")).is_equal("https://api.test/v1/feed?[redacted]")
	assert_str(Scrub.url("https://api.test/v1/feed")).is_equal("https://api.test/v1/feed")

func test_nested_structures_and_depth_limit() -> void:
	# 超过深度上限的整枝直接换成 [redacted]，不去猜里面还有什么。
	var deep: Dictionary = {"lat": 31.2304}
	for i in 12:
		deep = {"wrap": deep}
	assert_bool(str(Scrub.payload(deep)).contains("31.2304")).is_false()
	var got: Dictionary = Scrub.payload({"items": [{"text": "hi", "id": "p1"}, {"lat": 1.0}]})
	var items: Array = got["items"]
	assert_str(str((items[0] as Dictionary)["text"])).is_equal(Scrub.REDACTED)
	assert_str(str((items[0] as Dictionary)["id"])).is_equal("p1")
	assert_str(str((items[1] as Dictionary)["lat"])).is_equal(Scrub.REDACTED)
