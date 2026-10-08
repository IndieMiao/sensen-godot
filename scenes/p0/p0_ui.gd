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
## A target in another space (TodayRow `Show on map`): leave for the map and point at its pin ("home",
## "pond:<id>", "tackle").
signal show_on_map(target: String)
signal home_choice(choice: String)
signal recenter()
signal place_pressed()
signal home_requested()        # FISH-4 "Go home · Free"
signal tackle_requested()      # FISH-5 rod variant "Tackle Shop"

const _RESIDENT_SHEET_H := 443.0   # RES-PIP: Sheet 443 of 800
const _CLOSE_ABOVE_SHEET := 6.0    # RES-PIP: Close · 44 px sits 6 above the sheet, 16 in from the right
const _CLOSE_ABOVE_SPECIALTY := 2.0   # MARKET-SPECIALTY: Close 44 at (300, 617), the sheet at y 663
const _FLOAT_HUG_CHARS := 32         # longer float copy wraps to two lines (FloatText Layout=Wrap)
const _CLOSE_ABOVE_CARD := 8.0     # RES-KAI-TALK: 8 above the dialogue bar, flush with its right edge
const _AFFINITY_INSET := 8.0       # RES-KAI-TALK: the affinity float sits 8 in from the bar's left edge …
const _AFFINITY_ABOVE := 6.0       # … and 6 above its top
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
var _icons := {}          # id -> UiWorldIconButton (SGODOT-250)
var _name_bars := {}      # id -> UiWorldNameBar
var _npc_tags := {}       # id -> UiNpcNameTag
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
## The pond the tackle keeper names when no outpost ctx says which (the map's tackle pin before SGODOT-227).
var tackle_place := "Reed Pond"
var bar_mode := "farm"          # "farm" (seeds) or "fish" (bait) — the quick bar holds the current action's consumables
var surface := "farm"
## Set by the runtime: true when the current world can move its camera to a spot (p0_show_spot). Show
## buttons (Today, NeedSource) only appear then, so a Show never closes a panel and does nothing (LOCK-08).
var can_show_spot := Callable()
## The resident id within reach in an outpost, "" elsewhere (the runtime asks the world's p0_near_resident).
var near_resident := Callable()
## Where the player is (the session's space: home = the farm and the farmhouse, pond, outpost, mine, map); set by
## the runtime on every attach. "" without a runtime (tests, the gallery): space_here() then goes by the surface.
var space := ""
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
	if dev_tools_on(OS.is_debug_build(), P0Session.is_demo_build()): _build_dev()
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
	if tips and not modal_kind in ["card", "kitchen_card"]:   # the farmhouse's COOK-4 is a result card too
		var key := tips.next()
		if key != "": _show_tip(str(P0Guide.TIPS[key]))

func _build_hud() -> void:
	hud = UiHud.new()
	hud.theme = UiKit.theme()
	hud.safe_top = safe_top()
	hud.avatar_pressed.connect(open_profile)   # LOCK-06: the avatar opens Profile (SGODOT-225)
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
	_radial.picked.connect(func(id: String):
		if id != bar_mode: set_mode(id)
		_keys.pop_tool())   # the key's tool badge pops with the pick, the current action's too (247)
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

## The +1h / +4h clock buttons: test builds only. The demo APK is a debug export too, but its server has no dev
## routes (P0_DEV=0, dev/skip is 404) and the buttons covered the Toast's end (李元芳, int6), so it has none.
static func dev_tools_on(debug_build: bool, demo_build: bool) -> bool:
	return debug_build and not demo_build

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
	if _bag != null and is_instance_valid(_bag) and modal_kind in ["bag", "gear", "gift"]: _bag.refresh(v)
	if _counter != null and is_instance_valid(_counter) and modal_kind == "counter":
		var was: String = _counter.section
		_counter.refresh(v)
		if was == "board" or _counter.is_short(): _fill_board(_counter)   # board rows follow Accept / Deliver (only on change)
	if _profile != null and is_instance_valid(_profile) and modal_kind == "profile": _profile.update(v)
	if workbench() != null: _workbench.refresh(v)
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
	_bar.visible = _bar_shown() and (_modal == null or is_bar_docked())   # docked in the bag drawer it stays
	_bar.bag_only = not action
	_bar_sig = []
	if _radial.is_open(): _radial.close()
	_bar.cancel_drag()   # no lifted slot or drop zones left over when fishing starts or the map opens
	_creel.visible = action and bar_mode == "fish"
	_status.visible = action and _status_text.text != ""
	if _dev_box: _dev_box.visible = world
	for c in _cards.values(): (c as Control).visible = false
	for b in _badges.values(): (b as Control).visible = false
	for m in _icons.values() + _name_bars.values() + _npc_tags.values(): (m as Control).visible = false
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
	# Over the bar it came off: on the scene, or over the bag drawer's top row when the bar is docked there (the
	# drawer and its scrim sit above the scene layer, so it goes on the drawer's layer then; 刘邦 on #38).
	(_modal if is_bar_docked() and _modal != null else _kit).add_child(_undo_toast)
	# Its height is only known once the message has wrapped at the card's width: refit then, keeping the bottom edge.
	var t := _undo_toast
	t.minimum_size_changed.connect(func(): if is_instance_valid(t): t.reset_size())
	t.resized.connect(_place_undo_toast)
	t.reset_size()
	_place_undo_toast()
	_undo_toast.undo_pressed.connect(func(): _undo_remove(was))

## BAR-DRAG-4: left 16 (the page margin), its bottom SPACE_WITHIN over the bar's top edge, wherever the bar is.
func _place_undo_toast() -> void:
	if _undo_toast == null or not is_instance_valid(_undo_toast): return
	_undo_toast.global_position = Vector2(_kit.global_position.x + UiTokens.SPACE_PAGE,
		_bar.get_global_rect().position.y - UiTokens.SPACE_WITHIN - _undo_toast.size.y)

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

# ---------------------------------------------------------------- world prompts (SGODOT-250, LOCK-07 v2 / LOCK-16 v2)
## A facility within view and about 8 m: its icon button (WorldIconButton 1674:101157) centred on `screen` (this UI's
## coordinates, like tag()). `near` grows a seat 1.1× with a primary edge; `status` (a UiStatusBadge.State, -1 none)
## turns the whole button into the StatusBadge. A tap on it is a tap on `hit` (default `screen`), with tapped_card =
## id. Call it every frame for each shown facility that is not the open one; it folds that facility's name strip if
## it was open. Hidden under a card or drawer, and outside the band between the HUD and the quick bar.
func world_icon(id: String, icon: Texture2D, screen: Vector2, show: bool, near := false, status := -1, hit := Vector2.INF) -> void:
	var b: UiWorldIconButton = _icons.get(id)
	if b == null:
		b = UiWorldIconButton.new()
		_kit.add_child(b)
		_kit.move_child(b, 0)
		_icons[id] = b
	var on := show and _modal == null
	var bar: UiWorldNameBar = _name_bars.get(id)
	if bar != null and bar.visible: _fold_name_bar(bar)
	b.visible = on and (bar == null or not bar.visible) and _marker_area().has_point(screen)
	if not on: return
	_card_hits[id] = screen if hit == Vector2.INF else hit
	b.icon = icon
	b.near = near
	b.status = status
	b.place_at(screen)

