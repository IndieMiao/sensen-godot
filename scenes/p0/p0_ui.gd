class_name P0Ui
extends CanvasLayer
## P0 milestone-1 UI layer, built in code from the batch-1/2 design (1080 × 2400 design px ÷ 3 = logical px).
## Two-row HUD · quick bar 5 + Bag · main action button · bag drawer · Bao's greeting + stall drawer (p(4)) ·
## Energy Card (facts only, §3.7.2) · bench Rest card · level-up banner · floats · world tags · toasts.

signal joystick(v: Vector2)
signal tapped(screen_pos: Vector2)
signal action_pressed(cmd: Dictionary)
signal seed_selected(seed_id: String)
signal command(cmd: Dictionary)
signal dev_skip(minutes: int)

const PAPER := Color("fbf8f1")
const CARD := Color(0.984, 0.973, 0.945, 0.94)
const EDGE := Color("e1dac8")
const INK := Color("2f3a33")
const INK2 := Color("6e7b74")
const GREEN := Color("7fc66a")
const GREEN_D := Color("5fa85a")
const AMBER := Color("e3b341")
const AMBER_D := Color("b8831c")
const BLUE := Color("6fa8dc")
const TERRA := Color("f6e2d6")
const DIS := Color("d6d5ce")

var view: Dictionary = {}
var root: Control
var pad: Control
var _hud_energy: Label
var _hud_regen: Label
var _hud_bar: Control
var _hud_coins: Label
var _today: Label
var _avatar: Control
var _fab: Control
var _fab_icon: TextureRect
var _fab_verb: Label
var _fab_sub: Label
var _fab_state: Dictionary = {}
var _bar_box: HBoxContainer
var _bar_ids: Array = []
var selected_seed := ""
var _modal: Control
var _tags := {}
var _toast: Label
var _toast_left := 0.0
var _regular: FontVariation

# ---------------------------------------------------------------- build
func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = GameUi.theme()
	add_child(root)
	pad = _TouchPad.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.ui = self
	root.add_child(pad)
	_build_hud()
	_build_bar()
	_build_fab()
	_toast = _label("", 11, INK, true)
	_toast.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.96), 14, EDGE, 1, Vector4(12, 8, 12, 8)))
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-150, 104)
	_toast.custom_minimum_size = Vector2(300, 0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.hide()
	root.add_child(_toast)
	if OS.is_debug_build(): _build_dev()

func _process(dt: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= dt
		if _toast_left <= 0.0: _toast.hide()

func _build_hud() -> void:
	_avatar = _AvatarRing.new()
	_avatar.position = Vector2(10, 16)
	_avatar.size = Vector2(37, 37)
	root.add_child(_avatar)
	var ecard := PanelContainer.new()
	ecard.add_theme_stylebox_override("panel", _box(CARD, 12, EDGE, 1, Vector4(8, 5, 8, 5)))
	ecard.position = Vector2(52, 16)
	ecard.custom_minimum_size = Vector2(112, 37)
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 1)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 3)
	top.add_child(_icon("energy", 13))
	_hud_energy = _label("200/200", 13, INK, true)
	top.add_child(_hud_energy)
	ev.add_child(top)
	_hud_bar = _EnergyBar.new()
	_hud_bar.custom_minimum_size = Vector2(80, 4)
	ev.add_child(_hud_bar)
	_hud_regen = _label("Full", 8, INK2)
	ev.add_child(_hud_regen)
	ecard.add_child(ev)
	root.add_child(ecard)
	var right := HBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-128, 22)
	right.add_theme_constant_override("separation", 6)
	var coins := PanelContainer.new()
	coins.add_theme_stylebox_override("panel", _box(CARD, 12, EDGE, 1, Vector4(10, 4, 8, 4)))
	var ch := HBoxContainer.new()
	_hud_coins = _label("180", 12, INK, true)
	ch.add_child(_hud_coins)
	ch.add_child(_icon("coin", 13))
	coins.add_child(ch)
	right.add_child(coins)
	var bell := PanelContainer.new()
	bell.add_theme_stylebox_override("panel", _box(CARD, 16, EDGE, 1, Vector4(6, 6, 6, 6)))
	bell.add_child(_icon("bell", 18))
	right.add_child(bell)
	root.add_child(right)
	# row 2: Today chip (left) · place chip "City · Space" (right)
	var today := PanelContainer.new()
	today.add_theme_stylebox_override("panel", _box(CARD, 11, EDGE, 1, Vector4(8, 4, 8, 4)))
	today.position = Vector2(10, 64)
	var th := HBoxContainer.new()
	th.add_child(_label("Today ·", 10, INK, true))
	_today = _label("Sow your first plot", 10, INK)
	_today.custom_minimum_size = Vector2(150, 0)
	_today.clip_text = true
	th.add_child(_today)
	today.add_child(th)
	root.add_child(today)
	var place := PanelContainer.new()
	place.add_theme_stylebox_override("panel", _box(CARD, 11, EDGE, 1, Vector4(8, 4, 8, 4)))
	place.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	place.position = Vector2(-128, 64)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 3)
	ph.add_child(_icon("home", 11))
	ph.add_child(_label("Shanghai · Homestead", 10, INK, true))
	place.add_child(ph)
	root.add_child(place)

