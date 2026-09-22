extends Control
## Isolated fixtures of shipped UI. Host ADB supplies all taps and swipes.

const PHASES := ["party", "nearby", "stall", "bag", "wardrobe_parts", "wardrobe_tabs", "nested"]
var phase := -1
var stage: Control
var target: Control
var scroll: ScrollContainer
var outer: ScrollContainer
var clicks := 0
var commands := 0
var ready_for_input := false
var elapsed := 0.0
var next_button: Button
var output := "user://scroll-proof"

func _draw() -> void:
	draw_rect(get_viewport_rect(), GameUi.MINT)

func _ready() -> void:
	Localization.select_language("en")
	theme = GameUi.theme()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	next_button = GameUi.button("chevron-right", "Next QA case", "Next QA case")
	next_button.name = "NextCase"
	next_button.position = Vector2(20, 24)
	next_button.size = Vector2(250, 44)
	next_button.pressed.connect(_next)
	add_child(next_button)
	_next.call_deferred()

func _session() -> FarmSession:
	var session := FarmSession.new(ApiClient.new("https://example.invalid/v1", func(_method, _path, _headers, _body):
		commands += 1
		return {"status": 503, "json": {"code": "QA_BLOCKED"}}))
	session.player_id = "scroll-qa"
	session.state = {"wallet": 180, "clock": {"chapter_index": 3}, "stall": {"settled": 0},
		"inventory": {"produce": {"R": 12, "L": 12, "C": 12, "H": 12}, "seeds": {"R": {"bought": 3, "bound": 3}}},
		"bag": {"version": 1, "sequence": 1, "capacity": 24, "slots": [], "overflow": [], "equipped": {}}}
	for i in 24:
		session.state.bag.slots.append({"id": "b%d" % i, "item_id": "seed_R", "quantity": i + 1, "quality": "normal", "seed_lot": "bought"})
	return session

func _next() -> void:
	ready_for_input = false
	if stage:
		remove_child(stage)
		stage.queue_free()
	phase += 1
	if phase >= PHASES.size():
		FileAccess.open(output.path_join("done.json"), FileAccess.WRITE).store_string('{"done":true}')
		return
	target = null
	outer = null
	clicks = 0
	commands = 0
	stage = Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.name = PHASES[phase]
	stage.size = get_viewport_rect().size
	add_child(stage)
	match PHASES[phase]:
		"party":
			var online := OnlineSpace.new()
			online.session = _session()
			online.kind = "farm"
			online.directory = {"travel_version": 1, "party": {"code": "SCROLL", "leader": "scroll-qa", "members": ["scroll-qa", "other"]}, "roster": []}
			stage.add_child(online)
			online.set_process(false)
			online.hud.hide()
			online.panel = PanelContainer.new()
			online.panel.position = Vector2(16, 110)
			online.panel.size = Vector2(328, 350)
			stage.add_child(online.panel)
			online._draw_party()
			scroll = online.panel.find_child("PartyScroll", true, false) as ScrollContainer
			for button in online.panel.find_children("*", "BaseButton", true, false):
				if button.text == "Disband party": target = button
		"nearby":
			var panel := NearbyPanel.new()
			stage.add_child(panel)
			panel.set_available_space(80, 300)
			var entries := []
			for i in 18: entries.append({"farm_id": "f%d" % i, "avatar_ref": "seed:qa%d" % i, "nursery_stage": "cleared"})
			panel.set_entries(entries, entries.size())
			scroll = panel._scroll
			target = panel.cards()[1]
		"stall":
			var panel := StallSheet.new()
			stage.add_child(panel)
			panel.refresh(_session().state, ["R", "L", "C", "H"])
			panel.fit_height(Vector2(360, 580))
			panel.show()
			scroll = panel._scroll
			target = panel._produce_rows.L.button
		"bag":
			var panel := BagPanel.new()
			panel.setup(_session())
			panel.position = Vector2(16, 100)
			panel.size = Vector2(328, 450)
			stage.add_child(panel)
			await _settle()
			scroll = panel.body_scroll
			target = panel.grid.get_child(4)
		"wardrobe_parts", "wardrobe_tabs":
			var room: Node = load("res://scenes/dressing_room/dressing_room.tscn").instantiate()
			var panel = room.get_node("UI/SafeArea/VBox/Drawer/VBox")
			panel.get_parent().remove_child(panel)
			room.free()
			panel.position = Vector2(20, 160)
			panel.size = Vector2(240, 240)
			stage.add_child(panel)
			var rig := AvatarRig.new()
			stage.add_child(rig)
			panel.setup(rig)
			if PHASES[phase] == "wardrobe_parts":
				scroll = panel.get_node("PartsScroll")
				target = panel.grid.get_child(4)
			else:
				# Constrain this fixture so the currently short set of five tabs overflows.
				panel.get_node("PartsScroll").hide()
				panel.size.x = 140
				scroll = panel.get_node("TabsScroll")
				target = panel.tabs.get_child(1)
		"nested":
			outer = TouchScrollContainer.new()
			outer.position = Vector2(20, 140)
			outer.size = Vector2(280, 220)
			outer.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			stage.add_child(outer)
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			outer.add_child(col)
			scroll = TouchScrollContainer.new()
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.custom_minimum_size.y = 80
			col.add_child(scroll)
			var row := HBoxContainer.new()
			scroll.add_child(row)
			for i in 8:
				var button := GameUi.button("users-round", "Card %d" % i, "Card")
				button.custom_minimum_size = Vector2(120, 64)
				row.add_child(button)
			target = row.get_child(1)
			var filler := Control.new()
			filler.custom_minimum_size.y = 600
			col.add_child(filler)
	await _settle()
	if scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		scroll.scroll_vertical = maxi(0, int(target.global_position.y - scroll.global_position.y - scroll.size.y * 0.65))
	await _settle()
	for button in stage.find_children("*", "BaseButton", true, false):
		button.pressed.connect(func(): clicks += 1)
	ready_for_input = true
	_publish()

func _settle() -> void:
	for i in 8: await get_tree().process_frame

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed > 0.15 and ready_for_input:
		elapsed = 0
		_publish()

func _rect(control: Control) -> Array:
	var rect := get_viewport().get_screen_transform() * control.get_global_rect()
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func _publish() -> void:
	var controls := []
	for control in stage.find_children("*", "BaseButton", true, false):
		if not control.is_visible_in_tree(): continue
		var clipped: Rect2 = control.get_global_rect()
		var parent: Node = control.get_parent()
		while parent != stage and parent != null:
			if parent is Control and parent.clip_contents: clipped = clipped.intersection(parent.get_global_rect())
			parent = parent.get_parent()
		if not clipped.encloses(control.get_global_rect()): continue
		controls.append({"path": str(control.get_path()), "text": control.text, "disabled": control.disabled, "rect": _rect(control)})
	var snapshot := {"phase": PHASES[phase], "clicks": clicks, "commands": commands,
		"scroll": [scroll.scroll_horizontal, scroll.scroll_vertical], "outer": [outer.scroll_horizontal, outer.scroll_vertical] if outer else [],
		"target": _rect(target) if is_instance_valid(target) else [], "next": _rect(next_button), "controls": controls}
	FileAccess.open(output.path_join("state.json"), FileAccess.WRITE).store_string(JSON.stringify(snapshot))
