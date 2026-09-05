extends Node
## 自动玩家：用**真实 farm.tscn + 真实 FarmSession** 打隔离服务端，只按大按钮，从荒地一路
## 做到卖菜、买种子、再次播种九格并由服务端完成 D0。单测只证明各零件。
##   godot --headless --path . tools/dev/g3_play.tscn   （FARM_BASE 可覆盖端点）
## 去掉 --headless 并设置 FARM_PROBE_SHOTS 可保存阶段截图；不加速或修改服务器时间。
## 以场景而不是 --script 运行：--script 不加载 autoload，farm.tscn 依赖 Avatar/Net/AppRouter。

var _fails := 0
var farm: Node
var session: FarmSession
var _wire_commands: Array = []
var _command_errors: Array = []
var _server_cells: Array = []
var _choice_existed := false
var _choice_contents := ""
var _local_data_restored := false
var _install_contents := ""
var _install_existed := false
var _started_at := 0
var _finishing := false

func _ok(cond: bool, what: String) -> bool:
	print(("  PASS  " if cond else "  FAIL  ") + what)
	if not cond:
		_fails += 1
	return cond

func _until(cond: Callable, seconds: float) -> bool:
	var t0 := Time.get_ticks_msec()
	var last_progress := t0
	while Time.get_ticks_msec() - t0 < seconds * 1000.0:
		if cond.call():
			return true
		if Time.get_ticks_msec() - last_progress >= 30_000:
			print("   Waiting %.0fs; CTA: %s" % [float(Time.get_ticks_msec() - t0) / 1000.0,
				str(farm.hud._cta.text) if is_instance_valid(farm) else "loading"])
			last_progress = Time.get_ticks_msec()
		await get_tree().process_frame
	return cond.call()

func _work_cta(label: String) -> bool:
	if not _ok(not farm.hud._cta.disabled, "CTA 可操作：%s" % label): return false
	farm.hud._cta.pressed.emit()
	var idle := await _until(func(): return not farm.runner.is_busy() and farm._in_flight == 0, 240.0)
	_ok(idle, "队列 %s 走完" % label)
	await get_tree().process_frame
	await get_tree().process_frame
	return idle

func _growing_counts() -> Dictionary:
	var counts := {"R": 0, "L": 0, "total": 0}
	for id in session.state.cells:
		var slot: Dictionary = session.state.cells[id]
		if str(slot.state) != "growing": continue
		counts.total += 1
		counts[str(slot.crop)] = int(counts.get(str(slot.crop), 0)) + 1
	return counts

func _capture(stage: String) -> void:
	var directory := OS.get_environment("FARM_PROBE_SHOTS")
	if directory.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(directory)
	var target := directory.path_join("g3-%s.png" % stage)
	var snapshot := get_viewport().get_texture().get_image()
	_ok(snapshot.save_png(target) == OK, "保存截图 %s" % target)