func _build_bar() -> void:
	_bar_box = HBoxContainer.new()
	_bar_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_bar_box.position = Vector2(10, -41 - 53)
	_bar_box.add_theme_constant_override("separation", 4)
	root.add_child(_bar_box)

func _build_fab() -> void:
	_fab = _Fab.new()
	_fab.ui = self
	_fab.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fab.size = Vector2(59, 59)
	_fab.position = Vector2(-10 - 59, -41 - 53 - 14 - 59)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fab_icon = _icon("sow", 20)
	_fab_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_fab_icon)
	_fab_verb = _label("Sow", 10, INK, true)
	_fab_verb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_fab_verb)
	_fab_sub = _label("", 7, INK2)
	_fab_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_fab_sub)
	_fab.add_child(v)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _box(PAPER, 10, GREEN_D, 1, Vector4(2, 2, 2, 2)))
	badge.position = Vector2(-4, -4)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(_icon("hoe", 13))
	_fab.add_child(badge)
	root.add_child(_fab)
	var sw := Button.new()
	sw.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	sw.position = Vector2(-10 - 46, -41 - 53 - 14 - 59 - 8 - 32)
	sw.custom_minimum_size = Vector2(32, 32)
	sw.size = Vector2(32, 32)
	sw.icon = P0Logic.icon("switch")
	sw.expand_icon = true
	sw.add_theme_stylebox_override("normal", _box(Color(0.92, 0.92, 0.9, 0.9), 16, EDGE, 1, Vector4(6, 6, 6, 6)))
	sw.add_theme_stylebox_override("pressed", _box(Color(0.85, 0.85, 0.82, 0.9), 16, EDGE, 1, Vector4(6, 6, 6, 6)))
	sw.pressed.connect(func(): toast("Farming here · Fishing and Mining come with the pond and mine"))
	root.add_child(sw)

func _build_dev() -> void:
	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.position = Vector2(-96, 92)
	box.add_theme_constant_override("separation", 4)
	for m in [60, 240]:
		var b := _pill_button("+%dh" % (m / 60), false)
		b.custom_minimum_size = Vector2(42, 22)
		b.add_theme_font_size_override("font_size", 9)
		b.pressed.connect(func(): dev_skip.emit(m))
		box.add_child(b)
	root.add_child(box)

# ---------------------------------------------------------------- refresh
func set_view(v: Dictionary) -> void:
	view = v
	var e: Dictionary = v.get("energy", {})
	var val := int(e.get("value", 0))
	var mx := int(e.get("max", 200))
	_hud_energy.text = "%d/%d" % [val, mx]
	_hud_bar.set_meta("pct", clampf(float(val) / maxf(1.0, mx), 0.0, 1.0))
	_hud_bar.queue_redraw()
	var nx = e.get("next_in", null)
	_hud_regen.text = "Full" if nx == null else "+1 in " + P0Logic.duration(float(nx))
	_hud_coins.text = str(int(v.get("coins", 0)))
	_today.text = P0Logic.today_line(v)
	var sk: Dictionary = v.get("skills", {})
	_avatar.set_meta("farm", _skill_pct(sk.get("farming", {})))
	_avatar.set_meta("fish", _skill_pct(sk.get("fishing", {})))
	_avatar.queue_redraw()
	_refresh_bar()

