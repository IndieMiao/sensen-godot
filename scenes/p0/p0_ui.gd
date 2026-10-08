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
## A panel this UI does not own was asked for (the gate card's Cookbook, the Fish-dex's Cookbook tab): the host
## opens it if it can (LOCK-08: never by travelling).
signal panel_requested(panel: String)
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
var _toasts: ToastLayer   # Toast R1 (SGODOT-233): one at a time, above the quick bar
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
	_toasts = ToastLayer.new()
	_toasts.theme = UiKit.theme()
	root.add_child(_toasts)
	# Over the quick bar's top edge, left of the main action key; inside the bag the bar is docked at the drawer's
	# fixed bottom row, so the toast sits above that (WP2 D-01, q(16)). With no bar on screen: the bar's spot.
	_toasts.anchor_above(_bar)
	_toasts.action_pressed.connect(_on_toast_action)
	if dev_tools_on(OS.is_debug_build(), P0Session.is_demo_build()): _build_dev()
	if _pending.has("mode"): set_mode(_pending.mode)
	if _pending.has("place"): set_place(_pending.place)
	set_surface(_pending.get("surface", surface))
	if _pending.has("status"): set_status_line(_pending.status)
	_pending.clear()

func _process(dt: float) -> void:
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
		if was == "board": _fill_board(_counter)   # board cards follow Accept / Deliver
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
	var f := _make_float(text, UiFloatText.Tone.ITEM if tone is Color else int(tone), icon)
	f.play(_float_start(screen, [f], stack), stack)
	return f

func _make_float(text: String, tone: int, icon: Texture2D) -> UiFloatText:
	var f := UiFloatText.new(text, tone, icon, UiFloatText.Layout.WRAP if text.length() > _FLOAT_HUG_CHARS else UiFloatText.Layout.HUG)
	f.theme = UiKit.theme()
	root.add_child(f)
	return f

## Floats never rise over the HUD (int6, 李元芳: `+5 Cooking XP ★` crossed the Today chip; 不知火舞 233): a group's start
## is pushed down until its top line, at the top of its rise, still clears the HUD rows by FLOAT_HUD_GAP. `top_index`
## = that line's stack index (the group's lines minus one).
const FLOAT_HUD_GAP := 8.0
func _float_start(screen: Vector2, lines: Array, top_index: int) -> Vector2:
	var hud_bottom := _marker_area().position.y + _kit.global_position.y - root.global_position.y
	var h := 0.0
	for f in lines: h = maxf(h, (f as UiFloatText).shown_size().y)
	var lowest := hud_bottom + FLOAT_HUD_GAP + h + UiFloatText._RISE \
		+ UiFloatText._STACK_RISE * clampi(top_index, 0, UiFloatText._STACK_MAX - 1)
	return Vector2(screen.x, maxf(screen.y, lowest))

## The lowest a pushed-down group may start (its bottom): above the quick bar, an open drawer, and the main action key
## when the group's width reaches over it (不知火舞 233), in this UI's root space.
func _float_floor(x: float, half_w: float) -> float:
	var y := root.size.y
	for c in [_bar, _keys]:
		if c == null or not (c as Control).is_visible_in_tree(): continue
		var r := (c as Control).get_global_rect()
		var gx := x + root.global_position.x
		if c == _keys and (r.end.x < gx - half_w or r.position.x > gx + half_w): continue
		y = minf(y, r.position.y)
	if _modal != null and _modal.get_child_count() > 1:
		var content := _modal.get_child(1) as Control
		if content is UiDrawer: y = minf(y, content.get_global_rect().position.y)
	return y - root.global_position.y

# ---------------------------------------------------------------- one reply's floats (q(49) ①, §4.8.6)
## The order of one reply's lines: Energy → XP → items → coins → affinity (q(49) ①).
const FLOAT_ORDER := ["energy", "xp", "first", "item", "coins", "affinity"]
## Kinds a later reply adds into while their line is up: XP (`+40 XP · 20 plants`, §4.8.3 XP 入账). Items, Energy and
## coins float per reply (each plot's `+1 Radish`, each bed's `−2 Energy`).
const FLOAT_MERGE_KINDS := ["xp"]
const FLOAT_MAX_LINES := 3
## A line of a kind still up — before its fade starts (UiFloatText 650 ms) — takes the next reply's amount in place;
## while the action key is held (a held harvest, a labour beat apart) for as long as the line is still there.
const _FLOAT_MERGE_MS := 650
const _FLOAT_MERGE_PX := 32.0
var float_clock := Callable(Time, &"get_ticks_msec")
var _live_floats := {}   # kind -> {node, parts: {key: part}, at, ms}

