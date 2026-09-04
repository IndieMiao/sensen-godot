extends Node
## 自动玩家：用**真实 farm.tscn + 真实 FarmSession** 打线上服务端，只按大按钮，从荒地一路
## 做到卖菜、买种子。这是「交互模型 v2 在真服务端上闭环」的证据；单测只证明各零件。
##   godot --headless --path . tools/dev/g3_play.tscn   （FARM_BASE 可覆盖端点）
## 以场景而不是 --script 运行：--script 不加载 autoload，farm.tscn 依赖 Avatar/Net/AppRouter。

var _fails := 0
var farm: Node
var session: FarmSession

func _ok(cond: bool, what: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + what)
	if not cond:
		_fails += 1

func _until(cond: Callable, seconds: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < seconds * 1000.0:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()

func _ready() -> void:
	var base := OS.get_environment("FARM_BASE")
	if base.is_empty():
		base = "https://farm.sensenjoy.cn/v1"
	print("端点 %s" % base)
	DirAccess.remove_absolute(ApiClient.INSTALL_KEY_PATH)      # 每次一个新玩家
	session = FarmSession.new(ApiClient.new(base, ApiClient.make_http_transport(self)))
	await get_tree().process_frame

	print("\n1. 登录建场")
	_ok(await session.login(), "login")
	_ok(await session.ensure_farm("shanghai", "sh_a", 2), "ensure_farm %s" % session.layout_patch_id)
	var bp := FarmBlueprint.load_file(FarmBlueprint.asset_path(session.layout_patch_id, session.blueprint_revision))
	farm = (load("res://scenes/farm/farm.tscn") as PackedScene).instantiate()
	farm.setup({"blueprint": bp, "session": session})
	add_child(farm)
	await get_tree().process_frame
	_ok(farm.session == session, "farm 挂上会话")
	_ok(farm.hud._goals_header.text == "Day 1 goals · 0/7", "目标 0/7（实际 %s）" % farm.hud._goals_header.text)

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
		farm._on_cta()
		var idle := await _until(func(): return not farm.runner.is_busy() and farm._in_flight == 0, 240.0)
		_ok(idle, "队列 %s 走完" % label)
		await get_tree().process_frame
		await get_tree().process_frame
	Engine.time_scale = 1.0
	_ok(seen.has("Clear 9 plots"), "见到 Clear 9 plots")
	_ok(seen.has("Till 9 plots"), "见到 Till 9 plots")
	_ok(seen.has("Sow 6 Radish"), "见到 Sow 6 Radish")
	_ok(seen.has("Water 6 plots"), "见到 Water 6 plots")
	_ok(seen.has("Sow 3 Lettuce"), "见到 Sow 3 Lettuce")
	await session.refresh()
	var growing := 0
	for id in session.state.cells:
		if str(session.state.cells[id].state) == "growing":
			growing += 1
	_ok(growing == 9, "服务端 9 格 growing（实际 %d）" % growing)
	_ok(farm.hud._goals_header.text.begins_with("Day 1 goals · 4/7"), "目标 4/7（实际 %s）" % farm.hud._goals_header.text)
	_ok(str(farm.hud._cta.text) == "Crops are growing", "等待态 CTA（实际 %s）" % farm.hud._cta.text)

	print("\n3. 等教学萝卜成熟（3 分钟）")
	var ripe := await _until(func(): return str(farm.hud._cta.text).begins_with("Harvest"), 260.0)
	_ok(ripe, "CTA 变成 %s" % farm.hud._cta.text)
	_ok(str(farm.hud._cta.text) == "Harvest 6 plots", "Harvest 6 plots")
	Engine.time_scale = 4.0
	farm._on_cta()
	_ok(await _until(func(): return not farm.runner.is_busy() and farm._in_flight == 0, 240.0), "收获队列走完")
	Engine.time_scale = 1.0
	await get_tree().process_frame
	await session.refresh()
	_ok(int(session.state.inventory.produce.R) == 6, "库存 6 颗萝卜（实际 %d）" % int(session.state.inventory.produce.R))
	_ok(str(farm.hud._cta.text) == "Sell 6 at the stall", "CTA = Sell 6 at the stall（实际 %s）" % farm.hud._cta.text)

	print("\n4. 摊位：卖菜、买种子")
	var wallet0 := int(session.state.wallet)
	farm._open_stall()
	_ok(farm.stall.visible, "摊位打开")
	await farm._on_sell([{"kind": "produce", "id": "R", "qty": 6}])
	await session.refresh()
	_ok(int(session.state.wallet) == wallet0 + 48, "钱包 %d → %d（+48）" % [wallet0, int(session.state.wallet)])
	_ok(farm.hud._toast_label.text == "+48 coins", "toast +48 coins（实际 %s）" % farm.hud._toast_label.text)
	await farm._on_buy("R", 3)
	await session.refresh()
	_ok(int(session.state.wallet) == wallet0 + 48 - 12, "买 3 颗萝卜种子 -12 → %d" % int(session.state.wallet))
	_ok(int(session.state.inventory.seeds.R.bought) == 3, "种子 bought=3")
	await get_tree().process_frame
	var done := DayGoals.done_count(DayGoals.evaluate(session.state, session.state.cells))
	_ok(done >= 6, "目标至少 6/7（实际 %d）" % done)
	_ok(str(farm.hud._cta.text) == "Sow 3 Radish", "CTA 回到 Sow 3 Radish（实际 %s）" % farm.hud._cta.text)

	DirAccess.remove_absolute(ApiClient.INSTALL_KEY_PATH)
	print("\n%s（%d 项失败）" % ["全部通过" if _fails == 0 else "有失败", _fails])
	get_tree().quit(0 if _fails == 0 else 1)
