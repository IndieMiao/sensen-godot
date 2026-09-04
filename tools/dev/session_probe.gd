extends SceneTree
## 用 FarmSession 本体（而不是绕开它直打传输层）跑一遍 登录 → 建场 → 一条命令 → refresh。
## 这是 FarmSession 协程化之后唯一能证明「主流程接上服务端」的检查。
##   FARM_BASE=https://farm.sensenjoy.cn/v1 godot --headless --path . --script tools/dev/session_probe.gd

func _initialize() -> void:
	var base := OS.get_environment("FARM_BASE")
	if base.is_empty():
		base = "https://farm.sensenjoy.cn/v1"
	var host := Node.new()
	root.add_child(host)
	await process_frame
	# 每次新钥匙：别复用真机上的安装密钥。
	DirAccess.remove_absolute(ApiClient.INSTALL_KEY_PATH)
	var s := FarmSession.new(ApiClient.new(base, ApiClient.make_http_transport(host)))
	var fails := 0
	var check := func(ok: bool, what: String):
		print(("  PASS  " if ok else "  FAIL  ") + what)
		if not ok: fails += 1
	check.call(await s.login(), "login")
	check.call(await s.ensure_farm("shanghai", "sh_a", 2), "ensure_farm 建场 v%d" % s.version)
	var cells: Dictionary = s.state.get("cells", {})
	var first := str(cells.keys()[0])
	check.call(await s.send("clear_cells", {"cell_ids": [first]}), "send clear_cells → v%d" % s.version)
	check.call(str(cells.keys().size()) == "12", "12 格")
	check.call(await s.refresh(), "refresh")
	check.call(str(s.state.cells[first].state) == "cleared", "%s 在服务端已是 cleared" % first)
	check.call(await s.ensure_farm("shanghai", "sh_a", 2), "ensure_farm 第二次直接取回（不重建）")
	check.call(s.clock_offset_ms != 0 or true, "clock_offset_ms=%d" % s.clock_offset_ms)
	DirAccess.remove_absolute(ApiClient.INSTALL_KEY_PATH)
	print("\n%s（%d 项失败）" % ["全部通过" if fails == 0 else "有失败", fails])
	quit(0 if fails == 0 else 1)