## One server reply's floats (q(49) ①; §4.8.6). parts: [{kind, key, amount, fmt, tone, icon}] in any order — `fmt`
## takes the signed amount (`%s XP`, `%s Timber`); a part without fmt gives its `text` as it is (affinity). Parts of a
## kind share one line: the same key adds up (`+15 XP`, `−4 Energy`), different keys join (`+6 Timber · +2 Stone`).
## Lines go Energy → XP → items → coins → affinity, at most three; the rest join the third (`+6 Timber · +14 coins`),
## nothing is dropped. A kind still up from the last reply at the same place takes the new amounts in place and
## bumps (a held harvest: `+4 XP` → `+8 XP` …) instead of a new float. Returns the lines' floats.
func float_lines(parts: Array, at: Vector2) -> Array:
	var kinds := {}
	for p in parts:
		var k := str(p.get("kind", "item"))
		if not kinds.has(k): kinds[k] = {}
		_float_add(kinds[k], p)
	var order: Array = FLOAT_ORDER.filter(func(k): return kinds.has(k))
	for k in kinds:
		if not order.has(k): order.append(k)
	var shown: Array = []
	var fresh: Array = []   # [{kind, text, tone, icon, merged, overflow}] lines that need a new float
	var now := int(float_clock.call())
	for i in mini(order.size(), FLOAT_MAX_LINES):
		var k: String = order[i]
		var merged: Dictionary = kinds[k]
		var extra: Array = order.slice(FLOAT_MAX_LINES) if i == FLOAT_MAX_LINES - 1 else []
		if extra.is_empty() and k in FLOAT_MERGE_KINDS:
			var live: Dictionary = _live_floats.get(k, {})
			var node: UiFloatText = live.get("node") if not live.is_empty() and is_instance_valid(live.get("node")) else null
			# Held: the line stays where it rose while the player walks on (§4.8.3); otherwise the same place, briefly.
			var near := fab_held or (now - int(live.get("ms", 0)) < _FLOAT_MERGE_MS and (live.at as Vector2).distance_to(at) < _FLOAT_MERGE_PX)
			if node != null and not node.is_queued_for_deletion() and near:
				for p in merged.values(): _float_add(live.parts, p)
				(live.node as UiFloatText).bump(_float_line_text(live.parts))
				live.ms = now
				shown.append(live.node)
				continue
		var text := _float_line_text(merged)
		for e in extra: text += " · " + _float_line_text(kinds[e])   # the overflow joins the last line
		var first: Dictionary = merged.values()[0]
		var tone: int = first.get("tone", UiFloatText.Tone.ITEM)
		# Energy is coloured by what it adds up to; a line of text parts only (a floor fee) keeps its own tone.
		if k == "energy" and merged.values().any(func(p): return p.has("fmt")):
			tone = UiFloatText.Tone.ENERGY_COST if _float_sum(merged) < 0 else UiFloatText.Tone.ENERGY_GAIN
		fresh.append({kind = k, text = text, tone = tone, icon = first.get("icon", null), merged = merged, overflow = not extra.is_empty()})
	if fresh.is_empty(): return shown
	var base := shown.size()   # lines bumped in place keep the lower places
	var nodes: Array = fresh.map(func(l): return _make_float(l.text, l.tone, l.icon))
	var start := _float_start(at, nodes, base + nodes.size() - 1)
	var half_w := 0.0
	for n in nodes: half_w = maxf(half_w, (n as UiFloatText).shown_size().x * 0.5)
	if nodes.size() > 1 and start.y > at.y and start.y > _float_floor(at.x, half_w):
		# Pushed down under the HUD the group would sit on the bar, the key or a drawer: only the first line stays and
		# the rest join it (不知火舞 233, same joining as q(49) ①).
		for n in nodes: (n as UiFloatText).queue_free()
		var one: Dictionary = fresh[0].duplicate()
		one.text = " · ".join(fresh.map(func(l): return str(l.text)))
		one.overflow = true
		fresh = [one]
		nodes = [_make_float(one.text, one.tone, one.icon)]
		start = _float_start(at, nodes, base)
	for j in nodes.size():
		var f: UiFloatText = nodes[j]
		f.play(start, base + j)
		var l: Dictionary = fresh[j]
		if not l.overflow: _live_floats[l.kind] = {node = f, parts = (l.merged as Dictionary).duplicate(true), at = at, ms = now}
		shown.append(f)
	return shown

