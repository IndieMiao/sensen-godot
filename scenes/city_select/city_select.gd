extends Control
## 首次进入：自由选择全球任意城市（SGODOT-137）。
##
## 2026-09-28 决定 3：先不申请定位权限。默认城市由服务端按请求 IP 粗定位预填成一张确认卡，
## 用户点确认才落城（PRD §3.4：大致位置只推荐、不静默落入）。其余入口：按名字搜索、
## 有玩家的城市推荐。离线时退回本地精品城市（上海、洛杉矶）。

const SEARCH_DEBOUNCE_S := 0.35
const MAX_RESULTS := 4

## 只在冷启动的第一张选城页判断跳过；之后 change_scene 回来的选城页 current_scene 也是自己。
static var _boot_checked := false

var regions: FarmRegions
var suggested: Dictionary = {}
var _search_serial := 0
var _search_timer: Timer
var _city_card: Panel
var _city_column: VBoxContainer
var _city_card_layer: Control
var _suggest_box: VBoxContainer
var _suggest_label: Label
var _suggest_button: Button
var _search: LineEdit
var _results: VBoxContainer
var _popular_header: Label
var _account_button: Button

@onready var buttons: VBoxContainer = %Buttons
@onready var status: Label = %Status

## 已选定农场的玩家：返回农场所在城市 id（没有可用农场缓存则为空）。
static func owned_farm_region(p_regions: FarmRegions, choice: Dictionary) -> String:
	if p_regions == null or choice.is_empty(): return ""
	var bp := FarmBlueprint.load_choice(choice)
	if bp == null or bp.overlay.is_empty(): return ""
	return bp.region_id if not p_regions.region(bp.region_id).is_empty() else ""

## "Tokyo, Japan"：同名城市（伦敦 / 加拿大伦敦）靠国家与省份区分。精品城市（上海、洛杉矶）只写城市名。
static func city_label(view: Dictionary) -> String:
	var parts := [str(view.get("name", view.get("id", "")))]
	if bool(view.get("curated", false)): return parts[0]
	var admin := str(view.get("admin", ""))
	var country := str(view.get("country", ""))
	if not admin.is_empty() and admin != parts[0] and bool(view.get("curated", false)) == false and country in ["United States", "Canada", "Australia", "China", "India", "Brazil"]:
		parts.append(admin)
	if not country.is_empty(): parts.append(country)
	return ", ".join(parts)