## The one facility nearest and within reach: its name strip (WorldNameBar 1674:101190) opens from the icon button's
## spot in 160 ms — icon + `text` + at most one `fact` ("" for none). `side` UiWorldNameBar.Dir (the way the
## character faces), -1 = right; either way it flips at a screen edge. `dimmed`: used today (Rested today). With
## show false (or a world_icon call for the same id) it folds back, then the icon button returns.
func name_bar(id: String, icon: Texture2D, text: String, fact: String, screen: Vector2, show: bool, side := -1, dimmed := false, status := -1, hit := Vector2.INF) -> void:
	var bar: UiWorldNameBar = _name_bars.get(id)
	if bar == null:
		bar = UiWorldNameBar.new()
		bar.theme = UiKit.theme()
		bar.visible = false   # opens below
		_kit.add_child(bar)
		_kit.move_child(bar, 0)
		_name_bars[id] = bar
	if not (show and _modal == null):
		if bar.visible: _fold_name_bar(bar)
		return
	_card_hits[id] = screen if hit == Vector2.INF else hit
	bar.icon = icon
	bar.text = text
	bar.fact = fact
	bar.dimmed = dimmed
	bar.status = status
	bar.side = _name_bar_side(bar, screen, UiWorldNameBar.Dir.RIGHT if side < 0 else side, id)
	bar.anchor_at(screen + Vector2(_name_bar_shift(bar.rect_for(screen, bar.side)), 0.0))
	var b: UiWorldIconButton = _icons.get(id)
	if b: b.visible = false   # the strip stands in for its button
	_raise_marker(bar)   # the open strip draws over every icon button and badge (哪吒: a stove badge sat on a card)
	if not bar.visible or bar.get_meta("folding", false):
		if not bar.visible: bar.set_openness(0.0)
		bar.visible = true
		bar.set_meta("folding", false)
		bar.expand()

## World markers (cards, badges, icon buttons, strips, NPC tags) sit at the bottom of the UI, under the HUD and the
## bar; this one goes to the top of that group.
func _raise_marker(m: Control) -> void:
	var top := m.get_index()
	for group in [_cards, _badges, _icons, _name_bars, _npc_tags]:
		for other in group.values():
			if (other as Node).get_parent() == _kit: top = maxi(top, (other as Node).get_index())
	if top > m.get_index(): _kit.move_child(m, top)

func _fold_name_bar(bar: UiWorldNameBar) -> void:
	if bar.get_meta("folding", false): return
	bar.set_meta("folding", true)
	bar.collapse()
	var done := func():
		if is_instance_valid(bar) and bar.get_meta("folding", false):
			bar.visible = false
			bar.set_meta("folding", false)
	if bar.openness() <= 0.0 or not bar.is_inside_tree(): done.call()
	else: get_tree().create_timer(UiKit.secs(170.0)).timeout.connect(done)

## A shown world prompt's touch rect (its open strip, else its icon button) in global coordinates; empty when neither shows.
func prompt_rect(id: String) -> Rect2:
	for markers in [_name_bars, _icons]:
		var m: Control = markers.get(id)
		if m != null and m.is_visible_in_tree() and not m.get_meta("folding", false): return m.hit_rect()
	return Rect2()

## Which way a strip opens (不知火舞 on #59), in this order: ① the whole strip on screen with 12 px to spare (贴边翻转);
## ② not over an NPC's name tag or another facility's button (#57; 苏烈 on #59) — covered tags fade while it is open,
## covered buttons sit under it; ③ the way the character faces (`want`). If neither side fits, the roomier one: a
## strip may cover a button, never leave the screen.
func _name_bar_side(bar: UiWorldNameBar, screen: Vector2, want: int, id := "") -> int:
	var other := UiWorldNameBar.Dir.LEFT if want == UiWorldNameBar.Dir.RIGHT else UiWorldNameBar.Dir.RIGHT
	var area := _marker_area()
	var room := func(d: int) -> float:   # px to spare at the tighter edge (negative: off screen)
		var r := bar.rect_for(screen, d)
		return minf(r.position.x - area.position.x, area.end.x - r.end.x) - UiTokens.SPACE_ROW
	var fits_want: bool = room.call(want) >= 0.0
	var fits_other: bool = room.call(other) >= 0.0
	if fits_want != fits_other: return want if fits_want else other
	if not fits_want: return want if room.call(want) >= room.call(other) else other
	if _covers_marker(bar.rect_for(screen, want), id) and not _covers_marker(bar.rect_for(screen, other), id): return other
	return want

## Last resort when neither side fits (a long fact near the middle of a narrow screen): slide the strip back on
## screen, 12 px from the edge, off its button's spot — never off screen (不知火舞 on #59). The tap still goes to `hit`.
func _name_bar_shift(r: Rect2) -> float:
	var area := _marker_area()
	var lo := area.position.x + UiTokens.SPACE_ROW
	var hi := area.end.x - UiTokens.SPACE_ROW
	if r.position.x < lo: return minf(lo - r.position.x, maxf(0.0, hi - r.end.x))
	if r.end.x > hi: return -minf(r.end.x - hi, maxf(0.0, r.position.x - lo))
	return 0.0

## An interactable NPC's name over its head (NpcNameTag 1674:101195): the name only; `highlight` when nearest within
## reach. `talking`: this NPC is the one speaking in the keeper greeting card or the resident dialogue bar — its tag
## stays up and highlighted over that card while every other tag and icon button hides (NPC-G1, #57); under any other
## card or drawer all tags hide. A tag an open name strip covers fades out until the strip folds (#57). Display only —
## the NPC itself takes the tap.
func npc_tag(id: String, text: String, head_screen: Vector2, show: bool, highlight := false, talking := false) -> void:
	var t: UiNpcNameTag = _npc_tags.get(id)
	if t == null:
		t = UiNpcNameTag.new()
		t.theme = UiKit.theme()
		_kit.add_child(t)
		_kit.move_child(t, 0)
		_npc_tags[id] = t
	var over := talking and _modal != null and modal_kind in ["greeting", "resident"]
	# The speaker's tag sits over the card's veil (NPC-G1: it keeps its primary edge); otherwise back among the markers.
	if over and t.get_parent() != root:
		t.reparent(root)
		root.move_child(t, -1)
	elif not over and t.get_parent() != _kit:
		t.reparent(_kit)
		_kit.move_child(t, 0)
	t.visible = show and (_modal == null or over) and _marker_area().has_point(head_screen)
	if not t.visible: return
	t.text = text
	t.highlight = highlight or talking
	t.place_over(head_screen)
	_yield_tag(t, _modal == null and _strip_covers(Rect2(t.position, t.size)))

## Fade a name tag out while an open strip covers it, back in once it folds (120 ms).
func _yield_tag(t: UiNpcNameTag, covered: bool) -> void:
	if bool(t.get_meta("covered", false)) == covered: return
	t.set_meta("covered", covered)
	var tw := t.create_tween()
	tw.tween_property(t, "modulate:a", 0.0 if covered else 1.0, UiKit.secs(120.0))

## Rects (this UI's coordinates) of the name strips open or opening now.
func _open_strips() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for bar in _name_bars.values():
		if (bar as UiWorldNameBar).visible and not bar.get_meta("folding", false): out.append((bar as UiWorldNameBar).full_rect())
	return out

func _strip_covers(r: Rect2) -> bool:
	return _open_strips().any(func(s: Rect2): return s.grow(UiTokens.SPACE_ROW).intersects(r))

## Whether a strip at `strip` would cover an NPC's name tag or another facility's icon button (not `own`'s).
func _covers_marker(strip: Rect2, own: String) -> bool:
	for t in _npc_tags.values():
		var tag := t as UiNpcNameTag
		if tag.visible and strip.grow(UiTokens.SPACE_ROW).intersects(Rect2(tag.position, tag.size)): return true
	for id in _icons:
		var b := _icons[id] as UiWorldIconButton
		if str(id) != own and b.visible and strip.grow(UiTokens.SPACE_WITHIN).intersects(Rect2(b.position, b.size).grow(-8.0)): return true
	return false

