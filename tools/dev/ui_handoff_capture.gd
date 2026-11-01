extends "res://tools/dev/character_visual_probe.gd"
## Current production views, isolated presentation fixtures, no game-service writes.
const DIR := "user://ui-handoff"
var catalog: Array = []
var serial = 0
var group = ""
var model: FarmSession
var screen: Node
var android = false

class VoicePreview extends RefCounted:
	signal voice_event(raw: String)
	func capabilities() -> String: return '{"protocol":1,"supported":true}'
	func disconnect_voice(_id: String) -> void: pass

func _ready() -> void:
	android = OS.get_name() == "Android"
	Localization.select_language("zh_CN")
	get_tree().root.gui_embed_subwindows = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	Voice.set_process(false)
	Voice.set_backend(VoicePreview.new())
	group = str(ProjectSettings.get_setting("handoff/group", "all"))
	if FileAccess.file_exists(DIR.path_join("group.txt")): group = FileAccess.get_file_as_string(DIR.path_join("group.txt")).strip_edges()
	for file in ["done.json", "step.json", "ack.txt"]:
		if FileAccess.file_exists(DIR.path_join(file)): DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(file)))
	call_deferred("_atlas")

func fresh() -> FarmSession:
	var s = _inventory_session()
	s.player_id = "player01-demo"
	s.client.token = "ui-presentation-only"
	s.farm_id = "art-demo-farm"
	s.layout_patch_id = "sh_b"
	s.blueprint_revision = 2
	s.region_id = "shanghai"
	s.state.character = {"version": 1, "hp": 76, "buffs": []}
	s.state.journey.unlocks.append_array(["crafting", "growth", "route_woodland", "route_riverside", "route_gardens"])
	s.state.journey.workshop = {"sequence": 2, "stock": {"planter": 2, "lantern": 2, "crate": 2}, "displays": {}}
	s.state.journey.contributions = {}
	s.state.journey.gathering = {"sequence": 0, "planned": "", "current": ""}
	s.state.journey.opportunities = {"nursery": {"sequence": 0, "variant": 0, "accepted": false}, "bistro": {"sequence": 0, "variant": 2, "accepted": false}, "restorer": {"sequence": 0, "variant": 2, "accepted": false}}
	s.state.mine = {"version": 1, "run": 0, "floor": 0, "deepest_floor": 1, "cleared_floors": [], "broken": {}, "elevator_unlocked": false}
	var sword = {"id": "weapon-demo", "item_id": "rusty_sword", "quantity": 1, "quality": "normal", "instance_id": "weapon-instance"}
	s.state.bag.equipped.weapon = sword
	for id in ["copper_pickaxe", "foraging_gloves", "artisan_apron", "copper_sword", "trail_boots"]:
		if not ItemCatalog.definition(id).is_empty():
			s.state.bag.slots.append({"id": id+"-demo", "item_id": id, "quantity": 1, "quality": "normal", "instance_id": id+"-instance"})
	while s.state.bag.slots.size() > 24: s.state.bag.slots.remove_at(0)
	# Valid layout cells with four readable crop states.
	var bp = FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_b", 2))
	var cells: Array = []
	for bed in bp.beds():
		for cell in bed.cells: cells.append(FarmBlueprint._cs(cell))
	var order: Array = []
	for i in JourneyProgress.data().field_growth.order: order.append(cells[int(i)])
	s.state.field_progress = {"order": order, "plots": 9, "planted": 9, "harvested": 6}
	s.state.cells = {}
	for i in cells.size():
		s.state.cells[cells[i]] = {"state": "wild" if i % 4 == 0 else "tilled", "crop": null, "ready_at": null, "care_weather": null, "careful": false, "care_done_at": null}
	Net.session = s
	Net.online_available = false
	return s

func _atlas() -> void:
	model = fresh()
	if group == "supplement": await supplement_pages()
	if group == "corrections": await correction_pages()
	if group in ["all", "entry"]: await entry_pages()
	if group in ["all", "wardrobe"]: await wardrobe_pages()
	if group in ["all", "farm"]: await farm_pages()
	if group in ["all", "inventory"]: await inventory_pages()
	if group in ["all", "places"]: await place_pages()
	if group in ["all", "street"]: await street_pages()
	if group in ["all", "mine"]: await mine_pages()
	if group in ["all", "online"]: await online_pages()
	if group in ["all", "extra"]: await extra_pages()
	if group in ["all", "legacy"]: await legacy_pages()
	FileAccess.open(DIR.path_join("catalog.json"), FileAccess.WRITE).store_string(JSON.stringify(catalog, "\t"))
	FileAccess.open(DIR.path_join("done.json"), FileAccess.WRITE).store_string(JSON.stringify({"done": true, "screens": catalog.size(), "captures": serial}))
	print("UI_HANDOFF_DONE ", catalog.size(), " screens ", serial, " images")

func mount(node: Node) -> Node:
	screen = node
	add_child(node)
	await _settle(40)
	return node

func clear_screen() -> void:
	Voice._wanted = false
	Voice.state = "idle"
	Voice.microphone = false
	Voice.participants = []
	Voice.changed.emit()
	if is_instance_valid(screen):
		if screen.has_method("suspend"): screen.suspend()
		remove_child(screen)
		screen.queue_free()
		screen = null
	await _settle(5)

