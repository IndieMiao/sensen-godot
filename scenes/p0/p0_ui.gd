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
## A pinch step about a screen point (the two-finger centre, or the mouse for a wheel tick).
signal zoom(factor: float, at: Vector2)
## The fingers lifted after a pinch (or a wheel tick ended): the scene springs back if past a zoom limit.
signal zoom_end
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
const ACTION_SURFACES := ["farm", "pond", "mine"]   # spaces with the action key group (SGODOT-231: the mine, Mining)
## A-08 ghost slot per action: [id prefix of the family, ghost icon, noun] (q(44): Seeds / Bait / Torch in P0).
const GHOST_FAMILY := {
	"farm": ["seed_", "seed_radish", "Seeds"],
	"fish": ["bait_", "bait_worm", "Bait"],
	"mine": ["torch", "torch", "Torch"],
}

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
var _undo_toast: UiUndoToast
var _cards := {}          # id -> UiTapCard
var _card_hits := {}      # id -> screen point a tap on the card forwards to the world (the facility's own tap point)
var _badges := {}         # id -> UiStatusBadge
## The finger card a `tapped` comes from, only while that signal is being handled ("" for a scene tap).
var tapped_card := ""
var _quick := {}          # per action: {pins: [], removed: []}, saved in quick_store (LOCK-05: 每个行动各记各的)
var _bar_sig := []        # last state pushed to the bar, so the per-frame refresh only rebuilds on change
var _auto_pick := true    # pick the first slot once when an action is entered (§10.3.3 ①), not after a deselect
var _mode_tool: Texture2D  # the current action's own tool icon for the key badge (set_action `tool` overrides per key)
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
var _status: PanelContainer     # SGODOT-231 mine status line (Rocks 2/6), where the creel sits while fishing
var _status_text: Label
var player_screen := Vector2(180, 320)   # set by the farm / pond each frame (mid-body): the radial fans out from it
var _modal: Control
var modal_kind := ""            # "stall", "bag", "kitchen", "card", ... — which drawer is open
var _kitchen_tab := "cookbook"
var _exp_slots: Array = []      # Experiment tab: ids placed in the pot
var _card_queue: Array = []
var _teach: PanelContainer
var _teach_left := 0.0
var tips: P0Guide.TipQueue   # the TipCard order and "shown before" (SGODOT-232 U6)
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
	if _pending.has("status"): set_status_line(_pending.status)
	_pending.clear()

func _process(dt: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= dt
		if _toast_left <= 0.0: _toast.hide()
	if _teach_left > 0.0:
		_teach_left -= dt
		if _teach_left <= 0.0: _hide_tip()
	# q(49): a waiting TipCard comes up only when no RewardMoment / result card is on screen; one already up stays.
	# TODO(SGODOT-232 U6): call tips.moment_opened / moment_closed from UiRewardMoment / MomentBanner once #24 lands;
	# until then the result cards (modal_kind "card") stand in for them.
	if tips and modal_kind != "card":
		var key := tips.next()
		if key != "": _show_tip(str(P0Guide.TIPS[key]))

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
	_status = PanelContainer.new()
	_status.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CHIP,
		UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT).with_margins(8, 3, 8, 3))
	_status.position = _creel.position
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_text = UiKit.label("", UiTokens.STYLE_C11_XB)
	_status.add_child(_status_text)
	_status.hide()
	_kit.add_child(_status)   # kit theme for the C11XB type style

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
	_mode_tool = P0Logic.icon("rod" if bar_mode == "fish" else "hoe")   # set_mode skips the mode it starts in
	_keys.tool_icon = _mode_tool
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

## One status line under the HUD where the creel sits while fishing (SGODOT-231: the mine's "Rocks 2/6", "Run 1/2
## today" for its first 3 s). "" hides it; changing action clears it.
func set_status_line(text: String) -> void:
	if not is_node_ready():
		_pending["status"] = text   # the mine sets it on its first frame, maybe before the HUD exists (苏烈, #39)
		return
	if _status_text.text != text: _status_text.text = text
	_status.visible = text != "" and surface in ACTION_SURFACES

## Which world the HUD sits on (§10.2.4): action spaces show everything; rooms are facility spaces
## (no quick bar, main action or switch key); the map shows only toasts and cards.
func set_surface(name: String) -> void:
	surface = name
	if not is_node_ready():
		_pending["surface"] = name
		return
	var action := name in ACTION_SURFACES
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
	_bar.cancel_drag()   # no lifted slot or drop zones left over when fishing starts or the map opens
	_creel.visible = action and bar_mode == "fish"
	_status.visible = action and _status_text.text != ""
	if _dev_box: _dev_box.visible = world
	for c in _cards.values(): (c as Control).visible = false
	for b in _badges.values(): (b as Control).visible = false
	_flush_held_toast()

## Action spaces show the full bar. Rooms (farmhouse kitchen, outposts) and the map keep only Bag, with no action
## or switch key (MAP-1, §10.3.5, o(8)); the map waits for map_bag. Busy worlds hide it.
func _bar_shown() -> bool:
	return surface in ACTION_SURFACES or surface == "room" or (surface == "map" and map_bag)

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
	# SGODOT-231: the mine shows the pickaxe; set_action's `tool` swaps in the equipped one.
	_mode_tool = P0Logic.icon("rod" if mode == "fish" else "pickaxe" if mode == "mine" else "hoe")
	_keys.tool_icon = _mode_tool
	_creel.visible = mode == "fish"
	set_status_line("")
	_refresh_bar()

func _refresh_bar() -> void:
	var store := _quick_for(bar_mode)
	# SGODOT-231: Mining's bar holds only what helps underground (a torch); seeds and bait never show there.
	var ids := P0MaterialLogic.mine_bar(view, _bar_ids, store.pins, store.removed) if bar_mode == "mine" \
		else P0Logic.quick_bar(view, _bar_ids, bar_mode, store.pins, store.removed)
	if bar_mode == "fish":
		if selected_bait != "" and not ids.has(selected_bait): selected_bait = ""
		# The last bait went on a hook: the slot stays pinned at 0, the hook goes empty (李白 q(44) ④).
		if selected_bait != "" and P0Logic.bag_count(view, selected_bait) <= 0:
			toast_when_clear("Out of %s · no bait on the hook" % P0Logic.item_name(view, selected_bait))
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
		# First slot on entering the action (§10.3.3 ①); a deliberate deselect stays deselected. Farming only: a
		# torch is chosen on purpose, like bait (§13.3.8: the key stays Mine).
		var stocked := ids.filter(func(id): return str(id) != "" and P0Logic.bag_count(view, str(id)) > 0)
		if _auto_pick and bar_mode == "farm" and selected_seed == "" and not stocked.is_empty():
			selected_seed = str(stocked[0])
			seed_selected.emit(selected_seed)
		if ids.any(func(id): return str(id) != ""): _auto_pick = false
	_bar_ids = ids
	var bag: Dictionary = view.get("bag", {})
	var counts := ids.map(func(id): return P0Logic.bag_count(view, str(id)) if str(id) != "" else 0)
	var used := _bag_slots().size()
	var sig := [bar_mode, ids, counts, store.pins.duplicate(), selected_bait if bar_mode == "fish" else selected_seed,
		used * 10 >= int(bag.get("capacity", 25)) * 9, modal_kind in ["bag", "gear"]]
	if sig == _bar_sig: return
	_bar_sig = sig
	var slots := []
	for i in ids.size():
		var id := str(ids[i])
		if id == "": slots.append({})   # a gap left by a drag-remove (LOCK-05 v1.10): no item, no pin
		else: slots.append({id = id, icon = P0Logic.icon(id), title = P0Logic.item_name(view, id), quantity = counts[i], pinned = store.pins.has(id)})
	# A-08 ghost (LOCK-04): a bar with nothing of this action in stock shows the action's family in the first empty
	# slot; a slot pinned at 0 is not stock (int5b hand test 9), Compost alone is. The first gap a drag-remove left
	# takes it (LOCK-05 v1.10), else the free end; five occupied slots leave no room, so no ghost. A tap opens the Bag
	# (ghost_tapped). TODO(SGODOT-225 bag drawer): open on the family tab (Seeds → Seeds, Bait → Tackle).
	var family: Array = GHOST_FAMILY.get(bar_mode, GHOST_FAMILY.farm)   # q(44): Seeds / Bait / Torch
	if not counts.any(func(n): return int(n) > 0):
		var ghost := {ghost = true, icon = P0Logic.icon(family[1]), title = family[2]}
		var gap := slots.find({})
		if gap >= 0: slots[gap] = ghost
		elif slots.size() < UiQuickBar.SLOTS: slots.append(ghost)
	_bar.slots = slots
	_bar.selected = sig[4]
	_bar.capacity_warning = sig[5]
	_bar.bag_open = sig[6]

func _on_slot_tapped(id: String) -> void:
	# A slot at 0 can't be picked; a light buzz says so (李白 q(44) ③), and a toast too: the release Journey build
	# has no vibrate permission (PR #12 re-review). The copy is the slot's refill hint (§10.3.3).
	if P0Logic.bag_count(view, id) <= 0 and id != selected_seed and id != selected_bait:
		if _bar.haptics and OS.has_feature("mobile"): Input.vibrate_handheld(10)
		toast("Craft at Workbench" if bar_mode == "mine" else "Buy at Homestead Stall")   # q(44) refill hints
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

## Dropped on the Pin / Unpin zone (LOCK-05 v1.11): the pin flips; the bar pops the badge, no PinMenu, no toast.
func _on_pin_toggled(id: String, pinned: bool) -> void:
	_set_pin(id, pinned)

func _set_pin(id: String, pinned: bool) -> void:
	var store := _quick_for(bar_mode)
	store.pins.erase(id)
	if pinned:
		store.pins.append(id)
		store.removed.erase(id)
	_save_quick()
	_refresh_bar()

## Drag onto another slot: the two swap places only; pins follow their items, nothing is pinned by it and no menu
## shows (LOCK-05 v1.11, 221 b0a83924). Onto a gap it simply moves there.
func _on_slots_swapped(a: int, b: int) -> void:
	while _bar_ids.size() <= maxi(a, b): _bar_ids.append("")
	var t = _bar_ids[a]
	_bar_ids[a] = _bar_ids[b]
	_bar_ids[b] = t
	_save_quick()
	_refresh_bar()

## Dropped on the remove zone: off the bar, still in the Bag (§10.3.4); its slot stays a gap, nothing refills it
## (LOCK-05 v1.10 BAR-DRAG-4), and an Info toast `<Item> off the bar · Undo` (5 s) puts it back, pin and place.
func _on_slot_removed(id: String) -> void:
	var store := _quick_for(bar_mode)
	var was := {id = id, index = _bar_ids.find(id), pinned = store.pins.has(id), mode = bar_mode}
	store.pins.erase(id)
	if not store.removed.has(id): store.removed.append(id)
	if was.index >= 0: _bar_ids[was.index] = ""
	if selected_seed == id: selected_seed = ""
	if selected_bait == id: selected_bait = ""
	_save_quick()
	_refresh_bar()
	_show_undo_toast(was)