## Facility / resident state mark (StatusBadge 1132:79554, STATE-ICONS): display only, the facility takes the tap.
## A scene tap: on a shown finger card it is that facility's tap, elsewhere the world's (also a double tap: a card
## never recenters the camera by accident). Returns true for a card tap, which then can't start a double tap either.
func _tap_at(global_pos: Vector2, double: bool) -> bool:
	# World prompts (SGODOT-250): an open name strip, then an icon button; a tap on either is its facility's tap.
	for markers in [_name_bars, _icons]:
		for id in markers:
			var m: Control = markers[id]
			if m.is_visible_in_tree() and m.hit_rect().has_point(global_pos):
				if _modal == null:
					tapped_card = str(id)
					tapped.emit(_card_hits[id])
					tapped_card = ""
				return true
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
	# 228 293b4190, for every CaptionPill: an open name strip over a mark's caption folds it to the mark while it shows.
	if caption != "" and b.visible and _strip_covers(Rect2(b.position, b.size)):
		b.caption = ""
		_place_marker(b, screen, false)

## Height a shown badge takes over `screen`, so a finger card over the same facility can sit above it.
func badge_height(id: String) -> float:
	var b: UiStatusBadge = _badges.get(id)
	return b.get_combined_minimum_size().y + _BADGE_CARD_GAP if b and b.visible else 0.0

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

## FloatText (1178:82191, UiFloatText from 2B; SGODOT-224): one line rising from `screen` (its bottom centre) in its
## tone; `stack` = the line's place in one reply (each starts 28 higher and 60 ms later, at most 3). Copy longer
## than one line wraps (Layout=Wrap, two lines at most). `tone` also takes the older Color argument (callers in
## other PRs, e.g. SGODOT-231's material notices): any colour draws in the ITEM tone.
func float_text(text: String, screen: Vector2, tone: Variant = UiFloatText.Tone.ITEM, icon: Texture2D = null, stack := 0) -> UiFloatText:
	var t: UiFloatText.Tone = UiFloatText.Tone.ITEM if tone is Color else int(tone)
	var f := UiFloatText.new(text, t, icon, UiFloatText.Layout.WRAP if text.length() > _FLOAT_HUG_CHARS else UiFloatText.Layout.HUG)
	f.theme = UiKit.theme()
	root.add_child(f)
	f.play(screen, stack)
	return f

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
	if _radial.is_open():
		_radial.close()
		return true
	if _modal != null:
		back_modal()
		return true
	return false

## What Back and a scrim tap do to the open layer: its own way back when it has one (a layer opened from the
## resident bar returns to the bar, as its own Close does), else close it (亚瑟 on #37).
var _modal_back := Callable()

func back_modal() -> void:
	if _modal_back.is_valid():
		var back := _modal_back
		_modal_back = Callable()
		back.call()
	else:
		close_modal()

## A world change ends the stick: a finger still down when the farmhouse door took the player in never sends its
## release to this pad (int5 hand test 029–030), so its ring would stay and the old world keep walking.
## The first attach (a world booted as the root scene, P0Runtime.ensure) runs before this UI's _ready built the pad:
## there is no stick to end yet (哪吒: `end_stick` on Nil at every farm start).
func end_stick() -> void:
	if pad != null: (pad as _TouchPad).end_stick()
	joystick.emit(Vector2.ZERO)

func has_modal() -> bool: return _modal != null or (_radial != null and _radial.is_open())

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
	_modal_back = Callable()   # each layer sets its own way back after it opens
	_bag_drag_end()   # a bag cell lifted toward the bar goes with its drawer
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
		if P0Ui.is_tap(e): back_modal())
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

## Bag | Gear drawer (SGODOT-225; LOCK-12 / 13, BAG-2-2 / BAG-2 · Gear): P0BagDrawer from the kit. Tapping a
## cell opens the F-07 bag card (UiInfoSheet, no Sell in the bag); the Gear side lists the tapped slot's
## candidates. No separate Tools & Gear panel and no Outfit tab (p(8)). The drawer follows the view while open.
var bag_side := "bag"
var gear_slot := "fishing"
var _bag: P0BagDrawer
var _eat_armed := ""   # dish whose partial-gain warning was shown; a second Eat eats (§7.17.1)

func open_bag(focus := "", side := "") -> void:
	if side != "": bag_side = side
	var d := P0BagDrawer.new(view, bag_side, focus)
	d.theme = UiKit.theme()
	d.safe_bottom = safe_bottom()
	d.place = space_here()   # home only at the homestead: an outpost room is a room, not home (亚瑟 on #37)
	d.set_gear_slot(gear_slot)
	d.close_requested.connect(close_modal)
	d.side_changed.connect(func(s: String):
		bag_side = s
		modal_kind = "bag" if s == "bag" else "gear")
	d.gear_slot_changed.connect(func(k: String): gear_slot = k)
	d.action_requested.connect(_bag_action)
	d.unavailable_requested.connect(_bag_unavailable)
	d.near = near_resident_info()
	d.pinned = func(id: String) -> bool: return is_pinned(id)
	d.bar_full = func(id: String) -> bool: return bar_action_of(id) != "" and not can_pin(id)
	d.grid.cell_gesture.connect(_on_bag_cell)
	if focus != "" and d.grid.selected_id == focus: d.grid.select(focus)   # the card again, with place and near set
	_eat_armed = ""
	_open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	_bag = d
	modal_kind = "bag" if bag_side == "bag" else "gear"
	# LOCK-12 / q(61): the drawer's first row is the quick bar itself, moved in (its end cell turns into Close);
	# _drop_modal moves it back. Spaces without an action (rooms, the map) have no slots to bring along.
	if not _bar.bag_only:
		dock_bar_into(d.quick_row)
		_bar.visible = true
	_bar_sig = []
	_refresh_bar()

# ---------------------------------------------------------------- the bag's way onto the quick bar (225, q(61))
## A bag cell some bar takes (seeds, fertiliser, bait) lifts on a long press (450 ms, LOCK-12 user decision on 197
## 5e4631b1) and opens only the Pin zone under the docked bar (BAR-DRAG-9); it rides the finger while the grid
## dims. Released on the Pin zone: pinned on its own action's bar (pin_to; a pinned one shows Unpin and unpins);
## on a slot of this bar: placed there, not pinned (place_at); anywhere else, or released in place: nothing.
const _BAG_RIDE_ABOVE := 24.0    # as the bar's own dragged slot (LOCK-04 v1.11)
const _BAG_HOVER_SCALE := 0.8    # over the Pin zone (InventoryCell State=lifted 1641:34159, runtime)
var _bag_drag := {}              # {id, ghost: UiItemCell, zone: UiBarDropZone}

func _on_bag_cell(it: Dictionary, o: Dictionary) -> void:
	var id := str(it.get("id", ""))
	match o.kind:
		&"lift":
			if _bag_drag.is_empty() and is_bar_docked() and bar_action_of(id) != "" and not bool(it.get("stored", false)):
				_bag_lift(it, o.get("pos", Vector2.ZERO))
		&"drag_start", &"drag_move":
			if not _bag_drag.is_empty(): _bag_drag_to(o.pos)
		&"drop":
			if not _bag_drag.is_empty(): _bag_drop(o.pos)
		&"long_press", &"cancel":   # released where it lifted, or the touch was taken: nothing changes
			_bag_drag_end()

