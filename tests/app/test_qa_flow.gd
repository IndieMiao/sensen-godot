extends GdUnitTestSuite
## QaFlow：触发条件解析与选择器辅助；完整步行只在模拟器 / 真机上跑（tools 目录之外，导出包里带着）。

func test_requested_from_args_or_env() -> void:
	assert_str(QaFlow.requested(PackedStringArray(["--qa-flow=Social"]), "")).is_equal("social")
	assert_str(QaFlow.requested(PackedStringArray(["--qa-scene=login"]), " social ")).is_equal("social")
	assert_str(QaFlow.requested(PackedStringArray(), "")).is_empty()
	assert_str(QaFlow.requested(PackedStringArray(["--qa-flow=social"]), "other")).is_equal("social") # 参数优先

func test_select_id_picks_by_item_id() -> void:
	var o := OptionButton.new()
	auto_free(o)
	for y in [2026, 2025, 2000]:
		o.add_item(str(y), y)
	QaFlow.select_id(o, 2000)
	assert_int(o.get_selected_id()).is_equal(2000)

func test_walker_is_not_attached_in_test_process() -> void:
	assert_bool(AppRouter.get_node_or_null("QaFlow") == null).is_true()

func test_parse_credentials_splits_on_first_colon_only() -> void:
	assert_that(QaFlow.parse_credentials("a@b.co:p:w:d")).is_equal({"email": "a@b.co", "password": "p:w:d"})
	assert_that(QaFlow.parse_credentials("nocolon")).is_equal({})
	assert_that(QaFlow.parse_credentials(":pw")).is_equal({})
	assert_that(QaFlow.parse_credentials("a@b.co:")).is_equal({})