func _show_undo_toast(was: Dictionary) -> void:
	if _undo_toast: _undo_toast.queue_free()
	_undo_toast = UiUndoToast.new("%s off the bar" % P0Logic.item_name(view, str(was.id)))
	_undo_toast.theme = UiKit.theme()
	_kit.add_child(_undo_toast)
	var size := _undo_toast.get_combined_minimum_size()
	_undo_toast.size = size
	_undo_toast.position = Vector2(UiTokens.SPACE_PAGE, _bar.position.y - UiTokens.SPACE_WITHIN - size.y)   # BAR-DRAG-4
	_undo_toast.undo_pressed.connect(func(): _undo_remove(was))

func _undo_remove(was: Dictionary) -> void:
	var store := _quick_for(str(was.mode))
	var id := str(was.id)
	store.removed.erase(id)
	if bool(was.pinned) and not store.pins.has(id): store.pins.append(id)
	if str(was.mode) == bar_mode:
		var i := int(was.index)
		if i >= 0 and i < _bar_ids.size() and str(_bar_ids[i]) == "": _bar_ids[i] = id
		elif not _bar_ids.has(id): _bar_ids.insert(clampi(i, 0, _bar_ids.size()), id)
	_save_quick()
	_bar_sig = []
	_refresh_bar()

# ---------------------------------------------------------------- the bag drawer's way onto the bar (SGODOT-225, q(61))
## The action whose bar takes this item ("farm": seeds and fertiliser, "fish": bait), or "" when none does.
func bar_action_of(id: String) -> String: return P0Logic.bar_action_of(id)

## The bar on screen takes this item (a seed never goes on the Fishing bar).
func accepts(id: String) -> bool: return bar_action_of(id) != "" and bar_action_of(id) == bar_mode

## Pinned on its own action's bar.
func is_pinned(id: String) -> bool:
	var mode := bar_action_of(id)
	return mode != "" and _quick_for(mode).pins.has(id)

## False when its action already has every slot pinned and it is not one of them (the detail card then greys Pin
## out: `Bar full · Unpin one first`), or when no bar takes it.
func can_pin(id: String) -> bool:
	var mode := bar_action_of(id)
	if mode == "": return false
	var pins: Array = _quick_for(mode).pins
	return pins.has(id) or pins.size() < UiQuickBar.SLOTS

## Detail card Pin / a bag item dropped on the Pin zone: pinned on its own action's bar. On the bar now showing it
## takes the first gap, else the free end, else the last unpinned slot (that item leaves the bar, not "removed");
## on another action's bar it is only recorded and leads that bar next time. Clears it from "removed".
func pin_to(id: String) -> bool:
	if not can_pin(id): return false
	var mode := bar_action_of(id)
	var store := _quick_for(mode)
	store.removed.erase(id)
	if not store.pins.has(id): store.pins.append(id)
	if mode == bar_mode and not _bar_ids.has(id):
		var hole := _bar_ids.find("")
		if hole >= 0: _bar_ids[hole] = id
		elif _bar_ids.size() < UiQuickBar.SLOTS: _bar_ids.append(id)
		else:
			for k in range(_bar_ids.size() - 1, -1, -1):
				if not store.pins.has(_bar_ids[k]):
					_bar_ids[k] = id
					break
	_save_quick()
	if mode == bar_mode: _refresh_bar()
	return true

## Detail card Unpin: stays where it is until the bar refills.
func unpin(id: String) -> void:
	var mode := bar_action_of(id)
	if mode == "": return
	_quick_for(mode).pins.erase(id)
	_save_quick()
	if mode == bar_mode: _refresh_bar()

## A bag item dropped on slot `index` of the bar on screen: placed there, not pinned (q(61)). A gap or the free end
## just takes it; an occupied slot's item leaves the bar with its pin and is not "removed"; an item already on the
## bar swaps places with that slot. Clears it from this action's "removed". False when this bar does not take it.
func place_at(index: int, id: String) -> bool:
	if not accepts(id) or index < 0 or index >= UiQuickBar.SLOTS: return false
	var store := _quick_for(bar_mode)
	store.removed.erase(id)
	while _bar_ids.size() <= index: _bar_ids.append("")
	var there := str(_bar_ids[index])
	var from := _bar_ids.find(id)
	if from >= 0:
		_bar_ids[from] = there
	elif there != "":
		store.pins.erase(there)
	_bar_ids[index] = id
	_save_quick()
	_refresh_bar()
	return true

func quick_bar_node() -> UiQuickBar: return _bar

var _bar_dock: Control = null
var _bar_home_index := 0

## The bag drawer's top row is this same bar, pushed up by the drawer (LOCK-04; plan §10.4): moved into `container`
## at its 336 × 68, drop zones opening below it. Any drag in progress is cancelled.
func dock_bar_into(container: Control) -> void:
	if container == null or _bar_dock == container: return
	_bar.cancel_drag()
	_bar.set_drop_target(-1)
	_bar_home_index = _bar.get_index()
	_bar.get_parent().remove_child(_bar)
	container.add_child(_bar)
	_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_bar.custom_minimum_size = Vector2(UiTokens.SIZE_QUICK_BAR_W, UiTokens.SIZE_QUICK_BAR_H)
	_bar.zones_below = true
	_bar_dock = container

## Back to its own place over the scene; a no-op when not docked. Every modal close comes through _drop_modal.
func undock_bar() -> void:
	if _bar_dock == null: return
	_bar.cancel_drag()
	_bar.set_drop_target(-1)
	if is_instance_valid(_bar.get_parent()): _bar.get_parent().remove_child(_bar)
	_kit.add_child(_bar)
	_kit.move_child(_bar, mini(_bar_home_index, _kit.get_child_count() - 1))
	_bar.custom_minimum_size = Vector2.ZERO
	_bar.zones_below = false
	_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_bar_dock = null
	_place_controls()

func is_bar_docked() -> bool: return _bar_dock != null

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
	# Mining's free moves keep it (show_free: LOCK-21 `Elevator · Free`, SGODOT-231).
	k.cost = "" if int(a.get("need", 0)) == 0 and sub == "Free" and not a.get("show_free", false) else sub
	if a.get("amber", false): k.state = UiSceneAction.State.INSUFFICIENT
	elif not a.get("enabled", false): k.state = UiSceneAction.State.UNAVAILABLE
	else: k.state = UiSceneAction.State.DEFAULT
	# The equipped tool in the key's badge (SGODOT-231: Starter / Copper Pickaxe at the mine mouth and inside); a key
	# without one shows the action's own tool, so the farm's Sow after the mouth is a hoe again (walkthrough fix).
	_keys.tool_icon = P0Logic.icon(str(a.tool)) if a.has("tool") else _mode_tool
	_fab_pills.visible = bool(a.get("creel_full", false)) and _keys.visible
	var need := int(a.get("need", 0))
	if need != _hud_need:   # the worlds call set_action every frame
		_hud_need = need
		_refresh_hud()   # SGODOT-222: the Energy chip turns Low when short of this action

func _fab_pressed() -> void:
	fab_verb = ""
	if _modal != null: return
	if not _fab_state.get("enabled", false):
		if _fab_state.has("toast"): toast(str(_fab_state.toast))   # SGODOT-231: unavailable keys say why (LOCK-10)
		return
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
			if _modal == null:
				# The world sees which card it was (tapped_card) as well as the facility's point, so another facility's
				# mark over that point can't take the tap (PR #21 review: the farmhouse card under the sign's caption).
				tapped_card = str(id)
				tapped.emit(_card_hits[id])
				tapped_card = ""
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

## True when a scene tap lands on a shown badge (with its caption): badges ignore the mouse, so the facility that
## owns one tests this to treat a tap on its mark as its own (StatusBadge: tapping the badge = tapping the object).
func badge_hit(id: String, screen: Vector2) -> bool:
	var r := badge_rect(id)
	return r.has_area() and r.grow(4).has_point(screen)

## Slide a shown finger card sideways off `avoid` (another facility's mark), keeping `gap` px between them; the
## pointer stays on its facility (TapCard Pointer=Left / Right), and the card stays on screen. Returns whether it moved.
## TODO(亚瑟, world controls): 不知火舞's general rule for marks under cards (SGODOT-228 293b4190) replaces this.
func slide_card_off(id: String, avoid: Rect2, gap := 8.0) -> bool:
	var c: UiTapCard = _cards.get(id)
	if c == null or not c.is_visible_in_tree() or not avoid.has_area(): return false
	var r := Rect2(c.position, c.size)
	if not r.grow(gap).intersects(avoid): return false
	var left := avoid.position.x - gap - r.end.x     # move this much (negative) to clear on the left
	var right := avoid.end.x + gap - r.position.x    # or this much to clear on the right
	var dx := left if absf(left) <= absf(right) else right
	var inner := Rect2(Vector2.ZERO, _kit.size).grow(-UiTokens.SPACE_WITHIN)
	var x := clampf(r.position.x + dx, inner.position.x, inner.end.x - r.size.x)
	if is_equal_approx(x, r.position.x): return false
	var aim: float = (_card_hits.get(id, r.get_center()) as Vector2).x
	c.position.x = x
	c.point_at(aim - x)
	return true

## A shown finger card's rect in root coordinates; empty when hidden.
func card_rect(id: String) -> Rect2:
	var c: UiTapCard = _cards.get(id)
	return Rect2(c.global_position - root.global_position, c.size) if c != null and c.is_visible_in_tree() else Rect2()

## A shown badge's rect (with its caption) in root coordinates; empty when hidden.
func badge_rect(id: String) -> Rect2:
	var b: UiStatusBadge = _badges.get(id)
	return Rect2(b.global_position - root.global_position, b.size) if b != null and b.is_visible_in_tree() else Rect2()

## Finger cards stay on screen (their facility is near, so on screen); a badge over an off-screen facility hides.
func _place_marker(m: Control, screen: Vector2, clamp_inside: bool) -> void:
	var size := m.get_combined_minimum_size()
	var area := _marker_area()
	var r := WorldAnchor.place(size, screen - Vector2(0, UiTokens.SPACE_WITHIN), area, UiTokens.SPACE_WITHIN, clamp_inside)
	m.visible = r.has_area()
	if not m.visible: return
	m.size = size
	m.position = r.position
	if m.has_method(&"point_at"): m.point_at(screen.x - r.position.x)

## Where world markers may sit (LOCK-07): below the two-row HUD and above the quick bar. A finger card is passive, so
## one lying under a HUD chip lost its tap to the chip (int5 hand test 8: the Homestead card slid under Energy and
## opened the Energy panel); a card clamps into this band instead, a badge outside it hides.
func _marker_area() -> Rect2:
	var top := 0.0
	if hud and hud.visible: top = UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + safe_top()
	var bottom := _kit.size.y
	if _bar.visible: bottom = minf(bottom, _bar.position.y)
	return Rect2(0.0, top, _kit.size.x, maxf(0.0, bottom - top))

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
## Going to the background cancels a slot drag: the slot flies back, nothing changes (LOCK-04 v1.10).
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT] and _bar != null: _bar.cancel_drag()