func _bag_lift(it: Dictionary, at: Vector2) -> void:
	var id := str(it.id)
	var ghost := UiItemCell.new(UiItemCell.Density.INVENTORY)
	ghost.theme = UiKit.theme()
	ghost.icon = it.get("icon", P0Logic.icon(id))
	ghost.quantity = "×%d" % int(it.get("qty", 0))
	ghost.rarity = int(it.get("rarity", 0))
	ghost.state = UiItemCell.State.LIFTED
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.top_level = true
	ghost.pivot_offset = ghost.custom_minimum_size * 0.5
	_modal.add_child(ghost)
	var zone := UiBarDropZone.new(UiBarDropZone.Kind.UNPIN if is_pinned(id) else UiBarDropZone.Kind.PIN)
	zone.theme = UiKit.theme()
	_modal.add_child(zone)
	zone.center = GestureArbiter.drop_zone_centers(_bar.get_global_rect(), true)[0]
	zone.appear()
	if _bag:
		_bag.grid.modulate.a = UiTokens.OPACITY_PENDING   # the grid dims and takes no drop (不知火舞 on 225)
		_bag.grid.lifted_id = id                          # its own cell turns into a dashed gap (BAR-DRAG-9)
	if _bar.haptics and OS.has_feature("mobile"): Input.vibrate_handheld(20)
	_bag_drag = {id = id, ghost = ghost, zone = zone}
	_bag_drag_to(at)

func _bag_drag_to(at: Vector2) -> void:
	var ghost: UiItemCell = _bag_drag.ghost
	var zone: UiBarDropZone = _bag_drag.zone
	var over := at.distance_to(zone.center) <= GestureArbiter.DROP_ZONE_HIT
	zone.hover = over
	ghost.scale = Vector2.ONE * (_BAG_HOVER_SCALE if over else 1.0)
	ghost.global_position = at - Vector2(ghost.custom_minimum_size.x * 0.5, ghost.custom_minimum_size.y + _BAG_RIDE_ABOVE)
	_bar.set_drop_target(-1 if over or not accepts(str(_bag_drag.id)) else _bar.slot_at(at))

func _bag_drop(at: Vector2) -> void:
	var id := str(_bag_drag.id)
	var on_zone := at.distance_to((_bag_drag.zone as UiBarDropZone).center) <= GestureArbiter.DROP_ZONE_HIT
	var slot := -1 if on_zone or not accepts(id) else _bar.slot_at(at)
	_bag_drag_end()
	if on_zone:
		if is_pinned(id): unpin(id)
		else: pin_to(id)
	elif slot >= 0: place_at(slot, id)
	else: return
	if _bag and _bag.grid.selected_id == id: _bag.grid.select(id)   # its card again: Pin ↔ Unpin

func _bag_drag_end() -> void:
	if _bag_drag.is_empty(): return
	if is_instance_valid(_bag_drag.ghost): (_bag_drag.ghost as Node).queue_free()
	if is_instance_valid(_bag_drag.zone): (_bag_drag.zone as UiBarDropZone).vanish()
	if _bag and is_instance_valid(_bag):
		_bag.grid.modulate.a = 1.0
		_bag.grid.lifted_id = ""
	_bar.set_drop_target(-1)
	_bag_drag = {}

## The resident within reach (near_resident): {id, name, gifted_today}, or {} when there is none.
func near_resident_info() -> Dictionary:
	var id := str(near_resident.call()) if near_resident.is_valid() else ""
	if id == "": return {}
	var def: Dictionary = P0Logic.content().get("residents", {}).get(id, {})
	var r: Dictionary = view.get("residents", {}).get(id, {})
	return {id = id, name = str(def.get("name", r.get("name", ""))), gifted_today = bool(r.get("gift_today", false))}

## A greyed button on the bag card. A dish's `Gift to a resident` says where (李白 on 225); it never leaves the bag.
func _bag_unavailable(action: StringName, id: String, _reason: String) -> void:
	if action == &"gift" and P0ItemInfo.kind_of(view, id) == "dish" and near_resident_info().is_empty():
		toast("Find a resident at an outpost to gift this dish")

## A button on the bag card or a Gear row. The drawer only reports; commands go to the server from here.
func _bag_action(action: StringName, id: String, payload: Dictionary) -> void:
	match action:
		&"bag_room":   # BAG-5: Bag Upgrade I is a homestead matter; Show the house (or the homestead on the map)
			close_modal()
			if show_label("home", space_here(), spot_reachable()) == "Show": show_spot.emit("home")
			else: show_on_map.emit("home")
		&"eat":
			var confirm := str(P0Logic.eat_button(view, id).get("confirm", ""))
			if confirm != "" and _eat_armed != id:
				_eat_armed = id   # say the real gain first; the second Eat eats
				toast(confirm)
				return
			_eat_armed = ""
			close_modal()
			command.emit({"type": "eat", "item": id})
		&"equip":
			command.emit({"type": "equip", "item": id})
		&"lock", &"unlock":   # the title-area lock icon (F-07); Sell All skips locked items (SGODOT-228)
			command.emit({"type": String(action), "item": id})
		&"store":             # farm storage (SGODOT-228 store / take_out); the card shows Store only at home
			if space_here() == "home": command.emit({"type": "store", "item": id, "qty": payload.get("qty", "all")})
		&"take_out":          # a Farm Storage stack's card: Take 10 / Take all (payload qty 10 or "all")
			if space_here() == "home": command.emit({"type": "take_out", "item": id, "qty": payload.get("qty", "all")})
		&"gift":   # a dish's `Gift to <Name>` (不知火舞 on 225): that resident's gift drawer with this dish selected
			var near := near_resident_info()
			if P0ItemInfo.kind_of(view, id) != "dish" or near.is_empty() or bool(near.gifted_today): return
			close_modal()
			open_gift(str(near.id), id)
		&"pin", &"unpin":   # the card's Pin / Unpin (q(61)): on the item's own action's bar; the card then flips
			if is_pinned(id): unpin(id)
			elif not pin_to(id): return   # five pinned: the card already says Bar full · Unpin one first
			if _bag: _bag.grid.select(id)
		_:
			push_warning("P0 bag: no command for %s" % action)

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

## Keeper greeting (KeeperGreeting 1205:83238, LOCK-16; NPC-G1 / G1-2 / G1-3 / G1-4): every keeper greets first.
## `Role · Name`, `Does it · Place`, the line (P0Logic.keeper_lines, facts from view.keepers), then Trade (the counter),
## the question (its answer replaces the line) and Just passing by. role = the counter id ("tackle", "tea", "post",
## "market"); ctx = the outpost's keeper ctx {keeper, place, nearest} (SGODOT-227), passed through untouched and kept
## for the counter's keeper bar.
func open_keeper_greeting(role: String, ctx := {}) -> void:
	if not ctx.is_empty(): _counter_ctx[role] = ctx
	var c: Dictionary = _counter_ctx.get(role, {})
	var lines := P0Logic.keeper_lines(view, role, c)
	var who: Array = P0CounterDrawer.KEEPERS.get(role, ["", ""])
	var name := str(c.get("keeper", who[1]))
	var card := UiDialogueCard.new(P0CounterDrawer.keeper_portrait(name, true), "%s · %s" % [str(c.get("role", who[0])), name], "",
		str(lines.greet))
	card.theme = UiKit.theme()
	card.portrait_size = UiDialogueCard.KEEPER_PORTRAIT
	card.place = str(lines.line)
	var trade := UiCommandButton.new(str(lines.trade))
	trade.activated.connect(func(): open_counter(role))
	card.content.add_child(trade)
	if str(lines.question) != "" and str(lines.answer) != "":
		var ask := UiCommandButton.new(str(lines.question), UiCommandButton.Kind.SECONDARY)
		ask.activated.connect(func(): card.line = str(lines.answer))
		card.content.add_child(ask)
	var bye := UiDismissButton.new(str(lines.leave))
	bye.pressed.connect(close_modal)
	card.content.add_child(bye)
	card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	card.offset_left = UiTokens.SIZE_QUICK_BAR_X
	card.offset_right = -UiTokens.SIZE_QUICK_BAR_X
	card.offset_bottom = -bottom_pad()
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_open_modal(card, 0.0, true)
	modal_kind = "greeting"

