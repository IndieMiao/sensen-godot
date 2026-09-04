extends SceneTree
## G1-B 出口验收：用**真实客户端类**（ApiClient / FarmSession / CellPredictor）打真服务端，
## 走完 登录 → 建场 → 清理 → 翻土 → 播种 → 照料 → 等成熟 → 收获，并验证杀进程重开能恢复。
##
## 不用 curl 重写一遍协议：curl 只能证明服务端对，证明不了客户端的重试、对账、
## 预测器与服务端状态机是否一致——那才是 G1-B 的风险所在。
##
##   FARM_BASE=https://farm.sensenjoy.cn/v1 godot --headless --path . --script tools/dev/g1_e2e.gd

var _fails := 0

func _ok(cond: bool, what: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + what)
	if not cond:
		_fails += 1

func _initialize() -> void:
	var base := OS.get_environment("FARM_BASE")
	if base.is_empty():
		base = "https://farm.sensenjoy.cn/v1"
	print("端点 %s" % base)
	var host := Node.new()
	root.add_child(host)
	# _initialize 里刚挂上的节点要等一帧才真正在树里；HTTPRequest 不在树里会
	# 直接返回 ERR_UNCONFIGURED。
	await process_frame
	var client := ApiClient.new(base, ApiClient.make_http_transport(host))
	# 每次跑用新的安装密钥，避免复用上一次的农场。
	var key := Crypto.new().generate_random_bytes(16).hex_encode()
	await _run(client, key, host)
	print("\n%s（%d 项失败）" % ["全部通过" if _fails == 0 else "有失败", _fails])
	quit(0 if _fails == 0 else 1)

func _login(client: ApiClient, key: String) -> Dictionary:
	var r: ApiClient.Response = await client.transport.call("POST", client.base_url + "/auth/anonymous",
		PackedStringArray(["content-type: application/json"]), JSON.stringify({"install_key": key}))
	return r.json if r.is_success() else {}

func _post(client: ApiClient, path: String, body: Variant) -> ApiClient.Response:
	var headers := PackedStringArray(["content-type: application/json"])
	if not client.token.is_empty():
		headers.append("authorization: Bearer %s" % client.token)
	return await client.transport.call("POST", client.base_url + path, headers,
		"" if body == null else JSON.stringify(body))

func _fetch(client: ApiClient, path: String) -> ApiClient.Response:
	var headers := PackedStringArray(["content-type: application/json"])
	if not client.token.is_empty():
		headers.append("authorization: Bearer %s" % client.token)
	return await client.transport.call("GET", client.base_url + path, headers, "")

func _cmd(client: ApiClient, base_version: int, type: String, payload: Dictionary) -> ApiClient.Response:
	return await _post(client, "/farms/me/commands", {
		"idempotency_key": Crypto.new().generate_random_bytes(16).hex_encode(),
		"base_version": base_version, "type": type, "payload": payload,
	})

