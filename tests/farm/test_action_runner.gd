extends GdUnitTestSuite
## 动作队列：逐格、按序、每格 2 秒。

var _started: Array
var _done: Array
var _empty: int

func _runner() -> ActionRunner:
	_started = []
	_done = []
	_empty = 0
	var r := ActionRunner.new()
	r.cell_started.connect(func(c, a): _started.append([c, a]))
	r.cell_done.connect(func(c, a): _done.append([c, a]))
	r.queue_empty.connect(func(): _empty += 1)
	return r

func test_runs_cells_one_at_a_time_in_order() -> void:
	var r := _runner()
	r.enqueue([Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)], "till")
	r.step(0.0)                                    # 起手第一格
	assert_that(r.current_cell()).is_equal(Vector2i(1, 1))
	assert_int(_started.size()).is_equal(1)
	r.step(1.9)
	assert_int(_done.size()).is_equal(0)            # 还没满 2 秒
	r.step(0.1)
	assert_int(_done.size()).is_equal(1)
	assert_that(r.current_cell()).is_equal(Vector2i(2, 1))
	r.step(ActionRunner.ACTION_S)
	r.step(ActionRunner.ACTION_S)
	assert_int(_done.size()).is_equal(3)
	assert_bool(r.is_busy()).is_false()
	assert_int(_empty).is_equal(1)

func test_first_cell_gets_a_full_slice() -> void:
	# 起手那帧不计时；否则第一格会被吞掉一个 dt，长队列越走越偏。
	var r := _runner()
	r.enqueue([Vector2i(1, 1)], "sow")
	r.step(0.5)                                    # 这帧只负责起手
	r.step(ActionRunner.ACTION_S - 0.01)
	assert_int(_done.size()).is_equal(0)
	r.step(0.01)
	assert_int(_done.size()).is_equal(1)

func test_progress_reports_fraction_of_current_cell() -> void:
	var r := _runner()
	r.enqueue([Vector2i(1, 1)], "clear")
	assert_float(r.progress()).is_equal(0.0)
	r.step(0.0)
	r.step(ActionRunner.ACTION_S * 0.5)
	assert_float(r.progress()).is_equal_approx(0.5, 0.01)

func test_cancel_keeps_the_cell_already_underway() -> void:
	# 正在进行的那格命令可能已经发出去了，中途丢弃会让本地与服务端对不上。
	var r := _runner()
	r.enqueue([Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)], "water")
	r.step(0.0)
	assert_int(r.cancel_pending()).is_equal(2)
	assert_bool(r.is_busy()).is_true()
	r.step(ActionRunner.ACTION_S)
	assert_int(_done.size()).is_equal(1)
	assert_bool(r.is_busy()).is_false()

func test_enqueue_while_running_appends_without_restarting() -> void:
	var r := _runner()
	r.enqueue([Vector2i(1, 1)], "till")
	r.step(0.0)
	r.step(1.0)
	r.enqueue([Vector2i(2, 1)], "till")
	assert_that(r.current_cell()).is_equal(Vector2i(1, 1))
	assert_int(r.pending_count()).is_equal(2)
	r.step(1.0)
	assert_that(r.current_cell()).is_equal(Vector2i(2, 1))

func test_idle_runner_emits_nothing() -> void:
	var r := _runner()
	r.step(10.0)
	assert_int(_started.size()).is_equal(0)
	assert_int(_empty).is_equal(0)
	assert_bool(r.is_busy()).is_false()

func test_abort_current_skips_done_and_moves_on() -> void:
	# 本地预测就判定不合法：放弃这格、不发 cell_done（也就不会发命令），后面的照常。
	var r := _runner()
	r.enqueue([Vector2i(1, 1), Vector2i(2, 1)], "clear")
	r.step(0.0)
	r.abort_current()
	assert_int(_done.size()).is_equal(0)
	r.step(0.0)
	assert_that(r.current_cell()).is_equal(Vector2i(2, 1))
	r.step(ActionRunner.ACTION_S)
	assert_int(_done.size()).is_equal(1)
	assert_int(_empty).is_equal(1)

func test_enqueue_skips_cells_already_queued_or_in_progress() -> void:
	var r := _runner()
	assert_int(r.enqueue([Vector2i(1, 1), Vector2i(2, 1)], "clear")).is_equal(2)
	assert_int(r.enqueue([Vector2i(1, 1), Vector2i(3, 1)], "clear")).is_equal(1)
	r.step(0.0)                                   # 1,1 正在做
	assert_int(r.enqueue([Vector2i(1, 1)], "clear")).is_equal(0)
	assert_int(r.pending_count()).is_equal(3)