## The tackle shop before the outposts open it with their ctx (the map's tackle pin, P0_SHOT "kai").
func open_kai_greeting() -> void:
	open_keeper_greeting("tackle", {"keeper": "Finn", "place": "Xuhui Tackle Shop", "nearest": {"name": tackle_place, "site": "pond"}})

## Counters (SGODOT-224; LOCK-15 / 16; FARM-6, NPC-2, NPC-2-2, NPC-6, NPC-7-P0): one drawer for every counter,
## P0CounterDrawer. role = the shop id ("homestead", "tackle", "market", "tea", "post"); opts: section ("buy" |
## "board" | "specialty": #14 opens the Market Board and City Specialty directly) and ctx (the outpost's keeper ctx).
## The drawer follows the view while open (set_view); its buttons come back here as commands with the shop.
var _counter: P0CounterDrawer
var _counter_ctx := {}   # role -> the last keeper ctx an outpost gave

func open_counter(role: String, opts := {}) -> void:
	if opts.has("ctx"): _counter_ctx[role] = opts.ctx
	var d := P0CounterDrawer.new(view, role, _counter_ctx.get(role, {}), str(opts.get("section", "buy")))
	d.theme = UiKit.theme()
	d.safe_bottom = safe_bottom()
	d.close_requested.connect(close_modal)
	d.action_requested.connect(func(a: StringName, id: String, p: Dictionary): _counter_action(role, a, id, p))
	d.section_changed.connect(func(sec: String): if sec == "board": _fill_board(d))
	_open_modal(d, UiTokens.OPACITY_SCRIM_COUNTER, true)
	if d.section == "specialty": _close_above(d, _CLOSE_ABOVE_SPECIALTY, P0CounterDrawer.SPECIALTY_PAD)   # MARKET-SPECIALTY
	_counter = d
	modal_kind = "counter"
	if d.section == "board" or d.is_short(): _fill_board(d)

func _counter_action(role: String, action: StringName, id: String, payload: Dictionary) -> void:
	match action:
		&"buy": command.emit({"type": "buy", "item": id, "qty": int(payload.get("qty", 1)), "shop": role})
		&"sell": command.emit({"type": "sell", "item": id, "qty": payload.get("qty", 1), "shop": role})
		&"drink": command.emit({"type": "drink", "item": id, "shop": role})
		&"lock", &"unlock": command.emit({"type": String(action), "item": id})
		_: push_warning("P0 counter: no command for %s" % action)

## A counter's events (P0Runtime): the keeper says what just happened (TEA-DONE `Enjoy. Next cup's 50 coins.`,
## the rod strung after buying it); the drawer itself follows the view.
func counter_events(events: Array) -> void:
	if _counter == null or not is_instance_valid(_counter): return
	var bar := _counter.keeper_bar   # none at the unattended Homestead Stall (p(6)): its board rows still turn Done
	for ev in events:
		match str(ev.get("kind", "")):
			"drink":
				if bar == null: continue
				var price := int(view.get("drinks", {}).get("price", 0))
				bar.line = ("Enjoy. Next cup's %d coins." % price) if int(ev.get("left", 0)) > 0 \
					else str(P0Logic.keeper_lines(view, _counter.role, _counter.ctx).get("counter", ""))
			"item":
				if bar != null and str(ev.get("id", "")).begins_with("rod_") and int(ev.get("delta", 0)) > 0:
					bar.line = "Strung and ready — it's on your belt. Swap rods in Bag › Gear."
			"request":
				if str(ev.get("status", "")) == "done": _board_done(_counter, str(ev.get("id", "")), int(ev.get("coins", 0)))

## A board request's own sheet (BOARD-1), from its row's title ›.
func open_board_request(role: String, id: String) -> void:
	P0BoardRequest.open(self, role, id)

## The request BOARD-3 asked the server to drop: {role, id, title, noun, item} until its dropped event arrives.
var pending_drop := {}

## The server dropped a request: BOARD-DROPPED when it was the one confirmed here.
func board_dropped(id: String) -> void:
	if pending_drop.is_empty() or str(pending_drop.get("id", "")) != id: return
	var gone := pending_drop
	pending_drop = {}
	P0BoardRequest.dropped(self, gone)

## A request delivered from this drawer: its row stays, Done, until the drawer closes, and the coins float up from
## where its button was (BOARD-DONE; 不知火舞 on 224: no result card, the page facts follow the view).
func _board_done(d: P0CounterDrawer, id: String, coins: int) -> void:
	var row: Dictionary = d.get_meta("board_seen", {}).get(id, {})
	if row.is_empty(): return
	var done: Dictionary = d.get_meta("board_done", {})
	done[int(row.slot)] = row
	d.set_meta("board_done", done)
	d.set_meta("board_key", 0)
	_fill_board(d)
	var at: Vector2 = d.get_meta("board_spots", {}).get(id, Vector2.INF)
	if at != Vector2.INF and coins > 0:
		float_text("+%d coins" % coins, at - root.global_position, UiFloatText.Tone.COINS, P0Logic.icon("coin"))

## The board page of a counter: the Stall Board or the Market Board (view.boards[stall | market]).
func _fill_board(d: P0CounterDrawer) -> void:
	var board := P0Board.board_id(d.role)
	var cards := P0Board.cards(view, board, d.get_meta("board_done", {}))
	var facts := P0Board.facts(view, board)
	# The runtime sets the view every frame: the rows are rebuilt only when they change, or a tap pressed on one
	# button would be released on its replacement and lost (蒙恬 rc0: the first Accept after switching to the board did
	# nothing). The page facts (a countdown) update in place. The P0 market fills its board while Buy shows too (its
	# height is the taller page's) and re-measures only then.
	var key := [cards, facts.map(func(f): return f[0]), view.get("bag", {})].hash()
	if d.get_meta("board_key", 0) == key:
		var rows := d.board.get_children().filter(func(c): return c is HBoxContainer and not c is UiBoardCard and not c.is_queued_for_deletion())
		for i in mini(rows.size(), facts.size()): ((rows[i] as HBoxContainer).get_child(1) as Label).text = str(facts[i][1])
		return
	d.set_meta("board_key", key)
	# What each row was and where its button sat: a delivery empties the slot before counter_events runs, and the row
	# then turns Done in place with the coins floating up from its button (不知火舞 on 224).
	var seen: Dictionary = d.get_meta("board_seen", {})
	var spots: Dictionary = d.get_meta("board_spots", {})
	for c in d.board.get_children():
		if c is UiBoardCard and c.is_visible_in_tree():
			spots[(c as UiBoardCard).request_id] = (c as UiBoardCard).command_button().get_global_rect().get_center()
		c.hide()
		c.queue_free()
	for c in cards:
		if not bool(c.done): seen[str(c.id)] = c
	d.set_meta("board_seen", seen)
	d.set_meta("board_spots", spots)
	_board(d, facts, cards)
	if d.is_short(): d.fit_height()

## Gear lives in the bag drawer now (p(8)); callers that opened Tools & Gear land on the Gear side.
func open_gear() -> void:
	open_bag("", "gear")

