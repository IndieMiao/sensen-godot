extends Node
## G0 UI 预览宿主，作为 tools/dev/ui_preview.tscn 的目标场景使用（它负责注入手机安全区）。
##
## mode = select：SafeArea → Root → SelectPanel，喂 regions.json 第一个城市的真实候选
##   （512×512 的 preview.png）。2026-09-04 真机截图里「卡片撑破面板、盖住 Create Farm」
##   只有喂真图才复现——单测用的 PlaceholderTexture2D(64×64) 恰好等于预览高度，测不出。
## mode = farm：farm.tscn + sh_a 蓝图，直接挂树、不经 AppRouter 压栈。
##
##   G0_SHOT=/tmp/g0/select.png G0_FRAMES=20 godot --path . --resolution 360x800 \
##         tools/dev/ui_preview.tscn -- res://tools/dev/g0_select_preview.tscn flat
##   G0_SHOT=/tmp/g0/farm.png G0_FRAMES=120 godot --path . --resolution 360x800 \
##         tools/dev/ui_preview.tscn -- res://tools/dev/g0_farm_preview.tscn notch
## 360×800 窗口在 stretch=canvas_items/expand 下就是 360×800 逻辑视口，与 vivo V2509A 一致；
## G0_SHOT 指定截图路径（截完自动退出），G0_FRAMES 是截图前等待的帧数（农场要等
## Avatar 异步装配落地，≥120）。

@export_enum("select", "farm", "home", "visit") var mode := "select"

const FARM_BLUEPRINT := "res://assets/blueprints/sh_a/r2/farm_blueprint.json"

func _ready() -> void:
	if mode == "farm":
		_farm()
	elif mode == "home":
		_home()
	elif mode == "visit":
		_visit()
	else:
		_select()
	var shot := OS.get_environment("G0_SHOT")
	if not shot.is_empty():
		_capture(shot, int(OS.get_environment("G0_FRAMES")) if OS.has_environment("G0_FRAMES") else 120)

## 自己截根视口的纹理再退出，不走 --write-movie：桌面窗口高度会被屏幕钳住，movie 帧
## 只截到视口中段（2026-09-04 实测 720×1600 请求下只拿到 720×1280 的中段裁切）。
## 用 --resolution 360x800 把窗口开在屏幕装得下的尺寸，视口逻辑尺寸即 360×800。
func _capture(path: String, frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("g0_preview: window=%s visible=%s shot=%s -> %s" % [
		DisplayServer.window_get_size(), get_viewport().get_visible_rect().size, img.get_size(), path])
	get_tree().quit()

func _select() -> void:
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(page)
	# 一层地图色的底，方便看清面板边缘（真机上这里是 Mapbox 底图）。
	var bg := ColorRect.new()
	bg.color = Color(0.93, 0.91, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(bg)
	var safe := SafeAreaMargin.new()
	safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(safe)
	var root := Control.new()
	root.name = "Root"
	safe.add_child(root)
	var panel := SelectPanel.new()
	root.add_child(panel)
	var regions := FarmRegions.load_default()
	var items: Array = []
	for c in regions.regions[0].candidates:
		var id := str(c.layout_patch_id)
		var path := "res://assets/blueprints/%s/r%d/preview.png" % [id, int(c.get("revision", 1))]
		items.append({"id": id, "name": str(c.name),
			"preview": load(path) if ResourceLoader.exists(path) else null})
	panel.set_candidates(items)
	panel.focus(items[0].id)

## 喂一个假会话：第 0 章开局 + 一畦已翻土、一格在长、一格熟了，HUD 才有内容可看。
func _farm() -> void:
	var bp := FarmBlueprint.load_file(FARM_BLUEPRINT)
	var cells := {}
	var beds := bp.beds()
	var now := int(Time.get_unix_time_from_system() * 1000)
	for b in beds.size():
		for i in 3:
			var c: Vector2i = beds[b].cells[i]
			var slot := {"state": "wild", "crop": null, "care_done_at": null, "ready_at": null}
			if b == 1:
				slot.state = "tilled"
			if b == 2 and i == 0:
				slot = {"state": "growing", "crop": "R", "care_done_at": 0, "ready_at": 1}
			if b == 2 and i == 1:
				slot = {"state": "growing", "crop": "L", "care_done_at": now - 90000, "ready_at": now + 180000}
			if OS.get_environment("G0_STATE") == "sow":
				slot = {"state": "tilled", "crop": null, "care_done_at": null, "ready_at": null} if b == 0 else {"state": "growing", "crop": "R" if b == 1 else "L", "care_done_at": now - 90000, "ready_at": now + 180000}
			cells["%d,%d" % [c.x, c.y]] = slot
	var s := FarmSession.new(ApiClient.new("https://example.test/v1", FakeTransport.new([]).callable()))
	s.client.token = "tok"
	s.farm_id = "preview"
	s.layout_patch_id = bp.layout_patch_id
	s.blueprint_revision = bp.revision
	s.state = {"cells": cells, "beds_unlocked": 3, "wallet": 180,
		"inventory": {"seeds": {"R": {"bought": 0, "bound": 6}, "L": {"bought": 0, "bound": 3},
			"C": {"bought": 0, "bound": 0}, "H": {"bought": 0, "bound": 0}}, "produce": {"R": 0, "L": 0, "C": 0, "H": 0}},
		"clock": {"chapter_index": 0, "field_condition": "sunny"},
		"xp": {"total": 0, "first_clear_cells": ["x"], "first_harvest_crops": []}, "stall": {"settled": 0}, "sales_facts": {}}
	var farm := (load("res://scenes/farm/farm.tscn") as PackedScene).instantiate()
	farm.setup({"blueprint": bp, "session": s})
	add_child(farm)
	await get_tree().process_frame
	match OS.get_environment("G0_PANEL"):
		"stall":
			s.state.inventory.produce = {"R": 6, "L": 3}
			farm._open_stall()
		"goals": farm.hud.show_modal(farm.hud._goals)
		"director": farm.hud.show_modal(farm.director)

## mode = home：已有农场后的地图常态——Nearby Farmers + My Farm。桌面无地图桥，底图是
## 「Map preview」占位；Net 尚未 boot 完成，所以条目来自随包样例（正好也验证兜底路径）。
func _home() -> void:
	FarmChoice.save("sh_a", 2)
	FarmRegions.save_choice("shanghai")
	var m := (load("res://scenes/map_poc/map_poc.tscn") as PackedScene).instantiate()
	add_child(m)
	await get_tree().process_frame
	if m.nearby_panel and m.nearby_panel.card_count() > 0:
		m.nearby_panel.focus(str(m.nearby_panel.cards()[0].get_meta("farm_id")))

## mode = visit：只读访客实例，喂随包的繁茂样例（sh_b）。
func _visit() -> void:
	var snap: Dictionary = PresetSnapshots.snapshot(PresetSnapshots.entries("shanghai")[0].farm_id)
	var bp := FarmBlueprint.load_file(FarmBlueprint.asset_path(str(snap.layout_patch_id), int(snap.blueprint_revision)))
	var farm := (load("res://scenes/farm/farm.tscn") as PackedScene).instantiate()
	farm.setup({"visitor": true, "snapshot": snap, "blueprint": bp})
	add_child(farm)
	await get_tree().create_timer(1.0).timeout
	farm._stamp()