func _ready() -> void:
	_started_at = Time.get_ticks_msec()
	var base := OS.get_environment("FARM_BASE")
	if base.is_empty():
		base = "http://127.0.0.1:3101/v1"
	print("端点 %s" % base)
	_choice_existed = FileAccess.file_exists(FarmChoice.PATH)
	if _choice_existed: _choice_contents = FileAccess.get_file_as_string(FarmChoice.PATH)
	_install_existed = FileAccess.file_exists(ApiClient.INSTALL_KEY_PATH)
	if _install_existed: _install_contents = FileAccess.get_file_as_string(ApiClient.INSTALL_KEY_PATH)
	session = FarmSession.new(ApiClient.new(base, _isolated_transport()))
	get_tree().create_timer(600.0, true, false, true).timeout.connect(func():
		_ok(false, "Probe exceeded ten minutes")
		_finish())
	await get_tree().process_frame

	print("\n1. 登录建场")
	# 瞬时网络抖动不该让整轮作废：登录最多重试 3 次。
	var logged := false
	for attempt in 3:
		logged = await session.login()
		if logged:
			break
		await get_tree().create_timer(2.0).timeout
	if not _ok(logged, "login%s" % ("" if logged else "（%s）" % session.last_error_code)):
		_finish()
		return
	var location := {"lat": 31.228, "lng": 121.481}
	if not _ok(await session.ensure_farm("shanghai", "sh_a", 2, location), "ensure_farm with saved position"):
		_finish()
		return
	_ok(session.location == location, "服务端保存独立位置")
	print("   Test player %s; farm %s" % [session.player_id, session.farm_id])
	_server_cells = session.state.cells.keys()
	var bp := FarmBlueprint.load_choice({"layout_patch_id": session.layout_patch_id,
		"revision": session.blueprint_revision, "location": session.location})
	farm = (load("res://scenes/farm/farm.tscn") as PackedScene).instantiate()
	farm.setup({"blueprint": bp, "session": session})
	add_child(farm)
	await get_tree().process_frame
	_ok(farm.session == session, "farm 挂上会话")
	_ok(farm.interior != null and farm.bp.grid == Vector2i(20, 20), "进入 3x3 FarmInterior")
	var remapped := true
	for local_id in farm.predictor.cells:
		var source_id: String = farm.interior.source_id(str(local_id))
		remapped = remapped and _server_cells.has(source_id) and source_id != str(local_id)
	_ok(remapped and farm.predictor.cells.size() == _server_cells.size(), "展示格和锁定预留格都映射到原始服务器格")
	_ok(farm._actionable_view().size() == 9, "只有 9 个展示格可操作，预留畦仍锁定")
	_ok(farm.hud._goals_header.text.begins_with("Goals · 1/7"), "目标 1/7（实际 %s）" % farm.hud._goals_header.text)
	_ok(not bool(DayGoals.progress(session.state, session.derived, session.server_now()).complete), "建场尚未完成 D0")
	await _capture("fresh")

	print("\n2. 只按大按钮，直到没事可做")
	Engine.time_scale = 4.0   # 走路与 2 秒/格只是节奏，加速不影响服务端
	var seen: Array = []
	for i in 12:
		var label: String = farm.hud._cta.text
		var enabled: bool = not farm.hud._cta.disabled
		seen.append(label)
		print("   CTA: %s%s" % [label, "" if enabled else "（禁用）"])
		if not enabled or label.begins_with("Sell") or label.begins_with("Buy"):
			break
		if not await _work_cta(label):
			_finish()
			return
	Engine.time_scale = 1.0
	_ok(seen.has("Clear 9 plots"), "见到 Clear 9 plots")
	_ok(seen.has("Till 9 plots"), "见到 Till 9 plots")
	_ok(seen.has("Sow 6 Radish"), "见到 Sow 6 Radish")
	var care_label := "%s 6 plots" % NextStep.care_verb(str(session.state.clock.field_condition))
	_ok(seen.has(care_label), "见到 %s" % care_label)
	_ok(not seen.has("Sow 3 Lettuce"), "首次收获前不会提前播种生菜")
	await session.refresh()
	var growing := _growing_counts()
	if not _ok(growing.total == 6 and growing.R == 6 and growing.L == 0,
			"教学轮只有 6R growing（实际 %s）" % str(growing)):
		_finish()
		return
	_ok(farm.hud._goals_header.text.begins_with("Goals · 5/7"), "目标 5/7（实际 %s）" % farm.hud._goals_header.text)
	_ok(int(session.state.inventory.seeds.L.bound) == 3, "次日 3L 绑定种子保留在仓库")
	_ok(str(farm.hud._cta.text) == "First harvest is growing", "教学等待态 CTA（实际 %s）" % farm.hud._cta.text)
	var tutorial_duration_valid := true
	for id in session.state.cells:
		var slot: Dictionary = session.state.cells[id]
		if str(slot.crop) == "R":
			tutorial_duration_valid = tutorial_duration_valid and int(slot.ready_at) - int(slot.care_done_at) == 180_000
	_ok(tutorial_duration_valid, "教学萝卜使用真实 180 秒服务器成熟时间")
	await _capture("tutorial-growing")

	print("\n3. 等教学萝卜成熟（3 分钟）")
	# 六颗萝卜的浇水时刻差一两秒，会一颗一颗熟；等到六颗都能收再按。
	var ripe := await _until(func(): return str(farm.hud._cta.text) == "Harvest 6 plots", 260.0)
	if not _ok(ripe, "CTA 变成 %s" % farm.hud._cta.text):
		_finish()
		return
	Engine.time_scale = 4.0
	if not await _work_cta(str(farm.hud._cta.text)):
		_finish()
		return
	Engine.time_scale = 1.0
	await get_tree().process_frame
	await session.refresh()
	_ok(int(session.state.inventory.produce.R) == 6, "库存 6 颗萝卜（实际 %d）" % int(session.state.inventory.produce.R))
	_ok(farm.hud._goals_header.text.begins_with("Goals · 6/7"), "首次收获后目标仍是 6/7（实际 %s）" % farm.hud._goals_header.text)
	_ok(str(session.state.chapters[0].status) == "active", "首次收获不会提前完成服务端 D0")
	_ok(not bool(DayGoals.progress(session.state, session.derived, session.server_now()).complete), "客户端仍等待次日新批次")
	await _capture("first-harvest")

	print("\n4. 摊位：卖菜、买种子")
	var wallet0 := int(session.state.wallet)
	farm.hud._stall.pressed.emit()
	_ok(farm.stall.visible, "摊位打开")
	var before_sale := session.version
	_ok(not farm.stall._sell_all.disabled and farm.stall._sell_items.size() == 1, "Sell all 汇总可售萝卜")
	farm.stall._sell_all.pressed.emit()
	_ok(await _until(func(): return session.version > before_sale, 20.0), "Sell all 按钮完成交易")
	await get_tree().process_frame
	_ok(int(session.state.wallet) == wallet0 + 48, "钱包 %d → %d（+48）" % [wallet0, int(session.state.wallet)])
	_ok(farm.hud._toast_label.text == "+48 coins", "toast +48 coins（实际 %s）" % farm.hud._toast_label.text)
	_ok(int(session.state.inventory.produce.R) == 0, "Sell all 清空可售萝卜")
	for purchase in 2:
		var before_buy := session.version
		var buy: Button = farm.stall._seed_rows["R"].button
		if not _ok(not buy.disabled, "第 %d 次 Buy 3 按钮可用" % (purchase + 1)):
			_finish()
			return
		buy.pressed.emit()
		if not _ok(await _until(func(): return session.version > before_buy, 20.0), "Buy 3 按钮完成交易"):
			_finish()
			return
		await get_tree().process_frame
		_ok(int(session.state.wallet) == wallet0 + 48 - 12 * (purchase + 1), "每次买 3 颗萝卜种子 -12 → %d" % int(session.state.wallet))
		_ok(int(session.state.inventory.seeds.R.bought) == 3 * (purchase + 1), "萝卜种子 bought=%d" % int(session.state.inventory.seeds.R.bought))
	var done := DayGoals.done_count(DayGoals.evaluate(session.state, session.state.cells))
	_ok(done == 6, "买种子不会推进章节目标（实际 %d/7）" % done)
	farm.stall.closed.emit()
	await get_tree().process_frame
	_ok(not farm.stall.visible, "关闭摊位回到农场")
	var radish_seed: Button = farm.hud._seed_buttons["R"]
	if not _ok(not radish_seed.disabled, "选择刚买的萝卜种子"):
		_finish()
		return
	radish_seed.pressed.emit()
	await get_tree().process_frame
	_ok(str(farm.hud._cta.text) == "Sow 6 Radish", "CTA 回到 Sow 6 Radish（实际 %s）" % farm.hud._cta.text)

	print("\n5. 实际播种并照料次日九格")
	Engine.time_scale = 4.0
	var next_seen: Array = []
	for i in 8:
		var label: String = farm.hud._cta.text
		print("   Next batch CTA: %s" % label)
		next_seen.append(label)
		if farm.hud._cta.disabled or str(farm.hud._action) == "stall": break
		if not await _work_cta(label):
			_finish()
			return
	Engine.time_scale = 1.0
	_ok(next_seen.has("Sow 6 Radish") and next_seen.has("Sow 3 Lettuce"), "通过实际 CTA 播下 6R + 3L")
	_ok(next_seen.has(care_label) and next_seen.has("%s 3 plots" % NextStep.care_verb(str(session.state.clock.field_condition))), "通过实际 CTA 照料两种作物")
	await session.refresh()
	growing = _growing_counts()
	_ok(growing.total == 9 and growing.R == 6 and growing.L == 3, "次日九格 growing（实际 %s）" % str(growing))
	_ok(bool(DayGoals.progress(session.state, session.derived, session.server_now()).complete), "客户端确认 D0 complete")
	_ok(str(session.state.chapters[0].status) == "done", "服务端正式记录 D0 done")
	_ok(bool(session.state.chapters[0].step_flags.get("next_batch_sown_and_cared", false)), "服务端记录真实次日批次播种及照料事实")
	var next_at = session.derived.get("next_chapter_opens_at")
	_ok((next_at is int or next_at is float) and int(next_at) > session.server_now(), "返回有效的下一章开放时间")
	_ok(farm.hud._goals_header.text.begins_with("Goals · 7/7"), "完成新批次后目标 7/7（实际 %s）" % farm.hud._goals_header.text)
	_ok(int(session.state.clock.chapter_index) == 0, "同一天不会自动跳到 D1")
	_ok(int(session.state.inventory.seeds.R.bought) == 0 and int(session.state.inventory.seeds.L.bound) == 0, "本轮恰好用完购买的 6R 和绑定的 3L")
	await _capture("d0-complete")
	var mapped_commands := true
	var command_counts := {}
	for command in _wire_commands:
		command_counts[command.type] = int(command_counts.get(command.type, 0)) + 1
		for id in command.cell_ids:
			mapped_commands = mapped_commands and _server_cells.has(str(id))
	_ok(mapped_commands and _wire_commands.size() == 54, "所有农事请求携带源蓝图格 ID（%d 次）" % _wire_commands.size())
	_ok(command_counts == {"clear_cells": 9, "till_cells": 9, "sow_cells": 15, "apply_care": 15, "harvest_cells": 6}, "两轮农事命令数量精确匹配")
	_ok(_command_errors.is_empty(), "无服务器命令拒绝（%s）" % str(_command_errors))
	print("   Applied farm commands: %s" % JSON.stringify(command_counts))
	_finish()