## Android Back closes what is on top first, one layer per press (LOCK-06, int5 hand test 012–013 / 023–024): the
## a quick slot being dragged (it flies back, LOCK-04 v1.11; the PinMenu is gone), the radial, then a card or
## drawer. True when it closed something; the world only leaves on false.
func close_top_layer() -> bool:
	if _bar != null and (_bar.is_dragging() or _bar.is_lifted()):   # lifted and not moved yet counts too (刘邦 on #38)
		_bar.cancel_drag()
		return true
	if _radial.visible:
		_radial.close()
		return true
	if _modal != null:
		close_modal()
		return true
	return false

## A world change ends the stick: a finger still down when the farmhouse door took the player in never sends its
## release to this pad (int5 hand test 029–030), so its ring would stay and the old world keep walking.
## The first attach (a world booted as the root scene, P0Runtime.ensure) runs before this UI's _ready built the pad:
## there is no stick to end yet (哪吒: `end_stick` on Nil at every farm start).
func end_stick() -> void:
	if pad != null: (pad as _TouchPad).end_stick()
	joystick.emit(Vector2.ZERO)

func has_modal() -> bool: return _modal != null or (_radial != null and _radial.visible)

func close_modal() -> void:
	_drop_modal()
	if not _card_queue.is_empty():
		var next: Callable = _card_queue.pop_front()
		next.call_deferred()
	else:
		_flush_held_toast()

## A toast that must not be lost under the fishing presentation (layer 30, over this layer) or a result card: the
## last bait goes at the reel's settlement, while the panel still shows the landing (int5b hand test 10). Shown at
## once when nothing covers the UI, else held until the world is back from "busy" and no card is open or queued.
var _held_toast := ""

func toast_when_clear(text: String) -> void:
	_held_toast = text
	_flush_held_toast()

func _flush_held_toast() -> void:
	if _held_toast == "" or not is_node_ready(): return
	if surface == "busy" or _modal != null or not _card_queue.is_empty(): return
	toast(_held_toast)
	_held_toast = ""

## Result cards (catch, dish, level up) wait their turn instead of replacing each other.
func queue_card(show: Callable) -> void:
	if _modal == null and _card_queue.is_empty(): show.call()
	else: _card_queue.append(show)

func _drop_modal() -> void:
	undock_bar()   # before the drawer holding it goes (SGODOT-225)
	if _modal: _modal.queue_free()
	_modal = null
	var was_kitchen := modal_kind == "kitchen"
	modal_kind = ""
	if was_kitchen: _refresh_hud()   # back out of the farmhouse
	_keys.visible = surface in ACTION_SURFACES
	_bar.visible = _bar_shown()
	_fab_pills.visible = _keys.visible and bool(_fab_state.get("creel_full", false))

func _open_modal(content: Control, dim := 0.32, hide_controls := false) -> void:
	_bar.cancel_drag()   # a drawer or card opening cancels a slot drag (LOCK-04 v1.10)
	_drop_modal()
	var veil := ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.184, 0.227, 0.2, dim)
	veil.gui_input.connect(func(e: InputEvent):
		if P0Ui.is_tap(e): close_modal())
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(veil)
	holder.add_child(content)
	if surface == "map" and content is PanelContainer:
		# Over the map, translucent paper lets the map's own buttons ghost through the card.
		var sb := (content as PanelContainer).get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			sb = sb.duplicate()
			(sb as StyleBoxFlat).bg_color.a = 1.0
			content.add_theme_stylebox_override("panel", sb)
	root.add_child(holder)
	_modal = holder
	if hide_controls:
		_keys.visible = false
		_fab_pills.visible = false
		_bar.visible = false

## Bottom system inset (gesture bar, rounded corners) in UI units; 0 on desktop.
func safe_bottom() -> float:
	if not (OS.has_feature("android") or OS.has_feature("ios")): return 0.0
	return UIMetrics.safe_margins(DisplayServer.get_display_safe_area(), DisplayServer.window_get_size(),
		get_viewport().get_visible_rect().size, 0.0).w

## Bottom edge for cards that sit low (NPC greetings): on the quick bar's baseline (41 from the bottom,
## FISH-1 / NPC-G1), or clear of a taller gesture bar — never against the screen edge.
func bottom_pad() -> float:
	return maxf(41.0, safe_bottom() + 16.0)

func _sheet(height: float, title: String, icon_id := "") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -height
	panel.add_theme_stylebox_override("panel", _box(CARD, 16, EDGE, 1, Vector4(10, 8, 10, 12 + safe_bottom()), true))
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

## Bag drawer: capacity, a 5-column grid, and a detail row for the tapped item (dishes: Eat).
## Bag drawer with the Bag | Gear switch (BAG-2, p(8)): one place to see and equip gear; no separate
## Tools & Gear panel and no Outfit tab.
var bag_side := "bag"
var gear_slot := "fishing"

func open_bag(focus := "", side := "") -> void:
	if side != "": bag_side = side
	var used := _bag_slots().size()
	var capacity := int(view.get("bag", {}).get("capacity", 25))
	var v := _sheet(500, "Bag" if bag_side == "bag" else "Gear", "bag" if bag_side == "bag" else "rod")
	modal_kind = "bag" if bag_side == "bag" else "gear"
	v.add_child(_bag_switch("Bag %d/%d" % [used, capacity]))
	if bag_side == "gear":
		_gear_side(v)
		return
	var cap := _CapBar.new()
	cap.custom_minimum_size = Vector2(0, 5)
	cap.set_meta("pct", float(_bag_slots().size()) / maxf(1.0, float(view.get("bag", {}).get("capacity", 25))))
	v.add_child(cap)
	var detail := HBoxContainer.new()
	detail.custom_minimum_size = Vector2(0, 54)
	detail.add_theme_constant_override("separation", 8)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	var slots := _bag_slots()
	for i in int(view.get("bag", {}).get("capacity", 25)):
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(58, 58)
		if i < slots.size():
			var st: Dictionary = slots[i]
			var id := str(st.id)
			var info := P0Logic.item(view, id)
			var edge := P0Logic.rarity_color(int(info.get("rarity", 1))) if info.has("rarity") and not id.begins_with("crop_") else EDGE
			cell.add_theme_stylebox_override("panel", _box(PAPER, 10, edge, 2 if edge != EDGE else 1, Vector4(4, 4, 4, 2)))
			var box := VBoxContainer.new()
			box.add_theme_constant_override("separation", 0)
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var ic := _icon(str(info.get("base", id)), 30)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			box.add_child(ic)
			var q := _label(("%s ×%d" % ["★".repeat(int(info.get("quality", 0))), int(st.qty)]).strip_edges(), 9, INK, true)
			q.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			box.add_child(q)
			cell.add_child(box)
			cell.gui_input.connect(func(e: InputEvent):
				if P0Ui.is_tap(e):
					_fill_detail(detail, id))
		else:
			cell.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.2), 10, Color("d9c7a6"), 1, Vector4(4, 4, 4, 4)))
		grid.add_child(cell)
	v.add_child(detail)
	v.add_child(grid)
	v.add_child(_label(P0Logic.meal_line(view), 9, INK2))
	if focus != "" and P0Logic.bag_count(view, focus) > 0: _fill_detail(detail, focus)
	else: detail.add_child(_label("Tap an item. Dishes can be eaten here.", 9, INK2))

func _fill_detail(detail: HBoxContainer, id: String) -> void:
	for c in detail.get_children(): c.queue_free()
	var info := P0Logic.item(view, id)
	detail.add_child(_icon(str(info.get("base", id)), 40))
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	var title := P0Logic.dish_label(view, id) if id.begins_with("dish_") else P0Logic.item_name(view, id)
	mid.add_child(_label("%s ×%d" % [title, P0Logic.bag_count(view, id)], 11, INK, true))
	var line := _label(_item_line(id), 8, INK2)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(line)
	detail.add_child(mid)
	if id.begins_with("dish_"):
		var eb := P0Logic.eat_button(view, id)
		var b := _pill_button(str(eb.text), true)
		b.custom_minimum_size = Vector2(118, 34)
		b.add_theme_font_size_override("font_size", 9)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.disabled = not eb.get("enabled", false)
		var confirm := str(eb.get("confirm", ""))
		b.pressed.connect(func():
			if confirm != "" and b.text != confirm:
				b.text = confirm   # §7.17.1: say the real gain first, the second tap eats
				return
			close_modal()
			command.emit({"type": "eat", "item": id}))
		detail.add_child(b)

func _item_line(id: String) -> String:
	var info := P0Logic.item(view, id)
	if id.begins_with("seed_"):
		var c := P0Logic.crop_for_seed(view, id)
		return "%d Energy per plot · ready in %dh" % [int(c.get("energy", 2)), int(c.get("grow_h", 4))]
	if id.begins_with("crop_") or id.begins_with("fish_"):
		var parts: Array = []
		if id.begins_with("fish_"): parts.append(P0Logic.rarity_name(view, int(info.get("rarity", 1))))
		parts.append("Sells for %d at the Homestead Stall" % int(info.get("sell", 0)))
		if not info.get("cook", false) and id.begins_with("fish_"): parts.append("Not for cooking")
		return " · ".join(parts)
	if id.begins_with("dish_"):
		if str(info.get("base", "")) == "dish_mystery": return "Mystery Dish · +%d Energy" % int(info.get("full", 5))
		return "%s · +%d Energy" % [P0Logic.rarity_name(view, int(info.get("rarity", 1))), int(info.get("full", 20))]
	if id.begins_with("bait_"):
		return "Used at the bite · more Fine fish, shorter wait"
	return ""

func _bag_slots() -> Array: return view.get("bag", {}).get("slots", [])

## A tapped NEED-TILE: one source line just above it; Show only moves the camera (LOCK-10 / LOCK-08).
func _show_need_source(tile: Control, id: String) -> void:
	var src := P0Logic.need_source(view, id)
	var go := str(src.go) if spot_reachable() else ""
	var on_show := Callable() if go == "" else func():
		close_modal()
		show_spot.emit(go)
	var layer := UiNeedSource.popup(root, tile.get_global_rect(), str(src.text), on_show)
	layer.theme = UiKit.theme()