var _float_batch := {}   # Vector2i anchor -> {at, parts}, flushed once at the end of the frame

## Adds parts to this frame's batch at `at` (see float_lines): everything one server reply says — the runtime's
## Energy / XP / items / coins and a world's own lines (a gather's `+6 Timber · Stored`, a floor fee) — lands in one
## float_lines call, so the three-line cap and the order hold across callers.
func queue_floats(parts: Array, at: Vector2) -> void:
	if parts.is_empty(): return
	if _float_batch.is_empty(): _flush_floats.call_deferred()
	var key := Vector2i(at.round())
	if not _float_batch.has(key): _float_batch[key] = {at = at, parts = []}
	(_float_batch[key].parts as Array).append_array(parts)

func _flush_floats() -> void:
	var batch := _float_batch
	_float_batch = {}
	for k in batch: float_lines(batch[k].parts, batch[k].at)

static func _float_add(into: Dictionary, p: Dictionary) -> void:
	var key := str(p.get("key", p.get("fmt", p.get("text", ""))))
	if into.has(key) and p.has("fmt"):
		into[key].amount = int(into[key].amount) + int(p.get("amount", 0))
		into[key].count = int(into[key].get("count", 1)) + int(p.get("count", 1))
	else: into[key] = p.duplicate()   # a new key, or a text part (the latest wins)

static func _float_sum(parts: Dictionary) -> int:
	var n := 0
	for p in parts.values(): n += int(p.get("amount", 0))
	return n

static func _float_line_text(parts: Dictionary) -> String:
	return " · ".join(parts.values().map(func(p: Dictionary) -> String:
		if not p.has("fmt"): return str(p.get("text", ""))
		var a := int(p.get("amount", 0))
		var line := str(p.fmt) % (("+%d" % a) if a >= 0 else ("−%d" % -a))
		# A held harvest's XP counts its plants once more than one went into it: `+40 XP · 20 plants`.
		if str(p.get("unit", "")) != "" and int(p.get("count", 1)) > 1: line += " · %d %s" % [int(p.count), str(p.unit)]
		return line))

## Toast (Toast R1, §4.8.6; q(49) ⑤): one at a time, a new one replaces the one showing and the same sentence again
## within 2 s only stays up longer. Info; `seconds` > 0 overrides the length rule (2 s + 0.5 s per 20 characters,
## at most 5 s). A tap closes it early. Feedback the player must confirm is a card, never a toast.
func toast(text: String, seconds := 0.0) -> void:
	if not _toasts: return
	_aim_toast()
	_toasts.show_toast(text, ToastLayer.Severity.INFO, "", seconds)

## Where the toast sits (WP2 D-01, q(16)): over the quick bar's top edge, in the scene or docked in the bag; over a
## drawer without the bar (the workbench, a counter), just above the drawer's top edge — clear of its rows and of the
## Close key on the right — when there is room under the HUD; else the bar's spot.
func _aim_toast() -> void:
	if _bar != null and _bar.is_visible_in_tree():
		_toasts.anchor_above(_bar)
		return
	var content: Control = _modal.get_child(1) if _modal != null and _modal.get_child_count() > 1 else null
	if content != null and content.is_visible_in_tree():
		var top := content.get_global_rect().position.y - root.global_position.y
		var hud_bottom := _marker_area().position.y + _kit.global_position.y - root.global_position.y
		if top - UiTokens.SPACE_OVERLAY_BODY - UiTokens.SIZE_TOAST_MIN_H >= hud_bottom:
			_toasts.anchor_above(content)
			return
	_toasts.anchor_above(_bar)

## A refused command (§4.8.6 `命令被拒（非体力）`, wording per appendix B) or FISH-4's full creel. `action` adds a
## guiding line (`Open bag ›`) that acts in place and never travels (LOCK-08).
func toast_error(text: String, action := "") -> void:
	if not _toasts: return
	_aim_toast()
	_toasts.show_toast(text, ToastLayer.Severity.ERROR, action)

## Done, worth saying once: a cleared mine floor, a resident's meal (§4.8.6 Toast Success).
func toast_success(text: String) -> void:
	if not _toasts: return
	_aim_toast()
	_toasts.show_toast(text, ToastLayer.Severity.SUCCESS)

