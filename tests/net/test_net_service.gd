extends GdUnitTestSuite
## 全局 Net：启动登录、取回农场、测试进程不自动联网。

func _net(responses: Array) -> Array:
	var t := FakeTransport.new(responses)
	var n = load("res://modules/net/net_service.gd").new()
	add_child(auto_free(n))
	n.use_transport(t.callable())
	return [n, t]

func test_test_process_never_auto_boots() -> void:
	# 396 条单测每次启动都去打线上服务器是不可接受的。
	assert_bool(Net.is_test_process()).is_true()
	assert_bool(Net.booted_once).is_false()

func test_boot_logs_in_and_recovers_existing_farm() -> void:
	var pair := _net([
		{"status": 200, "json": {"player_id": "p1", "token": "tok"}},
		{"status": 200, "json": {"farm_id": "f1", "version": 3, "state": {"wallet": 12}}},
	])
	var n = pair[0]
	var flips := []
	n.booted.connect(func(v): flips.append(v))
	assert_bool(await n.boot()).is_true()
	assert_bool(n.logged_in()).is_true()
	assert_bool(n.session.has_farm()).is_true()
	assert_int(n.session.version).is_equal(3)
	assert_array(flips).is_equal([true])

func test_boot_with_no_farm_yet_is_still_logged_in() -> void:
	var pair := _net([
		{"status": 200, "json": {"player_id": "p1", "token": "tok"}},
		{"status": 404, "json": {"code": "NO_FARM"}},
	])
	var n = pair[0]
	assert_bool(await n.boot()).is_true()
	assert_bool(n.logged_in()).is_true()
	assert_bool(n.session.has_farm()).is_false()
	assert_str(n.session.last_error_code).is_equal("NO_FARM")

func test_boot_failure_does_not_crash_and_reports_false() -> void:
	var pair := _net([{"error": "down"}])
	var n = pair[0]
	assert_bool(await n.boot()).is_false()
	assert_bool(n.logged_in()).is_false()

func test_nearby_and_snapshot_wrap_status() -> void:
	var pair := _net([
		{"status": 200, "json": {"region_id": "shanghai", "count": 2, "entries": [{"farm_id": "a"}, {"farm_id": "b"}]}},
		{"status": 404, "json": {"code": "NOT_FOUND"}},
		{"status": 200, "json": {"farm_id": "a", "cells": []}},
	])
	var n = pair[0]
	var t: FakeTransport = pair[1]
	var near: Dictionary = await n.nearby("shanghai")
	assert_bool(near.ok).is_true()
	assert_int(near.count).is_equal(2)
	assert_bool(str(t.requests[0].url).ends_with("/nearby?region_id=shanghai")).is_true()
	var miss: Dictionary = await n.snapshot("zzz")
	assert_bool(miss.ok).is_false()
	assert_int(miss.status).is_equal(404)
	var hit: Dictionary = await n.snapshot("a")
	assert_bool(hit.ok).is_true()
	assert_str(str(hit.snapshot.farm_id)).is_equal("a")

func test_base_url_override_file() -> void:
	var configured_base := Net.base_url()
	var f := FileAccess.open(Net.SERVER_OVERRIDE, FileAccess.WRITE)
	f.store_string("http://192.168.124.53:3000/v1/\n")
	f.close()
	assert_str(Net.base_url()).is_equal("http://192.168.124.53:3000/v1")
	DirAccess.remove_absolute(Net.SERVER_OVERRIDE)
	assert_str(Net.base_url()).is_equal(configured_base)