## Old Kai's greeting (p(4)): same card, his own line and options; Trade opens the tackle counter.
func open_kai_greeting() -> void:
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	card.offset_bottom = -bottom_pad()
	card.offset_top = card.offset_bottom - 184
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN   # taller content grows up, never past the bottom pad
	card.offset_left = 10
	card.offset_right = -10
	card.add_theme_stylebox_override("panel", _box(CARD, 16, EDGE, 1, Vector4(8, 8, 10, 8)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var face := TextureRect.new()   # Old Kai mending a net in his shop (NPC-1b look)
	face.texture = load("res://assets/p0/art/kai-portrait.jpg")
	face.custom_minimum_size = Vector2(100, 171)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	h.add_child(face)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	v.add_child(_label("Tackle Keeper · Old Kai", 13, INK, true))
	v.add_child(_label("Rods and bait · " + tackle_place, 8, INK2))
	var line := _label("“%s”" % _kai_line(), 10, INK)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(200, 0)
	v.add_child(line)
	var trade := _pill_button("Trade · see the rods", true)
	trade.pressed.connect(open_tackle)
	v.add_child(trade)
	var ask := _pill_button("What's biting?", false)
	ask.pressed.connect(func(): line.text = "“Round ponds keep crucian, carp, perch and bass — koi too, if your rod can hold her. The winding ones add mullet and trout.”")
	v.add_child(ask)
	var bye := _flat_button("Just passing by")
	bye.pressed.connect(close_modal)
	v.add_child(bye)
	h.add_child(v)
	card.add_child(h)
	_open_modal(card, 0.22, true)
	modal_kind = "greeting"

func _kai_line() -> String:
	var lv := int(view.get("skills", {}).get("fishing", {}).get("level", 1))
	for g in view.get("gear", {}).get("rods", []):
		if str(g.id) == "rod_reed" and g.get("owned", false): return "That Reed Rod suits you. Golden Koi won't snap it — at Fishing Lv4 she's yours."
	if lv >= 3: return "Fishing Lv3 already? The Reed Rod holds Rare fish. 80 coins and she's yours."
	return "A Starter Rod lands Common and Fine fish. The Reed Rod holds Rare ones — come back at Fishing Lv3."

## Tackle counter (sea-blue keeper bar, §9.11): rods go to Bag › Gear, bait to the bag; nothing is sold here.
func open_tackle(bubble := "") -> void:
	var v := _sheet(420, "Old Kai's Tackle · " + tackle_place, "rod")
	modal_kind = "tackle"
	var kp := PanelContainer.new()
	kp.add_theme_stylebox_override("panel", _box(SEA_LIGHT, 12, SEA_LIGHT, 0, Vector4(8, 6, 8, 6)))
	var kv := VBoxContainer.new()
	kv.add_child(_label("Tackle Keeper · Old Kai", 9, INK, true))
	var say := _label("“%s”" % (bubble if bubble != "" else "Pick a rod, I'll string it. Fish sell best at your own stall."), 9, INK)
	say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	say.custom_minimum_size = Vector2(280, 0)
	kv.add_child(say)
	kp.add_child(kv)
	v.add_child(kp)
	v.add_child(_label("Buy", 11, INK, true))
	for row in view.get("tackle", {}).get("buy", []):
		var id := str(row.id)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		h.custom_minimum_size = Vector2(0, 46)
		var ic := _icon(id, 30)
		if not row.get("unlocked", false): ic.modulate = Color(1, 1, 1, 0.45)
		h.add_child(ic)
		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_theme_constant_override("separation", 0)
		mid.add_child(_label(str(row.name), 10, INK if row.get("unlocked", false) else INK2, true))
		var sub := "%d coins · holds up to %s · goes to Gear" % [int(row.price), P0Logic.rarity_name(view, int(row.reach))] if row.get("reach", null) != null else "%d coins · %d left today · Bag ×%d" % [int(row.price), int(row.get("left", 0)), P0Logic.bag_count(view, id)]
		mid.add_child(_label(sub, 8, INK2))
		h.add_child(mid)
		if not row.get("unlocked", false):
			var lk := _label("Fishing Lv%d · %d XP to go" % [int(row.gate), int(row.xp_to_go)], 8, INK2, true)
			lk.add_theme_stylebox_override("normal", _box(DIS, 10, DIS, 0, Vector4(8, 4, 8, 4)))
			h.add_child(lk)
		elif row.get("owned", false):
			var ow := _label("Owned", 9, GREEN_D, true)
			h.add_child(ow)
		else:
			var q := 1
			var b := _pill_button("Buy · %d" % int(row.price), true)
			b.custom_minimum_size = Vector2(76, 30)
			b.pressed.connect(func(): command.emit({"type": "buy", "item": id, "qty": q, "shop": "tackle"}))
			h.add_child(b)
		v.add_child(h)
	var gear := _pill_button("Bag › Gear", false)
	gear.pressed.connect(open_gear)
	v.add_child(gear)

## Bag | Gear segmented switch under the drawer title.
func _bag_switch(bag_text: String) -> Control:
	var track := PanelContainer.new()
	track.add_theme_stylebox_override("panel", _box(Color("ede8dc"), 16, Color("ede8dc"), 0, Vector4(3, 3, 3, 3)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	for side in [["bag", "bag", bag_text], ["gear", "rod", "Gear"]]:
		var on: bool = bag_side == side[0]
		var b := Button.new()
		b.text = str(side[2])
		b.icon = P0Logic.icon(str(side[1]))
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 13)
		b.add_theme_font_size_override("font_size", 10)
		b.custom_minimum_size = Vector2(0, 28)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(b, PAPER if on else Color("ede8dc"), EDGE if on else Color("ede8dc"), 13)
		b.add_theme_color_override("font_color", INK if on else INK2)
		var key := str(side[0])
		b.pressed.connect(func(): if bag_side != key: open_bag("", key))
		row.add_child(b)
	track.add_child(row)
	return track

## Gear side (BAG-2): Equipped six slots; tap a slot to list what can go in it (Equipped / Equip / greyed
## gate and where it comes from). Gear takes no Bag space.
func _gear_side(v: VBoxContainer) -> void:
	var g: Dictionary = view.get("gear", {})
	var slots: Dictionary = g.get("slots", {})
	var head := HBoxContainer.new()
	var eq := _label("Equipped", 11, INK, true)
	eq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(eq)
	head.add_child(_label("Tap a slot to change it", 8, INK2))
	v.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for key in ["farming", "fishing", "mining", "combat", "ring", "charm"]:
		var item := str(slots.get(key, ""))
		var empty := item == ""
		var on: bool = key == gear_slot
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(0, 66)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.4) if empty else PAPER, 9,
			GREEN_D if on else Color("cfc6b0") if empty else EDGE, 2 if on else 1, Vector4(2, 3, 2, 3)))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 1)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := _label(key.capitalize(), 6, Color("a98bd6") if key in ["ring", "charm"] else INK2, true)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(t)
		var ic := _icon(item if not empty else "question", 22)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if empty: ic.modulate = Color(1, 1, 1, 0.3)
		col.add_child(ic)
		var n := _label("Empty" if empty else P0Logic.item_name(view, item), 6, INK2 if empty else INK, true)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(n)
		cell.add_child(col)
		var k := str(key)
		cell.gui_input.connect(func(e: InputEvent):
			if P0Ui.is_tap(e) and gear_slot != k:
				gear_slot = k
				open_bag("", "gear"))
		row.add_child(cell)
	v.add_child(row)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	v.add_child(gap)
	var list_head := HBoxContainer.new()
	var lt := _label("%s slot" % gear_slot.capitalize(), 11, INK, true)
	lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_head.add_child(lt)
	v.add_child(list_head)
	if gear_slot == "fishing":
		var rods: Array = g.get("rods", [])
		var level := int(view.get("skills", {}).get("fishing", {}).get("level", 1))
		var locked := rods.filter(func(r): return not r.get("owned", false) and level < int(r.level)).size()
		list_head.add_child(_label("%d rods%s" % [rods.size(), " · %d locked" % locked if locked > 0 else ""], 8, INK2))
		var base_ms := float(P0Logic.content().get("fishing", {}).get("hook_window_ms", 2200))
		for r in rods: v.add_child(_rod_row(r, level, base_ms))
	elif slots.get(gear_slot, "") != "":
		var item := str(slots[gear_slot])
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.add_child(_icon(item, 28))
		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_child(_label(P0Logic.item_name(view, item), 10, INK, true))
		mid.add_child(_label("Starter tool · better ones come later", 8, INK2))
		h.add_child(mid)
		h.add_child(_equipped_badge())
		v.add_child(h)
	else:
		v.add_child(_label("Nothing for this slot yet.", 9, INK2))
	var foot := _label("Gear doesn't take Bag space", 8, INK2)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(foot)

func _rod_row(r: Dictionary, level: int, base_ms: float) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.custom_minimum_size = Vector2(0, 40)
	var owned: bool = r.get("owned", false)
	var ic := _icon(str(r.id), 28)
	if not owned: ic.modulate = Color(1, 1, 1, 0.5)
	h.add_child(ic)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 5)
	name_row.add_child(_label(str(r.name), 10, INK if owned else INK2, true))
	if r.get("equipped", false): name_row.add_child(_equipped_badge())
	mid.add_child(name_row)
	var reach := P0Logic.rarity_name(view, int(r.reach))
	var sub := "Bite window %.1f s · lands up to %s" % [(base_ms + float(r.hook_bonus_ms)) / 1000.0, reach] if owned \
		else "Lands up to %s · %d coins at Old Kai's Tackle" % [reach, int(r.price)]
	mid.add_child(_label(sub, 8, INK2))
	h.add_child(mid)
	if owned and not r.get("equipped", false):
		var id := str(r.id)
		var b := _pill_button("Equip", true)
		b.custom_minimum_size = Vector2(64, 30)
		b.pressed.connect(func(): command.emit({"type": "equip", "item": id}))
		h.add_child(b)
	elif not owned:
		var gate := _label(("Fishing Lv%d" % int(r.level)) if level < int(r.level) else "At Old Kai's", 8, INK2, true)
		gate.add_theme_stylebox_override("normal", _box(DIS, 12, DIS, 0, Vector4(8, 4, 8, 4)))
		h.add_child(gate)
	return h

func _equipped_badge() -> Control:
	var l := _label("Equipped", 7, GREEN_D, true)
	l.add_theme_stylebox_override("normal", _box(Color("e6f4df"), 7, Color("bfe0b3"), 1, Vector4(5, 1, 5, 1)))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

## Gear lives in the bag drawer now (p(8)); callers that opened Tools & Gear land on the Gear side.
func open_gear() -> void:
	open_bag("", "gear")

## Homestead Stall (FARM-6, p(6)): unattended — no keeper bar, no greeting; Buy rows with level gates,
## Sell your produce (no Sell Tab; produce, no quota) and the Stall Board.
var stall_tab := "buy"

func open_stall(tab := "") -> void:
	if tab != "": stall_tab = tab
	var keep_scroll := 0
	if modal_kind == "stall" and _modal:
		var old := _modal.find_child("StallScroll", true, false) as ScrollContainer
		if old: keep_scroll = old.scroll_vertical   # a rebuild after Buy / Sell stays where the player was
	var v := _sheet(470 if stall_tab == "buy" else 320, "Homestead Stall", "stall")
	modal_kind = "stall"
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	var board: Dictionary = view.get("stall", {}).get("board", {})
	var open_reqs: Array = board.get("requests", []).filter(func(r): return str(r.status) != "done")
	for t in [["buy", "Buy"], ["board", "Stall Board" + (" · %d" % open_reqs.size() if not open_reqs.is_empty() else "")]]:
		var tb := _pill_button(str(t[1]), t[0] == stall_tab)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key := str(t[0])
		tb.pressed.connect(func(): open_stall(key))
		tabs.add_child(tb)
	v.add_child(tabs)
	if stall_tab == "board":
		_board(v, board)
		return
	var scroll := TouchScrollContainer.new()   # drags that start on a row or cell still scroll (WP7-B F-04 §4)
	scroll.name = "StallScroll"
	scroll.custom_minimum_size = Vector2(0, 370)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	v.add_child(scroll)
	if keep_scroll > 0: scroll.set_deferred("scroll_vertical", keep_scroll)
	list.add_child(_label("Buy", 11, INK, true))
	for row in view.get("stall", {}).get("buy", []):
		list.add_child(_buy_row(row))
	var produce: Array = []
	for st in _bag_slots():
		var id := str(st.id)
		if (id.begins_with("crop_") or id.begins_with("fish_")) and not produce.has(id): produce.append(id)
	list.add_child(_label("Sell here · produce and fish, no daily limit", 11, INK, true))
	if produce.is_empty():
		list.add_child(_label("Nothing to sell yet — harvest or fish first.", 9, INK2))
	for id in produce: list.add_child(_sell_row(id))

