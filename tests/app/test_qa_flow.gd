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


## watch：在给定秒数内按间隔补拍，步骤名 watch_NN，报告不会被标成 done。
func test_watch_takes_periodic_shots_until_deadline() -> void:
	var w := QaFlow.new()
	w.out_dir = "user://qa_test"
	w.watch_interval_s = 0.05
	add_child(w)
	auto_free(w)
	await w.watch(1)
	assert_int(w.report.steps.size()).is_greater_equal(2)
	assert_str(str(w.report.steps[0].name)).is_equal("watch_01")
	assert_bool(bool(w.report.steps[-1].saved)).is_true()
	assert_bool(bool(w.report.done)).is_false()
	assert_bool(FileAccess.file_exists("user://qa_test/report.json")).is_true()
	var span_ms: int = int(w.report.steps[-1].at_ms) - int(w.report.steps[0].at_ms)
	assert_int(span_ms).is_less(1500)