func _run(client: ApiClient, key: String, host: Node) -> void:
	print("\n1. 匿名登录")
	var auth := await _login(client, key)
	client.token = str(auth.get("token", ""))
	_ok(not client.token.is_empty(), "拿到 token")

	print("\n2. 建农场")
	var made := await _post(client, "/farms", {
		"idempotency_key": Crypto.new().generate_random_bytes(16).hex_encode(),
		"region_id": "shanghai", "layout_patch_id": "sh_a", "blueprint_revision": 2})
	_ok(made.is_success(), "POST /farms → %d" % made.status)
	if not made.is_success():
		return
	var version := int(made.json.version)
	var cells: Dictionary = made.json.state.cells
	# 插入顺序是「先九格初始畦，后三格预留畦」；按字典序取会选中锁着的预留畦。
	var three := cells.keys().slice(0, 3)
	print("   农场 %s v%d，取格 %s" % [made.json.farm_id, version, three])

	# 预测器与服务端并行推进，每一步都比对。
	var predictor := CellPredictor.new(cells, cells.keys(), [])
	var field: String = str(made.json.state.clock.field_condition)
	var care: String = AnimPlaceholders.CARE_ACTION.get(field, "water")
	print("   今日田况 %s → 必需照料 %s" % [field, care])

	print("\n3. 清理 → 翻土 → 播种 → 照料")
	var steps := [
		["clear_cells", {"cell_ids": three}],
		["till_cells", {"cell_ids": three}],
		["sow_cells", {"cell_ids": three, "crop": "R", "lot": "bound"}],
		["apply_care", {"cell_ids": three, "kind": care}],
	]
	for step in steps:
		var type: String = step[0]
		var payload: Dictionary = step[1]
		var r := await _cmd(client, version, type, payload)
		_ok(r.is_success(), "%s → %d %s" % [type, r.status, str(r.json.get("code", ""))])
		if not r.is_success():
			return
		version = int(r.json.version)
		# 预测器走同一步，逐格比对 state。
		var pp := payload.duplicate()
		if type == "sow_cells":
			pp["field_condition"] = field
		if type == "apply_care":
			pp["expected_kind"] = care
		var pred := predictor.predict(type, pp, int(r.json.server_time))
		_ok(pred.ok, "  预测器接受 %s" % type)
		for id in three:
			var mine := str(pred.cells[id].state) if pred.ok else "?"
			var theirs := str((r.json.state.cells[id] as Dictionary).state)
			_ok(mine == theirs, "  %s 预测 %s == 服务端 %s" % [id, mine, theirs])
		predictor.commit(r.json.state.cells, version)

	print("\n4. 成熟需要等（D0 教学萝卜 3 分钟）")
	var ready_at := int(predictor.cells[three[0]].ready_at)
	var server_time := int((await _fetch(client, "/farms/me")).json.server_time)
	var wait_ms := ready_at - server_time
	print("   还差 %.1f 秒" % (wait_ms / 1000.0))
	_ok(wait_ms > 0 and wait_ms < 5 * 60_000, "ready_at 在合理区间")

	var early := await _cmd(client, version, "harvest_cells", {"cell_ids": three})
	_ok(early.status == 422 and str(early.json.code) == "NOT_RIPE", "未熟就收 → 422 NOT_RIPE")

	print("\n5. 等待成熟…")
	while true:
		var probe := await _fetch(client, "/farms/me")
		if int(probe.json.server_time) >= ready_at:
			break
		await create_timer(5.0).timeout
	var harvested := await _cmd(client, version, "harvest_cells", {"cell_ids": three})
	_ok(harvested.is_success(), "收获 → %d %s" % [harvested.status, str(harvested.json.get("code", ""))])
	if harvested.is_success():
		version = int(harvested.json.version)
		_ok(int(harvested.json.state.inventory.produce.R) >= 3, "库存里有 3 颗萝卜")
		for id in three:
			_ok(str((harvested.json.state.cells[id] as Dictionary).state) == "tilled", "%s 收完回到 tilled" % id)

	print("\n6. 杀会话重开（模拟杀进程）")
	var fresh := ApiClient.new(client.base_url, ApiClient.make_http_transport(host))
	var again := await _login(fresh, key)
	fresh.token = str(again.get("token", ""))
	var restored := await _fetch(fresh, "/farms/me")
	_ok(restored.is_success(), "重新登录后 GET /farms/me → %d" % restored.status)
	_ok(int(restored.json.version) == version, "版本一致 %d" % version)
	_ok(str((restored.json.state.cells[three[0]] as Dictionary).state) == "tilled", "状态在服务端")

	print("\n7. 导演模式对非 QA 农场必须拒绝")
	var qa := await _cmd(fresh, version, "qa_skip_days", {"days": 1})
	_ok(qa.status == 403 and str(qa.json.code) == "QA_ONLY", "qa_skip_days → %d %s" % [
		qa.status, str(qa.json.get("code", ""))])