## Stall Board (FARM-6 tab): request cards with a need tile; Accept tracks it, Deliver pays coins (no XP).
func _board(v: VBoxContainer, board: Dictionary) -> void:
	# A delivered request leaves the board and frees its slot (§14.5 "完成打勾并补位").
	var reqs: Array = board.get("requests", []).filter(func(r): return str(r.status) != "done")
	for r in reqs:
		var card := PanelContainer.new()
		var done := str(r.status) == "done"
		card.add_theme_stylebox_override("panel", _box(PAPER if not done else Color(1, 1, 1, 0.5), 14, AMBER if str(r.status) == "accepted" else EDGE, 2 if str(r.status) == "accepted" else 1, Vector4(10, 8, 10, 8)))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var item_id := str(r.item)
		var tile := UiNeedTile.new(P0Logic.item_name(view, item_id), int(r.have), int(r.qty), UiNeedTile.Size.M, P0Logic.icon(item_id))
		tile.theme = UiKit.theme()
		tile.pressed.connect(func(): _show_need_source(tile, item_id))
		h.add_child(tile)
		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_theme_constant_override("separation", 1)
		mid.add_child(_label(str(r.title) + (" · done" if done else ""), 12, INK if not done else INK2, true))
		var what := P0Logic.item_name(view, str(r.item))   # fish plurals stay as they are ("2 Pond Crucian")
		if int(r.qty) > 1 and not str(r.item).begins_with("fish_"): what = P0Logic.plural(what)
		var line := _label("%d %s · %s · %d coins · Deliver here" % [int(r.qty), what, str(r.get("where", "")), int(r.coins)], 8, INK2)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(1, 0)   # wraps in what the NEED-TILE and the button leave
		mid.add_child(line)
		h.add_child(mid)
		if not done:
			var id := str(r.id)
			var b: Button
			if str(r.status) == "open":
				b = _pill_button("Accept", true)
				b.pressed.connect(func(): command.emit({"type": "accept", "request": id}))
			elif int(r.have) >= int(r.qty):
				b = _pill_button("Deliver", true)
				b.pressed.connect(func(): command.emit({"type": "deliver", "request": id}))
			else:
				b = _pill_button("Tracking", false)
				b.disabled = true
			b.custom_minimum_size = Vector2(78, 34)
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # the NEED-TILE makes the card taller
			h.add_child(b)
		card.add_child(h)
		v.add_child(card)
	for i in maxi(0, int(board.get("slots", 2)) - reqs.size()):
		var empty := _label("New request in %s" % P0Logic.duration(float(board.get("refill_in", 0))), 10, INK2, true)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(0, 56)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.3), 14, Color("d9c7a6"), 1, Vector4(8, 6, 8, 6)))
		v.add_child(empty)

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
	if id.begins_with("seed_"):
		mid.add_child(_label("%d coins · %d Energy a plot · Bag ×%d" % [int(row.price), int(row.energy), P0Logic.bag_count(view, id)], 8, INK2))
	else:
		mid.add_child(_label("%d coins · %d left today · Bag ×%d" % [int(row.price), int(row.get("left", 0)), P0Logic.bag_count(view, id)], 8, INK2))
	h.add_child(mid)
	if not row.get("unlocked", false):
		var lk := _label("%s Lv%d · %d XP to go" % [str(row.get("skill", "farming")).capitalize(), int(row.gate), int(row.xp_to_go)], 8, INK2, true)
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
	var price := int(P0Logic.item(view, id).get("sell", view.get("prices", {}).get(id, 0)))
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

## Energy Card (§3.7.2 / HUD-3): facts, a Wait line, RECOVER tiles that only guide, one button that closes.
## The ONE Energy interface (LOCK-09): a centred card over the modal scrim. Its only button is
## `Free to do now` (closes it); tiles only guide (open the bag or move the camera), never act.
func open_energy_card(need: int, verb: String) -> void:
	var f := P0Logic.energy_card(view, need, verb, surface not in ["pond", "busy"])   # away from home: the pond (later the mine)
	for t in f.tiles: t.icon = P0Logic.icon(str(t.icon))
	var card := UiEnergyCard.card(f)
	card.theme = UiKit.theme()
	card.free_pressed.connect(func():   # §3.7.4: closes the card, then Today lists what costs no Energy now
		close_modal()
		open_today(P0Guide.free_now(view)))
	card.tile_pressed.connect(func(go: String):
		close_modal()
		if go == "bag": open_bag()
		elif go.begins_with("outpost:"): place_pressed.emit()   # Show on map: the Tea House is a map place (pin focus: MAP-1)
		else: show_spot.emit(go))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(card)
	_open_modal(center, UiTokens.OPACITY_SCRIM_MODAL)
	modal_kind = "energy"

## Tapping the HUD Energy chip: the same interface's panel under the chip, pointing at it (LOCK-09).
func open_energy_panel() -> void:
	var f := P0Logic.energy_panel(view)
	for u in f.uses: u.icon = P0Logic.icon(str(u.icon))
	var panel := UiEnergyCard.panel(f)
	panel.theme = UiKit.theme()
	var chip := hud.energy_chip_rect()
	var x := clampf(chip.position.x - UiTokens.SPACE_WITHIN, UiTokens.SIZE_HUD_X, root.size.x - UiTokens.SIZE_ENERGY_PANEL_W - UiTokens.SIZE_HUD_X)
	panel.position = Vector2(x, chip.end.y + UiTokens.SPACE_ROW)
	panel.pointer_x = chip.get_center().x - x
	_open_modal(panel, 0.0)
	modal_kind = "energy_panel"

## The farmhouse (§3.4.3 "回家休息 Rest"; COOK-1 kitchen inside): one card, two doors.
func open_home_card() -> void:
	var r: Dictionary = view.get("rest", {})
	var used := int(r.get("used", 0)) >= int(r.get("limit", 1))
	var e: Dictionary = view.get("energy", {})
	var full := int(e.get("value", 0)) >= int(e.get("max", 200))
	var card := _center_card(280)
	modal_kind = "home"
	card.add_child(_label("Home · Farmhouse", 13, INK, true))
	var st = view.get("cooking", {}).get("stove", null)
	var kitchen_line := "Kitchen · Cook"
	if st != null: kitchen_line = "Kitchen · Dish ready" if float(st.get("ready_in", 0)) <= 0.0 else "Kitchen · Cooking " + P0Logic.duration(float(st.get("ready_in", 0)))
	var k := _pill_button(kitchen_line, true)
	k.pressed.connect(func(): close_modal(); home_choice.emit("kitchen"))
	card.add_child(k)
	var rest_text := "Rest · +%d Energy · once a day" % int(r.get("amount", 60))
	if used: rest_text = "Rested today · resets in " + P0Logic.duration(float(r.get("resets_in", 0)))
	elif full: rest_text = "Rest · Energy full"
	var b := _pill_button(rest_text, false)
	b.disabled = used or full
	b.pressed.connect(func(): close_modal(); command.emit({"type": "rest"}))
	card.add_child(b)
	var bye := _flat_button("Not now")
	bye.pressed.connect(close_modal)
	card.add_child(bye)

func open_rest_card() -> void:
	var r: Dictionary = view.get("rest", {})
	var used := int(r.get("used", 0)) >= int(r.get("limit", 1))
	var e: Dictionary = view.get("energy", {})
	var full := int(e.get("value", 0)) >= int(e.get("max", 200))
	var card := _center_card(260)
	card.add_child(_label("Home · Rest", 12, INK, true))
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
	var unlock := P0Logic.unlock_line(view, str(ev.skill), int(ev.level))
	if unlock != "":
		var ul := _label(unlock, 10, INK, true)
		ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ul.custom_minimum_size = Vector2(280, 0)
		card.add_child(ul)
	for g in ev.get("gifts", []):
		var gid := str(g[0])
		if gid.begins_with("recipe:"):
			card.add_child(_label("Recipe card: %s" % P0Logic.item_name(view, gid.substr(7)), 10, INK, true))
		else:
			card.add_child(_label("Level-up gift: %d %s" % [int(g[1]), P0Logic.item_name(view, gid)], 10, INK, true))
	var ok := _pill_button("Got it", true)
	ok.pressed.connect(close_modal)
	card.add_child(ok)