func _skill_pct(s: Dictionary) -> float:
	if s.is_empty() or s.get("next", null) == null: return 1.0
	return clampf(float(int(s.xp) - int(s.floor)) / maxf(1.0, float(int(s.next) - int(s.floor))), 0.0, 1.0)

func _refresh_bar() -> void:
	var ids := P0Logic.quick_bar(view, _bar_ids)
	if selected_seed != "" and not ids.has(selected_seed): selected_seed = ""
	if selected_seed == "" and not ids.is_empty():
		selected_seed = str(ids[0])
		seed_selected.emit(selected_seed)
	if ids == _bar_ids and _bar_box.get_child_count() > 0:
		_update_bar_counts()
		return
	_bar_ids = ids
	for c in _bar_box.get_children(): c.queue_free()
	for i in 5:
		var slot := _slot(str(ids[i]) if i < ids.size() else "")
		_bar_box.add_child(slot)
	var bag := Button.new()
	bag.custom_minimum_size = Vector2(53, 53)
	bag.text = "Bag"
	bag.icon = P0Logic.icon("bag")
	bag.expand_icon = false
	bag.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	bag.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bag.add_theme_font_size_override("font_size", 10)
	bag.add_theme_constant_override("icon_max_width", 22)
	_style_button(bag, PAPER, EDGE, 11)
	bag.pressed.connect(open_bag)
	_bar_box.add_child(bag)

func _update_bar_counts() -> void:
	for i in mini(_bar_ids.size(), 5):
		var slot := _bar_box.get_child(i)
		var cnt := slot.find_child("Count", true, false) as Label
		if cnt: cnt.text = "×%d" % P0Logic.bag_count(view, str(_bar_ids[i]))
		slot.set_meta("selected", str(_bar_ids[i]) == selected_seed)
		slot.queue_redraw()

func _slot(seed_id: String) -> Control:
	var slot := _Slot.new()
	slot.custom_minimum_size = Vector2(53, 53)
	slot.set_meta("selected", seed_id != "" and seed_id == selected_seed)
	if seed_id == "":
		slot.set_meta("ghost", true)
		return slot
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 3
	col.offset_right = -3
	col.offset_top = 3
	col.offset_bottom = -2
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := _icon(seed_id, 24)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ic)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := _label(P0Logic.item_name(view, seed_id).replace(" Seeds", ""), 7, INK, true)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	row.add_child(nm)
	var cnt := _label("×%d" % P0Logic.bag_count(view, seed_id), 8, INK, true)
	cnt.name = "Count"
	row.add_child(cnt)
	col.add_child(row)
	slot.add_child(col)
	slot.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
			selected_seed = seed_id
			seed_selected.emit(seed_id)
			_update_bar_counts())
	return slot

## Main action button state from P0Logic.main_action().
func set_action(a: Dictionary) -> void:
	_fab_state = a
	_fab_icon.texture = P0Logic.icon(str(a.get("icon", "sow")))
	_fab_verb.text = str(a.get("verb", ""))
	_fab_sub.text = str(a.get("sub", ""))
	_fab_verb.add_theme_color_override("font_color", AMBER_D if a.get("amber", false) else (INK if a.get("enabled", false) else INK2))
	_fab.set_meta("state", a)
	_fab.queue_redraw()

func _fab_pressed() -> void:
	if not _fab_state.get("enabled", false) or _modal != null: return
	action_pressed.emit(_fab_state.get("cmd", {}))

# ---------------------------------------------------------------- world tags & floats
func tag(id: String, text: String, screen: Vector2, show: bool, lit := false) -> void:
	var t: Label = _tags.get(id)
	if t == null:
		t = _label("", 10, INK, true)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(t)
		root.move_child(t, 1)
		_tags[id] = t
	t.visible = show and _modal == null
	if not t.visible: return
	t.text = text
	t.add_theme_stylebox_override("normal", _box(Color("e6f4df") if lit else CARD, 11, GREEN_D if lit else EDGE, 1, Vector4(8, 3, 8, 3)))
	t.reset_size()
	t.position = screen - Vector2(t.size.x * 0.5, t.size.y + 6)