## What the toast says now ("" when none is up).
func toast_text() -> String: return _toasts.current_text() if _toasts else ""

func _on_toast_action(action: String) -> void:
	match action:
		"Open bag": open_bag()

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
	if _moment_open:   # a result moment went: a waiting TipCard may come up now (q(49) ⑥)
		_moment_open = false
		if tips: tips.moment_closed()
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
	root.move_child(_toasts, -1)   # a toast stays readable over a drawer or card
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
	var ctx: Dictionary = _counter_ctx.get(role, {}).duplicate()
	# STALL-NEW-2 (E-04): this visit's rows say `◆ New for you` for what opened since the last one; then it is seen.
	if role == "homestead":
		ctx["new"] = stall_new_ids()
		_mark_stall_seen()
	var d := P0CounterDrawer.new(view, role, ctx, str(opts.get("section", "buy")))
	d.theme = UiKit.theme()
	d.safe_bottom = safe_bottom()
	d.close_requested.connect(close_modal)
	d.action_requested.connect(func(a: StringName, id: String, p: Dictionary): _counter_action(role, a, id, p))
	d.section_changed.connect(func(sec: String): if sec == "board": _fill_board(d))
	_open_modal(d, UiTokens.OPACITY_SCRIM_COUNTER, true)
	if d.section == "specialty": _close_above(d, _CLOSE_ABOVE_SPECIALTY, P0CounterDrawer.SPECIALTY_PAD)   # MARKET-SPECIALTY
	_counter = d
	modal_kind = "counter"
	if d.section == "board": _fill_board(d)

## STALL-NEW (E-04, 1378:92885 / §9.5.2): Homestead Stall goods unlocked since the stall was last opened — the stall's
## world icon wears New until a visit, whose rows then read `◆ New for you`. What the player could already buy when this
## build first saw them counts as seen (no New on day one); kept with the teaching tips on this device.
func stall_new_ids() -> Array:
	var open: Array = (view.get("stall", {}).get("buy", []) as Array).filter(func(o): return bool(o.get("unlocked", true))).map(func(o): return str(o.id))
	if open.is_empty(): return []
	_load_tips()
	if not _taught.has("stall_seen"):
		_taught["stall_seen"] = open
		_save_tips()
		return []
	var seen: Array = _taught.stall_seen
	return open.filter(func(id): return not seen.has(id))

func stall_has_new() -> bool: return not stall_new_ids().is_empty()

func _mark_stall_seen() -> void:
	var open: Array = (view.get("stall", {}).get("buy", []) as Array).filter(func(o): return bool(o.get("unlocked", true))).map(func(o): return str(o.id))
	_load_tips()
	var seen: Array = _taught.get("stall_seen", [])
	for id in open:
		if not seen.has(id): seen.append(id)
	_taught["stall_seen"] = seen
	_save_tips()

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
	if _counter == null or not is_instance_valid(_counter) or _counter.keeper_bar == null: return
	for ev in events:
		match str(ev.get("kind", "")):
			"drink":
				var price := int(view.get("drinks", {}).get("price", 0))
				_counter.keeper_bar.line = ("Enjoy. Next cup's %d coins." % price) if int(ev.get("left", 0)) > 0 \
					else str(P0Logic.keeper_lines(view, _counter.role, _counter.ctx).get("counter", ""))
			"item":
				if str(ev.get("id", "")).begins_with("rod_") and int(ev.get("delta", 0)) > 0:
					_counter.keeper_bar.line = "Strung and ready — it's on your belt. Swap rods in Bag › Gear."

## The board page of a counter: the Stall Board (legacy view.stall.board) or the Market Board (view.boards.market).
func _fill_board(d: P0CounterDrawer) -> void:
	for c in d.board.get_children():
		c.hide()
		c.queue_free()
	_board(d.board, view.get("stall", {}).get("board", {}) if d.role == "homestead" else market_board(view))