func _center_card(width: float) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.add_theme_stylebox_override("panel", _box(CARD, 16, EDGE, 1, Vector4(14, 12, 14, 12)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	panel.add_child(v)
	center.add_child(panel)
	_open_modal(center, 0.3)
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



## §10.2.3: the switch key fans the four actions out from the character (ActionRadial, LOCK-04); what this
## spot can't do is greyed with the reason. P0 preselects by where you stand (plots → Farming, water → Fishing).
func open_radial() -> void:
	if _radial.visible:
		_radial.close()
		return
	if _modal != null:
		close_modal()
		return
	_bar.cancel_drag()
	var options := []
	for it in [["farm", "hoe", "Farming", "No plots here"], ["fish", "fish", "Fishing", "No water nearby"],
			["mine", "pickaxe", "Mining", "Enter the mine"], ["combat", "sword", "Combat", "Mine floors 3–5"]]:
		options.append({id = it[0], name = it[2], icon = P0Logic.icon(it[1]), available = it[0] == bar_mode, reason = it[3]})
	_radial.options = options
	_radial.selected = bar_mode
	_radial.open_at(player_screen - _kit.global_position)

## Today panel (§14.5, LOCK-06): at most three rows right under the HUD chips; Show only moves the camera.
## rows: Today's own (P0Logic.today_rows) unless given, e.g. P0Guide.free_now after the Energy card's Free to do now.
## go "map" / "pond:<id>" / "outpost:<role>" is a place on the map: `Show on map` leaves for it (pin focus with MAP-1;
## SGODOT-225 #37 brings show_on_map(target), which this switches to once merged).
func open_today(given: Array = []) -> void:
	var rows := given if not given.is_empty() else P0Logic.today_rows(view)
	var shown := rows.map(func(r):
		var d: Dictionary = r.duplicate()
		d.icon = P0Logic.icon(str(r.icon))
		var go := str(r.go)
		var on_map := _map_target(go)
		d.action = "Show on map" if on_map and surface != "map" else ("Show" if go != "" and not on_map and spot_reachable() else "")
		return d)
	var panel := UiTodayPanel.new(shown)
	panel.theme = UiKit.theme()
	panel.position = Vector2(UiTokens.SIZE_TODAY_PANEL_X, UiTokens.SIZE_TODAY_PANEL_Y + safe_top())
	panel.show_pressed.connect(func(i: int):
		close_modal()
		if _map_target(str(rows[i].go)): place_pressed.emit()
		else: show_spot.emit(str(rows[i].go)))
	_open_modal(panel, 0.0)
	modal_kind = "today"

static func _map_target(go: String) -> bool:
	return go == "map" or go.begins_with("pond:") or go.begins_with("outpost:")

## Whether a Show can move the camera in the current world (the pond has no camera targets yet).
func spot_reachable() -> bool:
	return can_show_spot.is_valid() and bool(can_show_spot.call())

## The bell (parcels / letters). TODO(stage 4, SGODOT-234 Inbox): the Inbox drawer with its tabs and Claim. Until
## then the parcels waiting for a free slot (SGODOT-232) are listed read-only, one line each, soonest to expire first
## (奕星 on #11); `No parcels` only when there are none (LOCK-14).
func open_inbox() -> void:
	var v := _sheet(220, "Inbox", "bell")
	modal_kind = "inbox"
	var lines := P0Logic.parcel_lines(view)
	if lines.is_empty():
		var empty := UiEmptyState.new("No parcels", P0Logic.icon("bell"))
		empty.theme = UiKit.theme()
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(empty)
		return
	var list := VBoxContainer.new()
	list.theme = UiKit.theme()
	list.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	for line in lines: list.add_child(UiKit.label(str(line), UiTokens.STYLE_BODY_B14))
	v.add_child(list)

## SKILL-1 (P0 cut): three track cards — level ring, XP and how far to go, what the next level opens —
## and the "First times" collection tiles. Opened from the avatar ring.
func open_skills() -> void:
	var v := _sheet(520, "Skills", "xp")
	modal_kind = "skills"
	var sk: Dictionary = view.get("skills", {})
	for key in ["farming", "fishing", "cooking"]:
		var s: Dictionary = sk.get(key, {})
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _box(PAPER, 14, EDGE, 1, Vector4(10, 8, 10, 8)))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var ring := _LevelRing.new()
		ring.custom_minimum_size = Vector2(58, 58)
		ring.set_meta("pct", _skill_pct(s))
		ring.set_meta("text", "Lv %d" % int(s.get("level", 1)))
		h.add_child(ring)
		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_theme_constant_override("separation", 1)
		var name_row := HBoxContainer.new()
		name_row.add_child(_label(key.capitalize(), 13, INK, true))
		if key == "cooking":
			var slots := int(view.get("cooking", {}).get("slots", 2))
			name_row.add_child(_label("  " + "●".repeat(slots) + "○".repeat(maxi(0, 3 - slots)), 11, GREEN_D, true))
		mid.add_child(name_row)
		var nxt = s.get("next", null)
		if nxt == null:
			mid.add_child(_label("%d XP · top level" % int(s.get("xp", 0)), 9, INK2))
		else:
			mid.add_child(_label("%d / %d XP · %d to go" % [int(s.xp), int(nxt), int(nxt) - int(s.xp)], 9, INK2))
		var nl := _label(P0Logic.next_line(view, key, int(s.get("level", 1)) + 1), 9, AMBER_D, true)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size = Vector2(200, 0)
		mid.add_child(nl)
		h.add_child(mid)
		card.add_child(h)
		v.add_child(card)
	v.add_child(_label("First times", 11, INK, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var firsts: Array = view.get("firsts", [])
	var crops := firsts.filter(func(f): return str(f).begins_with("harvest:")).size()
	var dex: Array = view.get("fishing", {}).get("dex", [])
	var fish := dex.filter(func(d): return int(d.get("caught", 0)) > 0).size()
	var pages: Array = view.get("cooking", {}).get("cookbook", [])
	var dishes := pages.filter(func(p): return p.get("cooked", false)).size()
	for t in [["crop_radish", "Crops", crops, (view.get("crops", []) as Array).size()], ["fish_crucian", "Fish", fish, dex.size()], ["dish_grilled_crucian", "Dishes", dishes, pages.size()]]:
		# Collection counts: NEED-TILE count state (LOCK-10 q(7)), display only.
		var tile := UiNeedTile.new(str(t[1]), int(t[2]), int(t[3]), UiNeedTile.Size.M, P0Logic.icon(str(t[0])), true)
		tile.theme = UiKit.theme()
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tile)
	v.add_child(row)

# ---------------------------------------------------------------- one-line teaching cards (§14.3)
const TIPS_PATH := "user://p0_tips.json"

## A one-sentence card above the quick bar, once per account on this device; tap or 7 s to dismiss.
## Never a hand animation, never moves the player (§14.3 "不画手指动画循环").
## A TipCard (q(44): the eight P0 sentences in P0Guide.TIPS, each once; shown in order through P0Guide.TipQueue,
## timed like a Toast and closed by doing what it teaches, a tap, or time). `_text` is ignored: the copy is P0Guide's.
func teach(key: String, _text := "") -> void:
	_load_tips()
	if tips == null: tips = P0Guide.TipQueue.new(_taught)
	tips.request(key)

## The player did what the tip on screen teaches (sow / cast / cook / heat): it closes now.
func tip_did(action: String) -> void:
	if tips and tips.did(action): _hide_tip(false)

func _hide_tip(close_queue := true) -> void:
	_teach_left = 0.0
	if _teach: _teach.hide()
	if close_queue and tips: tips.close()

func _show_tip(text: String) -> void:
	for k in tips.seen: _taught[k] = true
	_save_tips()
	if _teach == null:
		_teach = PanelContainer.new()
		_teach.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_teach.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_teach.add_theme_stylebox_override("panel", _box(Color("2f3a33"), 14, Color("2f3a33"), 0, Vector4(12, 8, 12, 8)))
		var l := _label("", 11, PAPER, true)
		l.name = "Text"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_teach.add_child(l)
		_teach.gui_input.connect(func(e: InputEvent):
			if P0Ui.is_tap(e) or (e is InputEventScreenTouch and e.pressed): _hide_tip())
		root.add_child(_teach)
		_place_controls()
	(_teach.get_node("Text") as Label).text = text
	_teach.show()
	_teach_left = P0Guide.tip_seconds(text)

# ---------------------------------------------------------------- M2: kitchen, catch and dish cards
## Stove panel (§7.2.7, COOK-2a/2b): Cookbook (known pages cook in one tap, missing ones say what is short)
## and Experiment (free slots from the bag). Cooking costs no Energy.
func open_kitchen(tab := "") -> void:
	teach("cook")   # Tap Cook to grill your first fish (§14.2 minute 14–16)
	if tab != "": _kitchen_tab = tab
	var ck: Dictionary = view.get("cooking", {})
	var lvl := int(view.get("skills", {}).get("cooking", {}).get("level", 1))
	var v := _sheet(540 if _kitchen_tab == "cookbook" else 440, "Stove · Empty · Cooking Lv%d" % lvl, "stove")
	modal_kind = "kitchen"
	_refresh_hud()   # the kitchen is the farmhouse's stove corner: the chip reads "Shanghai · Farmhouse"
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	var pages: Array = ck.get("cookbook", [])
	var known := pages.filter(func(p): return p.get("known", false)).size()
	for t in [["cookbook", "Cookbook %d/%d" % [known, pages.size()]], ["experiment", "Experiment"]]:
		var b := _pill_button(str(t[1]), t[0] == _kitchen_tab)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key := str(t[0])
		b.pressed.connect(func(): open_kitchen(key))
		tabs.add_child(b)
	v.add_child(tabs)
	v.add_child(_label(P0Logic.meal_line(view), 8, INK2))
	if _kitchen_tab == "cookbook": _cookbook(v, pages)
	else: _experiment(v, int(ck.get("slots", 2)))

func _cookbook(v: VBoxContainer, pages: Array) -> void:
	var scroll := TouchScrollContainer.new()   # drags that start on a row or cell still scroll (WP7-B F-04 §4)
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	v.add_child(scroll)
	var order := pages.duplicate()
	order.sort_custom(func(a, b):
		if bool(a.known) != bool(b.known): return bool(a.known)
		if bool(a.get("can_cook", false)) != bool(b.get("can_cook", false)): return bool(a.get("can_cook", false))
		return int(a.rarity) < int(b.rarity))
	for page in order:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		h.custom_minimum_size = Vector2(0, 46)
		var known := bool(page.get("known", false))
		var ic := _icon(str(page.id) if known else "question", 30)
		if not known: ic.modulate = Color(1, 1, 1, 0.35)
		h.add_child(ic)
		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_theme_constant_override("separation", 0)
		var nm := HBoxContainer.new()
		nm.add_theme_constant_override("separation", 4)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(7, 7)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = P0Logic.rarity_color(int(page.rarity))
		nm.add_child(dot)
		nm.add_child(_label(str(page.name) if known else "Unknown dish", 10, INK if known else INK2, true))
		mid.add_child(nm)
		mid.add_child(_label(P0Logic.page_line(view, page), 8, INK2))
		var parts: Array = []
		for token in page.get("in", []):
			parts.append(P0Logic.ingredient_label(view, str(token)) + ("" if not known or str(token).length() <= 2 else " · have %d" % P0Logic.bag_count(view, str(token))))
		var ing := _label(" + ".join(parts) if known else ("1 ingredient" if int(page.get("slots", 1)) == 1 else "%d ingredients" % int(page.get("slots", 1))) + " · discover it in Experiment", 8, INK2)
		ing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mid.add_child(ing)
		h.add_child(mid)
		if known:
			var slots_ok := int(page.get("slots", 1)) <= int(view.get("cooking", {}).get("slots", 2))
			var b := _pill_button("Cook" if page.get("can_cook", false) else ("Cooking Lv4" if not slots_ok else "Missing"), true)
			b.custom_minimum_size = Vector2(70, 30)
			b.disabled = not page.get("can_cook", false)
			var pid := str(page.id)
			b.pressed.connect(func(): close_modal(); command.emit({"type": "cook", "recipe": pid}))
			h.add_child(b)
		else:
			var b := _pill_button("Try ›", false)
			b.custom_minimum_size = Vector2(56, 30)
			b.pressed.connect(func(): open_kitchen("experiment"))
			h.add_child(b)
		list.add_child(h)

func _experiment(v: VBoxContainer, slots: int) -> void:
	_exp_slots = _exp_slots.filter(func(id): return P0Logic.bag_count(view, str(id)) > 0)
	while _exp_slots.size() > slots: _exp_slots.pop_back()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 3:
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(70, 70)
		if i >= slots:
			cell.add_theme_stylebox_override("panel", _box(DIS, 35, DIS, 0, Vector4(4, 4, 4, 4)))
			var lk := _label("Cooking Lv4\n3rd slot", 8, INK2, true)
			lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lk.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cell.add_child(lk)
		elif i < _exp_slots.size():
			cell.add_theme_stylebox_override("panel", _box(PAPER, 35, GREEN_D, 2, Vector4(4, 4, 4, 4)))
			var box := VBoxContainer.new()
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.alignment = BoxContainer.ALIGNMENT_CENTER
			var ic := _icon(str(_exp_slots[i]), 30)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			box.add_child(ic)
			var x := _label("✕ " + P0Logic.item_name(view, str(_exp_slots[i])), 7, INK, true)
			x.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			x.clip_text = true
			box.add_child(x)
			cell.add_child(box)
			var idx := i
			cell.gui_input.connect(func(e: InputEvent):
				if P0Ui.is_tap(e):
					_exp_slots.remove_at(idx)
					open_kitchen("experiment"))
		else:
			cell.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.35), 35, Color("d9c7a6"), 1, Vector4(4, 4, 4, 4)))
		row.add_child(cell)
	v.add_child(row)
	var preview := _label(_experiment_preview(), 10, INK, true)
	preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview.add_theme_stylebox_override("normal", _box(PAPER, 12, EDGE, 1, Vector4(10, 4, 10, 4)))
	v.add_child(preview)
	v.add_child(_label("From your bag", 10, INK, true))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	var shown := {}
	for st in _bag_slots():
		var id := str(st.id)
		if shown.has(id) or not P0Logic.item(view, id).get("cook", false): continue
		shown[id] = true
		var left := P0Logic.bag_count(view, id) - _exp_slots.count(id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(58, 58)
		b.icon = P0Logic.icon(id)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 26)
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.text = "×%d" % left
		b.add_theme_font_size_override("font_size", 9)
		_style_button(b, PAPER, EDGE, 10)
		for k in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
			b.add_theme_color_override(k, Color.WHITE)
		b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.4))
		b.disabled = left <= 0 or _exp_slots.size() >= slots
		b.pressed.connect(func():
			_exp_slots.append(id)
			open_kitchen("experiment"))
		grid.add_child(b)
	if shown.is_empty(): v.add_child(_label("Fish or harvest something to cook.", 9, INK2))
	v.add_child(grid)
	var cook := _pill_button("Cook", true)
	cook.custom_minimum_size = Vector2(0, 40)
	cook.disabled = _exp_slots.is_empty()
	cook.pressed.connect(func():
		var items := _exp_slots.duplicate()
		_exp_slots.clear()
		close_modal()
		command.emit({"type": "cook", "items": items}))
	v.add_child(cook)