func _isolated_transport() -> Callable:
	var transport := ApiClient.make_http_transport(self)
	var probe_key := Crypto.new().generate_random_bytes(16).hex_encode()
	return func(method: String, url: String, headers: PackedStringArray, body_text: String) -> ApiClient.Response:
		var body: Dictionary = JSON.parse_string(body_text) if not body_text.is_empty() else {}
		if url.ends_with("/auth/anonymous"):
			body["install_key"] = probe_key
			body_text = JSON.stringify(body)
		var command := url.ends_with("/farms/me/commands")
		if command and body.get("payload", {}).has("cell_ids"):
			_wire_commands.append({"type": str(body.type), "cell_ids": body.payload.cell_ids.duplicate()})
		var response: ApiClient.Response = await transport.call(method, url, headers, body_text)
		if command and not response.is_success():
			_command_errors.append({"type": body.get("type", ""), "status": response.status,
				"code": response.json.get("code", response.error)})
		return response

func _restore_local_data() -> void:
	if _local_data_restored:
		return
	_local_data_restored = true
	if _choice_existed:
		var file := FileAccess.open(FarmChoice.PATH, FileAccess.WRITE)
		if file: file.store_string(_choice_contents)
	else:
		FarmChoice.clear()
	if _install_existed:
		if FileAccess.get_file_as_string(ApiClient.INSTALL_KEY_PATH) != _install_contents:
			var file := FileAccess.open(ApiClient.INSTALL_KEY_PATH, FileAccess.WRITE)
			if file: file.store_string(_install_contents)
	elif FileAccess.file_exists(ApiClient.INSTALL_KEY_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ApiClient.INSTALL_KEY_PATH))

func _finish() -> void:
	if _finishing: return
	_finishing = true
	Engine.time_scale = 1.0
	if _install_existed:
		_ok(FileAccess.get_file_as_string(ApiClient.INSTALL_KEY_PATH) == _install_contents, "本地安装密钥未变")
	_restore_local_data()
	print("\n%s（%d 项失败，%.1f 秒）" % ["全部通过" if _fails == 0 else "有失败", _fails,
		float(Time.get_ticks_msec() - _started_at) / 1000.0])
	get_tree().quit(0 if _fails == 0 else 1)

func _exit_tree() -> void:
	_restore_local_data()