func float_text(text: String, screen: Vector2, color: Color) -> void:
	var l := _label(text, 12, color, true)
	l.add_theme_color_override("font_outline_color", PAPER)
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	l.reset_size()
	l.position = screen - Vector2(l.size.x * 0.5, l.size.y)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 34, 1.1)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.5)
	tw.tween_callback(l.queue_free)

func toast(text: String, seconds := 2.6) -> void:
	_toast.text = text
	_toast.show()
	_toast_left = seconds

# ---------------------------------------------------------------- modals
func has_modal() -> bool: return _modal != null

func close_modal() -> void:
	if _modal: _modal.queue_free()
	_modal = null
	_fab.visible = true
	_bar_box.visible = true

func _open_modal(content: Control, dim := 0.32, hide_controls := false) -> void:
	close_modal()
	var veil := ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.184, 0.227, 0.2, dim)
	veil.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed): close_modal())
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(veil)
	holder.add_child(content)
	root.add_child(holder)
	_modal = holder
	if hide_controls:
		_fab.visible = false
		_bar_box.visible = false

func _sheet(height: float, title: String, icon_id := "") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -height
	panel.add_theme_stylebox_override("panel", _box(CARD, 16, EDGE, 1, Vector4(10, 8, 10, 12), true))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var head := HBoxContainer.new()
	if icon_id != "": head.add_child(_icon(icon_id, 14))
	var t := _label(title, 12, INK, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := Button.new()
	x.text = "✕"
	x.custom_minimum_size = Vector2(30, 30)
	_style_button(x, PAPER, EDGE, 15)
	x.pressed.connect(close_modal)
	head.add_child(x)
	v.add_child(head)
	_open_modal(panel, 0.3, true)
	return v

## Bag drawer: quick-bar row is the bar itself (P0: seeds shown), then capacity, then a 5-column grid.
func open_bag() -> void:
	var v := _sheet(380, "Bag %d/%d" % [_bag_slots().size(), int(view.get("bag", {}).get("capacity", 25))], "bag")
	var cap := _CapBar.new()
	cap.custom_minimum_size = Vector2(0, 5)
	cap.set_meta("pct", float(_bag_slots().size()) / maxf(1.0, float(view.get("bag", {}).get("capacity", 25))))
	v.add_child(cap)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	var detail := _label("Tap an item. Sell at Bao's Stall.", 9, INK2)
	for i in int(view.get("bag", {}).get("capacity", 25)):
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(58, 58)
		var slots := _bag_slots()
		if i < slots.size():
			var s: Dictionary = slots[i]
			cell.add_theme_stylebox_override("panel", _box(PAPER, 10, EDGE, 1, Vector4(4, 4, 4, 4)))
			var box := Control.new()
			var ic := _icon(str(s.id), 28)
			ic.position = Vector2(11, 4)
			box.add_child(ic)
			var q := _label("×%d" % int(s.qty), 9, INK, true)
			q.position = Vector2(26, 36)
			box.add_child(q)
			cell.add_child(box)
			var id := str(s.id)
			cell.gui_input.connect(func(e: InputEvent):
				if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
					detail.text = "%s ×%d · %s" % [P0Logic.item_name(view, id), P0Logic.bag_count(view, id), _item_line(id)])
		else:
			cell.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.2), 10, Color("d9c7a6"), 1, Vector4(4, 4, 4, 4)))
		grid.add_child(cell)
	v.add_child(detail)
	v.add_child(grid)

func _item_line(id: String) -> String:
	if id.begins_with("seed_"):
		var c := P0Logic.crop_for_seed(view, id)
		return "%d Energy per plot · ready in %dh" % [int(c.get("energy", 2)), int(c.get("grow_h", 4))]
	if id.begins_with("crop_"):
		return "Sells for %d at Bao's Stall" % int(view.get("prices", {}).get(id, 0))
	return ""

func _bag_slots() -> Array: return view.get("bag", {}).get("slots", [])