## Preview capsule: "? · Fine · 15 s · Unknown dish" — rarity is derivable from what is in the pot (§7.4.1).
func _experiment_preview() -> String:
	if _exp_slots.is_empty(): return "Put 1–%d ingredients in the pot" % int(view.get("cooking", {}).get("slots", 2))
	var fams := {}
	var top := 1
	var mains := 0
	for id in _exp_slots:
		var info := P0Logic.item(view, str(id))
		fams[str(info.get("family", "F"))] = true
		top = maxi(top, int(info.get("rarity", 1)))
		if str(info.get("family", "")) != "S": mains += 1
	if mains == 0: return "Needs a main ingredient"
	var known := P0Logic.match_known(view, _exp_slots)
	if not known.is_empty():
		var kt: Dictionary = view.get("cooking", {}).get("tiers", {}).get(str(int(known.rarity)), {})
		return "%s · %s · %d s · In your Cookbook" % [str(known.name), P0Logic.rarity_name(view, int(known.rarity)), int(kt.get("ms", 5000)) / 1000]
	var derive: Array = view.get("cooking", {}).get("derive", [[1, 2, 3], [2, 3, 3], [3, 3, 4], [4, 4, 4]])
	var r := int(derive[top - 1][mini(fams.size(), 3) - 1])
	var t: Dictionary = view.get("cooking", {}).get("tiers", {}).get(str(r), {})
	return "? · %s · %d s · Unknown dish" % [P0Logic.rarity_name(view, r), int(t.get("ms", 5000)) / 1000]

## FISH-3: "Caught! Pond Crucian · Common", XP lines, Fish-dex count, first-catch line.
func show_catch(fish_id: String, rarity: int, first_xp: int) -> void:
	# FISH-3: small cream card under the leaping fish; the scene stays bright (the +XP float is in it).
	var v := _scene_card(0.815, 0.54, 2.5)
	modal_kind = "card"
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 4)
	var dot := _RarityDot.new()
	dot.color = P0Logic.rarity_color(rarity)
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.add_child(dot)
	title.add_child(_label("Caught! %s" % P0Logic.item_name(view, fish_id), 13, INK, true))
	title.add_child(_label("·", 13, INK2, true))
	title.add_child(_label(P0Logic.rarity_name(view, rarity), 13, P0Logic.rarity_text_color(rarity), true))
	v.add_child(title)
	var dex: Array = view.get("fishing", {}).get("dex", [])
	var got := dex.filter(func(d): return int(d.get("caught", 0)) > 0).size()
	v.add_child(_label("Fish-dex %d/%d" % [got, dex.size()], 9, INK2, true))
	if first_xp > 0:
		# First catch of a species: a gold chip that shines for under three seconds.
		var chip := PanelContainer.new()
		var sb := _box(GOLD, 11, GOLD_D, 1, Vector4(8, 3, 9, 3))
		sb.shadow_color = Color(0.89, 0.70, 0.25, 0.45)
		sb.shadow_size = 8
		chip.add_theme_stylebox_override("panel", sb)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var ch := HBoxContainer.new()
		ch.add_theme_constant_override("separation", 4)
		ch.add_child(_icon("star", 11))
		ch.add_child(_label("First catch! +%d XP" % first_xp, 9, INK, true))
		chip.add_child(ch)
		v.add_child(chip)
		var tw := chip.create_tween().set_loops(3)
		tw.tween_property(sb, "shadow_size", 2, 0.5)
		tw.tween_property(sb, "shadow_size", 8, 0.5)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 5)
	v.add_child(gap)
	var keep := _pill_button("Keep fishing", true)
	keep.custom_minimum_size = Vector2(0, 37)
	keep.pressed.connect(close_modal)
	v.add_child(keep)

## FISH-5 / 5-2: four-line card — the fish that got away (glowing silhouette lighting up in a mini
## Fish-dex), what it needs, what that unlocks, Energy back. Level gate, rod gate, first lock.
func show_got_away(ev: Dictionary) -> void:
	var v := _scene_card(0.907, 0.46, 3.0)
	modal_kind = "card"
	var rarity := int(ev.get("rarity", 2))
	var fish := str(ev.get("fish", ""))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(73, 0)
	left.add_theme_constant_override("separation", 5)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	var sil := _Glow.new()
	sil.texture = P0Logic.icon("fish_glow")
	sil.color = P0Logic.rarity_color(rarity)
	sil.custom_minimum_size = Vector2(60, 60)
	sil.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(sil)
	left.add_child(_dex_mini(fish))
	h.add_child(left)
	var lines := VBoxContainer.new()
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_theme_constant_override("separation", 1)
	var rod_gate := not ev.has("need_level")
	var title := ""
	var body: Array = []
	if rod_gate:
		title = "Too heavy for your rod"
		var rod := P0Logic.rod_for(view, rarity)
		if not rod.is_empty(): body.append("%s · Fishing Lv%d · %d coins" % [str(rod.name), int(rod.level), int(rod.price)])
		body.append("Lands %s fish" % P0Logic.rarity_name(view, rarity))
	else:
		var need := int(ev.need_level)
		var opens := P0Logic.fish_at_level(view, need)
		var first_lock := first_time("first_lock")
		title = "Too strong" if first_lock else "%s fish got away" % P0Logic.rarity_name(view, rarity)
		body.append(P0Logic.level_gate_line(view, need))
		if not opens.is_empty():
			var names := ", ".join(opens.slice(0, 2))
			body.append(("Unlocks %s fish (%s)" % [P0Logic.rarity_name(view, rarity), names]) if first_lock else "Unlocks %s" % names)
	var t := _label(title, 13, INK, true)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_child(t)
	for line in body:
		var l := _label(str(line), 9, INK, true)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lines.add_child(l)
	lines.add_child(_label("%d Energy back" % int(ev.get("refund", 3)), 9, GREEN_D, true))
	h.add_child(lines)
	v.add_child(h)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 5)
	v.add_child(gap)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 5)
	var side := _pill_button("Tackle Shop" if rod_gate else "Fish-dex", false)
	side.pressed.connect(func():
		_drop_modal()
		if rod_gate: tackle_requested.emit()
		else: open_fishdex())
	var keep := _pill_button("Keep fishing", true)
	for b in [side, keep]:
		b.custom_minimum_size = Vector2(0, 37)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		acts.add_child(b)
	keep.pressed.connect(close_modal)
	v.add_child(acts)

## Six Fish-dex tiles around a fish (3 × 2, "Fish-dex" under them): caught ones in their rarity
## colour, the one that just got away lit, the rest blank.
func _dex_mini(fish: String) -> Control:
	var dex: Array = view.get("fishing", {}).get("dex", []).filter(func(d):
		var w = d.get("where", [])
		return not (w is Array) or w.has("pond") or w.has("river"))
	var at := maxi(0, dex.find_custom(func(d): return str(d.id) == fish))
	var from := clampi(at - 2, 0, maxi(0, dex.size() - 6))
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(Color("f1eada"), 7, EDGE, 1, Vector4(3, 3, 3, 2)))
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	for d in dex.slice(from, from + 6):
		var tile := _DexTile.new()
		tile.texture = P0Logic.icon("fish_glow")
		tile.custom_minimum_size = Vector2(19, 19)
		if str(d.id) == fish:
			tile.state = "lit"
			tile.glow = P0Logic.rarity_color(int(d.rarity))
		elif int(d.get("caught", 0)) > 0:
			tile.state = "caught"
			tile.glow = P0Logic.rarity_color(int(d.rarity))
		grid.add_child(tile)
	col.add_child(grid)
	var cap := _label("Fish-dex", 7, INK2, true)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
	box.add_child(col)
	return box

## A result card placed like the design's .modal (centred, top at a share of the screen, width a share
## of it) over an undimmed scene. Tapping outside or the button closes it; it also closes after auto_s.
func _scene_card(width_frac: float, top_frac: float, auto_s: float) -> VBoxContainer:
	var vp := root.size
	var w := roundf(vp.x * width_frac)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(w, 0)
	panel.position = Vector2(roundf((vp.x - w) * 0.5), roundf(vp.y * top_frac))
	panel.add_theme_stylebox_override("panel", _box(PAPER, 13, EDGE, 1, Vector4(13, 12, 13, 12)))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	_open_modal(panel, 0.0)
	var holder_id := _modal.get_instance_id()
	if auto_s > 0.0:
		get_tree().create_timer(auto_s).timeout.connect(func():
			if is_instance_valid(_modal) and _modal.get_instance_id() == holder_id: close_modal())
	return v

## True the first time a key comes up on this device (kept with the teaching tips).
func first_time(key: String) -> bool:
	_load_tips()
	if _taught.has(key): return false
	_taught[key] = true
	_save_tips()
	return true

