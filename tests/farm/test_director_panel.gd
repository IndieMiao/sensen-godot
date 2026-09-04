extends GdUnitTestSuite
## 导演面板：命令类型与 payload 正确、403 有明确提示、长按三秒才开。

const FARM_SCENE := "res://scenes/farm/farm.tscn"
const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

var _saved_navigation_pending: bool

func before_test() -> void:
	_saved_navigation_pending = AppRouter._navigation_pending

func after_test() -> void:
	AppRouter._navigation_pending = _saved_navigation_pending

func _farm() -> Node:
	var scene := (load(FARM_SCENE) as PackedScene).instantiate()
	scene.setup({"blueprint": FarmBlueprint.load_file(FIX)})
	add_child(auto_free(scene))
	return scene

## 装一个假会话：只记录发出的命令，按脚本回 ok/拒绝码。
func _fake_session(f: Node, responses: Array) -> FakeTransport:
	var t := FakeTransport.new(responses)
	var s := FarmSession.new(ApiClient.new("https://example.test/v1", t.callable()))
	s.player_id = "p-qa-1"
	s.state = {"clock": {"weather_day_index": 3}, "cells": {}}
	s.version = 1
	f.session = s
	return t

func test_speed_row_sends_qa_set_clock() -> void:
	var f := _farm()
	var t := _fake_session(f, [{"status": 200, "json": {"version": 2, "state": {}}}])
	f._on_director_command("qa_set_clock", {"scale": 480})
	assert_str(str(t.last_body().type)).is_equal("qa_set_clock")
	assert_int(int(t.last_body().payload.scale)).is_equal(480)

func test_skip_row_sends_qa_skip_days() -> void:
	var f := _farm()
	var t := _fake_session(f, [{"status": 200, "json": {"version": 2, "state": {}}}])
	f._on_director_command("qa_skip_days", {"days": 2})
	assert_str(str(t.last_body().type)).is_equal("qa_skip_days")
	assert_int(int(t.last_body().payload.days)).is_equal(2)

func test_weather_row_keys_the_override_by_weather_day_index() -> void:
	# 面板选的是「今天改成什么」，命令要的是天气日索引 → 田况。
	var f := _farm()
	var t := _fake_session(f, [{"status": 200, "json": {"version": 2, "state": {}}}])
	f._on_director_command("qa_set_weather", {"day": "wind"})
	var overrides: Dictionary = t.last_body().payload.overrides
	assert_bool(overrides.has("3")).is_true()
	assert_str(str(overrides["3"])).is_equal("wind")

func test_403_says_this_farm_is_not_qa_instead_of_failing_silently() -> void:
	var f := _farm()
	_fake_session(f, [{"status": 403, "json": {"code": "QA_ONLY"}}])
	f._on_director_command("qa_skip_days", {"days": 1})
	# 403 必须把 player_id 亮出来——QA 靠它把自己加进服务器白名单
	assert_str(f.director._status.text).is_equal(DirectorPanel.DENIED_TEXT + " · player p-qa-1")

func test_other_rejections_show_their_code() -> void:
	var f := _farm()
	_fake_session(f, [{"status": 422, "json": {"code": "BAD_QA_PARAM"}}])
	f._on_director_command("qa_set_clock", {"scale": 99999})
	assert_str(f.director._status.text).is_equal("Rejected: BAD_QA_PARAM")

func test_without_a_session_the_panel_says_offline() -> void:
	var f := _farm()
	f._on_director_command("qa_skip_days", {"days": 1})
	assert_str(f.director._status.text).is_equal("Rejected: OFFLINE")

func test_panel_is_hidden_until_the_title_is_held_three_seconds() -> void:
	# 不额外占屏幕：QA 面板不该在正式玩家界面上留按钮。
	var f := _farm()
	assert_bool(f.director.visible).is_false()
	var press := InputEventScreenTouch.new()
	press.pressed = true
	f._on_title_input(press)
	f._tick_title_hold(DirectorPanel.HOLD_S - 0.1)
	assert_bool(f.director.visible).is_false()
	f._tick_title_hold(0.2)
	assert_bool(f.director.visible).is_true()

func test_releasing_early_cancels_the_hold() -> void:
	var f := _farm()
	var press := InputEventScreenTouch.new()
	press.pressed = true
	f._on_title_input(press)
	f._tick_title_hold(1.0)
	var release := InputEventScreenTouch.new()
	release.pressed = false
	f._on_title_input(release)
	f._tick_title_hold(10.0)
	assert_bool(f.director.visible).is_false()

func test_480x_is_the_three_minute_day_preset() -> void:
	# 24 小时 ÷ 480 = 3 分钟。
	assert_bool(DirectorPanel.SCALES.has(480)).is_true()
	assert_int(24 * 60 / 480).is_equal(3)

func test_panel_text_is_english() -> void:
	var f := _farm()
	var stack: Array = [f.director]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var text := ""
		if n is Button:
			text = (n as Button).text
		elif n is Label:
			text = (n as Label).text
		for ch in text:
			assert_bool(ch.unicode_at(0) < 0x2E80).override_failure_message(
				"导演面板文案含非英文字符: %s" % text).is_true()