## p(4): every NPC greets before trading — Bao's greeting card (§9.4.2), live info in the line.
func open_greeting() -> void:
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	card.offset_top = -196
	card.offset_left = 10
	card.offset_right = -10
	card.offset_bottom = -12
	card.add_theme_stylebox_override("panel", _box(CARD, 16, EDGE, 1, Vector4(8, 8, 10, 8)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var portrait := TextureRect.new()
	portrait.texture = _bao_art(Rect2(430, 455, 214, 366))
	portrait.custom_minimum_size = Vector2(100, 171)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	h.add_child(portrait)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	var who := _label("Stallhand · Bao", 13, INK, true)
	v.add_child(who)
	v.add_child(_label("Keeps your stall · Homestead", 8, INK2))
	var line := _label("“%s”" % _bao_line(), 10, INK)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(200, 0)
	v.add_child(line)
	var trade := _pill_button("Trade · buy & sell", true)
	trade.pressed.connect(open_stall)
	v.add_child(trade)
	var ask := _pill_button("What's selling today?", false)
	ask.pressed.connect(func(): line.text = "“%s”" % _bao_answer())
	v.add_child(ask)
	var bye := _flat_button("Just passing by")
	bye.pressed.connect(close_modal)
	v.add_child(bye)
	h.add_child(v)
	card.add_child(h)
	_open_modal(card, 0.22, true)

func _bao_line() -> String:
	var radish := int(view.get("prices", {}).get("crop_radish", 5))
	var ready := 0
	for p in view.get("plots", []): if str(p.get("state", "")) == "ready": ready += 1
	if ready > 0: return "Morning! %d plots are ready out there. Radishes sell for %d each." % [ready, radish]
	return "Morning! Radishes sell for %d each today. Seeds never run out here." % radish

func _bao_answer() -> String:
	var parts: Array = []
	for id in ["crop_radish", "crop_lettuce", "crop_carrot", "crop_tomato"]:
		parts.append("%s %d" % [P0Logic.item_name(view, id), int(view.get("prices", {}).get(id, 0))])
	return "Everything you grow sells here, no daily limit — " + ", ".join(parts) + "."

func _bao_art(region: Rect2) -> Texture2D:
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/p0/art/homestead-stall.png")
	at.region = region
	return at

## Stall drawer: keeper bar (terracotta) · Buy rows with level gates · Sell your produce (no Sell Tab; produce, no quota).
func open_stall(bubble := "") -> void:
	var v := _sheet(520, "Bao's Stall · Homestead", "stall")
	var kp := PanelContainer.new()
	kp.add_theme_stylebox_override("panel", _box(TERRA, 12, TERRA, 0, Vector4(6, 6, 8, 6)))
	var kh := HBoxContainer.new()
	kh.add_theme_constant_override("separation", 8)
	var face := TextureRect.new()
	face.texture = _bao_art(Rect2(440, 470, 170, 170))
	face.custom_minimum_size = Vector2(38, 38)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	kh.add_child(face)
	var kv := VBoxContainer.new()
	kv.add_child(_label("Stallhand · Bao", 9, INK, true))
	var say := _label("“%s”" % (bubble if bubble != "" else "Radish seeds, 4 coins. Carrots open at Farming Lv2."), 9, INK)
	say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	say.custom_minimum_size = Vector2(260, 0)
	kv.add_child(say)
	kh.add_child(kv)
	kp.add_child(kh)
	v.add_child(kp)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 410)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	v.add_child(scroll)
	list.add_child(_label("Buy", 11, INK, true))
	for row in view.get("stall", {}).get("buy", []):
		list.add_child(_buy_row(row))
	var produce: Array = []
	for s in _bag_slots():
		var id := str(s.id)
		if id.begins_with("crop_") and not produce.has(id): produce.append(id)
	list.add_child(_label("Sell here · produce, no daily limit", 11, INK, true))
	if produce.is_empty():
		list.add_child(_label("Nothing to sell yet — harvest first.", 9, INK2))
	for id in produce: list.add_child(_sell_row(id))

func _buy_row(row: Dictionary) -> Control:
	var id := str(row.id)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.custom_minimum_size = Vector2(0, 40)
	var ic := _icon(id, 26)
	if not row.get("unlocked", false): ic.modulate = Color(1, 1, 1, 0.45)
	h.add_child(ic)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	mid.add_child(_label(str(row.name), 10, INK if row.get("unlocked", false) else INK2, true))
	mid.add_child(_label("%d coins · %d Energy a plot · Bag ×%d" % [int(row.price), int(row.energy), P0Logic.bag_count(view, id)], 8, INK2))
	h.add_child(mid)
	if not row.get("unlocked", false):
		var lk := _label("Farming Lv%d · %d XP to go" % [int(row.gate), int(row.xp_to_go)], 8, INK2, true)
		lk.add_theme_stylebox_override("normal", _box(DIS, 10, DIS, 0, Vector4(8, 4, 8, 4)))
		h.add_child(lk)
		return h
	for q in [1, 10]:
		var b := _pill_button("Buy %d · %d" % [q, int(row.price) * q], q == 10)
		b.custom_minimum_size = Vector2(62, 28)
		b.add_theme_font_size_override("font_size", 8)
		b.pressed.connect(func(): command.emit({"type": "buy", "item": id, "qty": q}))
		h.add_child(b)
	return h

func _sell_row(id: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.custom_minimum_size = Vector2(0, 40)
	h.add_child(_icon(id, 26))
	var n := P0Logic.bag_count(view, id)
	var price := int(view.get("prices", {}).get(id, 0))
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(_label("%s ×%d" % [P0Logic.item_name(view, id), n], 10, INK, true))
	mid.add_child(_label("%d each · Sell All = %d coins" % [price, price * n], 8, INK2))
	h.add_child(mid)
	var one := _pill_button("Sell", false)
	one.custom_minimum_size = Vector2(48, 28)
	one.pressed.connect(func(): command.emit({"type": "sell", "item": id, "qty": 1}))
	h.add_child(one)
	var all := _pill_button("Sell All", true)
	all.custom_minimum_size = Vector2(60, 28)
	all.pressed.connect(func(): command.emit({"type": "sell", "item": id, "qty": n}))
	h.add_child(all)
	return h

## Energy Card (§3.7.2): only facts; tiles guide; one button closes.
func open_energy_card(need: int, verb: String) -> void:
	var f := P0Logic.energy_card(view, need, verb)
	var card := _center_card(300)
	card.add_child(_label(str(f.title), 12, INK, true))
	card.add_child(_label(str(f.have), 11, INK))
	card.add_child(_label(str(f.gap), 11, AMBER_D, true))
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 6)
	tiles.add_child(_tile("rest", str(f.rest), "The bench is by the house"))
	tiles.add_child(_tile("bag", "Open bag", "", func(): close_modal(); open_bag()))
	card.add_child(tiles)
	var ok := _pill_button("Free to do now", true)
	ok.pressed.connect(close_modal)
	card.add_child(ok)

func open_rest_card() -> void:
	var r: Dictionary = view.get("rest", {})
	var used := int(r.get("used", 0)) >= int(r.get("limit", 1))
	var e: Dictionary = view.get("energy", {})
	var full := int(e.get("value", 0)) >= int(e.get("max", 200))
	var card := _center_card(260)
	card.add_child(_label("Bench · Rest", 12, INK, true))
	card.add_child(_label("+%d Energy · once a day" % int(r.get("amount", 60)), 11, INK))
	var b := _pill_button("Rest", true)
	if used:
		card.add_child(_label("Used today · resets in " + P0Logic.duration(float(r.get("resets_in", 0))), 10, INK2))
		b.disabled = true
	elif full:
		card.add_child(_label("Energy full", 10, INK2))
		b.disabled = true
	b.pressed.connect(func(): close_modal(); command.emit({"type": "rest"}))
	card.add_child(b)

func show_level_up(ev: Dictionary) -> void:
	var card := _center_card(310)
	card.add_child(_label("LEVEL UP", 10, GREEN_D, true))
	var t := _label("%s Lv %d" % [str(ev.skill).capitalize(), int(ev.level)], 26, GREEN_D, true)
	card.add_child(t)
	if int(ev.get("energy", 0)) > 0: card.add_child(_label("+%d Energy" % int(ev.energy), 14, GREEN_D, true))
	for g in ev.get("gifts", []):
		card.add_child(_label("Level-up gift: %d %s" % [int(g[1]), P0Logic.item_name(view, str(g[0]))], 10, INK, true))
	var ok := _pill_button("Got it", true)
	ok.pressed.connect(close_modal)
	card.add_child(ok)

func _center_card(width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(width, 0)
	panel.add_theme_stylebox_override("panel", _box(CARD, 16, EDGE, 1, Vector4(14, 12, 14, 12)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	panel.add_child(v)
	_open_modal(panel, 0.3)
	panel.position = Vector2(-width * 0.5, -120)
	return v

func _tile(icon_id: String, text: String, note: String, cb := Callable()) -> Control:
	var b := Button.new()
	b.text = text
	b.icon = P0Logic.icon(icon_id)
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 18)
	b.add_theme_font_size_override("font_size", 9)
	b.custom_minimum_size = Vector2(130, 40)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_button(b, PAPER, EDGE, 10)
	b.pressed.connect(func():
		if cb.is_valid(): cb.call()
		elif note != "": toast(note))
	return b

# ---------------------------------------------------------------- helpers
func _label(text: String, size: int, color: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if not bold:
		if _regular == null:
			_regular = FontVariation.new()
			_regular.base_font = load("res://assets/ui/fonts/Nunito.ttf")
			_regular.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
		l.add_theme_font_override("font", _regular)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _icon(id: String, side: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = P0Logic.icon(id)
	t.custom_minimum_size = Vector2(side, side)
	t.size = Vector2(side, side)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _box(bg: Color, radius: int, edge: Color, edge_w: int, pad4: Vector4, top_only := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(edge_w)
	if top_only:
		s.corner_radius_top_left = radius
		s.corner_radius_top_right = radius
	else:
		s.set_corner_radius_all(radius)
	s.content_margin_left = pad4.x
	s.content_margin_top = pad4.y
	s.content_margin_right = pad4.z
	s.content_margin_bottom = pad4.w
	return s

func _style_button(b: Button, bg: Color, edge: Color, radius: int) -> void:
	b.add_theme_stylebox_override("normal", _box(bg, radius, edge, 1, Vector4(8, 4, 8, 4)))
	b.add_theme_stylebox_override("hover", _box(bg.lightened(0.04), radius, edge, 1, Vector4(8, 4, 8, 4)))
	b.add_theme_stylebox_override("pressed", _box(bg.darkened(0.08), radius, edge, 1, Vector4(8, 4, 8, 4)))
	b.add_theme_stylebox_override("disabled", _box(DIS, radius, DIS, 1, Vector4(8, 4, 8, 4)))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_disabled_color", INK2)

func _pill_button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 32)
	b.add_theme_font_size_override("font_size", 11)
	if primary:
		_style_button(b, GREEN, GREEN_D, 16)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
	else:
		_style_button(b, PAPER, GREEN_D, 16)
	return b

func _flat_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_color_override("font_color", INK2)
	return b

# ---------------------------------------------------------------- small drawn widgets
class _TouchPad extends Control:
	## Scene area: a press-and-drag is the floating joystick (§10.1); a short tap picks a facility.
	var ui: P0Ui
	var _down := false
	var _start := Vector2.ZERO
	var _now := Vector2.ZERO
	var _t := 0
	var _id := -1
	const RADIUS := 43.0
	func _ready() -> void: mouse_filter = Control.MOUSE_FILTER_STOP
	func _gui_input(e: InputEvent) -> void:
		var pressed := false
		var released := false
		var pos := Vector2.ZERO
		if e is InputEventScreenTouch:
			if e.pressed and _id < 0:
				pressed = true
				_id = e.index
			elif not e.pressed and e.index == _id:
				released = true
				_id = -1
			pos = e.position
		elif e is InputEventScreenDrag and e.index == _id:
			_move(e.position)
			return
		elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			pressed = e.pressed
			released = not e.pressed
			pos = e.position
		elif e is InputEventMouseMotion and _down:
			_move(e.position)
			return
		if pressed:
			_down = true
			_start = pos
			_now = pos
			_t = Time.get_ticks_msec()
			queue_redraw()
		elif released and _down:
			_down = false
			ui.joystick.emit(Vector2.ZERO)
			if _now.distance_to(_start) < 12.0 and Time.get_ticks_msec() - _t < 350:
				ui.tapped.emit(pos)
			queue_redraw()
	func _move(p: Vector2) -> void:
		if not _down: return
		_now = p
		var v := (p - _start) / RADIUS
		if v.length() > 1.0: v = v.normalized()
		ui.joystick.emit(Vector2.ZERO if v.length() < 0.15 else v)
		queue_redraw()
	func _draw() -> void:
		if not _down or _now.distance_to(_start) < 12.0: return
		draw_circle(_start, RADIUS, Color(1, 1, 1, 0.35))
		draw_arc(_start, RADIUS, 0, TAU, 48, Color(0.37, 0.66, 0.35, 0.7), 2.0)
		var k := _start + ((_now - _start).limit_length(RADIUS))
		draw_circle(k, RADIUS * 0.45, Color(0.98, 0.97, 0.94, 0.95))
		draw_circle(k, RADIUS * 0.3, Color(0.5, 0.78, 0.42))

class _Fab extends Control:
	var ui: P0Ui
	func _ready() -> void: mouse_filter = Control.MOUSE_FILTER_STOP
	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
			ui._fab_pressed()
			accept_event()
	func _draw() -> void:
		var st: Dictionary = get_meta("state", {})
		var c := size * 0.5
		var fill := Color("fbf8f1")
		var ring := Color("7fc66a")
		if st.get("amber", false):
			fill = Color("fbf1da")
			ring = Color("e3b341")
		elif not st.get("enabled", false):
			fill = Color("eceae4")
			ring = Color("c4c2ba")
		draw_circle(c + Vector2(0, 2), size.x * 0.5, Color(0.18, 0.23, 0.2, 0.08))
		draw_circle(c, size.x * 0.5, fill)
		draw_arc(c, size.x * 0.5 - 1.3, 0, TAU, 64, ring, 2.6)

class _Slot extends Control:
	func _ready() -> void: mouse_filter = Control.MOUSE_FILTER_STOP
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(11)
		if get_meta("ghost", false):
			s.bg_color = Color(1, 1, 1, 0.25)
			s.border_color = Color("d9c7a6")
			s.set_border_width_all(1)
		elif get_meta("selected", false):
			s.bg_color = Color("fbf8f1")
			s.border_color = Color("5fa85a")
			s.set_border_width_all(2)
		else:
			s.bg_color = Color(0.984, 0.973, 0.945, 0.94)
			s.border_color = Color("e1dac8")
			s.set_border_width_all(1)
		draw_style_box(s, r)

class _AvatarRing extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.5 - 2
		draw_circle(c, r - 3, Color("e9d3b4"))
		draw_arc(c, r, -PI * 0.5, PI * 0.5, 32, Color(0.5, 0.78, 0.42, 0.28), 3.0)
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + PI * float(get_meta("farm", 0.0)), 32, Color("7fc66a"), 3.0)
		draw_arc(c, r, PI * 0.5, PI * 1.5, 32, Color(0.44, 0.66, 0.86, 0.28), 3.0)
		draw_arc(c, r, PI * 0.5, PI * 0.5 + PI * float(get_meta("fish", 0.0)), 32, Color("6fa8dc"), 3.0)
		draw_circle(c + Vector2(0, -3), r * 0.42, Color("8a5a3b"))

class _EnergyBar extends Control:
	func _draw() -> void:
		var pct := float(get_meta("pct", 1.0))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.18, 0.23, 0.2, 0.12))
		var col := Color("6cbf73") if pct >= 0.25 else (Color("e3b341") if pct >= 0.1 else Color("e07a5f"))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * pct, size.y)), col)

class _CapBar extends Control:
	func _draw() -> void:
		var pct := float(get_meta("pct", 0.0))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.18, 0.23, 0.2, 0.12))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * pct, size.y)), Color("e3b341") if pct >= 0.9 else Color("7fc66a"))