## The older entries now open the counter drawer (SGODOT-224).
func open_stall(tab := "") -> void:
	open_counter("homestead", {"section": tab if tab != "" else "buy"})

func open_tackle(_bubble := "") -> void:
	open_counter("tackle")

## A counter's board page (FARM-6 Stall Board tab, NPC-2-2 Market Board; BOARD-READY / SHORT / DONE): the page facts,
## then one UiBoardCard per request — Track sends accept, Deliver pays coins (no XP), a gap on the button says what is
## missing, a NeedTile shows where it comes from, the title opens the request (BOARD-1).
func _board(d: P0CounterDrawer, facts: Array, cards: Array) -> void:
	for f in facts: d.board.add_child(UiBoardCard.fact_row(str(f[0]), str(f[1])))
	for c in cards:
		var card := UiBoardCard.new()
		card.show_request(c)
		var cmd: Dictionary = c.cmd
		var id := str(c.id)
		card.command_pressed.connect(func(): if not cmd.is_empty(): command.emit(cmd))
		card.unavailable_pressed.connect(func(r: String): toast(r))
		card.need_pressed.connect(func(item: String, tile: UiNeedTile): _show_need_source(tile, item))
		card.info_pressed.connect(func(): open_board_request(d.role, id))
		d.board.add_child(card)

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
		elif show_label(go, space_here(), spot_reachable()) == "Show": show_spot.emit(go)
		else: show_on_map.emit(map_target(go)))   # Tea's outpost, or home from the pond
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
	var card := _center_card(280)
	modal_kind = "home"
	card.add_child(_label("Home · Farmhouse", 13, INK, true))
	var st = view.get("cooking", {}).get("stove", null)
	var kitchen_line := "Kitchen · Cook"
	if st != null: kitchen_line = "Kitchen · Dish ready" if float(st.get("ready_in", 0)) <= 0.0 else "Kitchen · Cooking " + P0Logic.duration(float(st.get("ready_in", 0)))
	var k := _pill_button(kitchen_line, true)
	k.pressed.connect(func(): close_modal(); home_choice.emit("kitchen"))
	card.add_child(k)
	# Rest moved to the bench by the farmhouse (q(30), FARM-7): the door card keeps the kitchen only.
	var bye := _flat_button("Not now")
	bye.pressed.connect(close_modal)
	card.add_child(bye)

