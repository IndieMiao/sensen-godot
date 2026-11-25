extends SceneTree
## Real preview scene UIs under a non-English locale; no native map, HTTP or farm rendering.
var checks := 0
var failures := 0
var labels := {
	"Retry": "重试", "San Francisco": "旧金山", "Back": "返回",
	"Back to map": "返回地图", "Preview in 3D": "三维预览",
	"Loading dynamic farm…": "加载农场", "Dynamic farm": "动态农场",
	"Loading preview…": "加载预览", "Art preview · Walk and explore": "探索预览",
	"This dynamic farm preview is not available.": "不可用",
	"This farm preview could not be opened.": "无法打开",
	"328 FRIDA KAHLO WAY": "测试地名翻译",
	"Make this my first home": "设为我的第一个家", "Enter my farm": "进入我的地",
	"Give up and choose again": "放弃并重选", "Claim": "认领", "Cancel": "取消", "Sign in": "登录",
	"Claim this parcel?": "认领确认", "You can only have one home.": "只能有一个家",
	"My home": "我的家园", "Sign out": "退出登录", "Not claimed": "未认领", "Sign out on this phone?": "退出确认",
	"Parcel": "地块", "Your home": "我的家", "Market": "市场", "Carpenter": "木匠",
	"Can't reach the server. You're still signed in.": "账号保留提示"
}

func _initialize() -> void:
	_run.call_deferred()

func verify(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", label)

func text_nodes(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	if node is Label or node is Button: found.append(node)
	for child in node.get_children(): found.append_array(text_nodes(child))
	return found

func _run() -> void:
	var previous := TranslationServer.get_locale()
	var translation := Translation.new()
	translation.locale = "zh_CN"
	for source in labels: translation.add_message(source, labels[source])
	TranslationServer.add_translation(translation)
	TranslationServer.set_locale("zh_CN")
	await process_frame
	var outside := Button.new(); outside.text = "Retry"; root.add_child(outside)
	verify(String(outside.atr(outside.text)) == "重试", "Chinese automatic translation is active outside preview scenes")
	var map_page = load("res://scenes/dynamic_farm/dynamic_farm_map.tscn").instantiate()
	root.add_child(map_page)
	for text in ["Retry", "San Francisco", "Preview in 3D", "Make this my first home", "Enter my farm", "Give up and choose again", "Claim", "Cancel", "Sign in", "Sign out"]:
		var nodes := text_nodes(map_page).filter(func(n: Node): return n is Button and n.text == text)
		verify(nodes.size() >= 1 and nodes.all(func(n: Node): return String(n.atr(n.text)) == text), "map button stays English: " + text)
	for prefix in ["Claim this parcel", "You can only have one home.", "Sign out on this phone?", "Can't reach the server."]:
		var lines := text_nodes(map_page).filter(func(n: Node): return n is Label and n.text.begins_with(prefix))
		verify(lines.size() == 1 and String(lines[0].atr(lines[0].text)) == lines[0].text, "map line stays English: " + prefix)
	# The glass keys draw their glyphs; Back and My home are named in their tooltips (C-106).
	for text in ["Back", "My home"]:
		var keys := text_nodes(map_page).filter(func(n: Node): return n is Button and n.tooltip_text == text)
		verify(keys.size() == 1 and String(keys[0].atr(keys[0].tooltip_text)) == text, "map key stays English: " + text)
	map_page._card_tag.text = "Parcel"; map_page._details.text = "Not claimed"
	for node in [map_page._card_tag.label(), map_page._details]:
		verify(String(node.atr(node.text)) == node.text, "parcel card line stays English: " + node.text)
	map_page._show_candidates([{"block_id": "p-1", "name": "328 FRIDA KAHLO WAY"}])
	var rows: Array = map_page._choices.get_children()
	verify(rows.size() == 1 and rows[0].text == "328 FRIDA KAHLO WAY" and String(rows[0].atr(rows[0].text)) == "328 FRIDA KAHLO WAY",
		"overlapping parcel address stays unchanged")
	var host = load("res://scenes/dynamic_farm/dynamic_farm_host.tscn").instantiate()
	root.add_child(host) # Invalid context intentionally displays the real retry/error UI.
	for node in text_nodes(host):
		if node is Label or node is Button:
			verify(String(node.atr(node.text)) == node.text, "host error/action stays English: " + node.text)
	var farm = load("res://scenes/dynamic_farm/dynamic_farm.tscn").instantiate()
	root.add_child(farm) # Builds real UI, then rejects missing payload before creating any geometry.
	for node in text_nodes(farm):
		verify(String(node.atr(node.text)) == node.text, "3D preview UI stays English: " + node.text)
	TranslationServer.set_locale("en")
	await process_frame
	TranslationServer.set_locale("zh_CN")
	await process_frame
	verify(text_nodes(map_page).filter(func(n: Node): return n is Button and n.text == "Retry").all(func(n: Node): return String(n.atr(n.text)) == "Retry"), "preview ignores later global locale changes")
	verify(String(outside.atr(outside.text)) == "重试", "preview does not disable global game translation")
	# C-142 (owner's C-101#91): no player-facing text carries "sensen".
	for page in [map_page, host, farm]:
		var named := text_nodes(page).filter(func(n: Node): return "sensen" in (n.text + n.tooltip_text).to_lower())
		verify(named.is_empty(), "no sensen in visible text: " + page.name)
	map_page.queue_free(); host.queue_free(); farm.queue_free(); outside.queue_free()
	await process_frame
	TranslationServer.remove_translation(translation)
	TranslationServer.set_locale(previous)
	print("DYNAMIC ENGLISH UI ", checks - failures, "/", checks)
	quit(1 if failures else 0)