func _ready() -> void:
	# 启动页才跳过：已有农场直接进地图并落在自己农场上；从地图主动回到选城页时照常显示。
	if not _boot_checked and get_tree().current_scene == self:
		_boot_checked = true
		var own_region := owned_farm_region(FarmRegions.load_default(), FarmChoice.load())
		if not own_region.is_empty():
			FarmRegions.save_choice(own_region)
			AppRouter.go_to_map.call_deferred()
			return
	theme = GameUi.theme()
	var language_layer := Control.new()
	language_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$SafeArea.add_child(language_layer)
	var language := LanguageButton.new()
	language_layer.add_child(language)
	language.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	language.offset_left = -44
	language.offset_bottom = 44
	_account_button = GameUi.button("user-round", "", L10n.text("Account"))
	_account_button.name = "AccountButton"
	language_layer.add_child(_account_button)
	_account_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_account_button.offset_left = -92
	_account_button.offset_right = -48
	_account_button.offset_bottom = 44
	_account_button.pressed.connect(_open_account)
	var backdrop := ColorRect.new()
	backdrop.color = GameUi.PAPER
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	move_child(backdrop, 0)
	var background_path := "res://assets/ui/backgrounds/map-social.png"
	if not ResourceLoader.exists(background_path): background_path = "res://assets/ui/backgrounds/city-garden.png"
	if ResourceLoader.exists(background_path):
		var scenery := TextureRect.new()
		scenery.name = "Scenery"
		scenery.texture = load(background_path)
		scenery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scenery.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		scenery.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		scenery.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(scenery)
		move_child(scenery, 1)
	_city_column = $SafeArea/VBox
	_city_column.add_theme_constant_override("separation", 10)
	_city_column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	$SafeArea/VBox/Title.text = "Choose a city"
	$SafeArea/VBox/Title.add_theme_font_size_override("font_size", 22)
	$SafeArea/VBox/Title.custom_minimum_size.y = 40
	var symbol := GameUi.picture(GameUi.icon("map-pin"), 36)
	symbol.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_city_column.add_child(symbol)
	_city_column.move_child(symbol, 0)
	# Default city from the network address: a suggestion the player confirms, never an automatic pick.
	_suggest_box = VBoxContainer.new()
	_suggest_box.name = "Suggestion"
	_suggest_box.add_theme_constant_override("separation", 6)
	_suggest_box.visible = false
	_city_column.add_child(_suggest_box)
	_city_column.move_child(_suggest_box, 2)
	_suggest_label = GameUi.label("", 13, GameUi.MUTED)
	_suggest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_suggest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_suggest_box.add_child(_suggest_label)
	_suggest_button = GameUi.button("map-pin", " ", "", true)
	_suggest_button.name = "SuggestedCity"
	_suggest_button.custom_minimum_size.y = 54
	_suggest_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_suggest_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_suggest_button.pressed.connect(func(): choose_city(suggested))
	_suggest_box.add_child(_suggest_button)
	_search = LineEdit.new()
	_search.name = "Search"
	_search.placeholder_text = L10n.text("Search for any city")
	_search.custom_minimum_size = Vector2(0, 48)
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search_changed)
	_city_column.add_child(_search)
	_city_column.move_child(_search, 3)
	_results = VBoxContainer.new()
	_results.name = "Results"
	_results.add_theme_constant_override("separation", 6)
	_city_column.add_child(_results)
	_city_column.move_child(_results, 4)
	_popular_header = GameUi.label(L10n.text("Popular cities"), 12, GameUi.MUTED)
	_city_column.add_child(_popular_header)
	_city_column.move_child(_popular_header, 5)
	buttons.add_theme_constant_override("separation", 8)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", GameUi.MUTED)
	status.custom_minimum_size.y = 24
	status.text = ""
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = SEARCH_DEBOUNCE_S
	_search_timer.timeout.connect(_run_search)
	add_child(_search_timer)
	regions = FarmRegions.load_default()
	if regions == null:
		status.text = "Missing city configuration"
		return
	# Offline-safe list first: the curated cities ship with the app.
	_show_popular(regions.regions.filter(func(r): return not bool(r.get("global", false))).map(_region_view))
	_city_card_layer = Control.new()
	_city_card_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$SafeArea.add_child(_city_card_layer)
	$SafeArea.move_child(_city_card_layer, 0)
	_city_card = Panel.new()
	_city_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_city_card.add_theme_stylebox_override("panel", GameUi.panel_style(18))
	_city_card_layer.add_child(_city_card)
	_city_card_layer.resized.connect(_layout_city_card)
	_city_column.minimum_size_changed.connect(_layout_city_card.call_deferred)
	_layout_city_card.call_deferred()
	if Net and not Net.is_test_process():
		_load_directory.call_deferred()
	if Net:
		Net.account_changed.connect(_on_account_changed)
		Net.booted.connect(_on_net_booted)

func _on_net_booted(_ok: bool) -> void:
	_on_account_changed(not Net.is_guest())

## 新设备登录已有农场的账号：直接回到自己的农场，不必再选城。
func _on_account_changed(signed_in: bool) -> void:
	if not signed_in or not is_inside_tree() or not Net.session.has_farm(): return
	var choice := Net.session.farm_choice()
	if FarmBlueprint.load_choice(choice) == null: return
	await Net.ensure_city(Net.session.region_id)
	if not is_inside_tree(): return
	FarmChoice.save_choice(choice)
	choose(Net.session.region_id)

func _region_view(r: Dictionary) -> Dictionary:
	return {"id": str(r.id), "name": str(r.get("name", r.id)), "country": str(r.get("country", "")), "curated": true,
		"center": r.get("center", []), "placement_bounds": r.get("placement_bounds", []), "timezone": str(r.get("timezone", "UTC"))}