## view.boards.market in the Stall Board's shape ({slots, requests [{id, title, item, qty, have, coins, where,
## status}], refill_in}) so one renderer draws both boards.
static func market_board(v: Dictionary) -> Dictionary:
	var b: Dictionary = v.get("boards", {}).get("market", {})
	var reqs := []
	var refill := -1.0
	for sl in b.get("slots", []):
		if sl.get("empty", false):
			if sl.has("refill_in"): refill = float(sl.refill_in) if refill < 0.0 else minf(refill, float(sl.refill_in))
			continue
		var any := ("any %s %s" % [P0Logic.rarity_name(v, int(sl.rarity)), str(sl.kind)]) if sl.get("rarity", null) != null else "any " + str(sl.get("kind", ""))
		reqs.append({"id": str(sl.id), "title": str(sl.get("title", "")), "item": str(sl.get("icon", "")), "qty": int(sl.get("qty", 1)),
			"have": int(sl.get("have", 0)), "coins": int(sl.get("coins", 0)), "status": str(sl.get("status", "open")),
			"where": any if (sl.get("items", []) as Array).is_empty() else ("any pond" if str(sl.get("kind", "")) == "fish" else "from your farm")})
	return {"slots": (b.get("slots", []) as Array).size(), "requests": reqs, "refill_in": maxf(refill, 0.0)}

## Gear lives in the bag drawer now (p(8)); callers that opened Tools & Gear land on the Gear side.
func open_gear() -> void:
	open_bag("", "gear")

## The older entries now open the counter drawer (SGODOT-224).
func open_stall(tab := "") -> void:
	open_counter("homestead", {"section": tab if tab != "" else "buy"})

func open_tackle(_bubble := "") -> void:
	open_counter("tackle")

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

## A skill level-up (§4.8.3 / §4.8.6): the MomentBanner P0Logic.level_banner builds — the account's first one with the
## teaching line and `Use bait` (≤ 3 s), later ones 1.5 s with what opened and what is next. `first`: no skill had
## levelled before this one.
func show_level_up(ev: Dictionary, first := false) -> void:
	var spec := P0Logic.level_banner(view, ev, first)
	show_banner(spec, func(): _banner_action(str(spec.get("action_id", ""))))

func _banner_action(id: String) -> void:
	match id:
		"use_bait":   # puts the gift bait on the hook, in place (the quick bar's bait slot, q(44))
			for s in _bag_slots():
				if str(s.get("id", "")).begins_with("bait_"):
					if bar_mode == "fish" and selected_bait != str(s.id): _on_slot_tapped(str(s.id))
					break

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
	page.collection_pressed.connect(func(key: String):
		if key == "fish": open_fishdex(func(): open_profile())
		elif can_request_panel(): request_panel("cookbook"))
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
## Where the teaching tips and "shown before" keys live (tests point it at their own file).
var tips_path := TIPS_PATH

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

# ---------------------------------------------------------------- result moments (SGODOT-233, q(49) / §4.8.6)
## A RewardMoment (哪吒's kit card) on its own: one at a time through queue_card (q(49) ④). Without buttons it folds
## away after MOMENT_AUTO_S or on a tap anywhere and the scene stays bright (③); with buttons it waits for them and
## a tap outside is the caller's back. The guide's TipCards wait while a moment is up (⑥, P0Guide.TipQueue).
const MOMENT_AUTO_S := 1.5
const _BANNER_UNDER_HUD := 10.0   # MomentBanner y108: 10 under the HUD's two rows (16 + 82)
const _MOMENT_TOP := 0.54   # under the leaping fish / the plate (where FISH-3 sat)
var _moment_open := false

func show_moment(card: Control, auto_close := true, seconds := MOMENT_AUTO_S) -> void:
	card.theme = UiKit.theme()
	_open_modal(card, 0.0)
	modal_kind = "card"
	_moment_open = true
	if tips: tips.moment_opened()
	# A RewardMoment sits centred low in the scene; a MomentBanner under the HUD (MomentBanner x16 y108 of 800).
	var banner := card is UiMomentBanner
	var place := func():
		if is_instance_valid(card):
			var y := (UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + _BANNER_UNDER_HUD + safe_top()) if banner else root.size.y * _MOMENT_TOP
			card.position = Vector2(roundf((root.size.x - card.size.x) * 0.5), roundf(y))
	card.resized.connect(place)
	place.call()
	if not auto_close: return
	var holder_id := _modal.get_instance_id()
	card.gui_input.connect(func(e: InputEvent): if P0Ui.is_tap(e): close_modal())
	get_tree().create_timer(seconds).timeout.connect(func():
		if is_instance_valid(_modal) and _modal.get_instance_id() == holder_id: close_modal())