func rect_pixels(control: Control) -> Array:
	var r: Rect2 = get_viewport().get_screen_transform() * control.get_global_rect()
	return [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]

func snapshot(file: String, extra := {}) -> void:
	await _settle(5)
	serial += 1
	var payload = {"serial": serial, "file": file, "group": group}.merged(extra)
	if android:
		FileAccess.open(DIR.path_join("step.json"), FileAccess.WRITE).store_string(JSON.stringify(payload))
		var start = Time.get_ticks_msec()
		while true:
			if FileAccess.file_exists(DIR.path_join("ack.txt")) and FileAccess.get_file_as_string(DIR.path_join("ack.txt")).strip_edges() == str(serial): break
			if Time.get_ticks_msec() - start > 90000:
				push_error("Capture driver did not acknowledge " + file)
				get_tree().quit(3)
				return
			await get_tree().create_timer(0.1).timeout
	else:
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://output/ui-handoff-2026-09-16/raw/" + file))
	print("UI_HANDOFF_CAPTURE ", file)

func page(id: String, title: String, entry: String, description: String, root: Node, scrolls: Array = [], note := "") -> void:
	for sc in scrolls:
		sc.scroll_vertical = 0
		sc.scroll_horizontal = 0
	await _settle(7)
	var record = {"id": id, "title": title, "entry": entry, "description": description, "note": note,
		"source": root.scene_file_path if not root.scene_file_path.is_empty() else root.get_script().resource_path if root.get_script() else "", "image": id+".png", "scrolls": []}
	await snapshot(id+".png")
	for idx in scrolls.size():
		var sc: ScrollContainer = scrolls[idx]
		if not sc.is_visible_in_tree(): continue
		var vertical = sc.get_v_scroll_bar().max_value - sc.get_v_scroll_bar().page
		var horizontal = sc.get_h_scroll_bar().max_value - sc.get_h_scroll_bar().page
		for axis in ["vertical", "horizontal"]:
			var maximum = vertical if axis == "vertical" else horizontal
			if maximum <= 1: continue
			var extent = sc.get_v_scroll_bar().page if axis == "vertical" else sc.get_h_scroll_bar().page
			var proof = {"axis": axis, "rect": rect_pixels(sc), "max": maximum, "extent": extent, "parts": []}
			var offset = 0
			var segment = 0
			while true:
				if axis == "vertical": sc.scroll_vertical = offset
				else: sc.scroll_horizontal = offset
				await _settle(5)
				var actual = sc.scroll_vertical if axis == "vertical" else sc.scroll_horizontal
				var name = "%s-scroll%d-%s-%02d.png" % [id, idx, axis, segment]
				await snapshot(name, {"scroll": true})
				proof.parts.append({"file": name, "offset": actual})
				if actual >= maximum - 1: break
				offset = mini(roundi(maximum), actual + maxi(1, floori(extent * 0.72)))
				segment += 1
				if segment > 40: break
			if axis == "vertical": sc.scroll_vertical = 0
			else: sc.scroll_horizontal = 0
			record.scrolls.append(proof)
	catalog.append(record)
	FileAccess.open(DIR.path_join("catalog.json"), FileAccess.WRITE).store_string(JSON.stringify(catalog, "\t"))

func entry_pages() -> void:
	var city = await mount(load(AppRouter.CITY_SELECT).instantiate())
	await page("01-city", "选择城市", "首次进入", "选择上海或洛杉矶，也可请求定位；右上角可切换语言。", city)
	city.status.text = L10n.text("Location timed out — please choose a city manually")
	await page("02-city-location-failed", "定位失败提示", "选择城市 → 使用当前城市", "定位超时后保留手选城市入口。", city, [], "定位失败展示状态")
	city.status.text = ""
	var language: LanguageButton = city.find_child("LanguageButton", true, false)
	language.get_popup().popup(Rect2i(Vector2i(225, 65), Vector2i(110, 100)))
	await page("03-language", "语言菜单", "城市页或地图 → 语言", "简体中文和英语切换。系统菜单样式与页面按钮需要一起考虑。", city)
	language.get_popup().hide()
	await clear_screen()
	FarmRegions.save_choice("shanghai")
	FarmChoice.save("sh_b", 2)
	model = fresh()
	var map_scene = await mount(load(AppRouter.MAP).instantiate())
	await get_tree().create_timer(4).timeout
	await page("04-map", "世界地图", "选择城市后 / 底部地图", "真实地图上显示自己的角色、附近农场；底部进入街区、回农场和换装。", map_scene)
	map_scene._set_nearby_open(true)
	await _settle(10)
	var nearby = map_scene.nearby_panel
	var near_scrolls: Array = nearby.find_children("*", "ScrollContainer", true, false)
	await page("05-nearby", "附近玩家与农场列表", "地图 → 附近列表", "展示附近农场条目，选择条目后定位对应玩家与农场模型。", map_scene, near_scrolls)
	if not nearby.entries.is_empty():
		nearby.focus(str(nearby.entries[0].farm_id))
		await get_tree().create_timer(0.8).timeout
		await page("06-map-farm-selected", "地图选中农场", "附近列表 → 选择农场", "选中角色旁显示农场微缩模型和拜访入口。", map_scene)
	await clear_screen()
	FarmChoice.save("sh_b", 2)
	var loading = await mount(load("res://modules/ui/loading_overlay.gd").new())
	await page("08-loading", "场景加载", "打开街区、农场、换装等场景", "场景资源加载时的遮罩和进度反馈。", loading)
	loading.failed()
	await page("09-loading-failed", "场景加载失败", "加载异常", "错误提示与关闭/返回操作。", loading)
	await clear_screen()

