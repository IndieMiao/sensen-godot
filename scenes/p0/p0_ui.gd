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
signal zoom(factor: float)
signal show_spot(where: String)
signal home_choice(choice: String)
signal recenter()
signal place_pressed()
signal home_requested()        # FISH-4 "Go home · Free"
signal tackle_requested()      # FISH-5 rod variant "Tackle Shop"

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
const DIS := Color("d6d5ce")
const SEA := Color("cfe3ee")        # Old Kai's role colour (tackle · sea blue)
const SEA_LIGHT := Color("e3eff5")
const GOLD := Color("e9c35e")        # kit-cook --gold-light → --gold
const GOLD_D := Color("c9962a")
const RED := Color("e07a5f")         # --energy-red
const XP := Color("1f8c88")          # --xp-deep (floating XP)
var quick_store := "user://p0_quickbar.json"   # per-action pins / removals (tests point it elsewhere)
const _KEY_ABOVE_BAR := 40.0        # BAR-1 482:18: ActionKey bottom at y 668, quick bar top at 708
const _BADGE_CARD_GAP := 4.0        # a finger card over a facility that also shows a badge sits this far above it

var view: Dictionary = {}
var root: Control
var pad: Control
var hud: UiHud                   # two-row HUD (SGODOT-222, LOCK-06)
var _place_text := "Shanghai · Homestead"
var _fab_state: Dictionary = {}
var fab_held := false            # §14.2: hold the main action to keep sowing along a row
var fab_verb := ""
## SGODOT-221 world controls (UI kit, own theme layer): quick bar, action key group, radial, finger cards, badges.
var _kit: Control
var _bar: UiQuickBar
var _keys: UiActionKey
var _radial: UiActionRadial
var _pin_menu: UiPinMenu
var _cards := {}          # id -> UiTapCard
var _card_hits := {}      # id -> screen point a tap on the card forwards to the world (the facility's own tap point)
var _badges := {}         # id -> UiStatusBadge
var _quick := {}          # per action: {pins: [], removed: []}, saved in quick_store (LOCK-05: 每个行动各记各的)
var _bar_sig := []        # last state pushed to the bar, so the per-frame refresh only rebuilds on change
var _auto_pick := true    # pick the first slot once when an action is entered (§10.3.3 ①), not after a deselect
## MAP-1 keeps only Bag at the bottom of the map. The P0 map still carries the old Map / Farm / Me dock and its
## zoom column where Bag would sit, so the map turns this on when that dock leaves (with the new HUD, SGODOT-222).
## TODO(MAP-1, follow-up PR after #11 and #12, reviewed by 刘邦): p0_map drops the old dock and sets map_bag = true.
## Not part of PR #12 (奕星 2026-10-08).
var map_bag := false
var _bar_ids: Array = []
var selected_seed := ""
var selected_bait := ""
## Where Old Kai keeps shop (a fixed map place since ponds moved to the map).
var tackle_place := "Reed Pond"
var bar_mode := "farm"          # "farm" (seeds) or "fish" (bait) — the quick bar holds the current action's consumables
var surface := "farm"
## Set by the runtime: true when the current world can move its camera to a spot (p0_show_spot). Show
## buttons (Today, NeedSource) only appear then, so a Show never closes a panel and does nothing (LOCK-08).
var can_show_spot := Callable()
var _hud_world := true   # set_surface: the map has no HUD
var _hud_hash := 0       # last state given to hud.apply
var _hud_need := -1      # main action's Energy need last seen by the HUD
var _pending := {}   # surface / place / mode set before the HUD exists (the runtime attaches early)
var _dev_box: Control
var _creel: PanelContainer
var _creel_count: Label
var _creel_free: Label
var _fab_pills: HBoxContainer
var player_screen := Vector2(180, 320)   # set by the farm / pond each frame (mid-body): the radial fans out from it
var _modal: Control
var modal_kind := ""            # "stall", "bag", "kitchen", "card", ... — which drawer is open
var _kitchen_tab := "cookbook"
var _exp_slots: Array = []      # Experiment tab: ids placed in the pot
var _card_queue: Array = []
var _teach: PanelContainer
var _teach_left := 0.0
var _taught := {}
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
	# App copy is English-only (user rule 2026-09-04): keep the Localization autoload from translating P0 labels.
	root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
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
	_toast.position = Vector2(-150, 150)
	_toast.custom_minimum_size = Vector2(300, 0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.hide()
	root.add_child(_toast)
	if OS.is_debug_build(): _build_dev()
	if _pending.has("mode"): set_mode(_pending.mode)
	if _pending.has("place"): set_place(_pending.place)
	set_surface(_pending.get("surface", surface))
	_pending.clear()

func _process(dt: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= dt
		if _toast_left <= 0.0: _toast.hide()
	if _teach_left > 0.0:
		_teach_left -= dt
		if _teach_left <= 0.0 and _teach: _teach.hide()

func _build_hud() -> void:
	hud = UiHud.new()
	hud.theme = UiKit.theme()
	hud.safe_top = safe_top()
	# TODO(SGODOT-225, Profile page): the avatar opens Profile (LOCK-06); P0 opens Skills until then.
	hud.avatar_pressed.connect(open_skills)
	hud.energy_pressed.connect(open_energy_panel)
	hud.inbox_pressed.connect(open_inbox)
	hud.today_pressed.connect(open_today)
	hud.place_pressed.connect(func(): place_pressed.emit())   # the location chip is the way back to the map
	root.add_child(hud)
	_creel = PanelContainer.new()
	_creel.add_theme_stylebox_override("panel", _box(CARD, 11, EDGE, 1, Vector4(6, 3, 8, 3)))
	_creel.position = Vector2(UiTokens.SIZE_TODAY_PANEL_X, UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + UiTokens.SPACE_WITHIN + safe_top())   # under the two-row HUD
	var crh := HBoxContainer.new()
	crh.add_theme_constant_override("separation", 4)
	crh.add_child(_icon("creel", 11))
	_creel_count = _label("Creel 0", 9, INK, true)
	crh.add_child(_creel_count)
	crh.add_child(_label("·", 9, INK2, true))
	_creel_free = _label("0 free", 9, GREEN_D, true)
	crh.add_child(_creel_free)
	_creel.add_child(crh)
	_creel.hide()
	_creel.mouse_filter = Control.MOUSE_FILTER_STOP
	_creel.gui_input.connect(func(e: InputEvent):
		if P0Ui.is_tap(e): open_fishdex())
	root.add_child(_creel)

func _build_bar() -> void:
	# Phase 1A world controls (SGODOT-221) sit in their own layer with the UI kit theme; the other P0 panels
	# keep the old GameUi theme until phase 2 rebuilds them.
	_kit = Control.new()
	_kit.theme = UiKit.theme()
	_kit.set_anchors_preset(Control.PRESET_FULL_RECT)
	_kit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_kit)
	_load_quick()
	_bar = UiQuickBar.new()
	_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_kit.add_child(_bar)
	_bar.slot_tapped.connect(_on_slot_tapped)
	_bar.ghost_tapped.connect(func(_i: int): open_bag())
	_bar.pin_toggled.connect(_on_pin_toggled)
	_bar.slots_swapped.connect(_on_slots_swapped)
	_bar.slot_removed.connect(_on_slot_removed)
	_bar.bag_requested.connect(func(): open_bag())
	_bar.close_requested.connect(close_modal)
	_bar.handle_tapped.connect(open_radial)

func _build_fab() -> void:
	_keys = UiActionKey.new()
	_keys.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_kit.add_child(_keys)
	# Touch-down fires like the shipped key; holding keeps fab_held up so the farm repeats along a row (§14.2).
	_keys.key().pressed_down.connect(func():
		fab_held = true
		_fab_pressed())
	_keys.key().released.connect(func(): fab_held = false)
	_keys.switch_pressed.connect(open_radial)
	_keys.tool_icon = P0Logic.icon("rod" if bar_mode == "fish" else "hoe")   # set_mode skips the mode it starts in
	_radial = UiActionRadial.new()
	_kit.add_child(_radial)
	_radial.picked.connect(func(id: String): if id != bar_mode: set_mode(id))
	# FISH-4: two pills above the switch key while the creel is full.
	_fab_pills = HBoxContainer.new()
	_fab_pills.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fab_pills.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fab_pills.add_theme_constant_override("separation", 5)
	var open_bag_pill := _pill_button("Open Bag", false)
	open_bag_pill.pressed.connect(func(): open_bag())
	var home_pill := _pill_button("Go home · Free", false)
	_style_button(home_pill, PAPER, EDGE, 16)
	home_pill.pressed.connect(func(): home_requested.emit())
	for b in [open_bag_pill, home_pill]:
		b.add_theme_font_size_override("font_size", 10)
		b.custom_minimum_size = Vector2(0, 32)
		_fab_pills.add_child(b)
	_fab_pills.hide()
	root.add_child(_fab_pills)
	_place_controls()

## Bottom controls per BAR-1: bar at x 12, 24 above the safe bottom; the action group 16 from the right edge,
## 40 above the bar; the creel pills 8 above the group.
func _place_controls() -> void:
	var bottom := UiTokens.SIZE_QUICK_BAR_BOTTOM + safe_bottom()
	_bar.offset_left = UiTokens.SIZE_QUICK_BAR_X
	_bar.offset_right = UiTokens.SIZE_QUICK_BAR_X + UiTokens.SIZE_QUICK_BAR_W
	_bar.offset_bottom = -bottom
	_bar.offset_top = -bottom - UiTokens.SIZE_QUICK_BAR_H
	var key_bottom := bottom + UiTokens.SIZE_QUICK_BAR_H + _KEY_ABOVE_BAR
	_keys.offset_right = -UiTokens.SPACE_PAGE
	_keys.offset_left = -UiTokens.SPACE_PAGE - UiTokens.SIZE_ACTION_KEY_W
	_keys.offset_bottom = -key_bottom
	_keys.offset_top = -key_bottom - UiTokens.SIZE_ACTION_KEY_H
	if _teach:
		# The one-line teaching card sits above the quick bar and left of the action key group, clear of both
		# (PR #12 review fix 5), with the safe area already in `bottom`.
		_teach.offset_left = UiTokens.SPACE_PAGE
		_teach.offset_right = -(UiTokens.SPACE_PAGE + UiTokens.SIZE_ACTION_KEY_W + UiTokens.SPACE_OVERLAY_BODY)
		_teach.offset_bottom = -(bottom + UiTokens.SIZE_QUICK_BAR_H + UiTokens.SPACE_OVERLAY_BODY)
		_teach.offset_top = _teach.offset_bottom
	var pills_bottom := key_bottom + UiTokens.SIZE_ACTION_KEY_H + UiTokens.SPACE_OVERLAY_BODY
	_fab_pills.offset_right = -UiTokens.SPACE_PAGE
	_fab_pills.offset_left = -UiTokens.SPACE_PAGE - 1
	_fab_pills.offset_bottom = -pills_bottom
	_fab_pills.offset_top = -pills_bottom - 32

func _build_dev() -> void:
	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.position = Vector2(-96, 118 + safe_top())   # debug time skips, kept under the HUD on notched screens
	box.add_theme_constant_override("separation", 4)
	for m in [60, 240]:
		var b := _pill_button("+%dh" % (m / 60), false)
		b.custom_minimum_size = Vector2(42, 22)
		b.add_theme_font_size_override("font_size", 9)
		b.pressed.connect(func(): dev_skip.emit(m))
		box.add_child(b)
	root.add_child(box)
	_dev_box = box

# ---------------------------------------------------------------- refresh
func set_view(v: Dictionary) -> void:
	view = v
	_refresh_hud()
	_refresh_bar()

func _skill_pct(s: Dictionary) -> float: return P0Logic.skill_progress(s)

## HUD from the view, the next action's cost (Low = short of it) and where the player actually is: the
## kitchen is the farmhouse's stove corner, so the chip reads "Shanghai · Farmhouse" there (LOCK-06).
func _refresh_hud() -> void:
	if hud == null: return
	# No HUD before the first server view: an empty view would read as 0 Energy (red) and 0 coins, and its
	# chips would still take taps.
	hud.visible = _hud_world and not view.is_empty()
	if view.is_empty(): return
	var place := P0Logic.place_info(_place_text, "Farmhouse" if modal_kind == "kitchen" else "")
	var state := P0Logic.hud_state(view, {"next_cost": int(fab_state().get("need", 0)), "place": place})
	var h := state.hash()
	if h == _hud_hash: return   # set_view runs every frame: apply only what changed (the countdown, once a second)
	_hud_hash = h
	hud.apply(state)

## Top system inset (status bar, notch) in UI units; 0 on desktop.
func safe_top() -> float:
	if not (OS.has_feature("android") or OS.has_feature("ios")): return 0.0
	return UIMetrics.safe_margins(DisplayServer.get_display_safe_area(), DisplayServer.window_get_size(),
		get_viewport().get_visible_rect().size, 0.0).y

## The HUD's location chip and its coins / bell corner, for worlds that dock their own controls there.
func place_chip_rect() -> Rect2: return hud.place_chip_rect() if hud else Rect2()
func hud_corner_rect() -> Rect2: return hud.balances_rect() if hud else Rect2()

## Pond vs. plots: place chip, creel badge, fab badge and quick-bar contents follow where the player stands.
## Full place chip text: "City · Space" (Shanghai · Homestead / Shanghai · Willow Pond / … · Kitchen).
func set_place(text: String) -> void:
	if not is_node_ready():
		_pending["place"] = text
		return
	_place_text = text
	_refresh_hud()

## Which world the HUD sits on (§10.2.4): action spaces show everything; rooms are facility spaces
## (no quick bar, main action or switch key); the map shows only toasts and cards.
func set_surface(name: String) -> void:
	surface = name
	if not is_node_ready():
		_pending["surface"] = name
		return
	var action := name in ["farm", "pond"]
	var world := name != "map"
	_hud_world = world
	hud.visible = world and not view.is_empty()
	hud.show_balances = name != "busy"   # a busy world's own close button sits in the coins / bell corner
	pad.visible = world
	_keys.visible = action and _modal == null
	_fab_pills.visible = _keys.visible and bool(_fab_state.get("creel_full", false))
	_bar.visible = _bar_shown() and _modal == null
	_bar.bag_only = not action
	_bar_sig = []
	if _radial.visible: _radial.close()
	_close_pin_menu()   # no PinMenu left over when fishing starts or the map opens (PR #12 review)
	_creel.visible = action and bar_mode == "fish"
	if _dev_box: _dev_box.visible = world
	for c in _cards.values(): (c as Control).visible = false
	for b in _badges.values(): (b as Control).visible = false

## Action spaces show the full bar. Rooms (farmhouse kitchen, outposts) and the map keep only Bag, with no action
## or switch key (MAP-1, §10.3.5, o(8)); the map waits for map_bag. Busy worlds hide it.
func _bar_shown() -> bool:
	return surface in ["farm", "pond", "room"] or (surface == "map" and map_bag)

func set_mode(mode: String, place := "") -> void:
	if place != "": set_place(place)
	if not is_node_ready():
		_pending["mode"] = mode
		return
	if mode == bar_mode: return
	bar_mode = mode
	_bar_ids = []
	_bar_sig = []
	_auto_pick = true
	_keys.tool_icon = P0Logic.icon("rod" if mode == "fish" else "hoe")
	_creel.visible = mode == "fish"
	_refresh_bar()

func _refresh_bar() -> void:
	var store := _quick_for(bar_mode)
	var ids := P0Logic.quick_bar(view, _bar_ids, bar_mode, store.pins, store.removed)
	if bar_mode == "fish":
		if selected_bait != "" and not ids.has(selected_bait): selected_bait = ""
		# The last bait went on a hook: the slot stays pinned at 0, the hook goes empty (李白 q(44) ④).
		if selected_bait != "" and P0Logic.bag_count(view, selected_bait) <= 0:
			toast("Out of %s · no bait on the hook" % P0Logic.item_name(view, selected_bait))
			selected_bait = ""
		var free := int(view.get("bag", {}).get("free", 0))
		_creel_count.text = P0Logic.creel_line(view).get_slice(" · ", 0)
		_creel_free.text = "%d free" % free
		var full := free < 1
		_creel_free.add_theme_color_override("font_color", RED if full else GREEN_D)
		_creel.add_theme_stylebox_override("panel", _box(GOLD if full else CARD, 11, GOLD_D if full else EDGE, 1, Vector4(6, 3, 8, 3)))
	else:
		if selected_seed != "" and not ids.has(selected_seed): selected_seed = ""
		# A pinned seed sown to 0 stays on the bar but is deselected: the key reads Sow · Pick a seed and a held
		# row stops there (李白 q(44) ③, PR #12 review fix 2).
		if selected_seed != "" and P0Logic.bag_count(view, selected_seed) <= 0:
			selected_seed = ""
			seed_selected.emit("")
		# First slot on entering the action (§10.3.3 ①); a deliberate deselect stays deselected.
		var stocked := ids.filter(func(id): return P0Logic.bag_count(view, str(id)) > 0)
		if _auto_pick and selected_seed == "" and not stocked.is_empty():
			selected_seed = str(stocked[0])
			seed_selected.emit(selected_seed)
		if not ids.is_empty(): _auto_pick = false
	_bar_ids = ids
	var bag: Dictionary = view.get("bag", {})
	var counts := ids.map(func(id): return P0Logic.bag_count(view, str(id)))
	var used := _bag_slots().size()
	var sig := [bar_mode, ids, counts, store.pins.duplicate(), selected_bait if bar_mode == "fish" else selected_seed,
		used * 10 >= int(bag.get("capacity", 25)) * 9, modal_kind in ["bag", "gear"]]
	if sig == _bar_sig: return
	_bar_sig = sig
	var slots := []
	for i in ids.size():
		var id := str(ids[i])
		slots.append({id = id, icon = P0Logic.icon(id), title = P0Logic.item_name(view, id), quantity = counts[i], pinned = store.pins.has(id)})
	# A-08 ghost: a bar holding nothing of the action's family shows it in the first empty slot; a tap opens the
	# Bag (ghost_tapped). TODO(SGODOT-225 bag drawer): open on the family tab (Seeds → Seeds, Bait → Tackle) and
	# flash the slot 600 ms when a real item lands.
	var family: Array = ["bait_", "bait_worm", "Bait"] if bar_mode == "fish" else ["seed_", "seed_radish", "Seeds"]
	if slots.size() < UiQuickBar.SLOTS and not ids.any(func(id): return str(id).begins_with(family[0])):
		slots.append({ghost = true, icon = P0Logic.icon(family[1]), title = family[2]})
	_bar.slots = slots
	_bar.selected = sig[4]
	_bar.capacity_warning = sig[5]
	_bar.bag_open = sig[6]

func _on_slot_tapped(id: String) -> void:
	# A slot at 0 can't be picked; a light buzz says so (李白 q(44) ③), and a toast too: the release Journey build
	# has no vibrate permission (PR #12 re-review). The copy is the slot's refill hint (§10.3.3).
	if P0Logic.bag_count(view, id) <= 0 and id != selected_seed and id != selected_bait:
		if _bar.haptics and OS.has_feature("mobile"): Input.vibrate_handheld(10)
		toast("Buy at Homestead Stall")
		return
	if bar_mode == "fish":
		# Tapping bait only sets the current bait (0 Energy, nothing consumed); tap again to fish without bait.
		selected_bait = "" if selected_bait == id else id
		toast(("%s on the hook · used at the bite" % P0Logic.item_name(view, id)) if selected_bait != "" else "No bait")
	else:
		# Select, tap again to clear (§10.3.4); the main action then asks for a seed.
		selected_seed = "" if selected_seed == id else id
		seed_selected.emit(selected_seed)
	_refresh_bar()

func _on_pin_toggled(id: String, pinned: bool) -> void:
	_set_pin(id, pinned)
	_show_pin_menu(id, pinned)

func _set_pin(id: String, pinned: bool) -> void:
	var store := _quick_for(bar_mode)
	store.pins.erase(id)
	if pinned:
		store.pins.append(id)
		store.removed.erase(id)
	_save_quick()
	_refresh_bar()

## Drag onto another slot: the two swap places and both become pinned (§10.3.4).
func _on_slots_swapped(a: int, b: int) -> void:
	while _bar_ids.size() <= maxi(a, b): _bar_ids.append("")
	var t = _bar_ids[a]
	_bar_ids[a] = _bar_ids[b]
	_bar_ids[b] = t
	var store := _quick_for(bar_mode)
	for id in [_bar_ids[a], _bar_ids[b]]:
		if str(id) != "" and not store.pins.has(id): store.pins.append(id)
	_bar_ids = _bar_ids.filter(func(id): return str(id) != "")
	_save_quick()
	_refresh_bar()

## Fling off the bar: gone from the bar, still in the bag (§10.3.4); not refilled until pinned again.
func _on_slot_removed(id: String) -> void:
	var store := _quick_for(bar_mode)
	store.pins.erase(id)
	if not store.removed.has(id): store.removed.append(id)
	_bar_ids.erase(id)
	if selected_seed == id: selected_seed = ""
	if selected_bait == id: selected_bait = ""
	_save_quick()
	_refresh_bar()

## PinMenu over the slot a long press just toggled (LOCK-05): the new state and the reverse in one tap.
func _show_pin_menu(id: String, pinned: bool) -> void:
	if _pin_menu: _pin_menu.queue_free()
	_pin_menu = UiPinMenu.new(pinned)
	_kit.add_child(_pin_menu)
	var i := _bar_ids.find(id)
	var cell := _bar.cells()[clampi(i, 0, UiQuickBar.SLOTS - 1)]
	var tip := cell.get_global_rect().get_center().x - _kit.global_position.x
	var size := _pin_menu.get_combined_minimum_size()
	var x := clampf(tip - UiPinMenu.POINTER_TIP_X, UiTokens.SPACE_PAGE, _kit.size.x - UiTokens.SPACE_PAGE - size.x)
	_pin_menu.position = Vector2(x, _bar.position.y - size.y - UiTokens.SPACE_WITHIN)
	_pin_menu.pointer_x = tip - x - UiTokens.SIZE_POINTER_W * 0.5
	_pin_menu.toggled.connect(func():
		_set_pin(id, not pinned)
		_close_pin_menu())
	_pin_menu.dismissed.connect(_close_pin_menu)

func _close_pin_menu() -> void:
	if _pin_menu: _pin_menu.queue_free()
	_pin_menu = null

func _quick_for(mode: String) -> Dictionary:
	if not _quick.has(mode): _quick[mode] = {pins = [], removed = []}
	return _quick[mode]

func _load_quick() -> void:
	if not FileAccess.file_exists(quick_store): return
	var data = JSON.parse_string(FileAccess.get_file_as_string(quick_store))
	if not data is Dictionary: return
	for mode in data:
		var d: Dictionary = data[mode]
		_quick[mode] = {pins = Array(d.get("pins", [])), removed = Array(d.get("removed", []))}

func _save_quick() -> void:
	var f := FileAccess.open(quick_store, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(_quick))

## Main action key from P0Logic.main_action() / fish_action() (LOCK-02).
## TODO(SGODOT-221 → stage 3, F-08 command lifecycle): drive HOLDING (hold_progress) and PENDING from the command
## queue; P0 has no source for them yet.
func set_action(a: Dictionary) -> void:
	_fab_state = a
	var k := _keys.key()
	k.verb = str(a.get("verb", ""))
	var sub := str(a.get("sub", ""))
	# Zero-Energy actions carry no price (LOCK-02 "0 体力的动作不写价"); reasons and costs stay.
	k.cost = "" if int(a.get("need", 0)) == 0 and sub == "Free" else sub
	if a.get("amber", false): k.state = UiSceneAction.State.INSUFFICIENT
	elif not a.get("enabled", false): k.state = UiSceneAction.State.UNAVAILABLE
	else: k.state = UiSceneAction.State.DEFAULT
	_fab_pills.visible = bool(a.get("creel_full", false)) and _keys.visible
	var need := int(a.get("need", 0))
	if need != _hud_need:   # the worlds call set_action every frame
		_hud_need = need
		_refresh_hud()   # SGODOT-222: the Energy chip turns Low when short of this action

func _fab_pressed() -> void:
	fab_verb = ""
	if not _fab_state.get("enabled", false) or _modal != null: return
	fab_verb = str(_fab_state.get("verb", ""))
	action_pressed.emit(_fab_state.get("cmd", {}))

## While held, the farm repeats the action for each new plot with the same verb.
func fab_state() -> Dictionary: return _fab_state

# ---------------------------------------------------------------- world tags & floats
## Facility finger card (TapCard 1135:101133, LOCK-07 / LOCK-17): bottom centre `SPACE_WITHIN` above `screen`,
## kept inside the screen with its pointer still on the facility. Tapping the card is tapping the facility: it
## forwards `hit` (the facility's own tap point; defaults to `screen`) to the world as a tap. The card is passive:
## the scene pad under it gets the press, so a drag that starts on a card is the joystick, and only the pad's real
## tap (GestureArbiter thresholds) on the card's 44 px hit rect counts (_tap_at, PR #12 review fix 3).
func tag(id: String, text: String, screen: Vector2, show: bool, hit := Vector2.INF) -> void:
	var c: UiTapCard = _cards.get(id)
	if c == null:
		c = UiTapCard.new()
		c.passive = true
		_kit.add_child(c)
		_kit.move_child(c, 0)
		_cards[id] = c
	c.visible = show and _modal == null
	if not c.visible: return
	_card_hits[id] = screen if hit == Vector2.INF else hit
	c.text = text
	_place_marker(c, screen, true)

## Facility / resident state mark (StatusBadge 1132:79554, STATE-ICONS): display only, the facility takes the tap.
## A scene tap: on a shown finger card it is that facility's tap, elsewhere the world's (also a double tap: a card
## never recenters the camera by accident). Returns true for a card tap, which then can't start a double tap either.
func _tap_at(global_pos: Vector2, double: bool) -> bool:
	for id in _cards:
		var c: UiTapCard = _cards[id]
		if c.is_visible_in_tree() and c.hit_rect().has_point(global_pos):
			if _modal == null: tapped.emit(_card_hits[id])
			return true
	if double: recenter.emit()
	else: tapped.emit(global_pos - root.global_position)
	return false

func badge(id: String, state: UiStatusBadge.State, screen: Vector2, show: bool, caption := "", icon: Texture2D = null) -> void:
	var b: UiStatusBadge = _badges.get(id)
	if b == null:
		b = UiStatusBadge.new()
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_kit.add_child(b)
		_kit.move_child(b, 0)
		_badges[id] = b
	b.visible = show and _modal == null
	if not b.visible: return
	b.state = state
	b.caption = caption
	b.icon = icon
	_place_marker(b, screen, false)

## Height a shown badge takes over `screen`, so a finger card over the same facility can sit above it.
func badge_height(id: String) -> float:
	var b: UiStatusBadge = _badges.get(id)
	return b.get_combined_minimum_size().y + _BADGE_CARD_GAP if b and b.visible else 0.0

## Finger cards stay on screen (their facility is near, so on screen); a badge over an off-screen facility hides.
func _place_marker(m: Control, screen: Vector2, clamp_inside: bool) -> void:
	var size := m.get_combined_minimum_size()
	var area := Rect2(Vector2.ZERO, _kit.size)
	var r := WorldAnchor.place(size, screen - Vector2(0, UiTokens.SPACE_WITHIN), area, UiTokens.SPACE_WITHIN, clamp_inside)
	m.visible = r.has_area()
	if not m.visible: return
	m.size = size
	m.position = r.position
	if m.has_method(&"point_at"): m.point_at(screen.x - r.position.x)