## A MomentBanner (§4.8.3 / §4.8.6): queued like every moment (q(49) ④), gone after `seconds` or on a tap; its action
## button (Use bait) closes it and does the next step in place.
func show_banner(spec: Dictionary, on_action := Callable()) -> UiMomentBanner:
	var b := UiMomentBanner.new()
	b.kind = UiMomentBanner.Kind.COMPLETE if str(spec.get("kind", "")) == "complete" else UiMomentBanner.Kind.LEVEL_UP
	b.level = str(spec.get("level", ""))
	b.title = str(spec.get("title", ""))
	b.subtitle = str(spec.get("subtitle", ""))
	b.rewards = (spec.get("rewards", []) as Array).map(func(r): return UiFloatText.pill(str(r.text), int(r.tone), r.get("icon", null)))
	b.detail = str(spec.get("detail", ""))
	b.tip = str(spec.get("tip", ""))
	b.action = str(spec.get("action", ""))
	b.action_pressed.connect(func():
		close_modal()
		if on_action.is_valid(): on_action.call())
	show_moment(b, true, float(spec.get("seconds", MOMENT_AUTO_S)))
	return b

## FISH-3 · the first catch of a species (§4.8.6): `Caught!` / the fish · rarity / `Fish-dex 3/N`; the one-time strip
## `First catch! +15 XP` (and `New city! +10 XP`); a first Fine / Rare fish adds its Energy as a pill. No buttons.
## extras: {city_xp, energy} from the same response (P0Runtime).
func show_catch(fish_id: String, rarity: int, first_xp: int, extras := {}) -> void:
	var m := UiRewardMoment.new()
	m.tone = UiRewardMoment.Tone.REWARD
	m.event = "Caught!"
	m.icon = P0Logic.icon(fish_id)
	m.item_name = P0Logic.item_name(view, fish_id)
	m.rarity = rarity
	m.rarity_word = P0Logic.rarity_name(view, rarity)
	var once: Array = []
	if first_xp > 0: once.append("First catch! +%d XP" % first_xp)
	if int(extras.get("city_xp", 0)) > 0: once.append("New city! +%d XP" % int(extras.city_xp))
	m.strip = " · ".join(PackedStringArray(once))
	if m.strip != "": m.strip_icon = P0Logic.icon("star")
	if int(extras.get("energy", 0)) > 0:
		m.rewards = [UiFloatText.pill("+%d Energy" % int(extras.energy), UiFloatText.Tone.ENERGY_GAIN)]
	var dex: Array = view.get("fishing", {}).get("dex", [])
	m.note = "Fish-dex %d/%d" % [dex.filter(func(d): return int(d.get("caught", 0)) > 0).size(), dex.size()]
	show_moment(m)

## FISH-5 / 5-2 · a gate fish broke free, once per species (§4.8.6, q(55) / q(57)): `Too strong` (Fishing level) or
## `Too heavy for your rod` / the fish · rarity / what it needs / the Energy back as it really came back (the
## protection's `Energy refunded (8 left today)`, else `+3 Energy back`). No buttons: where to go next lives on the
## Fish-dex silhouette's gate card (q(57)).
func show_got_away(ev: Dictionary) -> void:
	var rarity := int(ev.get("rarity", 2))
	var fish := str(ev.get("fish", ""))
	var m := UiRewardMoment.new()
	m.tone = UiRewardMoment.Tone.NEUTRAL
	m.icon = P0Logic.icon(fish)
	m.item_name = P0Logic.item_name(view, fish)
	m.rarity = rarity
	m.rarity_word = P0Logic.rarity_name(view, rarity)
	m.event = "Too strong" if ev.has("need_level") else "Too heavy for your rod"
	m.note = P0Logic.break_free_need(view, ev)
	m.rewards = [UiFloatText.pill(P0Logic.refund_line(view, ev), UiFloatText.Tone.ENERGY_GAIN)]
	show_moment(m)