func wardrobe_pages() -> void:
	model = fresh()
	var dress = await mount(load(AppRouter.DRESS).instantiate())
	for slot in dress.parts_panel.visible_slot_names():
		dress.parts_panel._show_slot(slot, true)
		await _settle(90)
		var title = L10n.text(str(dress.parts_panel.SLOT_LABELS.get(slot, "Other")))
		await page("10-wardrobe-"+str(slot), "换装 · "+title, "地图 → 换装 → "+title, "上方角色预览支持拖动旋转，点击切换全身/局部；下方选择部件，顶部还原或完成保存。", dress, [dress.parts_panel.get_node("PartsScroll"), dress.parts_panel.get_node("TabsScroll")])
	dress._show_feedback(L10n.text("Saving..."))
	await page("11-wardrobe-feedback", "换装保存反馈", "换装 → 完成", "保存/失败等状态使用下方反馈区；部件加载过程中完成按钮会锁定。", dress)
	await clear_screen()

func new_farm() -> Node:
	model = fresh()
	var farm = load(AppRouter.FARM).instantiate()
	farm.setup({"blueprint": FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_b", 2)), "session": model})
	return await mount(farm)

func farm_pages() -> void:
	var farm = await new_farm()
	await page("20-farm", "我的农场", "地图 / 街区 → 我的农场", "农田与角色为主视图；包含选地操作、种子栏、背包、摊位、矿洞和在线状态。", farm)
	farm._open_stall()
	await _settle(8)
	await page("21-stall", "摊位 · 种子购买与出售", "农场 → 摊位", "购买各类种子、出售农作物或料理，并显示持有数量与每日结算额度。", farm, farm.hud.find_children("*", "ScrollContainer", true, false))
	farm.hud.close_modal()
	farm._open_life()
	await _settle(6)
	await page("22-farm-bag", "农场内背包底部面板", "农场 → 背包", "与其他场景共用背包、角色、委托功能；这里记录农场内的底部面板结构。", farm, farm.hud.find_children("*", "ScrollContainer", true, false))
	farm.hud.close_modal()
	farm.hud.show_toast(L10n.text("Health restored"))
	await page("23-farm-toast", "农场操作反馈", "收获、恢复体力等操作后", "短时消息反馈叠加于场景，不离开当前农场。", farm, [], "使用恢复体力文案展示反馈容器")
	await clear_screen()

func inventory_pages() -> void:
	var farm = await new_farm()
	var layer = CanvasLayer.new()
	layer.layer = 40
	farm.add_child(layer)
	var sheet = BagSheet.new()
	sheet.setup(model)
	layer.add_child(sheet)
	await _settle(8)
	sheet.open()
	await page("30-bag", "背包物品网格", "街区 / 地点 / 矿井 → 背包", "24 格容量、分类、搜索、排序、已装备工具和溢出入口；点击物品查看详情。", sheet, [sheet.active.body_scroll])
	for cat in ["all", "seed", "equipment"]:
		if cat not in ItemCatalog.CATEGORIES: continue
		sheet.active.category = cat
		sheet.active.query = "铜" if cat == "all" else ""
		sheet.active.search.text = sheet.active.query
		sheet.active.refresh()
		await _settle(5)
		await page("31-bag-filter-"+cat, "背包筛选 · "+("搜索铜" if cat == "all" else ItemCatalog.category_name(cat)), "背包 → 分类 / 搜索", "筛选保留原页面结构，并更新匹配的物品网格。", sheet, [sheet.active.body_scroll])
	sheet.active.category = "all"
	sheet.active.query = ""
	sheet.active.search.text = ""
	for item in ["copper_ore", "vegetable_soup", "crate", "copper_pickaxe", "foraging_gloves", "copper_sword", "trail_boots"]:
		var entries: Array = model.state.bag.slots.filter(func(e): return e.item_id == item)
		if entries.is_empty(): continue
		sheet.active.select_stack(str(entries[0].id))
		await _settle(7)
		await page("32-item-"+item, "物品详情 · "+ItemCatalog.name_of(item), "背包 → 点击物品", "物品图标、说明、数量及使用/装备/放置入口；装备页展示属性比较。", sheet, [sheet.active.body_scroll])
		if item == "copper_ore":
			for action in [["split", "拆分数量"], ["merge", "合并堆叠"], ["discard", "丢弃确认"]]:
				sheet.active._set_mode(action[0])
				await _settle(5)
				await page("33-item-"+action[0], "物品管理 · "+action[1], "物品详情 → "+action[1], "数量输入和确认操作；丢弃页有不可恢复提示。", sheet, [sheet.active.body_scroll])
	sheet.active.select_page("bag")
	sheet.active.showing_overflow = true
	sheet.active.refresh()
	await _settle(5)
	await page("34-bag-overflow", "背包溢出暂存", "背包 → 溢出物品", "背包满时获得的物品暂存于此，可在腾出空间后领取。", sheet, [sheet.active.body_scroll])
	sheet.active.showing_overflow = false
	sheet.active.select_page("character")
	model.state.character.buffs = [{"id": "soup_mining", "source_item_id": "vegetable_soup", "remaining_uses": 2}]
	sheet.active.refresh()
	await _settle(6)
	await page("35-character", "角色属性与装备", "背包 → 角色", "显示生命、基础/装备/料理加成、工具/武器/饰品槽和正在生效的料理；长页需看完整图。", sheet, [sheet.active.body_scroll])
	for slot in ["tool", "weapon", "accessory"]:
		sheet.active._choose_equipment(slot)
		await _settle(5)
		await page("36-equipment-"+slot, "更换装备 · "+L10n.text({"tool":"Tool slot","weapon":"Weapon slot","accessory":"Accessory slot"}[slot]), "角色 → 装备槽右侧更换", "选择背包中适用的装备，并查看当前装备。", sheet, [sheet.active.body_scroll])
	sheet.active.select_page("requests")
	await _settle(5)
	await page("37-requests-available", "委托列表 · 可接取", "背包 → 委托", "三位居民的委托、材料需求、奖励、详情、接取与刷新入口。", sheet, [sheet.active.body_scroll])
	for slot in JourneyRequests.SLOTS: model.state.journey.opportunities[slot].accepted = true
	model.state.journey.tracked_opportunity = {"slot": "restorer", "sequence": 0}
	sheet.active.refresh()
	await _settle(5)
	await page("38-requests-active", "委托列表 · 已接取与追踪", "接受委托后", "显示材料满足情况、前往目标、追踪/取消追踪、放弃和更换。", sheet, [sheet.active.body_scroll])
	for slot in JourneyRequests.SLOTS:
		sheet.active._show_request_details(slot)
		await _settle(5)
		await page("39-request-"+slot, "委托详情 · "+L10n.text(str(ResidentCast.definition(StreetCommons.RESIDENTS[slot]).name)), "委托列表 → 详情", "详细需求、当前持有数、奖励与前往交付入口。", sheet, [sheet.active.body_scroll])
	for op in ["abandon_opportunity", "decline_opportunity"]:
		sheet.active._confirm_request(op, "restorer")
		await _settle(5)
		await page("40-request-"+op, "委托"+("放弃" if op == "abandon_opportunity" else "更换")+"确认", "委托 → 放弃 / 更换", "确认改变当前委托，说明背包物品会保留。", sheet, [sheet.active.body_scroll])
	sheet.active.select_page("bag")
	model.offline = true
	sheet.active.refresh()
	await _settle(5)
	await page("41-bag-offline", "背包离线状态", "网络中断时打开背包", "保留可读库存，禁用需要服务器确认的操作并提供重连。", sheet, [sheet.active.body_scroll], "离线展示状态")
	await clear_screen()

func place_pages() -> void:
	var specs = {
		"nursery": [["resident", "花匠对话与委托"], ["board", "探索路线"], ["trail", "林间小径"], ["workbench", "工作台制作与装备配方"], ["path", "花园侧路"], ["project_seedbeds", "苗圃花床建设"], ["discovery_stone_hollow", "石间空地探索"]],
		"bistro": [["resident", "店主对话与委托"], ["counter", "厨房料理配方"], ["table", "餐桌分享"], ["trail", "菜园与石材路线"], ["project_terrace", "露台建设"], ["discovery_kitchen_garden", "厨房菜园探索"]],
		"courtyard": [["resident", "修复师对话与委托"], ["planter", "庭院摆件入口"], ["trail", "河畔小径"], ["project_waystation", "街角驿站建设"], ["discovery_reed_garden", "芦苇花园探索"]]}
	for place_id in specs:
		model = fresh()
		var place = JourneyPlace.new()
		place.place_id = place_id
		place.session = model
		await mount(place)
		var place_title = L10n.text(str(PlaceCatalog.find(place_id).name))
		await page("50-place-"+place_id, place_title+" · 场景总览", "街区 → "+place_title, "可步行的地点场景：居民、资源、功能设施及底部导航。", place)
		for spec in specs[place_id]:
			place._show_panel(spec[0])
			await _settle(8)
			await page("51-"+place_id+"-"+spec[0], place_title+" · "+spec[1], place_title+" → 对应角色或设施", "场景内弹出的操作面板；包含说明、需求与按钮，长列表已补齐完整内容。", place, [place.panel_scroll])
			if spec[0] == "resident":
				place.active_panel._requests_expanded = true
				place.active_panel.refresh()
				await _settle(6)
				await page("52-"+place_id+"-request-expanded", place_title+" · 展开居民委托", "居民对话 → 查看委托", "展开委托细节后显示需要的物品、奖励与接取/交付入口。", place, [place.panel_scroll])
		if place_id == "courtyard":
			place._arrange()
			place.panel.show()
			await _settle(8)
			await page("53-decoration", "庭院摆件编辑", "庭院 → 摆件 → 布置", "选择摆件，在场景中移动/旋转；可撤销、保存或取消。", place, [place.panel_scroll])
			place.active_panel.dirty = true
			place.active_panel.request_leave()
			await _settle(6)
			await page("54-decoration-confirm", "摆件未保存离开确认", "修改摆件 → 返回", "保留编辑、放弃或保存后离开的分支。", place, [place.panel_scroll])
		await clear_screen()

func street_pages() -> void:
	model = fresh()
	model.state.journey.facts.append_array(JourneyProgress.data().gatherings.requires)
	var street = JourneyStreet.new()
	street.setup({"session": model})
	await mount(street)
	await page("60-street", "街区步行主界面", "地图 → 街区 / 地点 → 返回街区", "角色在街道中行走，连接农场、苗圃、小馆、庭院；展示居民、目标和在线状态。", street)
	for slot in StreetCommons.RESIDENTS:
		if not street.residents.moments.has(slot): continue
		street._show_dialogue(slot)
		await _settle(6)
		await page("61-street-resident-"+slot, "街头居民 · "+L10n.text(str(ResidentCast.definition(StreetCommons.RESIDENTS[slot]).name)), "街区 → 点击居民", "街头对话、关系状态与委托入口，共用地点居民交互内容。", street, [street.dialogue_scroll])
		street._close_dialogue()
	for theme in JourneyGatherings.themes():
		street._show_gathering(theme)
		await _settle(6)
		await page("62-gathering-"+theme, "邻里聚会 · "+L10n.text(str(JourneyGatherings.themes()[theme].name)), "街区 → 聚会设施", "查看手作摆件、料理需求，准备聚会或前往其他聚会地点。", street, [street.dialogue_scroll])
		model.state.journey.gathering.planned = theme
		street.active_panel.refresh()
		await _settle(6)
		await page("63-gathering-ready-"+theme, "聚会筹备 · "+L10n.text(str(JourneyGatherings.themes()[theme].name)), "聚会 → 开始筹备", "筹备状态显示下一步行动、开席与取消筹备入口。", street, [street.dialogue_scroll])
		model.state.journey.gathering.planned = ""
		street._close_dialogue()
	street.confirmation.ask(L10n.text("My farm"))
	await page("64-entry-confirmation", "进入地点确认", "街区走到入口", "确认进入目标地点，或留在当前街道。", street)
	street.confirmation.dismiss(false)
	await clear_screen()
	var visitor = PresetSnapshots.snapshot("demo_sh_01")
	# Visitor scenes use the same production snapshot shape, populated from an isolated local farm.
	if visitor.is_empty(): visitor = {"farm_id":"art-neighbour", "layout_patch_id":"sh_b", "blueprint_revision":2, "region_id":"shanghai", "state":model.state, "owner_name":"邻居", "avatar_ref":"demo_sh_01"}
	var farm = load(AppRouter.FARM).instantiate()
	farm.setup({"visitor": true, "snapshot": visitor, "blueprint": FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_b", 2))})
	await mount(farm)
	await page("65-visitor-farm", "拜访他人农场", "地图选择农场 → 拜访", "访客视角显示农场与角色；操作权限与自己的农场不同。", farm)
	await clear_screen()

func mine_pages() -> void:
	var layout = preload("res://modules/mining/mine_layout.gd")
	for level in ([2] if group == "supplement" else [1, 3, 4, 5]):
		model = fresh()
		model.state.mine.floor = level
		model.state.mine.deepest_floor = level
		var mine = load(AppRouter.ONLINE_MINE).instantiate()
		mine.setup({"session": model})
		await mount(mine)
		mine.online.stop()
		mine.online.set_process(false)
		var bp: FarmBlueprint = layout.navigation(level, [], 0, "art-demo")
		var rocks: Array = []
		for rock in layout.rocks(level, 0, "art-demo"): rocks.append({"id":rock.id,"position":[rock.position.x,rock.position.z]})
		mine.online.world = {"run": 0, "floors": {str(level):{"broken":[],"hp":[]}}, "cleared":[],"elevator":false,
			"rocks":rocks,"navigation":{"cell":bp.cell_m,"rows":bp.masks.walkable,"spawn":[layout.SPAWN.x,layout.SPAWN.z]}}
		mine.online.floor_number = level
		mine.online.room = "mine:demo01"
		mine.online.joined = true
		mine.online.count = 3
		mine.online.self_state = {"hp": 76, "max_hp":100}
		mine.online._update_badge()
		mine._refresh()
		var enemies: Array = []
		for enemy_id in mine.combat.enemies:
			var row: Dictionary = mine.combat.enemies[enemy_id]
			enemies.append({"id":enemy_id,"phase":"idle","x":row.node.position.x,"z":row.node.position.z,"hp":row.hp})
		mine.combat.apply_monsters(enemies)
		mine.set_process(false)
		await _settle(10)
		await page("70-mine-floor-"+str(level), "多人矿井 · 第"+str(level)+"层", "农场矿洞 → 矿层", "共享矿井中的生命、怪物/矿石、摇杆、攻击、上下层、电梯及队伍入口。", mine)
		if level == 1:
			mine.online.world.elevator = true
			mine.online.world.cleared = [1,2,3,4,5]
			mine._refresh()
			await page("71-mine-elevator", "矿井电梯已解锁", "通关第五层后返回矿井", "永久电梯与楼层操作入口的完成态。", mine)
		if level == 3:
			mine.pause_button.set_pressed(true)
			await page("72-mine-paused", "矿井暂停移动", "矿井 → 暂停按钮", "暂停本地角色操作；多人矿井世界继续运行。", mine)
		await clear_screen()
	if group == "supplement": return
	var farm = await new_farm()
	farm.show_mine_rescue()
	await _settle(10)
	await page("73-mine-rescue", "战败获救与角色恢复", "矿井生命归零 → 返回农场", "自动返回农场并打开角色页，说明资源保留，可休息恢复生命。", farm, farm.hud.find_children("*", "ScrollContainer", true, false), "战败后展示状态")
	await clear_screen()

func online_pages() -> void:
	var farm = await new_farm()
	var online: OnlineSpace = farm.online
	online.set_process(false)
	var directory = {"protocol":1,"travel_version":1,"voice":{"available":true,"capacity":8},"capacity":300,"party":null,"farm_access":false,"roster":[]}
	model.client = ApiClient.new("https://presentation.invalid/v1", func(_m,_p,_h,_b): return ApiClient.Response.new(true,200,directory))
	model.client.token = "ui-presentation-only"
	online.directory = directory
	await online._open_party()
	await page("80-party-empty", "队伍面板 · 未组队", "农场/街区/矿井 → 在线按钮", "创建队伍或输入邀请码加入；另有矿井重置、线路切换和重连入口。", online, [online.panel.find_child("PartyScroll", true, false)])
	directory.party = {"id":"art-party","code":"ART126DEMO","leader":model.player_id,"members":[model.player_id,"player02-demo","player03-demo"]}
	for id in directory.party.members:
		directory.roster.append({"player":id,"online":true,"can_visit_farm":id=="player02-demo","scene":{"kind":"street","region_id":"shanghai","layout_patch_id":"sh_b","blueprint_revision":2,"channel":1}})
	online._selected_member = "player02-demo"
	online._draw_party()
	await page("81-party-leader", "队伍面板 · 队长", "创建队伍后", "邀请码、成员选择、前往队友/农场、开放访问、转让队长、移出成员与解散。", online, [online.panel.find_child("PartyScroll", true, false)])
	directory.party.leader = "player02-demo"
	online._draw_party()
	await page("82-party-member", "队伍面板 · 队员", "加入他人队伍后", "前往队长或成员，申请访问农场；队员可退出队伍，无队长管理按钮。", online, [online.panel.find_child("PartyScroll", true, false)])
	Voice._wanted = true
	Voice.state = "connected"
	Voice.microphone = false
	Voice.participants = [{"id":model.player_id,"name":"player01","speaking":false,"local":true},{"id":"player02-demo","name":"player02","speaking":true},{"id":"player03-demo","name":"player03","speaking":false}]
	Voice.changed.emit()
	await page("83-voice-connected", "队伍语音 · 连接与讲话", "队伍 → 加入语音", "显示语音人数、退出、麦克风、收听和正在讲话成员；初次加入默认静音。", online, [online.panel.find_child("PartyScroll", true, false)], "使用展示成员驱动真实 UI，未发起录音或通话")
	Voice.microphone = true
	Voice.listening = false
	Voice.changed.emit()
	await page("84-voice-mic", "队伍语音 · 开麦与关闭收听", "语音中 → 麦克风 / 收听开关", "麦克风与收听可独立控制，按钮文案随状态改变。", online, [online.panel.find_child("PartyScroll", true, false)], "展示状态")
	Voice.state = "reconnecting"
	Voice.error = "VOICE_FULL"
	Voice.changed.emit()
	await page("85-voice-error", "队伍语音 · 容量或连接异常", "加入失败 / 连接异常", "语音状态区提示容量或重连问题，保持退出入口。", online, [online.panel.find_child("PartyScroll", true, false)], "错误展示状态")
	Voice.error = ""
	Voice._wanted = false
	Voice.state = "idle"
	Voice.changed.emit()
	for item in [["reset", "Reset mine", "Reset all mine progress and unclaimed resources? Everyone must be outside."], ["travel", "Join leader's mine", "Use the leader's mine progress? Your previous mine entry will be replaced."]]:
		var confirmation = ConfirmationDialog.new()
		confirmation.title = L10n.text(item[1])
		confirmation.dialog_text = L10n.text(item[2])
		online.add_child(confirmation)
		online._show_confirmation(confirmation)
		await page("86-online-confirm-"+item[0], "联机确认 · "+L10n.text(item[1]), "队伍 → 对应操作", "影响矿井绑定或进度的二次确认；包含确认和取消。", online)
		confirmation.hide()
		confirmation.queue_free()
	online._copy_invite_code("ART126DEMO")
	await page("87-copy-toast", "邀请码复制提示", "队伍 → 点击邀请码", "顶部短时浮层确认已复制，随后自动消失。", online)
	await clear_screen()
	if android and Engine.has_singleton("GodotVoice"):
		var city = await mount(load(AppRouter.CITY_SELECT).instantiate())
		Engine.get_singleton("GodotVoice").request_permission("art-capture")
		await get_tree().create_timer(1).timeout
		await snapshot("88-system-microphone.png", {"dismiss_permission":true})
		catalog.append({"id":"88-system-microphone","title":"Android 麦克风授权","entry":"首次加入语音","description":"Android 系统授权弹窗，解释麦克风访问；弹窗本身由系统绘制。","note":"系统界面，仅供流程衔接参考；截图后拒绝授权，未录音。","image":"88-system-microphone.png","scrolls":[],"source":"Android system"})
		await clear_screen()

func legacy_pages() -> void:
	# Retained older profile UI lives behind non-journey saves; separate from current main flow.
	for place_id in ["nursery", "bistro", "courtyard"]:
		model = fresh()
		model.state.erase("journey")
		var place = load(AppRouter.PLACE).instantiate()
		place.setup({"place_id":place_id,"session":model})
		await mount(place)
		for tab in place._tab_buttons:
			place.select_tab(tab)
			await _settle(7)
			await page("90-legacy-"+place_id+"-"+str(tab).validate_filename(), "保留界面 · "+L10n.text(str(PlaceCatalog.find(place_id).name))+" / "+str(tab), "旧存档的地点页", "旧版本保留的分栏界面，单列为附录供组件核对。", place, [place.scroll], "兼容旧存档的保留界面；不代表当前新玩家的主流程")
		await clear_screen()
	var farm = await new_farm()
	var director: DirectorPanel = farm.get("director")
	if director:
		director.show()
		director.fit_height(farm.hud.get_viewport().get_visible_rect().size)
		await page("91-debug-director", "内部工具 · 导演面板", "内部 QA 入口", "时间倍率、跳日和天气调试工具。", farm, [], "内部调试附录，不作为普通玩家 UI 设计范围")
	await clear_screen()

func extra_pages() -> void:
	var farm = await new_farm()
	var cells: Dictionary = model.state.cells
	var order: Array = model.state.field_progress.order
	for i in mini(9, order.size()):
		cells[order[i]] = {"state":"growing" if i<6 else "sown", "crop":["R","L","C","H"][i%4], "care_weather":"sunny", "care_done_at":model.server_now()-5000, "ready_at":model.server_now() + (90000 if i%2==0 else -1000)}
	farm.predictor.commit(farm.interior.local_cells(cells), model.version)
	farm._render()
	farm._refresh_hud()
	await _settle(12)
	await page("24-farm-crops", "农场作物与收获状态", "播种、照料和生长后", "展示多种作物模型、生长/待照料/可收获状态，以及对应的底部行动提示。", farm)
	farm.hud.set_offline(true)
	await page("25-farm-offline", "农场网络中断提示", "网络中断", "场景保留，顶部展示离线/重连提示。", farm, [], "离线提示展示状态")
	farm.hud.set_offline(false)
	var layer = CanvasLayer.new()
	layer.layer = 40
	farm.add_child(layer)
	var sheet = BagSheet.new()
	sheet.setup(model)
	layer.add_child(sheet)
	await _settle(5)
	sheet.open()
	sheet.active.category_filter.get_popup().popup(Rect2i(Vector2i(25,210),Vector2i(250,240)))
	await page("42-bag-category-menu", "背包分类菜单", "背包 → 分类下拉", "全部、种子、农产品、料理、材料、手作和装备等分类入口。", sheet)
	sheet.active.category_filter.get_popup().hide()
	sheet.active._sort.get_popup().popup(Rect2i(Vector2i(150,180),Vector2i(170,100)))
	await page("43-bag-sort-menu", "背包排序菜单", "背包 → 排序", "按类别或名称整理物品。", sheet)
	sheet.active._sort.get_popup().hide()
	model.state.bag.slots[0] = {"id":"seed-demo","item_id":"seed_R","quantity":5,"quality":"normal","seed_lot":"bound"}
	sheet.active.select_stack("seed-demo")
	await _settle(5)
	await page("44-seed-details", "种子详情", "背包 → 种子", "种子说明、数量与播种入口，包含绑定种子管理规则的提示。", sheet, [sheet.active.body_scroll])
	model.state.journey.opportunities.nursery = {"sequence":1,"variant":1,"accepted":false,"last_completed":{"offer_id":"fresh_nursery_leaves","resident_id":"nursery_keeper","sequence":0,"consumed":{"L":2},"coins":18,"effect":"leaves","contribution":1}}
	sheet.active.select_page("requests")
	sheet.active._show_request_history("nursery")
	await _settle(5)
	await page("45-request-history", "委托交付回顾", "委托 → 上次交付", "查看已交付材料、获得金币和居民回复。", sheet, [sheet.active.body_scroll])
	sheet.active.select_page("bag")
	model.state.bag.slots = []
	model.state.bag.overflow = []
	sheet.active.refresh()
	await _settle(5)
	await page("46-bag-empty", "背包空状态", "新账号或清空背包后", "保留容量与筛选结构，网格显示空槽及空状态提示。", sheet, [sheet.active.body_scroll])
	await clear_screen()
	for pair in [["nursery","seedbeds"],["bistro","terrace"],["courtyard","waystation"]]:
		model = fresh()
		model.state.journey.facts.append_array(JourneyProgress.data().gatherings.requires)
		var place = JourneyPlace.new()
		place.place_id = pair[0]
		place.session = model
		await mount(place)
		place._show_panel("project_"+pair[1])
		await _settle(5)
		await page("55-facility-"+pair[1], "建成设施 · "+L10n.text(str(JourneyProgress.data().projects[pair[1]].name)), "建设完成后 → 点击设施", "建设完成后的持续使用、资源兑换或料理服务入口。", place, [place.panel_scroll], "已完成建设的展示状态")
		place._show_panel("display:"+pair[1]+":0")
		await _settle(5)
		await page("56-display-"+pair[1], "手作陈列 · "+L10n.text(str(PlaceCatalog.find(pair[0]).name)), "建成设施 → 陈列位置", "从持有手作中选择陈列物，或制定制作计划。", place, [place.panel_scroll])
		await clear_screen()

func supplement_pages() -> void:
	FarmChoice.save("sh_b",2)
	model = fresh()
	var dress = await mount(load(AppRouter.DRESS).instantiate())
	await _settle(90)
	await page("10a-wardrobe-full", "换装主界面 · 全身预览", "地图 → 换装", "进入时以全身视角展示当前装扮；切换分类后可聚焦相应部位。", dress)
	await clear_screen()
	model = fresh()
	model.state.journey.facts.append_array(JourneyProgress.data().gatherings.requires)
	model.state.journey.gathering.current = "garden"
	var street = JourneyStreet.new()
	street.setup({"session":model})
	await mount(street)
	street._show_gathering("garden")
	await _settle(8)
	await page("63b-gathering-active", "聚会进行中", "完成聚会筹备并开席", "邻居聚集后的状态，可继续准备一餐、收回手作或前往另一聚会。", street, [street.dialogue_scroll])
	await clear_screen()
	model = fresh()
	model.state.journey.facts.append_array(JourneyProgress.data().gatherings.requires)
	model.state.journey.workshop.displays.seedbeds = ["lantern","",""]
	var place = JourneyPlace.new()
	place.place_id = "nursery"
	place.session = model
	await mount(place)
	place._show_panel("display:seedbeds:0")
	await _settle(6)
	await page("56b-display-occupied", "手作陈列 · 已摆放", "陈列位置 → 已有手作", "查看当前陈列物，收回背包或替换为其他手作。", place, [place.panel_scroll])
	model.state.bag.slots = model.state.bag.slots.filter(func(e): return ItemCatalog.definition(str(e.item_id)).category != "equipment")
	model.state.journey.workshop.stock = {}
	place._show_panel("workbench")
	await _settle(6)
	await page("51b-workbench-craftable", "工作台 · 未持有装备与手作", "苗圃 → 工作台", "与已拥有状态对照，显示制作材料和可制作/材料不足的按钮状态。", place, [place.panel_scroll])
	await clear_screen()
	var farm = await new_farm()
	Voice._wanted = true
	Voice.state = "connected"
	Voice.microphone = true
	Voice.changed.emit()
	await page("89-voice-badge", "场景中的语音状态入口", "加入语音后关闭队伍面板", "场景右侧保留麦克风状态入口，点按可重新打开队伍语音控制。", farm, [], "语音展示状态，未开启录音")
	await clear_screen()
	model = fresh()
	model.state.erase("journey")
	place = load(AppRouter.PLACE).instantiate()
	place.setup({"place_id":"nursery","session":model})
	await mount(place)
	place.select_tab("events")
	await _settle(5)
	place.active_panel.open_event(str(place.active_panel._data.events[0].id))
	await _settle(5)
	await page("92-legacy-story", "保留界面 · 邻里故事详情", "旧存档地点 → 邻里故事 → 条目", "章节故事说明、进度与参与入口。", place, [place.scroll], "旧存档兼容界面")
	place._open_photo({"photo_variant":"personal","life_priority":true})
	await _settle(90)
	await page("93-legacy-photo", "保留界面 · 邻里合照", "旧存档周结算 → 合照", "玩家与三位居民的合照预览，提供返回和保存照片按钮。", place, [], "旧存档兼容界面；本次不保存至相册")
	await clear_screen()
	model = fresh()
	model.state.erase("journey")
	farm = load(AppRouter.FARM).instantiate()
	farm.setup({"blueprint":FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_b",2)),"session":model})
	await mount(farm)
	farm.hud.show_modal(farm.hud._goals)
	await _settle(5)
	await page("94-legacy-goals", "保留界面 · 章节目标", "旧存档农场 → 目标", "章节目标列表、完成进度与阶段反馈。", farm, farm.hud.find_children("*","ScrollContainer",true,false), "旧存档兼容界面")
	await clear_screen()

	await mine_pages()

func correction_pages() -> void:
	var farm = await new_farm()
	model.offline = true
	farm._refresh_hud()
	await _settle(10)
	await page("25-farm-offline", "农场网络中断提示", "网络中断", "场景保留，显示离线状态、重连入口并禁用需要网络确认的操作。", farm, [], "离线展示状态")
	model.offline = false
	farm._refresh_hud()
	var layer = CanvasLayer.new()
	layer.layer = 40
	farm.add_child(layer)
	var sheet = BagSheet.new()
	sheet.setup(model)
	layer.add_child(sheet)
	await _settle(5)
	sheet.open()
	sheet.active.category_filter.select(ItemCatalog.CATEGORIES.find("equipment"))
	sheet.active.category_filter.item_selected.emit(ItemCatalog.CATEGORIES.find("equipment"))
	await _settle(5)
	await page("31-bag-filter-equipment", "背包筛选 · 装备", "背包 → 分类 → 装备", "分类菜单选中装备，网格只显示匹配的工具、武器和配件。", sheet, [sheet.active.body_scroll])
	await clear_screen()
