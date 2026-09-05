extends SceneTree
## G2 出口验收（真服务端）。注意 --script 模式不加载 autoload：别在这里引用依赖 Avatar/Net
## 单例的类（SeededOutfit 之类），否则整个脚本编译失败且协程挂死不退出。：A 建场并开放访问 → B 在 nearby 看到 A 与两座预置农场 → B 取快照，
## 字段集精确、无主人私有数据 → A 关闭访问 → B 再取 404 → B 建场后返回访问，D4 前
## record_visit_return 被 CHAPTER_LOCKED（零奖励教学事实的闸门在服务端）。
##   FARM_BASE=https://farm.sensenjoy.cn/v1 godot --headless --path . --script tools/dev/g2_e2e.gd

var _fails := 0

func _ok(cond: bool, what: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + what)
	if not cond:
		_fails += 1

func _session(base: String, host: Node) -> FarmSession:
	DirAccess.remove_absolute(ApiClient.INSTALL_KEY_PATH)   # 每个会话一把新钥匙
	return FarmSession.new(ApiClient.new(base, ApiClient.make_http_transport(host)))

func _fetch(s: FarmSession, path: String) -> ApiClient.Response:
	return await s.client.request("GET", path)

func _initialize() -> void:
	var base := OS.get_environment("FARM_BASE")
	if base.is_empty():
		base = "https://farm.sensenjoy.cn/v1"
	print("端点 %s" % base)
	var host := Node.new()
	root.add_child(host)
	await process_frame

	print("\n1. A 登录建场，开放访问")
	var a := _session(base, host)
	_ok(await a.login(), "A login")
	_ok(await a.ensure_farm("shanghai", "sh_a", 2), "A ensure_farm")
	_ok(await a.send("set_visit_access", {"access": "anyone"}), "A set_visit_access anyone → v%d" % a.version)

	print("\n2. B 登录，看 nearby")
	var b := _session(base, host)
	_ok(await b.login(), "B login")
	var near: ApiClient.Response = await _fetch(b, "/nearby?region_id=shanghai")
	_ok(near.is_success(), "GET /nearby → %d" % near.status)
	var ids: Array = (near.json.get("entries", []) as Array).map(func(e): return str(e.farm_id))
	_ok(ids.has(a.farm_id), "nearby 含 A（count=%d）" % int(near.json.get("count", 0)))
	for pre in PresetSnapshots.entries("shanghai"):
		_ok(ids.has(str(pre.farm_id)), "nearby 含预置 %s（与随包同 id）" % str(pre.avatar_ref))
	if not (near.json.get("entries", []) as Array).is_empty():
		var e: Dictionary = near.json.entries[0]
		_ok(e.keys().size() <= 4 and e.has("farm_id") and e.has("avatar_ref") and e.has("nursery_stage"), "NearbyEntry 字段集精确")

	print("\n3. B 取 A 的快照")
	var snap: ApiClient.Response = await _fetch(b, "/farms/%s/snapshot" % a.farm_id)
	_ok(snap.is_success(), "GET snapshot → %d" % snap.status)
	var keys: Array = snap.json.keys()
	keys.sort()
	_ok(keys == ["avatar_ref", "beds_unlocked", "blueprint_revision", "cells", "farm_id", "layout_patch_id", "nursery",
		"props", "region_id", "server_time", "snapshot_revision", "snapshot_taken_at", "weather_snapshot"],
		"快照字段集精确: %s" % str(keys))
	var text := JSON.stringify(snap.json)
	for bad in ["wallet", "owner_id", "inventory", "residents", "xp", "ready_at", "lat", "lng"]:
		_ok(not text.contains('"%s"' % bad), "快照不含 %s" % bad)
	_ok(int(snap.json.get("snapshot_revision", 0)) >= 1, "snapshot_revision ≥ 1")
	var again: ApiClient.Response = await _fetch(b, "/farms/%s/snapshot" % a.farm_id)
	_ok(int(again.json.snapshot_taken_at) == int(snap.json.snapshot_taken_at), "同槽再取 taken_at 不变")

	print("\n4. 预置农场快照可取，且 CropField 能渲染它")
	var pre_id := str(PresetSnapshots.entries("shanghai")[0].farm_id)
	var pre_snap: ApiClient.Response = await _fetch(b, "/farms/%s/snapshot" % pre_id)
	_ok(pre_snap.is_success(), "预置快照 → %d" % pre_snap.status)
	var growing := (pre_snap.json.get("cells", []) as Array).filter(func(c): return str(c.state) == "growing").size()
	_ok(growing == 9, "繁茂样例 9 格 growing（实际 %d）" % growing)
	_ok(str(pre_snap.json.get("avatar_ref", "")) == "preset_a", "avatar_ref=preset_a")

	print("\n5. A 关闭访问 → B 再取 404，nearby 不再含 A")
	_ok(await a.send("set_visit_access", {"access": "only_me"}), "A set_visit_access only_me")
	var denied: ApiClient.Response = await _fetch(b, "/farms/%s/snapshot" % a.farm_id)
	_ok(denied.status == 404, "snapshot → %d" % denied.status)
	var near2: ApiClient.Response = await _fetch(b, "/nearby?region_id=shanghai")
	_ok(not (near2.json.get("entries", []) as Array).map(func(e): return str(e.farm_id)).has(a.farm_id), "nearby 不再含 A")

	print("\n6. B 建场后返回访问：D4 前 record_visit_return 被服务端闸门挡住（零奖励）")
	_ok(await b.ensure_farm("shanghai", "sh_a", 2), "B ensure_farm")
	var before := int(b.state.get("wallet", -1))
	var rec := await b.send("record_visit_return", {"visited_farm_id": pre_id})
	_ok(not rec and b.last_error_code == "CHAPTER_LOCKED", "record_visit_return → %s" % b.last_error_code)
	await b.refresh()
	_ok(int(b.state.get("wallet", -2)) == before, "钱包不变（%d）" % before)

	DirAccess.remove_absolute(ApiClient.INSTALL_KEY_PATH)
	print("\n%s（%d 项失败）" % ["全部通过" if _fails == 0 else "有失败", _fails])
	quit(0 if _fails == 0 else 1)