## The four-things gate card (§4.8.7, q(49); SKILL-2 482:169): the seed stall, counters, the Cookbook / Experiment
## third slot, workbench recipes, locked gathering spots and the Fish-dex silhouettes share it. An InfoSheet built by
## P0Logic.gate_spec (see there for `gate`). No Got it: a tap outside or Back closes it, one layer at a time —
## `back` reopens the panel it was opened from. Its one guiding button closes the card first, then moves the camera
## (Show my plots: Show here, the homestead pin elsewhere), opens Skills, or asks the host through panel_requested
## (Cookbook); it never travels (LOCK-08).
func open_gate_card(gate: Dictionary, back := Callable()) -> UiInfoSheet:
	var spec := P0Logic.gate_spec(view, gate)
	# A guide to a panel no host opens (the Cookbook before its read-only page exists) is left off.
	var own := ["skills"] + HOME_TARGETS
	spec.buttons = spec.buttons.filter(func(b): return str(b.get("payload", {}).get("go", "")) in own or can_request_panel())
	var sheet := UiInfoSheet.new()
	sheet.theme = UiKit.theme()
	sheet.rules = func(_id, _ctx, _o): return spec
	sheet.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.offset_left = UiTokens.SPACE_PAGE
	sheet.offset_right = -UiTokens.SPACE_PAGE
	sheet.offset_bottom = -bottom_pad()
	sheet.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sheet.action_requested.connect(func(action: StringName, _id: String, payload: Dictionary):
		if action == &"guide": _gate_guide(str(payload.get("go", ""))))
	_open_modal(sheet, 0.32, true)   # the card sits where the quick bar was; bar and keys hide under it
	modal_kind = "gate"
	sheet.open("gate", &"gate")
	_modal_back = back
	return sheet

func _gate_guide(go: String) -> void:
	close_modal()
	match go:
		"skills": open_skills()
		"plots", "stall", "stove", "board", "home", "bench":
			if show_label(go, space_here(), spot_reachable()) == "Show": show_spot.emit(go)
			else: show_on_map.emit(map_target(go))
		_: request_panel(go)

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
	if _taught.is_empty() and FileAccess.file_exists(tips_path):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(tips_path))
		if saved is Dictionary: _taught = saved

func _save_tips() -> void:
	var f := FileAccess.open(tips_path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(_taught))

## FISH-6 Fish-dex (SGODOT-233, P0FishDex): from the creel badge, the profile's Fish tile and the catch cards. A cell
## opens the gate card for a silhouette its level or rod holds back (q(57)), else the fish card; either comes back to
## the dex on Back or a tap outside. Fish caught since the last visit ring once (kept with the teaching tips).
func open_fishdex(back := Callable(), animate := true) -> void:
	_load_tips()
	var caught: Array = view.get("fishing", {}).get("dex", []).filter(func(f): return int(f.get("caught", 0)) > 0).map(func(f): return str(f.id))
	var seen: Array = _taught.get("dex_seen", [])
	var fresh := caught.filter(func(id): return not seen.has(id))
	if not fresh.is_empty():
		_taught["dex_seen"] = caught
		_save_tips()
	var d := P0FishDex.new(view, fresh)
	d.theme = UiKit.theme()
	d.animate = animate
	d.safe_bottom = safe_bottom()
	d.close_requested.connect(close_modal)
	d.close_pressed.connect(close_modal)
	var again := func(): open_fishdex(back, false)
	d.cell_pressed.connect(func(id: String):
		var gate := P0Logic.fish_gate(view, id)
		if not gate.is_empty() and not P0Logic.dex_caught(view, id): open_gate_card(gate, again)
		else: open_fish_card(id, again))
	_open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	modal_kind = "fishdex"
	_modal_back = back

## A Fish-dex cell's card (FISH-6 单格详情, P0): the fish, its rarity, `Caught ×3 · Pond · River` and the XP it
## gives now (`Full XP` / `XP 50% · Reduced` / `No XP · outleveled`), or `Not caught yet · Pond · River`.
func open_fish_card(id: String, back := Callable()) -> UiInfoSheet:
	var spec := P0Logic.fish_card_spec(view, id)
	var sheet := UiInfoSheet.new()
	sheet.theme = UiKit.theme()
	sheet.rules = func(_id, _ctx, _o): return spec
	sheet.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.offset_left = UiTokens.SPACE_PAGE
	sheet.offset_right = -UiTokens.SPACE_PAGE
	sheet.offset_bottom = -bottom_pad()
	sheet.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_open_modal(sheet, 0.32, true)
	modal_kind = "fish"
	sheet.open(id, &"dex")
	_modal_back = back
	return sheet

## A panel this UI does not own, opened by the host that listens on panel_requested.
func request_panel(panel: String) -> void:
	close_modal()
	panel_requested.emit(panel)

## Whether a host opens panels this UI does not own (a read-only Cookbook). Until one does, nothing offers them:
## no dead-end placeholder (不知火舞 233 walkthrough).
func can_request_panel() -> bool: return panel_requested.get_connections().size() > 0

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

