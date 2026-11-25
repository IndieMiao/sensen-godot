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
	"Can't reach the server. You're still signed in.": "账号保留提示",
	# C-144: the router's loading layer and the v3 sign-in panel.
	"Loading...": "正在加载…", "Go back": "返回", "Could not open this place": "无法打开这里",
	"Email": "邮箱", "Password": "密码", "Show": "显示", "Forgot password?": "忘记密码？", "or": "或",
	"Sign in with Google": "通过 Google 登录", "Create an account": "注册新账号", "Close": "关闭",
	"Create account": "注册", "Password (8+ characters)": "密码（至少 8 位）", "Confirm password": "确认密码",
	"Already have an account? Sign in": "已有账号？登录", "Signing in…": "正在登录…",
	"Email or password is incorrect.": "邮箱或密码错误。", "Enter a valid email address.": "请输入有效的邮箱地址。"
}
## Loaded at run time, like the map does: the panel uses the Net autoload.
const ACCOUNT_PANEL := "res://scenes/account/account_panel.gd"
const Overlay := preload("res://modules/ui/loading_overlay.gd")
const CJK := "[\\x{3000}-\\x{9fff}\\x{ff00}-\\x{ffef}]"

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

## Every Label / Button / LineEdit / OptionButton text as drawn (after automatic translation), with its node path.
func shown(node: Node) -> Array:
	var out := []
	for n in [node] + node.find_children("*", "", true, false):
		if not (n is Control) or not (n as Control).is_visible_in_tree(): continue
		var texts := []
		if n is Label or n is Button: texts.append(n.text)
		if n is LineEdit: texts.append_array([n.text, n.placeholder_text])
		if n is Control and not n.tooltip_text.is_empty(): texts.append(n.tooltip_text)
		if n is OptionButton:
			for i in n.item_count: texts.append(n.get_item_text(i))
		for t in texts:
			if not str(t).is_empty(): out.append([str(n.get_path()), String(n.atr(t))])
	return out

func has_cjk(text: String) -> bool:
	var re := RegEx.create_from_string(CJK)
	return re.search(text) != null

## C-144: the router's loading layer over the map's 3D scenes (V-361). The map asks open_instance for it in English; the
## main farm's layer (no english_ui) keeps translating.
func _loading_layer() -> void:
	var english = Overlay.new(); english.english = true; root.add_child(english)
	var main_farm = Overlay.new(); root.add_child(main_farm)
	await process_frame
	verify(english.message.text == "Loading..." and String(english.message.atr(english.message.text)) == "Loading...",
		"dynamic farm loading layer stays English: Loading...")
	verify(String(main_farm.message.atr(main_farm.message.text)) == "正在加载…", "main farm loading layer still translates")
	english.failed(); main_farm.failed()
	for pair in [[english.message, "Could not open this place"], [english.close_button, "Go back"]]:
		verify(pair[0].text == pair[1] and String(pair[0].atr(pair[0].text)) == pair[1], "dynamic farm loading failure stays English: " + pair[1])
	verify(String(main_farm.close_button.atr(main_farm.close_button.text)) == "返回", "main farm loading failure still translates")
	verify(shown(english).all(func(p): return not has_cjk(p[1])), "no Chinese anywhere on the English loading layer")
	english.queue_free(); main_farm.queue_free()
	# The real router: open_instance's english_ui reaches the layer it draws, and only that call's layer.
	var router := root.get_node_or_null("/root/AppRouter")
	verify(router != null, "AppRouter autoload present")
	if router == null: return
	for case in [[{Overlay.ENGLISH_UI: true}, true], [{}, false]]:
		var done := [false]
		var load_it := func(): await router._load_with_feedback("res://scenes/dynamic_farm/dynamic_farm_host.tscn", case[0]); done[0] = true
		load_it.call()
		var layer = router._loading
		verify(layer != null and layer.english == case[1], "router loading layer english=%s for %s" % [case[1], case[0]])
		var drawn := String(layer.message.atr(layer.message.text)) if layer != null else ""
		verify(drawn == ("Loading..." if case[1] else "正在加载…"), "router loading layer with %s draws %s" % [case[0], drawn])
		for i in 600:
			if done[0]: break
			await process_frame
		router._clear_transition()
	await process_frame

## C-144: the map's v3 sign-in panel (V-378): every mode the board covers is English whatever the locale, as approved in
## C-85 ④; the main farm's classic panel still translates.
func _sign_in_panel(map_page: Node) -> void:
	GoogleSignIn.force_available = true # the Android row (Google Play services), as on the phone
	for mode in ["sign_in", "sign_up", "forgot", "verify", "profile"]:
		var panel = load(ACCOUNT_PANEL).open(map_page, mode, "", true, true)
		await process_frame
		var chinese := shown(panel).filter(func(p): return has_cjk(p[1]))
		verify(chinese.is_empty(), "v3 %s panel stays English%s" % [mode, "" if chinese.is_empty() else ": " + str(chinese.slice(0, 3))])
		if mode == "sign_in":
			var texts := shown(panel).map(func(p): return p[1])
			for copy in ["Sign in", "Email", "Password", "Show", "Forgot password?", "or", "Sign in with Google", "Create an account"]:
				verify(copy in texts, "v3 sign-in shows the approved copy: " + copy)
			panel._say("Email or password is incorrect.", false)
			await process_frame
			verify(shown(panel).all(func(p): return not has_cjk(p[1])), "v3 sign-in error stays English")
		panel.free()
	GoogleSignIn.force_available = false
	var classic = load(ACCOUNT_PANEL).open(map_page, "sign_in")
	await process_frame
	verify(shown(classic).any(func(p): return p[1] == "邮箱"), "the main farm's panel still translates")
	classic.free()
	var opened: Array = map_page.find_children("*", "AccountPanel", true, false)
	verify(opened.is_empty(), "no sign-in panel left open")

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
	await _loading_layer()
	await _sign_in_panel(map_page)
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