## Rest bench sheet (FARM-7-2 482:52, q(30)): the bench is the one Rest entry. Title, state and effect (ObjectHeader),
## one fact row, then Rest (primary, the real gain when near full) or the reason it can't (grey), and Not now / Close.
func open_rest_card() -> void:
	var st := P0Logic.rest_state(view)
	var v := _kit_card()
	modal_kind = "rest"
	v.add_child(UiObjectHeader.new({title = "Rest bench", state = str(st.sheet_state), effect = str(st.effect)}))
	v.add_child(UiFactRow.new(str(st.fact), str(st.fact_value)))
	if str(st.state) != "used":
		var b := UiCommandButton.new(str(st.button) if st.can_rest else "", UiCommandButton.Kind.PRIMARY)
		if not st.can_rest: b.reason = str(st.reason)
		b.activated.connect(func(): close_modal(); command.emit({"type": "rest"}))
		v.add_child(b)
	var bye := UiDismissButton.new(str(st.close))
	bye.pressed.connect(close_modal)
	v.add_child(bye)
	if str(st.note) != "":
		var note := UiKit.label(str(st.note), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(note)

## A centred card in the UI kit's look (InformationSheet 932:71686: surface, card radius, 16 inset, 12 gap) for the
## phase-2 panels; the older P0 cards keep _center_card until they are rebuilt.
func _kit_card() -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.theme = UiKit.theme()
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = UiTokens.SIZE_QUICK_BAR_W
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CARD, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.with_margins(UiTokens.SIZE_SHEET_PAD, UiTokens.SIZE_SHEET_PAD, UiTokens.SIZE_SHEET_PAD, UiTokens.SIZE_SHEET_PAD)
	panel.add_theme_stylebox_override(&"panel", box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", int(UiTokens.SIZE_SHEET_GAP))
	panel.add_child(v)
	center.add_child(panel)
	_open_modal(center, UiTokens.OPACITY_SCRIM_MODAL)
	return v

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
	if _radial.is_open():
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
	_radial.open()   # around the screen centre (247, LOCK-03 v2)

## Today panel (§14.5, LOCK-06): at most three rows right under the HUD chips; Show only moves the camera.
## rows: Today's own (P0Logic.today_rows) unless given, e.g. P0Guide.free_now after the Energy card's Free to do now.
## Show / Show on map by show_label (#37): "pond:<id>", "outpost:<role>" and "map" open the map on that pin.
func open_today(given: Array = []) -> void:
	var rows := given if not given.is_empty() else P0Logic.today_rows(view)
	var shown := rows.map(func(r):
		var d: Dictionary = r.duplicate()
		d.icon = P0Logic.icon(str(r.icon))
		d.action = show_label(str(r.go), space_here(), spot_reachable())
		return d)
	var panel := UiTodayPanel.new(shown)
	panel.theme = UiKit.theme()
	panel.position = Vector2(UiTokens.SIZE_TODAY_PANEL_X, UiTokens.SIZE_TODAY_PANEL_Y + safe_top())
	panel.show_pressed.connect(func(i: int):
		close_modal()
		var go := str(rows[i].go)
		if show_label(go, space_here(), spot_reachable()) == "Show": show_spot.emit(go)
		else: show_on_map.emit(map_target(go)))
	_open_modal(panel, 0.0)
	modal_kind = "today"

## TodayRow action (不知火舞 on 197, 2026-10-08): a target in the current space reads `Show` and only moves the
## camera; a target somewhere else reads `Show on map` (the map opens on its pin). Homestead targets (plots,
## stall, stove) live on the farm; `pond:<id>` and `tackle` are map pins. "" = no target, no button.
const HOME_TARGETS := ["plots", "stall", "stove", "board", "home", "bench"]

static func show_label(go: String, here: String, camera_here: bool) -> String:
	if go == "": return ""
	# The homestead is one space: on the farm or in the farmhouse a farm target is Show (the runtime steps out of the
	# farmhouse first); anywhere else it is Show on map (亚瑟 on #37: the farmhouse used to send it to the map).
	if go in HOME_TARGETS and here in ["home", "farm"]: return "Show" if camera_here else ""
	# On the map every target is a pin: Show flies there (p0_map.p0_show_spot); Browse the map has nothing to do
	# (蒙恬 on #44: Show on map used to close Today and do nothing there).
	if here == "map": return "" if go == "map" else "Show"
	return "Show on map"

## Where the player is for Show and the bag: the runtime's space; without one (tests, the gallery) the surface says
## (farm and room count as home there).
func space_here() -> String:
	if space != "": return space
	return "home" if surface in ["farm", "room"] else ("pond" if surface == "busy" else surface)

## The map pin for a target elsewhere: the homestead for farm targets, else the target itself.
static func map_target(go: String) -> String:
	return "home" if go in HOME_TARGETS else go

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

## Resident dialogue bar (SGODOT-225, LOCK-18): greet first, then choose. Called by the outpost rooms (SGODOT-227)
## for res_pip / res_old_kai. Sends the day's `talk` (first-chat affinity, gift meal: the server decides) and
## shows the bar from P0Logic.resident_bar (SGODOT-228). Returns false when the view has no such resident.
var _resident := ""
var _reply := {}   # {id, line}: the resident's answer shown in the bubble until another resident's bar opens

func open_resident(id: String) -> bool:
	var d := P0Logic.resident_bar(view, id)
	if d.is_empty(): return false
	if _resident != id or modal_kind != "resident": command.emit({"type": "talk", "resident": id})
	if _resident != id: _reply = {}
	_resident = id
	_show_resident(d)
	return true

## RES-KAI-TALK / RESIDENT-GIFT-MYSTERY: with the resident's bar open, an affinity change is a FloatText pill
## (Affinity tone) over the bar's top-left, `+2 · first chat today`, and their answer replaces the bubble line until
## another resident's bar opens. Returns false when the bar is not showing that resident (the caller floats it).
func resident_affinity(ev: Dictionary, reply := "") -> bool:
	var id := str(ev.get("resident", ""))
	if modal_kind != "resident" or id != _resident or _modal == null: return false
	if reply != "": _reply = {"id": id, "line": reply}
	if int(ev.get("delta", 0)) == 0: return true
	var bar: Control = _modal.get_child(1) if _modal.get_child_count() > 1 else null
	var ft := UiFloatText.new(affinity_text(ev), UiFloatText.Tone.AFFINITY)
	ft.theme = UiKit.theme()
	root.add_child(ft)
	var top_left := (bar.global_position - root.global_position) if bar != null else Vector2(UiTokens.SIZE_QUICK_BAR_X, root.size.y * 0.6)
	ft.play(top_left + Vector2(_AFFINITY_INSET + ft.shown_size().x * 0.5, -_AFFINITY_ABOVE))
	return true

## `+2 · first chat today`, `−2 · not a fan` (RES-KAI-TALK, RESIDENT-GIFT-MYSTERY); the other reasons are 刘邦's
## wording pending 李白 (SGODOT-225).
static func affinity_text(ev: Dictionary) -> String:
	var why := ""
	match str(ev.get("reason", "")):
		"chat": why = "first chat today"
		"request": why = "request done"
		"gift":
			why = {"loved": "loved it", "liked": "liked it", "received": "thanks", "not_a_fan": "not a fan"}.get(str(ev.get("verdict", "")), "")
	var n := ("%+d" % int(ev.get("delta", 0))).replace("-", "−")
	return n if why == "" else "%s · %s" % [n, why]

func _show_resident(d: Dictionary) -> void:
	var data := d.duplicate()
	data.portrait = _portrait(str(d.portrait))
	var ask := resident_ask(view, str(d.id))
	if ask != "": data.line = ask   # NPC-5: with a request open the bar asks it, in the request card's words (李白 q(46))
	if str(_reply.get("id", "")) == str(d.id): data.line = str(_reply.line)
	var bar := UiResidentBar.new(data)
	bar.theme = UiKit.theme()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = UiTokens.SIZE_QUICK_BAR_X
	bar.offset_right = -UiTokens.SIZE_QUICK_BAR_X
	bar.offset_bottom = -bottom_pad()
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var id := str(d.id)
	bar.gift_pressed.connect(func(): open_gift(id))
	bar.request_pressed.connect(func(): open_resident_request(id))
	bar.identity_pressed.connect(func(): open_resident_profile(id))
	bar.meal_pressed.connect(func(): _open_todays_meal(id))   # lesson_pressed: P0 has no lessons (lesson is always false)
	_open_modal(bar, 0.0, true)
	_close_above(bar, _CLOSE_ABOVE_CARD)
	modal_kind = "resident"

## Today's meal on the bar (§3.4.5): the dish they gave today, its card open in the bag; the Inbox when it waits there
## because the bag was full. The bar only offers it while the meal is still there (P0Logic.gift_meal).
func _open_todays_meal(id: String) -> void:
	var meal := P0Logic.gift_meal(view, id)
	match str(meal.get("at", "")):
		"bag": open_bag(str(meal.item), "bag")
		"inbox": open_inbox()

## The name on the bar: the resident's profile sheet (RES-PIP / RES-KAI). Back returns to the bar.
func open_resident_profile(id: String) -> void:
	var d := resident_profile_data(view, id)
	if d.is_empty(): return
	var sheet := UiDrawer.new(_RESIDENT_SHEET_H)
	sheet.pad = UiTokens.SPACE_PAGE
	sheet.theme = UiKit.theme()
	sheet.safe_bottom = safe_bottom()
	var page := UiResidentProfile.new(d)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.back_pressed.connect(func(): open_resident(id))
	sheet.body.add_child(page)
	sheet.close_requested.connect(close_modal)
	_open_modal(sheet, UiTokens.OPACITY_SCRIM_DRAWER, true)
	_close_above(sheet, _CLOSE_ABOVE_SHEET, UiTokens.SPACE_PAGE)
	modal_kind = "resident_profile"
	_modal_back = func(): open_resident(id)   # Android Back = the sheet's Back

## The workbench drawer (SGODOT-231 B2-06): P0WorkbenchDrawer over the view, Close 44 six above its top and 16 in
## (as RES-PIP's sheet). It follows the view while open; Craft / Equip go to the server, a grey button toasts its
## reason (LOCK-10) and a cost tile shows where the material comes from (NeedSource, Show only moves the camera,
## LOCK-08). What a craft shows afterwards (the card's float, the pickaxe's Moment, the gloves' banner) belongs to
## the farm's P0FarmMaterials.
const _WORKBENCH_KIND := "workbench"
var workbench_tab := "tools"
var _workbench: P0WorkbenchDrawer

func open_workbench(tab := "") -> P0WorkbenchDrawer:
	if tab != "": workbench_tab = tab
	var d := P0WorkbenchDrawer.new(view, workbench_tab)
	d.theme = UiKit.theme()
	d.safe_bottom = safe_bottom()
	d.close_requested.connect(close_modal)
	d.tab_changed.connect(func(t: String): workbench_tab = t)
	d.command_requested.connect(func(cmd: Dictionary): command.emit(cmd))
	d.unavailable_requested.connect(func(reason: String): toast(reason))
	d.source_requested.connect(_show_need_source)
	_open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	_close_above(d, _CLOSE_ABOVE_SHEET, UiTokens.SPACE_PAGE)
	_workbench = d
	modal_kind = _WORKBENCH_KIND
	return d

## The open workbench drawer, or null.
func workbench() -> P0WorkbenchDrawer:
	return _workbench if is_instance_valid(_workbench) and modal_kind == _WORKBENCH_KIND else null

## The open (not yet accepted) request's own line, e.g. Pip's `Could you catch me a fish? Any kind is fine.`; ""
## when the resident has no open request.
static func resident_ask(view_: Dictionary, id: String) -> String:
	var r: Dictionary = view_.get("residents", {}).get(id, {})
	var req = r.get("request", null)
	if not (req is Dictionary) or str(r.get("request_state", "open")) != "open": return ""
	for q in P0Logic.content().get("residents", {}).get(id, {}).get("requests", []):
		if str(q.get("id", "")) == str(req.get("id", "")): return str(q.get("text", ""))
	return ""

## RES-PIP data: face, name, role, stage, `Friendship have/need`, favourite style with a dish of that style.
## Details › has no page behind it in P0, so it stays hidden (TODO SGODOT-225 / 209: the resident's details page).
static func resident_profile_data(view_: Dictionary, id: String) -> Dictionary:
	var bar := P0Logic.resident_bar(view_, id)
	if bar.is_empty(): return {}
	var def: Dictionary = P0Logic.content().get("residents", {}).get(id, {})
	var likes := str(def.get("likes", ""))
	var dish := ""
	for r in P0Logic.content().get("cooking", {}).get("recipes", []):
		if str(r.get("style", "")) == likes:
			dish = str(r.get("id", ""))
			break
	var face_path := "res://assets/p0/art/residents/%s.svg" % id
	return {"face": load(face_path) if ResourceLoader.exists(face_path) else _portrait(str(def.get("portrait", ""))),
		"name": str(bar.name), "role": str(bar.role), "stage": str(bar.stage),
		"friendship": ("%d/%d" % [int(bar.have), int(bar.need)]) if str(bar.get("next", "")) != "" else str(int(bar.have)),
		"likes": likes, "likes_icon": P0Logic.icon(dish) if dish != "" else null, "details": false}

## A 44 Close above a bottom card or sheet, right-aligned `inset` in from its right edge and `gap` above its top
## (Close · 44 px: 6 above a sheet, 8 above the dialogue bar). It follows the content as it slides and resizes.
func _close_above(content: Control, gap: float, inset := 0.0) -> void:
	var close := UiCloseButton.new()
	close.theme = UiKit.theme()
	close.size = Vector2(UiTokens.SIZE_CLOSE, UiTokens.SIZE_CLOSE)
	var follow := func():
		if is_instance_valid(close):
			close.position = content.position + Vector2(content.size.x - inset - UiTokens.SIZE_CLOSE, -gap - UiTokens.SIZE_CLOSE)
	content.item_rect_changed.connect(follow)
	close.pressed.connect(close_modal)
	_modal.add_child(close)
	follow.call()

## The resident's portrait (assets/p0/art/<key>-portrait.jpg), or none.
static func _portrait(key: String) -> Texture2D:
	var path := "res://assets/p0/art/%s-portrait.jpg" % key
	return load(path) if key != "" and ResourceLoader.exists(path) else null

## Request on the bar: an open request shows the card (Accept / Not now); an accepted one that is ready
## delivers. The bar's button carries the gap or the wait, so it never dead-ends (LOCK-10 / 18).
func open_resident_request(id: String) -> void:
	var d := P0Logic.resident_bar(view, id)
	if d.is_empty(): return
	var cmd: Dictionary = d.get("request_cmd", {})
	if str(cmd.get("type", "")) == "deliver":
		close_modal()
		command.emit(cmd)
		return
	var card := UiRequestCard.new(_request_card_data(view, id, d))
	card.theme = UiKit.theme()
	card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	card.offset_left = UiTokens.SIZE_QUICK_BAR_X
	card.offset_right = -UiTokens.SIZE_QUICK_BAR_X
	card.offset_bottom = -bottom_pad()
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.action_pressed.connect(func():
		close_modal()
		if not cmd.is_empty(): command.emit(cmd))
	card.dismissed.connect(func(): open_resident(id))
	_open_modal(card, 0.0, true)
	modal_kind = "resident_request"
	_modal_back = func(): open_resident(id)

## ResidentRequestCard data from the resident's open request (content table + view facts).
static func _request_card_data(view_: Dictionary, id: String, bar: Dictionary) -> Dictionary:
	var def: Dictionary = P0Logic.content().get("residents", {}).get(id, {})
	var req: Dictionary = view_.get("residents", {}).get(id, {}).get("request", {}) if view_.get("residents", {}).get(id, {}).get("request", null) != null else {}
	var text := ""
	var need_line := ""
	var title := "%s's request" % str(def.get("name", ""))
	for q in def.get("requests", []):
		if str(q.get("id", "")) == str(req.get("id", "")):
			text = str(q.get("text", ""))
			need_line = str(q.get("need_line", ""))
	var kind := str(req.get("kind", ""))
	var need := {"name": "", "have": int(req.get("have", 0)), "need": int(req.get("qty", 1)), "icon": null}
	match kind:
		"fish":
			var rarity := int(req.get("rarity", 0)) if req.get("rarity", null) != null else 0
			need.name = (P0Logic.rarity_name(view_, rarity) + " fish") if rarity > 0 else "Fish"
			need.icon = P0Logic.icon("fish_crucian")
		"dish":
			need.name = "Any dish"
			need.icon = P0Logic.icon("pot")
		"sow":
			need.name = "Plots sown"
			need.icon = P0Logic.icon("sow")
	# Li Bai q(46): a request's own need line wins (`1 Rare fish · Golden Koi · Pond`); the tile shows the count itself.
	if need_line != "": need.name = need_line.trim_prefix("%d " % int(need.need))
	var reward := []
	if int(P0Logic.content().get("affinity", {}).get("request", 0)) > 0:
		reward.append("+%d Friendship" % int(P0Logic.content().affinity.request))
	if int(req.get("coins", 0)) > 0: reward.append("%d coins" % int(req.coins))
	return {"portrait": _portrait(str(def.get("portrait", ""))), "title": title,
		"who": "%s · %s · personal request" % [str(def.get("name", "")), str(def.get("role", ""))],
		"line": text, "needs": [need] if kind != "" else [], "reward": " · ".join(reward),
		"deliver_to": str(def.get("name", "")), "action": "Accept",
		"reason": str(bar.get("request_reason", ""))}

## Gift on the bar, or a dish card's `Gift to <Name>` (item: that dish, selected): the gift drawer (Bag side only,
## Dishes first); the card's Gift sends `gift`.
func open_gift(id: String, item := "") -> void:
	var def: Dictionary = P0Logic.content().get("residents", {}).get(id, {})
	var likes := str(def.get("likes", ""))
	var d := P0BagDrawer.new(view, "bag", item, {"kind": "resident", "id": id, "name": str(def.get("name", "")),
		"gifted_today": bool(view.get("residents", {}).get(id, {}).get("gift_today", false)),
		"likes": ("Likes %s · 1 gift a day" % likes) if likes != "" else "1 gift a day"})
	d.theme = UiKit.theme()
	d.safe_bottom = safe_bottom()
	d.close_requested.connect(func(): open_resident(id))
	d.action_requested.connect(func(a: StringName, item: String, _p: Dictionary):
		if a == &"gift":
			close_modal()
			command.emit({"type": "gift", "resident": id, "item": item}))
	_open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	_bag = d
	modal_kind = "gift"
	_modal_back = func(): open_resident(id)

## Own profile (SGODOT-225; PROFILE-1-P0, LOCK-22), opened from the HUD avatar. A skill ring opens the skill
## details; Edit look opens the dressing room above the current world and comes back here.
var _profile: P0ProfilePage

func open_profile(look_saved := false) -> void:
	var page := P0ProfilePage.new(view, safe_top(), look_saved)
	page.theme = UiKit.theme()
	page.back_pressed.connect(close_modal)
	page.skill_pressed.connect(func(_skill: String): open_skills())
	page.edit_look_pressed.connect(edit_look)
	_open_modal(page, 0.0, true)
	_profile = page
	modal_kind = "profile"

## The existing dressing room (Avatar outfit; the P0 actor follows the saved outfit). The P0 layer hides while
## it is on top and the profile comes back when it closes (Back or Done).
func edit_look() -> void:
	close_modal()
	var room := AppRouter.push_instance(AppRouter.DRESS)
	if room == null: return
	visible = false
	var saved := [false]   # Done saves the outfit; Back drops the draft
	var on_saved := func(_config): saved[0] = true
	Avatar.outfit_saved.connect(on_saved)
	room.tree_exited.connect(func():
		Avatar.outfit_saved.disconnect(on_saved)
		visible = true
		open_profile(saved[0]), CONNECT_ONE_SHOT)

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
	# The farmhouse's stove corner owns the cooking drawer (SGODOT-226): walk there and open it.
	var world = P0Runtime.ensure().world
	if is_instance_valid(world) and world.has_method("p0_open_kitchen"):
		world.call("p0_open_kitchen", tab if tab != "" else _kitchen_tab)
		return
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