func _load_tips() -> void:
	if _taught.is_empty() and FileAccess.file_exists(TIPS_PATH):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(TIPS_PATH))
		if saved is Dictionary: _taught = saved

func _save_tips() -> void:
	var f := FileAccess.open(TIPS_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(_taught))

func _card_buttons() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var dex := _pill_button("Fish-dex", false)
	dex.custom_minimum_size = Vector2(90, 32)
	dex.pressed.connect(func(): _drop_modal(); open_fishdex())
	row.add_child(dex)
	var ok := _pill_button("Keep fishing", true)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.pressed.connect(close_modal)
	row.add_child(ok)
	return row

## FISH-6 (P0 cut): rarity sections; caught = full colour + count, broke free = tinted silhouette with
## the level it needs, never seen = grey silhouette with where it lives.
func open_fishdex() -> void:
	var dex: Array = view.get("fishing", {}).get("dex", [])
	var got := dex.filter(func(d): return int(d.get("caught", 0)) > 0).size()
	var v := _sheet(470, "Fish-dex", "fish_crucian")
	modal_kind = "fishdex"
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var kinds := UiNeedTile.new("Kinds", got, dex.size(), UiNeedTile.Size.M, P0Logic.icon("fish_crucian"), true)
	kinds.theme = UiKit.theme()
	kinds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(kinds)
	var tv := VBoxContainer.new()
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_child(_label("%s · %s" % [str(view.get("fishing", {}).get("rod", "Starter Rod")), "holds up to %s" % P0Logic.rarity_name(view, int(view.get("fishing", {}).get("rod_reach", 2)))], 9, INK2))
	top.add_child(tv)
	v.add_child(top)
	for r in [1, 2, 3, 4]:
		var group := dex.filter(func(d): return int(d.get("rarity", 1)) == r)
		if group.is_empty(): continue
		var have := group.filter(func(d): return int(d.get("caught", 0)) > 0).size()
		var head := HBoxContainer.new()
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = P0Logic.rarity_color(r)
		head.add_child(dot)
		head.add_child(_label(" %s  %d/%d" % [P0Logic.rarity_name(view, r), have, group.size()], 10, INK, true))
		v.add_child(head)
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		for d in group:
			grid.add_child(_dex_cell(d))
		v.add_child(grid)

func _dex_cell(d: Dictionary) -> Control:
	var id := str(d.id)
	var n := int(d.get("caught", 0))
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(78, 78)
	cell.add_theme_stylebox_override("panel", _box(PAPER if n > 0 else Color(1, 1, 1, 0.45), 10, P0Logic.rarity_color(int(d.rarity)) if n > 0 else EDGE, 2 if n > 0 else 1, Vector4(4, 4, 4, 3)))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := _icon(id if n > 0 else "fish_glow", 34)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if n == 0: ic.modulate = P0Logic.rarity_color(int(d.rarity)) if d.get("seen", false) else Color("c9c4b6")
	box.add_child(ic)
	var name := _label(P0Logic.item_name(view, id) if n > 0 or d.get("seen", false) else "???", 8, INK if n > 0 else INK2, true)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.clip_text = true
	box.add_child(name)
	var where: Array = d.get("where", [])
	var note := "×%d" % n if n > 0 else ("Fishing Lv%d" % int(d.level) if int(d.level) > int(view.get("skills", {}).get("fishing", {}).get("level", 1)) else " · ".join(where.map(func(w): return str(w).capitalize())))
	var nl := _label(note, 7, INK2)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(nl)
	cell.add_child(box)
	return cell

## COOK-4 / COOK-6: the dish slides out; Eat now or Keep (bag).
func show_dish(ev: Dictionary, xp_lines: Array) -> void:
	var card := _center_card(290)
	modal_kind = "card"
	var dish := str(ev.get("dish", ""))
	var q := int(ev.get("quality", 0))
	var id := dish if q == 0 else "%s@%s" % [dish, ["plain", "good", "perfect"][q]]
	var info := P0Logic.item(view, id)
	var ic := _icon(dish, 72)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.add_child(ic)
	var mystery := bool(ev.get("mystery", false))
	var mc := P0Logic.mystery_card(ev)
	var title := str(mc.title) if mystery else P0Logic.dish_label(view, id)
	var t := _label(title, 15, INK, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(t)
	var sub := str(mc.sub) if mystery else "%s%s · +%d Energy" % [["", "Good · ", "Perfect · "][q], P0Logic.rarity_name(view, int(info.get("rarity", 1))), int(info.get("full", 20))]
	var s2 := _label(sub, 10, INK2, true)
	s2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(s2)
	if int(ev.get("qty", 1)) > 1:
		var extra := _label("Perfect pot · a second portion", 9, AMBER_D, true)
		extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(extra)
	for line in xp_lines:
		var l := _label(str(line), 11, Color("1e9bb0"), true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(l)
	var eb := P0Logic.eat_button(view, id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var eat := _pill_button(str(eb.text), true)
	eat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eat.disabled = not eb.get("enabled", false)
	eat.add_theme_font_size_override("font_size", 10)
	var confirm := str(eb.get("confirm", ""))
	eat.pressed.connect(func():
		if confirm != "" and eat.text != confirm:
			eat.text = confirm
			return
		close_modal()
		command.emit({"type": "eat", "item": id}))
	if mc.eat or not mystery: row.add_child(eat)
	else: eat.free()
	var keep := _pill_button("Keep" if mc.eat or not mystery else "OK", false)
	keep.custom_minimum_size = Vector2(70, 32)
	keep.pressed.connect(close_modal)
	row.add_child(keep)
	card.add_child(row)
	var ml := _label(P0Logic.meal_line(view), 8, INK2)
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(ml)

# ---------------------------------------------------------------- helpers
## One press = one action. Touch is emulated as a left mouse button (project default), so reacting to
## both InputEventScreenTouch and InputEventMouseButton would fire toggles and commands twice.
static func is_tap(e: InputEvent) -> bool:
	return e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT

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
	# Icons keep their own colours (the shared theme tints button icons dark).
	for k in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.45))

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
	## Scene area: a press-and-drag is the floating joystick (§10.1); a short tap picks a facility;
	## a double tap recenters; two fingers pinch-zoom (CTRL-1). Thresholds live in GestureArbiter (WP7-B F-04).
	var ui: P0Ui
	var _arb := GestureArbiter.new(GestureArbiter.Mode.SCENE)
	func _ready() -> void: mouse_filter = Control.MOUSE_FILTER_STOP
	func end_stick() -> void:
		# A pinch cut short (a world change, the app going to the background) still ends: its zoom springs back.
		var pinching := _arb.is_pinching()
		_arb.reset()
		queue_redraw()
		if pinching and ui != null: ui.zoom_end.emit()
	func _notification(what: int) -> void:
		if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT] and _arb.is_pinching(): end_stick()
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			ui.zoom.emit(0.9 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1, get_global_transform_with_canvas() * e.position)
			ui.zoom_end.emit()
			return
		for o in _arb.feed(e, Time.get_ticks_msec()):
			match o.kind:
				&"joystick_move":
					ui.joystick.emit(o.vector)
					queue_redraw()
				&"joystick_end":
					ui.joystick.emit(Vector2.ZERO)
					queue_redraw()
				&"tap":
					if ui._tap_at(get_global_transform() * o.pos, bool(o.double)): _arb.consume_tap()
				# Screen point for the camera: the canvas transform includes this UI layer's offset. Taps above go to
				# _tap_at in the UI's own global space (its markers live there); with P0Ui's layer at the origin the
				# two agree, so keep this pair in step if the layer ever moves (刘邦 on #47).
				&"pinch": ui.zoom.emit(o.factor, get_global_transform_with_canvas() * o.center)
				&"pinch_end": ui.zoom_end.emit()
	func _draw() -> void:
		var start := _arb.origin()
		var now := _arb.position()
		if not _arb.is_steering() or now.distance_to(start) < GestureArbiter.TAP_SLOP: return
		var radius := _arb.stick_radius
		draw_circle(start, radius, Color(1, 1, 1, 0.35))
		draw_arc(start, radius, 0, TAU, 48, Color(0.37, 0.66, 0.35, 0.7), 2.0)
		var k := start + ((now - start).limit_length(radius))
		draw_circle(k, radius * 0.45, Color(0.98, 0.97, 0.94, 0.95))
		draw_circle(k, radius * 0.3, Color(0.5, 0.78, 0.42))

class _RarityDot extends Control:   # FISH-3 title dot: rarity colour in a cream ring
	var color := Color.WHITE
	func _draw() -> void:
		draw_circle(size * 0.5, size.x * 0.5, P0Ui.PAPER)
		draw_circle(size * 0.5, size.x * 0.5 - 1.0, color)

class _Glow extends Control:   # FISH-5 silhouette with a soft rarity glow (kit-cook .four .sil .big)
	var texture: Texture2D
	var color := Color.WHITE
	func _draw() -> void:
		if texture == null: return
		var r := Rect2(Vector2.ZERO, size)
		for i in 3:
			var g := 2.5 + i * 2.5
			draw_texture_rect(texture, r.grow(g), false, Color(color, 0.16))
		draw_texture_rect(texture, r, false, color)

class _DexTile extends Control:   # FISH-5 mini Fish-dex tile: blank / caught (rarity colour) / lit (grey + glow ring)
	var texture: Texture2D
	var state := ""
	var glow := Color.WHITE
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if state == "lit":
			draw_rect(r.grow(2.0), Color(glow, 0.35), true)
		var sb := StyleBoxFlat.new()
		sb.bg_color = P0Ui.PAPER
		sb.border_color = Color(glow, 0.8) if state == "lit" else P0Ui.EDGE
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		draw_style_box(sb, r)
		if texture:
			var tint := glow if state == "caught" else Color("8a918c") if state == "lit" else Color("cfc6b0")
			draw_texture_rect(texture, r.grow(-size.x * 0.15), false, tint)

## Skill level ring on the Skills sheet (progress within the level). Item have / need is UiNeedTile (LOCK-10).
class _LevelRing extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 3
		draw_circle(c, r, Color("fbf8f1"))
		draw_arc(c, r, 0, TAU, 64, Color(0.18, 0.23, 0.2, 0.12), 4.0, true)
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * clampf(float(get_meta("pct", 0.0)), 0.0, 1.0), 64, Color("7fc66a"), 4.0, true)
		var tex: Texture2D = get_meta("icon") if has_meta("icon") else null
		if tex: draw_texture_rect(tex, Rect2(c - Vector2(r, r) * 0.62, Vector2(r, r) * 1.24), false)
		var text := str(get_meta("text", ""))
		if text != "":
			var font := get_theme_default_font()
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string(font, c + Vector2(-w * 0.5, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("2f3a33"))

class _CapBar extends Control:
	func _draw() -> void:
		var pct := float(get_meta("pct", 0.0))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.18, 0.23, 0.2, 0.12))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * pct, size.y)), Color("e3b341") if pct >= 0.9 else Color("7fc66a"))
