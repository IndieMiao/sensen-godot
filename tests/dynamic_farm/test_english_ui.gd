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
	"Give up and choose again": "放弃并重选", "Claim": "认领", "Cancel": "取消",
	"Claim this parcel? You can only have one home.": "认领确认"
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
	for text in ["Retry", "San Francisco", "Back", "Preview in 3D", "Make this my first home", "Enter my farm", "Give up and choose again", "Claim", "Cancel"]:
		var nodes := text_nodes(map_page).filter(func(n: Node): return n is Button and n.text == text)
		verify(nodes.size() == 1 and String(nodes[0].atr(nodes[0].text)) == text, "map button stays English: " + text)
	var confirm := text_nodes(map_page).filter(func(n: Node): return n is Label and n.text.begins_with("Claim this parcel"))
	verify(confirm.size() == 1 and String(confirm[0].atr(confirm[0].text)) == confirm[0].text, "claim confirmation stays English")
	map_page._choices.add_item("328 FRIDA KAHLO WAY")
	map_page._choices.select(0)
	var popup: PopupMenu = map_page._choices.get_popup()
	verify(String(map_page._choices.atr(map_page._choices.text)) == "328 FRIDA KAHLO WAY", "selected parcel address stays unchanged")
	verify(String(popup.atr(popup.get_item_text(0))) == "328 FRIDA KAHLO WAY", "parcel popup address stays unchanged")
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
	map_page.queue_free(); host.queue_free(); farm.queue_free(); outside.queue_free()
	await process_frame
	TranslationServer.remove_translation(translation)
	TranslationServer.set_locale(previous)
	print("DYNAMIC ENGLISH UI ", checks - failures, "/", checks)
	quit(1 if failures else 0)