func _layout_city_card() -> void:
	if not is_instance_valid(_city_card): return
	var area := _city_card_layer.size
	var width := minf(408, maxf(1, area.x - 16))
	_city_column.custom_minimum_size.x = maxf(1, width - 36)
	var height := minf(area.y, _city_column.get_combined_minimum_size().y + 36)
	_city_card.position = Vector2((area.x - width) * 0.5, (area.y - height) * 0.5)
	_city_card.size = Vector2(width, height)

func region_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c in buttons.get_children():
		if c is Button:
			out.append(c)
	return out

func result_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c in _results.get_children():
		if c is Button: out.append(c)
	return out

func _city_button(view: Dictionary, accent := false) -> Button:
	var label := city_label(view)
	var count := int(view.get("farm_count", 0))
	if count > 0: label += " · " + L10n.format_text("%d farms", count)
	var b := GameUi.button("map-pin", label, label, accent)
	b.theme_type_variation = &"ChoiceButton"
	b.custom_minimum_size = Vector2(0, 48)
	b.clip_text = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override("font_size", 14)
	b.set_meta("city_id", str(view.get("id", "")))
	b.pressed.connect(choose_city.bind(view))
	return b

func _show_popular(views: Array) -> void:
	for c in buttons.get_children(): c.queue_free()
	for view in views.slice(0, 8):
		buttons.add_child(_city_button(view))
	_popular_header.visible = not views.is_empty() and buttons.visible

## 服务端目录：IP 预填 + 有玩家的城市。失败就保留本地精品城市，不打扰玩家。
func _load_directory() -> void:
	var listed: ApiClient.Response = await Net.client.request("GET", "/cities")
	if not is_inside_tree(): return
	if listed.is_success() and listed.json.get("cities") is Array and not listed.json.cities.is_empty():
		_show_popular(listed.json.cities)
	var hint: ApiClient.Response = await Net.client.request("GET", "/cities/suggest")
	if not is_inside_tree(): return
	if hint.is_success() and hint.json.get("city") is Dictionary:
		show_suggestion(hint.json.city)

func show_suggestion(view: Dictionary) -> void:
	if str(view.get("id", "")).is_empty(): return
	suggested = view
	_suggest_label.text = L10n.text("You seem to be near")
	_suggest_button.text = city_label(view)
	_suggest_box.visible = true

func _on_search_changed(text: String) -> void:
	_search_serial += 1
	if text.strip_edges().length() < 2:
		show_results([])
		_search_timer.stop()
		return
	_search_timer.start()

func _run_search() -> void:
	var query := _search.text.strip_edges()
	if query.length() < 2: return
	_search_serial += 1
	var serial := _search_serial
	var r: ApiClient.Response = await Net.client.request("GET", "/cities/search?q=%s" % query.uri_encode())
	# A newer keystroke owns the list; late answers are dropped.
	if not is_inside_tree() or serial != _search_serial: return
	if not r.ok:
		status.text = L10n.text("Can't reach the server. Check your connection.")
		return
	status.text = ""
	show_results(r.json.get("cities", []) if r.is_success() else [])
	if r.is_success() and r.json.get("cities", []).is_empty():
		status.text = L10n.text("No city found. Try another spelling.")

func show_results(views: Array) -> void:
	for c in _results.get_children(): c.queue_free()
	for view in views.slice(0, MAX_RESULTS):
		_results.add_child(_city_button(view))
	# While searching, the popular list steps aside so the card stays on one screen.
	var searching := not views.is_empty() or (_search != null and _search.text.strip_edges().length() >= 2)
	buttons.visible = not searching
	_popular_header.visible = not searching and buttons.get_child_count() > 0

## 选中一座城市（服务端 cityView 或本地精品城市）。
func choose_city(view: Dictionary) -> void:
	var id := str(view.get("id", ""))
	if id.is_empty(): return
	if not bool(view.get("curated", false)) or regions == null or regions.region(id).is_empty():
		if FarmRegions.remember_city(view).is_empty(): return
	choose(id)

func choose(id: String) -> void:
	FarmRegions.save_choice(id)
	AppRouter.go_to_map()

func _open_account() -> void:
	if GameUi.modal_is_open(self): return
	AccountPanel.open(self, "account" if Net and not Net.is_guest() else "sign_in")
