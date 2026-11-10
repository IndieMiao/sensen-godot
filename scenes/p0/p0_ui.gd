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
## Go on a pond card opened away from the map (the Bite Board's, SGODOT-283): leave this world and walk into that pond,
## as the map card's Go does (P0Runtime._leave_then("go:pond:<id>")).
signal go_pond(id: String)
## A panel this UI does not own was asked for (the gate card's Cookbook, the Fish-dex's Cookbook tab): the host
## opens it if it can (LOCK-08: never by travelling).
signal panel_requested(panel: String)
signal recenter()
signal place_pressed()
signal tackle_requested()      # FISH-5 rod variant "Tackle Shop"
## Placement mode (P1, SGODOT-241): a press / drag / release on the scene, in screen points (phase "press", "drag",
## "release"); the world turns it into a spot. The bar's main key and Cancel come back as placement_done(ok).
signal placement_point(screen: Vector2, phase: String)
signal placement_done(ok: bool)
## The placement bar's optional middle key (`Rotate`, Decorate's 2×1 / 3×2 decor; spec.secondary).
signal placement_secondary
## Decorate (SGODOT-284): Farm Storage's Place / the stall toast's Place now (an item), HOME-1's Decorate › ("").
signal decor_requested(item: String)
## Two fingers in placement mode moved the picture by `px` (screen), about `at`: the world pans its camera.
signal placement_pan(px: Vector2, at: Vector2)
## A field recipe's Build on the workbench (SGODOT-241): the world opens placement mode for it.
signal placement_requested(recipe: String)
## LOOK-PICK (SGODOT-282): a look tapped on the card shows on the real farmhouse — the farm swaps that stage's parts;
## look "" ends the preview (the view's look again, once a set_look it was waiting for has landed).
signal look_previewed(stage: String, look: String)

const P0City := preload("res://modules/p0/p0_city.gd")   # the P0 home city (SGODOT-270)
const P0Travel := preload("res://modules/p0/p0_travel.gd")   # where the player is in the world (SGODOT-275)
const P0Clusters := preload("res://modules/p0/p0_clusters.gd")   # the home city's centre for Improve this map (q(133) v3)
const P0ArrivalCard := preload("res://modules/p0/p0_arrival_card.gd")   # the sheet the Passport and city pages use
const P0Locals := preload("res://modules/p0/p0_locals.gd")   # the keepers' local requests (q(272))
const P0LocalRequest := preload("res://scenes/p0/panels/p0_local_request.gd")   # a local request's card (q(272))
const _RESIDENT_SHEET_H := 443.0   # RES-PIP: Sheet 443 of 800
const _CLOSE_ABOVE_SHEET := 6.0    # RES-PIP: Close · 44 px sits 6 above the sheet, 16 in from the right
const _CLOSE_ABOVE_SPECIALTY := 2.0   # MARKET-SPECIALTY: Close 44 at (300, 617), the sheet at y 663
const _FLOAT_HUG_CHARS := 32         # longer float copy wraps to two lines (FloatText Layout=Wrap)
const _CLOSE_ABOVE_CARD := 8.0     # RES-KAI-TALK: 8 above the dialogue bar, flush with its right edge
const _AFFINITY_INSET := 8.0       # RES-KAI-TALK: the affinity float sits 8 in from the bar's left edge …
const _AFFINITY_ABOVE := 6.0       # … and 6 above its top
signal test_account_requested(action: String)
const TestAccounts := preload("res://modules/p0/p0_test_accounts.gd")
var test_accounts = TestAccounts.new()
const GuidePulses := preload("res://modules/p0/p0_guide_pulses.gd")
var guide_pulses = GuidePulses.new()
var _guide_pulse_wait := 0.0

var quick_store := "user://p0_quickbar.json"   # per-action pins / removals (tests point it elsewhere)
const _KEY_ABOVE_BAR := 40.0        # BAR-1 482:18: ActionKey bottom at y 668, quick bar top at 708
const _BADGE_CARD_GAP := 4.0        # a card over a facility that also shows a badge sits this far above it (the mine's EntryCard)
const ACTION_SURFACES := ["farm", "pond", "mine"]   # spaces with the action key group (SGODOT-231: the mine, Mining)
## The actions the world also offers on the switch key besides the current one (SGODOT-288: mine floors 3–5 offer
## Mining and Combat; the world sets it, P0Mine._go_floor). Empty: only the current action.
var actions_here: Array = []
## A-08 ghost slot per action: [id prefix of the family, ghost icon, noun] (q(44): Seeds / Bait / Torch in P0).
const GHOST_FAMILY := {
	"farm": ["seed_", "seed_radish", "Seeds"],
	"fish": ["bait_", "bait_worm", "Bait"],
	"mine": ["torch", "torch", "Torch"],
	"combat": ["potion_", "potion_heal", "Potion"],
}

var _potion_until_ms := -1
var _potion_second := -1

## The projected server view supplies potion_ready_in; a refused drink can resync from ready_in.
func set_potion_cooldown(remaining_ms: float) -> void:
	_potion_until_ms = Time.get_ticks_msec() + ceili(remaining_ms) if remaining_ms >= 0 else -1
	if is_node_ready(): _refresh_bar()

func potion_cooldown() -> float:
	return maxf(0.0, _potion_until_ms - Time.get_ticks_msec()) if _potion_until_ms >= 0 else -1.0

var view: Dictionary = {}
var root: Control
var pad: Control
var hud: UiHud                   # two-row HUD (SGODOT-222, LOCK-06)
var _place_text := P0City.chip("Homestead")
var _fab_state: Dictionary = {}
var fab_held := false            # §14.2: hold the main action to keep sowing along a row
var fab_verb := ""
## SGODOT-221 world controls (UI kit, own theme layer): quick bar, action key group, radial, world prompts, badges.
var _kit: Control
var _bar: UiQuickBar
var _keys: UiActionKey
var _radial: UiActionRadial
var _undo_toast: UiUndoToast
var _card_hits := {}      # id -> screen point a tap on the card forwards to the world (the facility's own tap point)
var _badges := {}         # id -> UiStatusBadge
var _icons := {}          # id -> UiWorldIconButton (SGODOT-250)
var _name_bars := {}      # id -> UiWorldNameBar
var _npc_tags := {}       # id -> UiNpcNameTag
## The world prompt a `tapped` comes from, only while that signal is being handled ("" for a scene tap).
var tapped_card := ""
var _quick := {}          # per action: {pins: [], removed: []}, saved in quick_store (LOCK-05: 每个行动各记各的)
var _bar_sig := []        # last state pushed to the bar, so the per-frame refresh only rebuilds on change
var _auto_pick := true    # pick the first slot once when an action is entered (§10.3.3 ①), not after a deselect
var _mode_tool: Texture2D  # the current action's own tool icon for the key badge (set_action `tool` overrides per key)
var _bar_ids: Array = []
var selected_seed := ""
var selected_bait := ""
## The pond the tackle keeper names when no outpost ctx says which (the map's tackle pin before SGODOT-227).
var tackle_place := str(P0Outposts.by_role("tackle").get("nearest", {}).get("name", "Pond"))
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
## The place the player is in there (the session's place: a pond or an outpost id), so a target at that very place reads
## Show (show_label); "" elsewhere.
var place := ""
var _hud_hash := 0       # last state given to hud.apply
var _today_key = null    # the Today icon's focus row (P0Logic.today_chip_key); null before the first view
var _dot_keys = null     # the Today rows' red-dot keys last seen (P0Logic.today_dots); null before the first view
var _dot_lit := false
var _hud_need := -1      # main action's Energy need last seen by the HUD
var _pending := {}   # surface / place / mode set before the HUD exists (the runtime attaches early)
var _dev_box: Control
var _creel: UiCreelBadge
var _status: PanelContainer     # SGODOT-231 mine status line (Rocks 2/6), where the creel sits while fishing
var _status_text: Label
var _trap_slots: PanelContainer   # `Trap slots 0/1` at the right of the creel row while the trap is picked (TRAP-2)
var _trap_slots_text: Label
var _hp: UiHpBar                # SGODOT-288 HPBar on mine floors 3–5, where the status line sits (it moves right)
var _elite_hp: UiHpBar          # EnemyHP Kind=Elite under it while the elite fights (COMBAT-ELITE)
var player_screen := Vector2(180, 320)   # set by the farm / pond each frame (mid-body): the radial fans out from it
var _modal: Control
var _modal_veil: ColorRect   # the open modal's scrim (the home pick's real map lets the drags through it)
var modal_kind := ""            # "stall", "bag", "inbox", "card", ... — which drawer is open
var _card_queue: Array = []
var _teach: UiTipCard
## When the TipCard on screen closes by time, in Time.get_ticks_msec(); 0: none. Wall-clock, not summed frame deltas: on
## slow frames the summed deltas ran far behind the clock, and a 2.5 s tip stayed ~11 s on the emulator (不知火舞 on 376).
var _teach_until_ms := 0
var tips: P0Guide.TipQueue   # the TipCard order and "shown before" (SGODOT-232 U6)
var _taught := {}
var _tip_over: Control = null   # the dialog an OVER_DIALOG tip is up over (P0Guide.OVER_DIALOG); it goes with it
var _toasts: ToastLayer   # Toast R1 (SGODOT-233): one at a time, above the quick bar
## The toasts and the system line draw over every card, the ones raised by z too: the move confirm card sits over the
## map's pin names (UiMapDestination.NAME_Z + 1), and a refusal or `Didn't go through` said while it is up must not
## fall under its scrim (周瑜 on #460). Their order among the rest still comes from move_child.
const OVER_CARDS_Z := UiMapDestination.NAME_Z + 2

# ---------------------------------------------------------------- build
func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = GameUi.theme()
	# Labels and buttons translate as they draw (0.2.21: English by default, 中文 by the player's choice) through P0's
	# own table (Localization.use_p0 took Journey's away); a name the table does not hold stays as it is.
	root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_INHERIT
	add_child(root)
	voice_match = VoiceMatchLink.new()   # the profile's Voice Profile (SGODOT-349)
	voice_match.name = "VoiceMatchLink"
	add_child(voice_match)
	pad = _TouchPad.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.ui = self
	root.add_child(pad)
	_build_hud()
	_build_bar()
	_build_fab()
	_toasts = ToastLayer.new()
	_toasts.theme = UiKit.theme()
	_toasts.z_index = OVER_CARDS_Z
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
	var second := ceili(potion_cooldown() / 1000.0)
	if second != _potion_second:
		_potion_second = second
		if bar_mode == "combat": _refresh_bar()
	guide_pulses.follow()
	_guide_pulse_wait -= dt
	if _guide_pulse_wait <= 0.0:
		_guide_pulse_wait = 0.1
		_refresh_guide_pulses()
	if _teach_until_ms > 0 and Time.get_ticks_msec() >= _teach_until_ms: _hide_tip()
	if _notice_left > 0.0:
		_notice_left -= dt
		if _notice_left <= 0.0: _hide_notice()
	# q(49): a waiting TipCard comes up only when no RewardMoment / result card is on screen; one already up stays.
	# show_moment / _drop_modal count Moments in the queue (tips.moment_opened / moment_closed). A dialog is always over
	# the TipCard, whichever opened first (不知火舞 on 341): while one is open — a result card (the farmhouse's COOK-4
	# too), the gate card, a confirm, a page — the tip waits; over a drawer (the stove's, the bag) it comes up.
	# A tip about the dialog it was asked for with (P0Guide.OVER_DIALOG: the travel card's) comes up over it, and goes
	# with it: the dialog closed (Fly, ✕) or another over it (the Energy card) — 不知火舞 355, G19.
	if tips and not _tips_held():
		var up := dialog_open()
		var key := tips.next(up)
		if key != "":
			_show_tip(P0Guide.tip_text(key), key)
			_tip_over = _modal if up else null
	if _tip_over != null and (not is_instance_valid(_tip_over) or _modal != _tip_over):
		_tip_over = null
		if tip_on_screen(): _hide_tip()
	if _teach and _teach.visible: _place_tip()
	_tick_ask(dt)
	if _notice and _notice.visible: _place_notice()

## Typed targets from the server; finding an existing control never opens a page or selects an item.
func _refresh_guide_pulses() -> void:
	var targets := {}
	if screen_kind() == -1:
		for mark in P0Guide.button_marks(view):
			var key := str(mark.button)
			if key in ["sow", "water", "harvest", "cast"] and _keys != null and not has_modal():
				if str(fab_state().get("cmd", {}).get("type", "")) == key and bool(fab_state().get("enabled", false)):
					if key != "cast" or space == "pond" and P0Guide.target_place(view, place):
						targets[key] = {node = _keys.key(), shape = UiGuidePulse.Shape.CIRCLE}
			elif key == "location" and hud != null and not has_modal():
				var rect := hud.place_chip_rect()
				targets[key] = {node = hud._place_chip, rect = Rect2(rect.position - hud._place_chip.global_position, rect.size)}
			elif key.begins_with("quickbar:") and _bar != null and not has_modal():
				targets[key] = {node = _bar.cell_for(key.trim_prefix("quickbar:")), flash = true}
			elif key in ["gift", "request"] and modal_kind == "resident" and _modal != null and _resident == P0Guide.marked_resident(view) and P0Guide.target_place(view, place):
				for bar in _modal.find_children("*", "UiResidentBar", true, false):
					targets[key + ":" + _resident] = {node = bar._gift if key == "gift" else bar._request}
			elif key == "cook" and modal_kind == "kitchen" and _modal != null:
				var page := str(mark.get("page", ""))
				for drawer in _modal.find_children("*", "P0KitchenDrawer", true, false):
					targets["cook:" + page] = {node = drawer.guide_cook_target(page)}
			elif key == "eat":   # S8 (SGODOT-368): that dish's Eat — the cook card's, the bag card's, the cabinet row's
				var dish := str(mark.get("item", ""))
				var node := _guide_eat_target(dish)
				if node != null: targets["eat:" + dish] = {node = node}
		for mark in P0Guide.guide_marks(view):
			if not mark is Dictionary or not bool(mark.get("pulse", false)): continue
			var object := str(mark.get("object", ""))
			if object in ["stove", "cabinet"] and space == "home" and not has_modal():
				var anchor := "room:use_stove_" if object == "stove" else "room:use_warming_cabinet"   # cabinet: S8's dish (SGODOT-368)
				for id in _name_bars:
					var bar: UiWorldNameBar = _name_bars[id]
					if str(id).begins_with(anchor) and bar.visible and bar.is_expanded():
						targets["object:" + object] = {node = bar}
						break
			var item := str(mark.get("item", ""))
			if item != "" and modal_kind == "gift" and is_instance_valid(_bag) and str(_bag.gift_to.get("id", "")) == P0Guide.marked_resident(view) and P0Guide.target_place(view, place):
				var cells := guide_gift_cells(_bag.grid, item)
				for id in cells:
					targets["item:" + id] = {node = cells[id], overlay = guide_item_overlay(_bag), shape = UiGuidePulse.Shape.CARD, radius = UiTokens.RADIUS_CELL}
			elif item != "" and modal_kind == "bag" and is_instance_valid(_bag) and not _bag.sheet.is_open():
				# S8's dish in the bag (SGODOT-368): its cells, as the Gift drawer's soup; none once its card is open
				var cells := guide_gift_cells(_bag.grid, item)
				for id in cells:
					targets["item:" + id] = {node = cells[id], overlay = guide_item_overlay(_bag), shape = UiGuidePulse.Shape.CARD, radius = UiTokens.RADIUS_CELL}
			elif item != "" and modal_kind == "storage" and _modal != null:
				for sheet in _modal.find_children("*", "P0StorageSheet", true, false):   # the cabinet's row of that dish
					var row: Control = sheet.guide_row(item)
					if row != null: targets["row:" + item] = {node = row}
	guide_pulses.update(view, targets)

## S8's Eat for a dish's base recipe (SGODOT-368), on whichever is open: the cook card showing that dish, the bag's
## card for it, the cabinet with that row selected; null otherwise (finding never opens or selects anything).
func _guide_eat_target(dish: String) -> Control:
	if _modal == null: return null
	if modal_kind == "kitchen_card":
		for card in _modal.find_children("*", "UiRewardMoment", true, false):
			if P0Logic.base_id(str(card.get_meta(&"dish", ""))) == dish: return card.primary_button()
	elif modal_kind == "bag" and is_instance_valid(_bag) and _bag.sheet.is_open() and P0Logic.base_id(_bag.sheet.item_id()) == dish:
		return _bag.sheet.button_for(&"eat")
	elif modal_kind == "storage":
		for sheet in _modal.find_children("*", "P0StorageSheet", true, false): return sheet.guide_eat(dish)
	return null

## A server item mark names a base recipe; all visible qualities use their own cell, without selecting any.
static func guide_gift_cells(grid: UiInventoryGrid, base: String) -> Dictionary:
	var cells := {}
	for item in grid.shown_items():
		var id := str(item.get("id", ""))
		if P0Logic.base_id(id) == base:
			var cell := grid.cell_for(id)
			if cell != null: cells[id] = cell
	return cells

## Outside the grid's clip, inside the drawer; a Node2D host avoids changing the PanelContainer's layout.
static func guide_item_overlay(drawer: Control) -> Control:
	var existing := drawer.get_node_or_null("GuidePulseHost/Overlay") as Control
	if existing != null: return existing
	var host := Node2D.new()
	host.name = "GuidePulseHost"
	drawer.add_child(host)
	var overlay := Control.new()
	overlay.name = "Overlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(overlay)
	return overlay

func _build_hud() -> void:
	hud = UiHud.new()
	hud.theme = UiKit.theme()
	hud.safe_top = safe_top()
	hud.avatar_pressed.connect(open_profile)   # LOCK-06: the avatar opens Profile (SGODOT-225)
	hud.energy_pressed.connect(open_energy_panel)
	hud.inbox_pressed.connect(open_inbox)
	hud.today_pressed.connect(func():   # the icon opens Today and, open, closes it (不知火舞 76ebeaad)
		if modal_kind == "today": close_modal()
		else: open_today())
	hud.place_pressed.connect(func(): place_pressed.emit())   # the location chip is the way back to the map
	root.add_child(hud)
	# CreelBadge 1126:79349 (FISH-1 / FISH-4; 不知火舞 on 235 B1, q(83)): under the two-row HUD, left; full, its tap says
	# why with Open bag ›, otherwise it opens the bag on its Fish page (the creel is the bag).
	_creel = UiCreelBadge.new(P0Logic.icon("fish"))
	_creel.theme = UiKit.theme()
	_creel.position = Vector2(UiTokens.SIZE_TODAY_PANEL_X, UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + UiTokens.SPACE_WITHIN + safe_top())
	_creel.hide()
	_creel.pressed.connect(func():
		if _creel.state == UiCreelBadge.State.FULL: toast_creel_full()
		else: open_bag("", "bag", "Fish"))
	root.add_child(_creel)

func _build_bar() -> void:
	# Phase 1A world controls (SGODOT-221) sit in their own layer with the UI kit theme; the panels and cards set the
	# kit theme on themselves (the hand-built P0 look went with SGODOT-235).
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
	_bar.ghost_tapped.connect(func(_i: int): open_bag("", "bag", "Materials" if bar_mode == "combat" else "All"))
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
	# TRAP-2 (不知火舞 B7 on 286): with the Fish Trap picked at a pond, `Trap slots 0/1` on the creel's row, right, in
	# the creel badge's pill (radius 12) but the StatusLine type, Bold 12 and no icon (283 3fa2398f); its right edge as
	# far in as the creel's left one
	_trap_slots = PanelContainer.new()
	_trap_slots.name = "TrapSlots"
	_trap_slots.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, 12.0, UiTokens.COLOR_BORDER,
		UiTokens.STROKE_DEFAULT).with_margins(10, 4, 10, 4))
	_trap_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trap_slots.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_trap_slots.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_trap_slots.offset_right = -UiTokens.SIZE_TODAY_PANEL_X
	_trap_slots_text = UiKit.label("", UiTokens.STYLE_CAPTION_B12)
	_trap_slots.add_child(_trap_slots_text)
	_trap_slots.hide()
	_kit.add_child(_trap_slots)
	_hp = UiHpBar.new(UiHpBar.Kind.PLAYER)
	_hp.position = _creel.position
	_hp.hide()
	_kit.add_child(_hp)
	_elite_hp = UiHpBar.new(UiHpBar.Kind.ELITE)
	_elite_hp.hide()
	_kit.add_child(_elite_hp)

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
	_place_controls()

## Bottom controls per BAR-1: bar at x 12, 24 above the safe bottom; the action group 16 from the right edge,
## 40 above the bar.
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

## The +1h / +4h clock buttons: test builds only. The demo APK is a debug export too, but its server has no dev
## routes (P0_DEV=0, dev/skip is 404) and the buttons covered the Toast's end (李元芳, int6), so it has none.
static func dev_tools_on(debug_build: bool, demo_build: bool) -> bool:
	return debug_build and not demo_build

var dev_legendary := false   # the test builds' Legend toggle (_build_dev): every reel the Legendary tier

func _build_dev() -> void:
	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN   # right-aligned, as wide as its buttons
	box.offset_right = -UiTokens.SPACE_PAGE
	box.offset_left = box.offset_right
	box.offset_top = 118 + safe_top()   # debug time skips, kept under the HUD on notched screens
	box.add_theme_constant_override("separation", 4)
	box.theme = UiKit.theme()
	for m in [60, 240]:   # a plain button in the compact secondary look: a dev tool, not a game command
		var b := Button.new()
		b.text = "+%dh" % (m / 60)
		b.theme_type_variation = UiTokens.BUTTON_CMD_SECONDARY_COMPACT
		b.pressed.connect(func(): dev_skip.emit(m))
		box.add_child(b)
	# q(282)'s reel recordings (SGODOT-389): while on, every bite reels as a Legendary fish (P0FishingPanel.on_cast). The
	# reel only: the server's fish is what lands. Test builds only, as the clock buttons.
	var legend := Button.new()
	legend.name = "DevLegendary"
	legend.text = "Legend"
	legend.toggle_mode = true
	legend.theme_type_variation = UiTokens.BUTTON_CMD_SECONDARY_COMPACT
	legend.toggled.connect(func(on: bool): dev_legendary = on)
	box.add_child(legend)
	root.add_child(box)
	_dev_box = box

# ---------------------------------------------------------------- refresh
func set_view(v: Dictionary) -> void:
	view = v
	var mine_at = v.get("mine", {}).get("at", null)
	set_potion_cooldown(float(mine_at.get("potion_ready_in", -1)) if mine_at is Dictionary else -1.0)
	if modal_kind == "first_dig" and JSON.stringify(P0Logic.GearLogic.first_dig(v)) != _first_dig_sig:
		if P0Logic.GearLogic.first_dig(v).is_empty(): close_modal()
		else: open_first_dig()
	_check_account(v)
	if _bag != null and is_instance_valid(_bag) and modal_kind in ["bag", "gear", "gift"]: _bag.refresh(v)
	if _counter != null and is_instance_valid(_counter) and modal_kind == "counter":
		var was: String = _counter.section
		_counter.refresh(v)
		if was == "board" or _counter.is_short(): _fill_board(_counter)   # board rows follow Accept / Deliver (only on change)
	if _profile != null and is_instance_valid(_profile) and modal_kind == "profile": _profile.update(v)
	if workbench() != null: _workbench.refresh(v)
	if compost_bin() != null: _compost.refresh(v)
	if inbox() != null: _inbox.refresh(v)
	if bite_board() != null: _bite_board.refresh(v)
	if notice_board() != null: _notice_board.refresh(v)
	if passport() != null: _passport.call("refresh", v)
	if blackjack() != null: _blackjack.refresh(v)
	_refresh_rest_card(v)
	_refresh_priest_keys()
	_watch_buffs(v)
	_refresh_hud()
	_refresh_bar()
	_refresh_request_reward()
	_refresh_today(false)


var _hold_here := ""
var _hold_until_server := false
var _hold_energy := {}
var _hold_coins := -1

## While the map flies the player to another city (q(147) ⑤, SGODOT-299) the place chip reads the city they left
## (`cluster`) — from Fly, while the view still says it too (SGODOT-361); "" lets it follow the view again, as on
## landing. until_server: only until the server's view says it (home's flight, landed before return_home).
func hold_here(cluster: String, until_server := false) -> void:
	if cluster == _hold_here and until_server == _hold_until_server: return
	_hold_here = cluster
	_hold_until_server = until_server
	_hud_hash = 0
	_refresh_hud()

func energy_held() -> bool:
	return not _hold_energy.is_empty()

## ...and the HUD's Energy reads what it was before the arrival (q(147) ⑥: a first visit's +10 comes with the landing),
## the coins too (q(261) ④: the HUD does not move under the cover); {} lets both follow the view again.
func hold_energy(energy: Dictionary, coins := -1) -> void:
	if energy.is_empty(): coins = -1
	if energy == _hold_energy and coins == _hold_coins: return
	_hold_energy = energy.duplicate()
	_hold_coins = coins
	_hud_hash = 0
	_refresh_hud()

## HUD from the view, the next action's cost (Low = short of it) and where the player actually is: the
## kitchen is the farmhouse's stove corner, so the chip reads "San Francisco · Farmhouse" there (LOCK-06).
func _refresh_hud() -> void:
	if hud == null: return
	# No HUD before the first server view: an empty view would read as 0 Energy (red) and 0 coins, and its
	# chips would still take taps. None over the home pick either: its pages lie on the real map (PR-2b, HOME-WELCOME).
	hud.visible = _hud_shown()
	if view.is_empty(): return
	if _hold_until_server and _hold_here == P0Travel.here(view): _hold_here = ""   # the server has caught up (home's flight)
	var seen := view
	if _hold_here != "" or not _hold_energy.is_empty():   # flying to another city (q(147) ⑤ ⑥, q(261) ④): until it lands
		seen = view.duplicate()
		if _hold_here != "":   # the chip keeps the city left
			var travel: Dictionary = (view.get("travel", {}) as Dictionary).duplicate()
			travel["here"] = _hold_here
			seen["travel"] = travel
		if not _hold_energy.is_empty(): seen["energy"] = _hold_energy   # and Energy what it was
		if _hold_coins >= 0: seen["coins"] = _hold_coins   # and the coins
	var place := P0Travel.place(seen, P0Logic.place_info(_place_text, "Farmhouse" if modal_kind == "kitchen" else ""), space)   # arrived in another city: Tokyo · Arrived (q(108))
	var state := P0Logic.hud_state(seen, {"next_cost": int(fab_state().get("need", 0)), "place": place})
	var dots: Array = state.get("today_dots", [])
	state.erase("today_dots")
	if dots != _dot_keys:   # only when the rows change: the seen keys are a file
		_dot_keys = dots.duplicate()
		_dot_lit = _today_unseen(dots)
	state["today_dot"] = _dot_lit
	var h := state.hash()
	if h == _hud_hash: return   # set_view runs every frame: apply only what changed (the countdown, once a second)
	_hud_hash = h
	hud.apply(state)
	# A new next step pulses the chip once (不知火舞 on 232): only when the focus row changes, never on the first view
	# or a countdown tick; nothing left to do ("All caught up") doesn't pulse.
	var key := str(state.get("today_key", ""))
	if _today_key != null and key != _today_key and key != "": hud.pulse_today()
	_today_key = key

## Top system inset (status bar, notch) in UI units; 0 on desktop.
func safe_top() -> float:
	# Not in the tree yet (the launch cover comes from a deferred call before the UI is in it): no viewport to read —
	# a Release engine crashed on its null (iOS 0.2.25, 蒙恬's stack: Viewport::get_visible_rect, this null). 0 for now;
	# show_screen reads it again once the screen is in the tree.
	if not is_inside_tree(): return 0.0
	# Desktop shots of a phone's status-bar inset (P0_DEV_SAFE_TOP=38: the emulator in int12-pre); unset everywhere else.
	if OS.has_environment("P0_DEV_SAFE_TOP"): return float(OS.get_environment("P0_DEV_SAFE_TOP"))
	if not (OS.has_feature("android") or OS.has_feature("ios")): return 0.0
	return UIMetrics.safe_margins(DisplayServer.get_display_safe_area(), DisplayServer.window_get_size(),
		get_viewport().get_visible_rect().size, 0.0).y

## The HUD's location chip and its coins / bell corner, for worlds that dock their own controls there.
func place_chip_rect() -> Rect2: return hud.place_chip_rect() if hud else Rect2()
func hud_corner_rect() -> Rect2: return hud.balances_rect() if hud else Rect2()

## Pond vs. plots: place chip, creel badge, fab badge and quick-bar contents follow where the player stands.
## Full place chip text: "City · Space" (San Francisco · Homestead / San Francisco · Willow Pond / … · Kitchen).
func set_place(text: String) -> void:
	if not is_node_ready():
		_pending["place"] = text
		return
	_place_text = text
	_refresh_hud()

## One status line under the HUD where the creel sits while fishing (SGODOT-231: the mine's `Rocks 2/6 · 3 monsters
## left`). "" hides it; changing action clears it.
## SGODOT-288 (COMBAT-1 / COMBAT-ELITE): the player's mine HP over the status line's spot; hp < 0 hides it. The status
## line then sits under the HP card, left-aligned with it, in the guard card's place (不知火舞 on #629: to its right it
## ran into the screen's edge at 360). A guard's card there while it fights ({} hides it); the status line hides with
## it — the card names the guard (不知火舞 on 288 / 355).
func set_hp(hp: int, maximum: int, elite := {}) -> void:
	if not is_node_ready(): return
	var on := hp >= 0 and surface in ACTION_SURFACES
	_hp.visible = on
	if on: _hp.set_hp(hp, maximum)
	_status.position.x = _creel.position.x
	_status.position.y = _creel.position.y + (_hp.get_combined_minimum_size().y + UiTokens.SPACE_WITHIN if on else 0.0)
	var boss := on and not elite.is_empty()
	_elite_hp.visible = boss
	_status.visible = _status_text.text != "" and surface in ACTION_SURFACES and not boss
	if boss:
		_elite_hp.title = str(elite.get("name", "Elite Slime"))
		_elite_hp.set_hp(int(elite.get("hp", 0)), int(elite.get("max", 1)))
		_elite_hp.position = Vector2(roundf((root.size.x - _elite_hp.get_combined_minimum_size().x) * 0.5) if root else 16.0,
			_creel.position.y + _hp.get_combined_minimum_size().y + UiTokens.SPACE_WITHIN)

func hp_bar() -> UiHpBar: return _hp
## The creel badge (where a trap's fish fly to, SGODOT-289).
func creel_badge() -> Control: return _creel
## The quick bar's Bag, where a row's harvest flies (SGODOT-289); null without a bar.
func bag_target() -> Control: return quick_bar_node().bag_end() if quick_bar_node() != null else null
## A trap's fish still flying to the badge ([{id, count}]): it counts each in as it lands (creel_landed).
var creel_in_flight: Array = []
func creel_flying(got: Array) -> void:
	creel_in_flight = got.duplicate(true)
	if _creel: _creel.text = P0Logic.creel_line(view, creel_in_flight)
func creel_landed(id: String) -> void:
	creel_in_flight = creel_in_flight.filter(func(f): return str(f.id) != id)
	if _creel: _creel.text = P0Logic.creel_line(view, creel_in_flight)
func elite_bar() -> UiHpBar: return _elite_hp

## The pond's `Trap slots 0/1` (P0Trap.slots_line while the trap is picked, else ""): on the creel's row, right, shown
## with the creel badge; the pond sets it every frame, and a world or mode change hides it until then.
func set_trap_slots(text: String) -> void:
	if not is_node_ready(): return
	if _trap_slots_text.text != text: _trap_slots_text.text = text
	_trap_slots.position.y = _creel.position.y
	_trap_slots.visible = text != "" and _creel.visible

func set_status_line(text: String) -> void:
	if not is_node_ready():
		_pending["status"] = text   # the mine sets it on its first frame, maybe before the HUD exists (苏烈, #39)
		return
	if _status_text.text != text: _status_text.text = text
	_status.visible = text != "" and surface in ACTION_SURFACES and not _elite_hp.visible

## Which world the HUD sits on (§10.2.4): action spaces show everything; rooms are facility spaces
## (no quick bar, main action or switch key); the map shows only toasts and cards.
func set_surface(name: String) -> void:
	if placing(): end_placement()   # a world change ends placement (nothing was sent)
	surface = name
	if tips: tips.leave_surface(name)   # the map's tip waiting under a card never comes up in the next world
	if not is_node_ready():
		_pending["surface"] = name
		return
	var action := name in ACTION_SURFACES
	var world := name != "map"
	# MAP-1 (§10.6.1): the map keeps the two-row HUD — avatar, Energy, coins, bell, Today, the place chip — but has no
	# stick (drag and pinch browse it).
	hud.visible = _hud_shown()
	hud.show_balances = name != "busy"   # a busy world's own close button sits in the coins / bell corner
	pad.visible = world
	_keys.visible = action and _modal == null
	_bar.visible = _bar_shown() and (_modal == null or is_bar_docked())   # docked in the bag drawer it stays
	_bar.bag_only = not action
	_bar_sig = []
	if _radial.is_open(): _radial.close()
	_bar.cancel_drag()   # no lifted slot or drop zones left over when fishing starts or the map opens
	_creel.visible = action and bar_mode == "fish"
	_trap_slots.visible = false   # the pond sets it again on its next frame
	_status.visible = action and _status_text.text != ""
	if _dev_box: _dev_box.visible = world
	for b in _badges.values(): (b as Control).visible = false
	for m in _icons.values() + _name_bars.values() + _npc_tags.values(): (m as Control).visible = false
	_flush_held_cards()
	_flush_held_toast()
	_flush_held_notice()

## Action spaces show the full bar. Rooms (farmhouse kitchen, outposts) and the map keep only Bag, with no action
## or switch key (MAP-1, §10.3.5, o(8)). Busy worlds hide it.
func _bar_shown() -> bool:
	return surface in ACTION_SURFACES or surface in ["room", "map"]

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
	_mode_tool = P0Logic.icon("rod" if mode == "fish" else "pickaxe" if mode == "mine" else "sword" if mode == "combat" else "hoe")
	_keys.tool_icon = _mode_tool
	_creel.visible = mode == "fish"
	_trap_slots.visible = false
	set_status_line("")
	_refresh_bar()

func _refresh_bar() -> void:
	var store := _quick_for(bar_mode)
	# SGODOT-231: Mining's bar holds only what helps underground (a torch); seeds and bait never show there.
	var ids := P0MaterialLogic.mine_bar(view, _bar_ids, store.pins, store.removed) if bar_mode == "mine" \
		else ([] as Array) if bar_mode == "combat" and surface != "mine" \
		else P0Logic.quick_bar(view, _bar_ids, bar_mode, store.pins, store.removed)
	if bar_mode == "fish":
		if selected_bait != "" and not ids.has(selected_bait): selected_bait = ""
		# The last bait went on a hook: the slot stays pinned at 0, the hook goes empty (李白 q(44) ④).
		if selected_bait != "" and P0Logic.bag_count(view, selected_bait) <= 0:
			if not selected_bait.begins_with("trap_"):   # a Fish Trap set in the water leaves the bar quietly
				toast_when_clear("Out of %s · no bait on the hook" % P0Logic.item_name(view, selected_bait))
			selected_bait = ""
		_creel.text = P0Logic.creel_line(view, creel_in_flight)
		_creel.state = UiCreelBadge.state_for(int(view.get("bag", {}).get("free", 0)))
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
		used * 10 >= int(bag.get("capacity", 25)) * 9, modal_kind in ["bag", "gear"], ceili(potion_cooldown() / 1000.0) if bar_mode == "combat" else 0]
	if sig == _bar_sig: return
	_bar_sig = sig
	var slots := []
	for i in ids.size():
		var id := str(ids[i])
		if id == "": slots.append({})   # a gap left by a drag-remove (LOCK-05 v1.10): no item, no pin
		else: slots.append({id = id, icon = P0Logic.icon(id), title = P0Logic.item_name(view, id), quantity = counts[i], pinned = store.pins.has(id)})
		if id != "" and bar_mode == "combat" and potion_cooldown() > 0:
			slots.back()["cooldown"] = P0Logic.duration(potion_cooldown())
	# A-08 ghost (LOCK-04): a bar with nothing of this action in stock shows the action's family in the first empty
	# slot; a slot pinned at 0 is not stock (int5b hand test 9), Compost alone is. The first gap a drag-remove left
	# takes it (LOCK-05 v1.10), else the free end; five occupied slots leave no room, so no ghost. A tap opens the Bag
	# (ghost_tapped). TODO(SGODOT-225 bag drawer): open on the family tab (Seeds → Seeds, Bait → Tackle).
	var family: Array = GHOST_FAMILY.get(bar_mode, GHOST_FAMILY.farm)   # q(44): Seeds / Bait / Torch
	if not counts.any(func(n): return int(n) > 0) and (bar_mode != "combat" or (surface == "mine" and P0Logic.GearLogic.potion_actions_enabled)):
		var ghost := {ghost = true, icon = P0Logic.icon(family[1]), title = family[2]}
		var gap := slots.find({})
		if gap >= 0: slots[gap] = ghost
		elif slots.size() < UiQuickBar.SLOTS: slots.append(ghost)
	_bar.slots = slots
	_bar.selected = sig[4]
	_bar.capacity_warning = sig[5]
	_bar.bag_open = sig[6]

func _on_slot_tapped(id: String) -> void:
	if id.begins_with("potion_") and not P0Logic.GearLogic.potion_actions_enabled: return
	# A slot at 0 can't be picked; a light buzz says so (李白 q(44) ③), and a toast too: the release Journey build
	# has no vibrate permission (PR #12 re-review). The copy is the slot's refill hint (§10.3.3).
	if P0Logic.bag_count(view, id) <= 0 and id != selected_seed and id != selected_bait:
		if _bar.haptics and OS.has_feature("mobile"): Input.vibrate_handheld(10)
		toast("Craft at Workbench" if bar_mode == "mine" else "Buy at Homestead Stall")   # q(44) refill hints
		return
	if bar_mode == "fish" and id.begins_with("trap_"):
		# The Fish Trap (SGODOT-283): selecting it turns the key into Set Trap; tap again for the rod. No toast.
		selected_bait = "" if selected_bait == id else id
	elif bar_mode == "fish":
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
	if bar_mode == "combat" and str(a.get("verb", "")) == "Attack" and view.get("gear", {}).has("weapon"):
		a = a.duplicate()
		a.tool = str(view.gear.weapon)
	if P0Logic.GearLogic.potion_actions_enabled and surface == "mine" and bar_mode == "combat" and str(a.get("verb", "")) == "Attack" and selected_seed.begins_with("potion_"):
		a = P0Logic.GearLogic.drink_action(view, selected_seed, potion_cooldown())
	# SYS-OFFLINE (WP6, §10.7.1): offline every action key is Unavailable with `Offline` as its second line (`Sow ·
	# Offline`, the verb follows the action); a tap says nothing more than the banner already does.
	if offline:
		a = a.duplicate()
		a.sub = "Offline"
		a.enabled = false
		a.amber = false
		a.need = 0
		a.erase("toast")
	_fab_state = a
	var k := _keys.key()
	k.verb = str(a.get("verb", ""))
	var sub := str(a.get("sub", ""))
	# Zero-Energy actions carry no price (LOCK-02 "0 体力的动作不写价", q(122): the verb alone, centred on the key — Set Trap,
	# Light Torch too); reasons and costs stay. Free stays only beside a paid choice (LOCK-21's rows), never on the key.
	k.cost = "" if int(a.get("need", 0)) == 0 and sub == "Free" else sub
	if a.get("amber", false): k.state = UiSceneAction.State.INSUFFICIENT
	elif not a.get("enabled", false): k.state = UiSceneAction.State.UNAVAILABLE
	else: k.state = UiSceneAction.State.DEFAULT
	# The equipped tool in the key's badge (SGODOT-231: Starter / Copper Pickaxe at the mine mouth and inside); a key
	# without one shows the action's own tool, so the farm's Sow after the mouth is a hoe again (walkthrough fix).
	_keys.tool_icon = P0Logic.icon(str(a.tool)) if a.has("tool") else _mode_tool
	var need := int(a.get("need", 0))
	if need != _hud_need:   # the worlds call set_action every frame
		_hud_need = need
		_refresh_hud()   # SGODOT-222: the Energy chip turns Low when short of this action

func _fab_pressed() -> void:
	fab_verb = ""
	if _modal != null: return
	if not _fab_state.get("enabled", false):
		if bool(_fab_state.get("creel_full", false)): toast_creel_full()   # FISH-4 / q(83): the greyed Cast · Creel full
		# SGODOT-231: unavailable keys say why (LOCK-10); one marked toast_break breaks a line too long at a « · »
		# (UiKit.break_at_dot; the full field's `Plots 8/8 · Homestead Lv2 adds 2`, 不知火舞 on #624)
		elif _fab_state.has("toast"): toast(str(_fab_state.toast), 0.0, bool(_fab_state.get("toast_break", false)))
		return
	fab_verb = str(_fab_state.get("verb", ""))
	action_pressed.emit(_fab_state.get("cmd", {}))

## While held, the farm repeats the action for each new plot with the same verb.
func fab_state() -> Dictionary: return _fab_state

# ---------------------------------------------------------------- world tags & floats
# ---------------------------------------------------------------- world prompts (SGODOT-250, LOCK-07 v2 / LOCK-16 v2)
## A facility within view and about 8 m: its icon button (WorldIconButton 1674:101157) centred on `screen` (this UI's
## coordinates, like tag()). `near` grows a seat 1.1× with a primary edge; `status` (a UiStatusBadge.State, -1 none)
## turns the whole button into the StatusBadge; `count` hangs its small count tag ("" none). A tap on it is a tap on
## `hit` (default `screen`), with tapped_card = id. Call it every frame for each shown facility that is not the open one; it folds that facility's name strip if
## it was open. Hidden under a card or drawer, and outside the band between the HUD and the quick bar.
func world_icon(id: String, icon: Texture2D, screen: Vector2, show: bool, near := false, status := -1, hit := Vector2.INF, count := "") -> void:
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
	b.count = count
	b.place_at(screen)
	_keep_off_sides(b, b.drawn_rect())
	# Over the action group: lifted KEY_CLEAR_PX over its top as a strip is (不知火舞 on 441, LOCK-07 38239b9a: the farm's
	# Mailbox button under the ⇄ once the player stood left of it). A tap on it still goes to `hit`.
	var drawn := b.drawn_rect()
	b.position.y += _name_bar_lift(Rect2(b.position + drawn.position, drawn.size), 0.0)
	# Covered by another facility's open strip (it had no clear side, 不知火舞 on 226 C21: off screen first, then other
	# buttons): this button fades while the strip is open and comes back once it folds, as covered name tags do (#57).
	_yield_tag(b, _modal == null and _strip_over(Rect2(b.position, b.size).grow(-8.0)))   # its 28 disc

## The one facility nearest and within reach: its name strip (WorldNameBar 1674:101190) opens from the icon button's
## spot in 160 ms — icon + `text` + at most one `fact` ("" for none). `side` UiWorldNameBar.Dir (the way the
## character faces), -1 = right; either way it flips at a screen edge. `dimmed`: used today (Rested today). With
## show false (or a world_icon call for the same id) it folds back, then the icon button returns.
## Nudge a world prompt (its icon button, or its open name strip): 1.15× and back (b84a5e01 ④, the kitchen's heat
## reminder for another stove). Nothing when it is not on screen.
func pulse_marker(id: String) -> void:
	var b: UiWorldIconButton = _icons.get(id)
	if b != null and b.visible: b.pulse()
	var bar: UiWorldNameBar = _name_bars.get(id)
	if bar != null and bar.visible:
		bar.pivot_offset = bar.size * 0.5
		var t := bar.create_tween()
		t.tween_property(bar, "scale", Vector2.ONE * 1.15, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_interval(0.6)
		t.tween_property(bar, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func name_bar(id: String, icon: Texture2D, text: String, fact: String, screen: Vector2, show: bool, side := -1, dimmed := false, status := -1, hit := Vector2.INF) -> void:
	var bar: UiWorldNameBar = _name_bars.get(id)
	if bar == null:
		bar = UiWorldNameBar.new()
		bar.theme = UiKit.theme()
		bar.visible = false   # opens below
		_kit.add_child(bar)
		_kit.move_child(bar, 0)
		_name_bars[id] = bar
	# Its facility off screen (a Show moved the camera away, 周瑜 on 231): no strip hanging at the edge, like the buttons.
	if not (show and _modal == null) or not _marker_area().has_point(screen):
		if bar.visible: _fold_name_bar(bar)
		return
	_card_hits[id] = screen if hit == Vector2.INF else hit
	bar.icon = icon
	bar.text = text
	bar.fact = fact
	bar.dimmed = dimmed
	bar.status = status
	bar.side = _name_bar_side(bar, screen, UiWorldNameBar.Dir.RIGHT if side < 0 else side, id)
	var shift := Vector2(_name_bar_shift(bar.rect_for(screen, bar.side)), 0.0)
	shift.y = _name_bar_lift(bar.rect_for(screen, bar.side), shift.x)
	bar.anchor_at(screen + shift)
	var b: UiWorldIconButton = _icons.get(id)
	if b: b.visible = false   # the strip stands in for its button
	_raise_marker(bar)   # above ordinary markers; teaching-plot states stay above facility strips (341 c76fc1ea)
	if not bar.visible or bar.get_meta("folding", false):
		if not bar.visible: bar.set_openness(0.0)
		bar.visible = true
		bar.set_meta("folding", false)
		bar.expand()

## World markers (cards, badges, icon buttons, strips, NPC tags) sit at the bottom of the UI, under the HUD and the
## bar; this one goes to the top of that group.
func _raise_marker(m: Control) -> void:
	var top := m.get_index()
	for group in [_badges, _icons, _name_bars, _npc_tags]:
		for other in group.values():
			if not m.get_meta("above_name_bars", false) and other.get_meta("above_name_bars", false): continue
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

## Which way a strip opens (不知火舞 on #59), in this order: ① the whole strip on screen with 12 px to spare (贴边翻转),
## the action group's keys counting as the screen's edge (_key_rects; 不知火舞 442 a9474fa3, 197);
## ② not over an NPC's name tag or another facility's button (#57; 苏烈 on #59) — covered tags fade while it is open,
## covered buttons sit under it; ③ the way the character faces (`want`). If neither side fits, the roomier one: a
## strip may cover a button, never leave the screen.
func _name_bar_side(bar: UiWorldNameBar, screen: Vector2, want: int, id := "") -> int:
	var other := UiWorldNameBar.Dir.LEFT if want == UiWorldNameBar.Dir.RIGHT else UiWorldNameBar.Dir.RIGHT
	var area := _marker_area()
	var keys := _key_rects()
	var room := func(d: int) -> float:   # px to spare at the tighter edge (negative: off screen, or over the keys)
		var r := bar.rect_for(screen, d)
		var spare := minf(r.position.x - area.position.x, area.end.x - r.end.x) - UiTokens.SPACE_ROW
		for k in keys: if r.intersects(k): spare = minf(spare, -(r.intersection(k).size.x))
		return spare
	var fits_want: bool = room.call(want) >= 0.0
	var fits_other: bool = room.call(other) >= 0.0
	if fits_want != fits_other: return want if fits_want else other
	if not fits_want: return want if room.call(want) >= room.call(other) else other
	if _covers_marker(bar.rect_for(screen, want), id) and not _covers_marker(bar.rect_for(screen, other), id): return other
	return want

## The action group's switch, tool badge and main key, each KEY_CLEAR_PX out, in this UI's coordinates: a name strip (and an icon button)
## keeps off them as off the screen's edge (不知火舞 442 a9474fa3, 197: the pond's camera turned 14.5°, a gathering
## point by the ⇄ showed its strip as `St`). Empty while the group is hidden (rooms' facilities, a panel up).
const KEY_CLEAR_PX := 8.0
## The same for a world's camera (P0Pond: the wild's pieces kept off them on the opening screen, 盘古 on 422).
func key_rects() -> Array: return _key_rects()
func _key_rects() -> Array:
	var out := []
	if _keys == null or not _keys.is_visible_in_tree(): return out
	for c in [_keys.switch_button(), _keys.tool_badge(), _keys.key()]:
		if c != null and (c as Control).is_visible_in_tree():
			var g := (c as Control).get_global_rect()
			out.append(Rect2(g.position - _kit.global_position, g.size).grow(KEY_CLEAR_PX))
	return out

## A strip still over the keys on the side it opens to (moved across by `dx`): lifted whole to KEY_CLEAR_PX over the
## group's top (the keys' rects already hold that gap); 0 when it clears them.
func _name_bar_lift(r: Rect2, dx: float) -> float:
	var at := Rect2(r.position + Vector2(dx, 0.0), r.size)
	var keys := _key_rects()
	if not keys.any(func(k): return at.intersects(k)): return 0.0
	var top := INF
	for k in keys:   # every key under its span, the switch over the main key too
		if (k as Rect2).position.x < at.end.x and (k as Rect2).end.x > at.position.x: top = minf(top, (k as Rect2).position.y)
	return minf(0.0, top - at.end.y)

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
## card or drawer all tags hide. A tag an open name strip covers fades out until the strip folds (#57). A tap on a
## shown tag is a tap on its NPC (tapped_card = id, as for icon buttons): the name is where players tap to talk.
func npc_tag(id: String, text: String, head_screen: Vector2, show: bool, highlight := false, talking := false, status := -1) -> void:
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
	t.status = status
	t.highlight = highlight or talking
	t.place_over(head_screen)
	_keep_off_sides(t, Rect2(Vector2.ZERO, t.size))
	_card_hits[id] = head_screen
	_yield_tag(t, _modal == null and _strip_covers(Rect2(t.position, t.size)))

## Fade a name tag or an icon button out while an open strip covers it, back in once it folds (120 ms).
func _yield_tag(t: Control, covered: bool) -> void:
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

## Whether an open strip lies over `r` itself, with no margin: an icon button only fades when it is really under one
## (a button just above a strip stays, C21).
func _strip_over(r: Rect2) -> bool:
	return _open_strips().any(func(s: Rect2): return s.intersects(r))

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
## A scene tap: on a shown icon button or name strip it is that facility's tap, on an NPC's name tag that NPC's,
## elsewhere the world's (also a double tap: a prompt never recenters the camera by accident). Returns true for a card
## tap, which then can't start a double tap either.
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
	# An NPC's name tag (not one faded under an open strip, which the strip's own tap has had first): that NPC's tap.
	# Where two tags' touch areas overlap, the tag whose centre is nearer.
	var tag_id := ""
	var tag_d := INF
	for id in _npc_tags:
		var t: UiNpcNameTag = _npc_tags[id]
		if not t.is_visible_in_tree() or bool(t.get_meta("covered", false)): continue
		var r := t.hit_rect()
		if r.has_point(global_pos) and r.get_center().distance_to(global_pos) < tag_d:
			tag_id = str(id)
			tag_d = r.get_center().distance_to(global_pos)
	if tag_id != "":
		if _modal == null:
			tapped_card = tag_id
			tapped.emit(_card_hits[tag_id])
			tapped_card = ""
		return true
	if double: recenter.emit()
	else: tapped.emit(global_pos - root.global_position)
	return false

func badge(id: String, state: UiStatusBadge.State, screen: Vector2, show: bool, caption := "", icon: Texture2D = null, above_name_bars := false) -> void:
	var b: UiStatusBadge = _badges.get(id)
	if b == null:
		b = UiStatusBadge.new()
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_kit.add_child(b)
		_kit.move_child(b, 0)
		_badges[id] = b
	b.visible = show and _modal == null
	if not b.visible: return
	b.set_meta("above_name_bars", above_name_bars)
	b.state = state
	b.caption = caption
	b.icon = icon
	_place_marker(b, screen, false)
	if above_name_bars: _raise_marker(b)   # stays in the world group, below HUD/cards; never raise its CanvasItem z
	# 228 293b4190, for every CaptionPill: an open name strip over a mark's caption folds it to the mark while it shows.
	# 341 c76fc1ea: teaching-plot states and their countdown pills instead draw over the facility strip.
	if not above_name_bars and caption != "" and b.visible and _strip_covers(Rect2(b.position, b.size)):
		b.caption = ""
		_place_marker(b, screen, false)

## Height a shown badge takes over `screen`, so a card over the same facility (the mine's EntryCard) can sit above it.
func badge_height(id: String) -> float:
	var b: UiStatusBadge = _badges.get(id)
	return b.get_combined_minimum_size().y + _BADGE_CARD_GAP if b and b.visible else 0.0

## clamp_inside keeps a marker on screen whatever its anchor; otherwise one whose anchor is in the band slides in
## PROMPT_EDGE from its sides and one whose anchor is out of it hides (不知火舞 on #127: the map labels' rule).
func _place_marker(m: Control, screen: Vector2, clamp_inside: bool) -> void:
	var size := m.get_combined_minimum_size()
	var area := _marker_area()
	var r := WorldAnchor.place(size, screen - Vector2(0, UiTokens.SPACE_WITHIN), area, PROMPT_EDGE, clamp_inside or area.has_point(screen))
	m.visible = r.has_area()
	if not m.visible: return
	m.size = size
	m.position = r.position
	if m.has_method(&"point_at"): m.point_at(screen.x - r.position.x)

## World prompts keep this far off the screen's sides (不知火舞 on #127, as the map's labels: CityMapView.LABEL_EDGE).
const PROMPT_EDGE := 8.0

## A prompt placed on its anchor slides in from a side it would come closer to than PROMPT_EDGE. `drawn`: its visible
## part in its own coordinates (an icon button draws its 28 disc in a 44 touch box), its scale about its pivot taken
## in; the touch area moves with it. Callers hide a prompt whose anchor is out of the band.
func _keep_off_sides(c: Control, drawn: Rect2) -> void:
	var area := _marker_area()
	var left := c.position.x + c.pivot_offset.x + (drawn.position.x - c.pivot_offset.x) * c.scale.x
	var right := left + drawn.size.x * c.scale.x
	if left < area.position.x + PROMPT_EDGE: c.position.x += area.position.x + PROMPT_EDGE - left
	elif right > area.end.x - PROMPT_EDGE: c.position.x -= right - (area.end.x - PROMPT_EDGE)

## Only Bag at the bottom (a room: no quick bar slots, no main key; 不知火舞 on #127): the room frames lower.
func bag_only() -> bool: return _bar != null and _bar.visible and _bar.bag_only and not _keys.visible

## The marker area (_marker_area) as it is with the HUD and the quick bar up in their places, whatever covers or docks
## them right now (the Bag drawer takes the bar into itself): what a world's opening shot frames for, so a panel open on
## arrival doesn't move the shot when it closes (int12-pre; 后裔 on #166). The bar's place is _place_controls'.
## Empty until the HUD has laid out.
func open_marker_area() -> Rect2:
	if _kit == null or _kit.size.y <= 0.0: return Rect2()
	var top := UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + safe_top()
	var bottom := _kit.size.y - UiTokens.SIZE_QUICK_BAR_BOTTOM - safe_bottom() - UiTokens.SIZE_QUICK_BAR_H
	return Rect2(0.0, top, _kit.size.x, maxf(0.0, bottom - top))

## The highest a card lifted off the player goes (SGODOT-266, 不知火舞 on #190; P0Actor.screen_box): 8 px under the
## HUD's second row.
const CARD_UNDER_HUD := 8.0
func card_top() -> float: return UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + safe_top() + CARD_UNDER_HUD

## A world card a tap opens — the mine mouth's, a mine floor's, a trap's EntryCard — placed as TapCard: its pointer's tip
## SPACE_WITHIN over `point` and still on it, the card inside card_area(), lifted clear of the player's `body` by `gap`
## (WorldAnchor.lift_clear, 不知火舞 on #190).
func place_card(card: UiEntryCard, point: Vector2, body: Rect2, gap: float) -> void:
	var size := card.get_combined_minimum_size()
	var r := WorldAnchor.place(size, point - Vector2(0, UiTokens.SPACE_WITHIN), card_area(), UiTokens.SPACE_WITHIN, true)
	r = WorldAnchor.lift_clear(r, body, gap, card_top())
	card.size = size
	card.position = r.position
	card.point_at(point.x - r.position.x)

## Where those cards may sit: the marker band as it is with the HUD and the quick bar in their places (open_marker_area),
## its top at card_top(). The cards are passive (the world's p0_tap resolves their taps), so one over a HUD chip lost its
## taps to the chip: on a short screen the mine mouth's four-row card rose over the location chip and `Continue run ·
## Free` opened the map (李元芳, 0.2.1 smoke d83191bb). The whole screen only before the HUD has laid out.
func card_area() -> Rect2:
	var band := open_marker_area()
	if not band.has_area(): return Rect2(Vector2.ZERO, root.size)
	var top := card_top() - UiTokens.SPACE_WITHIN   # WorldAnchor.place keeps SPACE_WITHIN inside the area
	return Rect2(band.position.x, top, band.size.x, maxf(0.0, band.end.y - top))

## Where world markers may sit (LOCK-07): below the two-row HUD and above the quick bar. A finger card is passive, so
## one lying under a HUD chip lost its tap to the chip (int5 hand test 8: the Homestead card slid under Energy and
## opened the Energy panel); a card clamps into this band instead, a badge outside it hides.
func _marker_area() -> Rect2:
	var top := 0.0
	if hud and hud.visible: top = UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + safe_top()
	var bottom := _kit.size.y
	if _bar.visible: bottom = minf(bottom, _bar.position.y)
	return Rect2(0.0, top, _kit.size.x, maxf(0.0, bottom - top))

## The band a world camera frames into (camera unification, 不知火舞 on 231): below the HUD's second row, above the
## quick bar and the main key group, in this UI's coordinates. A scene that fits along an axis centres in this band,
## so its front edge never sits under the bar or the key.
func camera_band() -> Rect2:
	var r := _marker_area()
	if _keys != null and _keys.is_visible_in_tree():
		r.end.y = minf(r.end.y, _keys.get_global_rect().position.y - root.global_position.y)
	return r

## The action group's column (its switch over its main key) in this UI's coordinates, as camera_band; empty while it
## is hidden. A world camera keeps a player standing on its side clear of its top (不知火舞 on 442).
func key_column() -> Rect2:
	if _keys == null or not _keys.is_visible_in_tree(): return Rect2()
	var g := _keys.get_global_rect()
	return Rect2(g.position - root.global_position, g.size)

## FloatText (1178:82191, UiFloatText from 2B; SGODOT-224): one line rising from `screen` (its bottom centre) in its
## tone; `stack` = the line's place in one reply (each starts 28 higher and 60 ms later, at most 3). Copy longer
## than one line wraps (Layout=Wrap, two lines at most). `tone` is a UiFloatText.Tone only: a Color used to be taken
## and drawn as ITEM, so a caller's gold or grey never showed (刘邦 on #158); a nothing-gained line is MUTED.
func float_text(text: String, screen: Vector2, tone: UiFloatText.Tone = UiFloatText.Tone.ITEM, icon: Texture2D = null, stack := 0) -> UiFloatText:
	var f := _make_float(text, tone, icon)
	f.play(_float_start(screen, [f], stack), stack)
	return f

func _make_float(text: String, tone: int, icon: Texture2D) -> UiFloatText:
	var f := UiFloatText.new(text, tone, icon, UiFloatText.Layout.WRAP if text.length() > _FLOAT_HUG_CHARS else UiFloatText.Layout.HUG)
	f.theme = UiKit.theme()
	# Inside the screen's side margins all the way through the pop, not only at rest (不知火舞 on #284, 289 46e61588)
	if root: f.bounds = Vector2(UiTokens.SPACE_PAGE, root.size.x - UiTokens.SPACE_PAGE)
	root.add_child(f)
	# A result moment on screen stays readable: the floats rise under its card, not over its rewards (李元芳 int7:
	# `+5 XP` across the level banner's `+3 Wild Herb`). In a drawer they stay on top (BOARD-DONE floats from a row).
	if _moment_open and _modal != null: root.move_child(f, _modal.get_index())
	return f

## Floats never rise over the HUD (int6, 李元芳: `+5 Cooking XP ★` crossed the Today chip; 不知火舞 233): a group's start
## is pushed down until its top line, at the top of its rise, still clears the HUD rows by FLOAT_HUD_GAP. `top_index`
## = that line's stack index (the group's lines minus one).
const FLOAT_HUD_GAP := 8.0
func _float_start(screen: Vector2, lines: Array, top_index: int, top_rise := -1.0) -> Vector2:
	var hud_bottom := _marker_area().position.y + _kit.global_position.y - root.global_position.y
	var h := 0.0
	for f in lines: h = maxf(h, (f as UiFloatText).shown_size().y)
	var lowest := hud_bottom + FLOAT_HUD_GAP + h + UiFloatText._RISE \
		+ (UiFloatText._STACK_RISE * clampi(top_index, 0, UiFloatText._STACK_MAX - 1) if top_rise < 0.0 else top_rise)
	# …and never past the screen's sides: a wide line from near an edge (a trap's three fish by the bank, SGODOT-289)
	# moves in until it is SPACE_PAGE clear of both (each line's own bounds also keep its pop inside them).
	var half := 0.0
	for f in lines: half = maxf(half, (f as UiFloatText).shown_size().x * 0.5)
	var x := screen.x
	if root and half > 0.0: x = clampf(x, half + UiTokens.SPACE_PAGE, maxf(half + UiTokens.SPACE_PAGE, root.size.x - half - UiTokens.SPACE_PAGE))
	return Vector2(x, maxf(screen.y, lowest))

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
const FLOAT_ORDER := ["energy", "xp", "first", "item", "saved", "request", "coins", "affinity", "result"]   # request: `Pond Catch 1/2` (q(103)); saved: Seed Saver's own line after the harvest's items (q(118)); result: a harvest the bag stopped, `Harvest 3 of 5 · bag full`, over its items (E-04, q(123))
## Kinds a later reply adds into while their line is up: XP (`+40 XP · 20 plants`, §4.8.3 XP 入账). Items, Energy and
## coins float per reply (each plot's `+1 Radish`, each bed's `−2 Energy`).
const FLOAT_MERGE_KINDS := ["xp"]
const FLOAT_MAX_LINES := 3
## Item lines hold at most two items: more go on to another line of their own above (q(124) ①; 不知火舞 on #284 3b425f91:
## `River Perch ×1 · Common Carp ×1` / `Arctic Char ×1`, every line its own float of the same height, no ` ·` left at
## a line's end, within FLOAT_MAX_LINES). Cook All's costs and a row's crops read the same way.
const FLOAT_SPLIT_KINDS := ["item"]
## Kinds whose parts each take a line of their own: two taken requests moved by one reply read `Fresh Greens 3/5` and
## `Market Basket · Carrot 5/6` on two lines (q(134) ④), within FLOAT_MAX_LINES like the rest.
const FLOAT_LINE_EACH := ["request"]
const FLOAT_ITEMS_PER_LINE := 2
## The lines one item group splits into pop together as one block, each its own height and this far apart, so they
## never meet, rising or at rest (不知火舞 on #289: Cook All's `−5 Pond Crucian · −2 Wild Herb` / `−2 Radish`).
const FLOAT_GROUP_GAP := 4.0
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
	var rows: Array = []   # [{kind, parts}] from the bottom: a kind's line, or an item line's pair (FLOAT_ITEMS_PER_LINE)
	for k in order:
		var all: Dictionary = kinds[k]
		if k in FLOAT_LINE_EACH:
			for key in all: rows.append({kind = k, parts = {key: all[key]}})
			continue
		# split only while the lines still fit the cap of three; past it the kind stays one line in its own order and joins
		# the cap's last line as any overflow does (q(49) ①, q(124) ①)
		var lines_after := 0   # the kinds above it, a request line each (FLOAT_LINE_EACH)
		for later in order.slice(order.find(k) + 1): lines_after += (kinds[later] as Dictionary).size() if later in FLOAT_LINE_EACH else 1
		var split_lines := ceili(float(all.size()) / FLOAT_ITEMS_PER_LINE)
		if not (k in FLOAT_SPLIT_KINDS and all.size() > FLOAT_ITEMS_PER_LINE) or rows.size() + split_lines + lines_after > FLOAT_MAX_LINES:
			rows.append({kind = k, parts = all})
			continue
		var keys: Array = all.keys()
		var pairs: Array = []
		for j in range(0, keys.size(), FLOAT_ITEMS_PER_LINE):
			var pair := {}
			for key in keys.slice(j, j + FLOAT_ITEMS_PER_LINE): pair[key] = all[key]
			pairs.append({kind = k, parts = pair, group = k})
		pairs.reverse()   # the first pair reads on top
		rows.append_array(pairs)
	var shown: Array = []
	var fresh: Array = []   # [{kind, text, tone, icon, merged, overflow}] lines that need a new float
	var now := int(float_clock.call())
	for i in mini(rows.size(), FLOAT_MAX_LINES):
		var k: String = rows[i].kind
		var merged: Dictionary = rows[i].parts
		var extra: Array = rows.slice(FLOAT_MAX_LINES) if i == FLOAT_MAX_LINES - 1 else []
		if extra.is_empty() and k in FLOAT_MERGE_KINDS:
			var live: Dictionary = _live_floats.get(k, {})
			var node: UiFloatText = live.get("node") if not live.is_empty() and is_instance_valid(live.get("node")) else null
			# Held: the line stays where it rose while the player walks on (§4.8.3); otherwise the same place, briefly.
			var near := fab_held or (not live.is_empty() and now - int(live.get("ms", 0)) < _FLOAT_MERGE_MS and (live.at as Vector2).distance_to(at) < _FLOAT_MERGE_PX)
			if node != null and not node.is_queued_for_deletion() and near:
				for p in merged.values(): _float_add(live.parts, p)
				(live.node as UiFloatText).bump(_float_line_text(live.parts))
				live.ms = now
				shown.append(live.node)
				continue
		var text := _float_line_text(merged)
		for e in extra: text += " · " + _float_line_text(e.parts)   # the overflow joins the last line
		var first: Dictionary = merged.values()[0]
		var tone: int = first.get("tone", UiFloatText.Tone.ITEM)
		# Energy is coloured by what it adds up to; a line of text parts only (a floor fee) keeps its own tone.
		if k == "energy" and merged.values().any(func(p): return p.has("fmt")):
			tone = UiFloatText.Tone.ENERGY_COST if _float_sum(merged) < 0 else UiFloatText.Tone.ENERGY_GAIN
		fresh.append({kind = k, text = text, tone = tone, icon = first.get("icon", null), merged = merged, overflow = not extra.is_empty(),
			group = str(rows[i].get("group", ""))})
	if fresh.is_empty(): return shown
	var base := shown.size()   # lines bumped in place keep the lower places
	var nodes: Array = fresh.map(func(l): return _make_float(l.text, l.tone, l.icon))
	# Each line's place: 28 above the one below (q(49)), but a split item group's lines stack by their own height and
	# FLOAT_GROUP_GAP and start together, growing from the group's lowest line (not one 60 ms after the other).
	var places: Array = []   # [rise of the line's group base, the line above that base, its start slot]
	var rise := UiFloatText._STACK_RISE * base
	var slot := base
	var group_base := rise
	for j in nodes.size():
		var joins: bool = j > 0 and str(fresh[j].group) != "" and str(fresh[j].group) == str(fresh[j - 1].group)
		if j > 0:
			rise += (float((nodes[j - 1] as UiFloatText).shown_size().y) + FLOAT_GROUP_GAP) if joins else UiFloatText._STACK_RISE
			if not joins: slot += 1
		if not joins: group_base = rise
		places.append([group_base, rise - group_base, slot])
	# …and pop to one peak: the lowest of the group's lines (a wide line's is capped), the same for each line
	var j0 := 0
	while j0 < nodes.size():
		var j1 := j0 + 1
		while j1 < nodes.size() and float(places[j1][1]) > 0.0: j1 += 1
		if j1 - j0 > 1:
			var low := INF
			for k in range(j0, j1): low = minf(low, (nodes[k] as UiFloatText).peak())
			for k in range(j0, j1): (nodes[k] as UiFloatText).peak_cap = low
		j0 = j1
	var start := _float_start(at, nodes, base + nodes.size() - 1, rise)
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
		if places.size() == nodes.size():
			f.group_rise = float(places[j][1])
			if f.group_rise > 0.0:   # rests on the line below as that one's font settles
				f.rest_gap = FLOAT_GROUP_GAP
				f.rests_on = nodes[j - 1]
			f.play(start, int(places[j][2]), float(places[j][0]))
		else: f.play(start, base + j)   # pushed down under the HUD: the group joined into one line
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
		var fmt := str(p.get("fmt_plural", p.fmt)) if absi(a) > 1 else str(p.fmt)   # fast crops, including held/merged harvests
		var line := fmt % (("+%d" % a) if a >= 0 else ("−%d" % -a))
		# A held harvest's XP counts its plants once more than one went into it: `+40 XP · 20 plants`.
		if str(p.get("unit", "")) != "" and int(p.get("count", 1)) > 1: line += " · %d %s" % [int(p.count), str(p.unit)]
		if str(p.get("tail", "")) != "": line += " · " + str(p.tail)   # Harvest ×N's `· First harvest` (q(124) ②)
		return line))

# ---------------------------------------------------------------- system states (SGODOT-233, WP6, §10.7.1)
## The runtime's network state: offline the action keys read `Offline` (set_action) and the Offline banner stays up.
var offline := false: set = set_offline
## The Offline banner's Retry: the runtime checks the server now.
signal sys_retry
var _sys: UiSysBanner
var _sys_id := 0
const _SYS_UNDER_HUD := 2.0   # SysBanner y 100: 2 under the HUD's two rows (16 + 82)

func set_offline(v: bool) -> void:
	offline = v
	# Every command button on screen reads `Offline` and does nothing; drawers stay open (§10.7.1).
	UiCommandButton.set_offline(get_tree() if is_inside_tree() else null, v)
	if is_node_ready() and not _fab_state.is_empty(): set_action(_fab_state)

func _exit_tree() -> void:
	if offline: UiCommandButton.set_offline(get_tree(), false)   # a static flag: it must not outlive this UI

## Panel command lifecycle (WP7-B F-08, §10.7.1): the runtime watches the session with it. A command key that starts
## in the same frame a sending button was pressed belongs to that button: it ignores repeat taps at once, dims after
## MOTION_PENDING_DELAY_MS without a reply (label kept), and comes back when the command settles (8 s at most).
var lifecycle := CommandLifecycle.new()

func _init() -> void:
	add_child(lifecycle)   # ticks SUBMITTING → PENDING; a child from the start, so a UI never added frees it too

func track_pressed(key: String) -> void:
	var b := UiCommandButton.take_pressed()
	if b != null and is_instance_valid(b): b.track(lifecycle, key)

# ---------------------------------------------------------------- whole-screen system states (SGODOT-233)
## One P0SysScreen at a time on its own layer over everything this UI draws (banners, toasts, drawers): §10.7.1's
## order is SYS-UPDATE > SYS-MAINT > SYS-LOADING, so a lower one never replaces a higher one. `screen_action(kind)`
## is its card's button (Retry, Check again, Update).
signal screen_action(kind: P0SysScreen.Kind)
## The card's way back (PLACE_FAIL's Go back, and Back while it shows).
signal screen_back(kind: P0SysScreen.Kind)
const SCREEN_LAYER := 100   # over the fishing presentation (30), under AppRouter's loading layer (120)
var _screen_layer: CanvasLayer
var _screen: P0SysScreen

static func _screen_rank(kind: int) -> int:
	return {P0SysScreen.Kind.UPDATE: 3, P0SysScreen.Kind.MAINT: 2}.get(kind, 1)

func show_screen(kind: P0SysScreen.Kind, detail := {}) -> void:
	if _screen != null and _screen_rank(_screen.kind) > _screen_rank(kind): return
	if _screen == null:
		_screen_layer = CanvasLayer.new()
		_screen_layer.layer = SCREEN_LAYER
		add_child(_screen_layer)
		_screen = P0SysScreen.new()
		_screen.primary_pressed.connect(func(k: P0SysScreen.Kind): screen_action.emit(k))
		_screen.secondary_pressed.connect(func(k: P0SysScreen.Kind): screen_back.emit(k))
		_screen_layer.add_child(_screen)
	_screen.show_kind(kind, detail)
	if test_accounts.is_test() and kind == P0SysScreen.Kind.FAIL:
		_screen.set_return_main(func(): test_account_requested.emit("main"))
	else: _screen.set_return_main(Callable())

## Takes the screen down when it is one of `kinds` (any when empty). Down at once for everything that asks; the launch
## splash (q(290): LAUNCH, Can't connect over it) still fades into the scene under it, at least 0.8 s after it showed.
func hide_screen(kinds: Array = []) -> void:
	if _screen == null or (not kinds.is_empty() and not kinds.has(_screen.kind)): return
	var layer := _screen_layer
	var was := _screen
	_screen_layer = null
	_screen = null
	if was.kind in [P0SysScreen.Kind.LAUNCH, P0SysScreen.Kind.FAIL]: was.leave(layer)
	else: layer.queue_free()

## The state on screen, -1 for none.
func screen_kind() -> int: return _screen.kind if _screen != null else -1

func screen() -> P0SysScreen: return _screen

## The place chip's text (`San Francisco · Reed Pond`): the resume cover names where the player is.
func place_text() -> String: return str(_pending.get("place", _place_text))

## The system line under the HUD (SysBanner, x 16 y 100): over the scene and over an open drawer (SYS-OFFLINE-3).
## `seconds` > 0 takes it down after that long (Back online 1.5 s, Didn't go through 3 s); 0 keeps it (Offline).
## Offline outranks Didn't go through (WP6 priority): while offline, a failed command does not replace it.
func show_sys(kind: UiSysBanner.Kind, message: String, seconds := 0.0) -> void:
	if _sys != null and is_instance_valid(_sys) and _sys.visible and _sys.kind == UiSysBanner.Kind.OFFLINE and kind == UiSysBanner.Kind.CMD_FAIL:
		return
	if _sys == null or not is_instance_valid(_sys):
		_sys = UiSysBanner.new()
		_sys.theme = UiKit.theme()
		_sys.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_sys.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_sys.retry_pressed.connect(func(): sys_retry.emit())
		_sys.z_index = OVER_CARDS_Z
		root.add_child(_sys)
	_sys.kind = kind
	_sys.message = message
	_sys.offset_left = -UiSysBanner.WIDTH * 0.5
	_sys.offset_right = UiSysBanner.WIDTH * 0.5
	_sys.offset_top = UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + _SYS_UNDER_HUD + safe_top()
	_sys.visible = true
	root.move_child(_sys, -1)
	_sys_id += 1
	_place_under_hud()
	if seconds > 0.0:
		var id := _sys_id
		get_tree().create_timer(seconds).timeout.connect(func():
			if id == _sys_id and is_instance_valid(_sys):
				_sys.visible = false
				_place_under_hud())

func hide_sys() -> void:
	_sys_id += 1
	if _sys != null and is_instance_valid(_sys): _sys.visible = false
	_place_under_hud()

## The creel badge and the status line sit under the HUD; the system line takes that spot while it is up, so they move
## down by SYS_SHIFT (WP6, 206 31317bce) and come back when it goes.
const SYS_SHIFT := 48.0
func _place_under_hud() -> void:
	var y := UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + UiTokens.SPACE_WITHIN + safe_top()
	if _sys != null and is_instance_valid(_sys) and _sys.visible: y += SYS_SHIFT
	for c in [_creel, _status, _trap_slots]:
		if c != null: (c as Control).position.y = y

## What the system line shows now ("" when it is down): tests and the runtime read it.
func sys_text() -> String: return _sys.message if _sys != null and is_instance_valid(_sys) and _sys.visible else ""

## Toast (Toast R1, §4.8.6; q(49) ⑤): one at a time, a new one replaces the one showing and the same sentence again
## within 2 s only stays up longer. Info; `seconds` > 0 overrides the length rule (2 s + 0.5 s per 20 characters,
## at most 5 s). A tap closes it early. Feedback the player must confirm is a card, never a toast.
func toast(text: String, seconds := 0.0, break_at_dot := false) -> void:
	if not _toasts: return
	if _cover_up:
		_cover_toast = {kind = "info", text = text, brk = break_at_dot}
		return
	_aim_toast()
	_toasts.show_toast(_break_at_dot(text) if break_at_dot else text, ToastLayer.Severity.INFO, "", seconds)

## The width the toast's text gets: ToastLayer's panel (its width, never wider than the layer less SPACE_PAGE each
## side, as _place sizes it) less the panel padding, the glyph and the gap after it. This reads ToastLayer's own
## layout (its _width, _ICON_GAP and the toast tokens), so a change there must come here too (哪吒 on #188);
## test_p0_pond_request_hints checks it against the laid-out label.
func toast_text_width() -> float:
	var panel: float = minf(_toasts._width, _toasts.size.x - UiTokens.SPACE_PAGE * 2.0) if _toasts.size.x > 0.0 else _toasts._width
	return panel - UiTokens.SIZE_TOAST_PAD_LEFT - UiTokens.SIZE_TOAST_PAD_RIGHT - UiTokens.SIZE_TOAST_ICON - ToastLayer._ICON_GAP

## A toast that opts in breaks its two lines at a " · " (UiKit.break_at_dot), measured with the toast's own label font
## at its current width; the toast itself still wraps by words. Measured and broken as it will read: under 中文 the
## whole line's Chinese (the table's) — broken in English first, its halves were looked up apart, and a half the table
## has no line for stayed English (`Fish from a pond` / `open one from the map`; 哪吒's shots for 李白's 452 list).
func _break_at_dot(text: String) -> String:
	var l: Label = _toasts._label
	if l == null: return text
	return UiKit.break_at_dot(tr(text), l.get_theme_font(&"font"), l.get_theme_font_size(&"font_size"), toast_text_width())

## Where the toast sits (WP2 D-01, q(16)): over the quick bar's top edge, in the scene or docked in the bag; over a
## drawer without the bar (the workbench, a counter), just above the drawer's top edge — clear of its rows and of the
## Close key on the right — when there is room under the HUD; else the bar's spot.
const _TOAST_DRAWER_FOOT := 16.0   # q(16): a toast's bottom edge over a drawer's bottom (GUESTBOOK-DELETED)

## A sheet a world lays over the scene without a modal (the stove's watch sheet and its ×, COOK-3): while it shows, toasts sit
## above it and draw over it (the Queue ×2 turn-over toast, q(71)); null clears it.
var _toast_over: Control
func set_toast_over(c: Control) -> void:
	_toast_over = c
	if c != null and _toasts and _toasts.get_parent() == root: root.move_child(_toasts, -1)

func _aim_toast() -> void:
	if _toast_over != null and is_instance_valid(_toast_over) and _toast_over.is_visible_in_tree() and _modal == null:
		_toasts.anchor_above(_toast_over)
		if _toasts.get_parent() == root: root.move_child(_toasts, -1)
		return
	if placing():   # placement: over its caption pill (or its card), never on it (不知火舞 on #624)
		_toasts.anchor_above(_place_bar.toast_dock())
		return
	if _bar != null and _bar.is_visible_in_tree():   # the scene's quick bar, or the bar docked in the bag (q(16))
		_toasts.anchor_above(_bar)
		return
	var content: Control = _modal.get_child(1) if _modal != null and _modal.get_child_count() > 1 else null
	if content is UiDrawer and content.is_visible_in_tree():
		# q(16), 不知火舞 on #86: in a drawer, above its fixed decision area; without one, at the drawer's foot (16 over
		# its bottom and the safe inset, 232 wide). Never above the drawer, never back at the bar's spot over it.
		var area := (content as UiDrawer).action_area()
		if area != null: _toasts.anchor_above(area)
		else: _toasts.anchor_bottom(root.size.y - _TOAST_DRAWER_FOOT - safe_bottom(), ToastLayer.NARROW_WIDTH)
		return
	# A sheet that is not a UiDrawer names its fixed decision area itself (meta "toast_above", e.g. HOME-1's button):
	# the same q(16) rule — the toast sits over it (不知火舞 on #150).
	if content != null and content.is_visible_in_tree() and content.has_meta(&"toast_above"):
		var dock = content.get_meta(&"toast_above")
		if dock is Control and is_instance_valid(dock) and (dock as Control).is_visible_in_tree():
			_toasts.anchor_above(dock)
			return
	if content != null and content.is_visible_in_tree():
		var top := content.get_global_rect().position.y - root.global_position.y
		var hud_bottom := _marker_area().position.y + _kit.global_position.y - root.global_position.y
		if top - UiTokens.SPACE_OVERLAY_BODY - UiTokens.SIZE_TOAST_MIN_H >= hud_bottom:
			_toasts.anchor_above(content)   # a card or sheet that leaves room above it
			return
	_toasts.anchor_above(_bar)

## A refused command (§4.8.6 `命令被拒（非体力）`, wording per appendix B) or FISH-4's full creel. `action` adds a
## guiding line (`Open bag ›`) that acts in place and never travels (LOCK-08). Two lines break at a " · ", the dot
## dropped, as Info toasts that opt in and Today's rows do (q(103); 不知火舞 11-02: `Pond Catch · Deliver to Wen` /
## `Shanghai`, not mid-phrase) — only a sentence with a " · " that a line cannot hold; any other wraps by words as before.
func toast_error(text: String, action := "") -> void:
	if not _toasts: return
	if _cover_up:
		_cover_toast = {kind = "error", text = text, action = action}
		return
	_toast_bag_tab = ""
	_aim_toast()
	_toasts.show_toast(_break_at_dot(text), ToastLayer.Severity.ERROR, action)

## FISH-4 / q(83): a full creel says one sentence — the badge's tap, the greyed Cast · Creel full and the server's
## creel_full alike — and its Open bag › opens the bag on its Fish page.
const CREEL_FULL := "Creel full · 0 free slots · Sell or cook first"
var _toast_bag_tab := ""   # the bag page the showing toast's Open bag › opens ("" = where the bag was)

func toast_creel_full() -> void:
	toast_error(creel_full_text(view), "Open bag")
	_toast_bag_tab = "Fish"

## q(259) (不知火舞's spec, huowu-q259-spec.md): away from home the second part says what the creel's fish fetch at this
## city's Tackle Shop and at home, `230 coins here · 304 at home` (the sums from the view's bag.creel_value, the same
## shape as the away sell card's `{a} each · {b} at home`); at home or without the two sums, `Sell or cook first`. Three
## lines, broken by the text itself — `Creel full · 0 free slots ·` / `230 coins here ·` / `304 at home`, each of which
## fits the toast's 232 — not left to the line breaker: no-break spaces held on the desktop but an Android build broke at
## one (`690 at` / `home`, 李元芳 on 366 c4560e68; without the text server's data the fallback breaker counts U+00A0 as
## a space).
static func creel_full_text(v: Dictionary) -> String:
	var worth = (v.get("bag", {}) as Dictionary).get("creel_value", null)
	if not (worth is Dictionary) or int(worth.get("here", 0)) <= 0 or int(worth.get("here", 0)) == int(worth.get("home", 0)):
		return CREEL_FULL
	return "Creel full · 0 free slots ·\n%s coins here ·\n%s at home" % [P0Travel.grouped(int(worth.here)), P0Travel.grouped(int(worth.home))]

## Done, worth saying once: a cleared mine floor, a resident's meal (§4.8.6 Toast Success). `action` adds its line
## (`Place now ›` after a decor purchase).
func toast_success(text: String, break_at_dot := false, action := "") -> void:
	if not _toasts: return
	if _cover_up:
		_cover_toast = {kind = "success", text = text, brk = break_at_dot, action = action}
		return
	_aim_toast()
	_toasts.show_toast(_break_at_dot(text) if break_at_dot else text, ToastLayer.Severity.SUCCESS, action)

## The priest's buffs' toasts (q(300) ⑨, spec v1.2 §4), from view.buffs as P0Logic.project counts it down: one new says
## what it does; one renewed (Pray drew it while on: its time up by more than BUFF_RENEW_MS — a server answer resets a
## projection by a fraction of a second) says `Twin Catch · back to 20 min`; one that runs out on screen says it has
## worn off. The first view after launch says nothing, nor does one gone at a jump (back from the background, offline:
## no catch-up, spec §4).
const BUFF_RENEW_MS := 5000.0
const BUFF_RENEWED := "%s · back to 20 min"   # the spec's words, as the translation table keys them (李白)
const BUFF_LINES := {"fish": "%s · %d min · every fish lands ×2", "farm": "%s · %d min · sow now, grow 2× faster"}
## q(305): from 11-15 a Legendary under the fish buff lands one, and the toast says so — the line for a take while the day's
## limit is on (view.buff_takes.limit set, home city 11-15 04:00 on); the demo week keeps BUFF_LINES' (不知火舞 (ii)).
const BUFF_LINE_FISH_LIMITED := "%s · %d min · fish ×2, Legendary ×1"

## The toast for a buff just taken, as `v` (the view of that moment: a buff that runs past 04:00 keeps what it said).
static func buff_line(id: String, v: Dictionary) -> String:
	var takes = v.get("buff_takes", null)
	if id == "fish" and takes is Dictionary and takes.get("limit", null) != null: return BUFF_LINE_FISH_LIMITED
	return BUFF_LINES[id]
var _buffs_seen = null   # {id: ms left} at the last view; null before the first

func _watch_buffs(v: Dictionary) -> void:
	var now := P0Logic.buffs_left(v)
	if _buffs_seen is Dictionary:
		var minutes := int(P0Logic.content().get("buffs", {}).get("minutes", 20))
		for id in P0Logic.BUFF_ORDER:
			if now.has(id) and not _buffs_seen.has(id):
				toast_success(buff_line(id, v) % [P0Logic.BUFF_NAMES[id], minutes], true)   # two lines after a ` · ` (q(305), 452)
			elif now.has(id) and float(now[id]) > float(_buffs_seen[id]) + BUFF_RENEW_MS:   # Pray drew one on (v1.2 §4)
				toast_success(BUFF_RENEWED % P0Logic.BUFF_NAMES[id])
			elif _buffs_seen.has(id) and not now.has(id) and float(_buffs_seen[id]) <= BUFF_RENEW_MS:
				toast("%s has worn off" % P0Logic.BUFF_NAMES[id])
	_buffs_seen = now

## DECOR-BOUGHT (Figma 2189:32861, q(111)): `Flower Planter` / `in Farm Storage` + `Place now ›`, which closes the drawer
## and opens Decorate with that piece picked.
var _toast_decor := ""
func toast_decor_bought(id: String) -> void:
	_toast_decor = id
	toast_success("%s · in Farm Storage" % P0Decor.name_of(id), true, "Place now")

## q(261) ⑦ (SGODOT-361): a toast said while a cross-city flight's cover is up waits until it is down and its welcome
## — and a first visit's card — has been said (`after_s`, then as toast_when_clear does); the latest one wins, as a
## toast replaces a shown one. SYS lines (show_sys) are not held.
var _cover_up := false
var _cover_toast := {}

func hold_toasts(on: bool, after_s := 0.0) -> void:
	_cover_up = on
	if on or _cover_toast.is_empty(): return
	var held := _cover_toast
	_cover_toast = {}
	if after_s <= 0.0 or not is_inside_tree(): _say_held(held)
	else: get_tree().create_timer(after_s).timeout.connect(func(): if not _cover_up: _say_held(held))

## An Info toast about the city the player is in (a Day Pass ended): held under a cover like any, it is said then only
## if the player is still in that city (q(261) ⑦: they may have flown on).
func toast_in_city(text: String, cluster: String) -> void:
	if _cover_up:
		_cover_toast = {kind = "info", text = text, city = cluster}
		return
	toast(text)

func _say_held(held: Dictionary) -> void:
	if held.has("city") and P0Travel.here(view) != str(held.city): return
	match str(held.kind):
		"error": toast_error(str(held.text), str(held.get("action", "")))
		"success": toast_success_when_clear(str(held.text), bool(held.get("brk", false)))
		_:   # as toast_when_clear, keeping its line break: after the welcome's card too
			_held_toast = str(held.text)
			_held_success = false
			_held_break = bool(held.get("brk", false))
			_held_after_tip = false
			_flush_held_toast()

## What the toast says now ("" when none is up).
func toast_text() -> String: return _toasts.current_text() if _toasts else ""

## Takes the toast down now (tests, or a panel that replaces what it said).
func clear_toast() -> void:
	if _toasts: _toasts.dismiss()

## `Space taken · clear it first`'s action (q(303), SGODOT-450): into Decorate on what holds the Kitchen Wing's cells.
const DECORATE_ACTION := "Decorate"

func _on_toast_action(action: String) -> void:
	match action:
		"Open bag": open_bag("", "bag" if _toast_bag_tab != "" else "", _toast_bag_tab)
		DECORATE_ACTION:
			if space_here() != "home": return
			close_modal()
			show_spot.emit(P0Logic.DECORATE_GO)   # in the farmhouse, out to the yard first (P0Runtime._show_spot)
		"Place now":
			if _toast_decor == "" or space_here() != "home": return
			close_modal()
			decor_requested.emit(_toast_decor)

# ---------------------------------------------------------------- modals
## Going to the background cancels a slot drag: the slot flies back, nothing changes (LOCK-04 v1.10).
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT] and _bar != null:
		_bar.cancel_drag()
		_bag_cancel()   # a bag cell lifted for the bar too (int9 F2)

## Android Back closes what is on top first, one layer per press (LOCK-06, int5 hand test 012–013 / 023–024): the
## a quick slot being dragged (it flies back, LOCK-04 v1.11; the PinMenu is gone), a bag cell lifted for the bar (it
## flies back into the grid, the drawer stays: int9 F2), the radial, then a card or drawer. True when it closed
## something; the world only leaves on false.
func close_top_layer() -> bool:
	if voice_blocks_back(): return true   # the voice-match page's own Back (SGODOT-349): the profile stays as it was
	if is_instance_valid(_ask):   # the soft prompt goes, not answered (不知火舞 350 7bffafd7)
		_put_ask_away()
		return true
	if _screen != null:   # SYS-LOADING / MAINT / UPDATE have no close: Back does nothing (q(74)) …
		if _screen.kind == P0SysScreen.Kind.PLACE_FAIL: screen_back.emit(_screen.kind)   # … but Couldn't get there's is Go back (q(78))
		return true
	if _bar != null and (_bar.is_dragging() or _bar.is_lifted()):   # lifted and not moved yet counts too (刘邦 on #38)
		_bar.cancel_drag()
		return true
	if not _bag_drag.is_empty():
		_bag_cancel()
		return true
	if _radial.is_open():
		_radial.close()
		return true
	if _modal != null:
		# An InfoSheet laid over the open panel (UiInfoSheet.layered) goes first: one layer per press (§4.8.7, 刘邦 on #73).
		var layers := _modal.find_children("InfoSheetLayer", "Control", true, false).filter(func(l): return not l.is_queued_for_deletion())
		if not layers.is_empty():
			((layers.back() as Control).find_children("*", "UiInfoSheet", true, false)[0] as UiInfoSheet).close()
			return true
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

## Nothing open over the world (q(235) ①): no page, drawer, card, dialogue or banner (all modal layers), no radial, no
## TipCard, InboxNotice or SysBanner. A Toast or a float does not count.
func calm() -> bool:
	return not has_modal() and not (is_instance_valid(_teach) and _teach.visible) \
		and not (is_instance_valid(_notice) and _notice.visible) and not (is_instance_valid(_sys) and _sys.visible)

# ---------------------------------------------------------------- the notification soft prompt (q(235), q(236) ④)
## It comes the first time all at once: the player on their own farm outdoors, the question's crops growing
## (P0Notify.ask_question), every finger up (the action key and the stick let go, no sowing or watering run) and nothing
## open (calm). Put away unanswered — and not asked — when the player leaves the farm outdoors (the farmhouse, the mine,
## the map), something opens (a panel, or an InboxNotice, banner, TipCard, SYS card or resident bar coming up), Back,
## or the app going to the background; a crop ripening or a held stick does not. Once put away it does not come again
## this run: the next launch or return from the background looks again (q(237) ③). Allow / Not now answer it.
const _ASK_EVERY_S := 0.5
var _ask: UiSoftPrompt
var _ask_left := 0.0
var _ask_rested := false   # put away unanswered: not again this run (ask_again: back from the background)
var _fingers := {}         # touch index (the mouse is -1) → down

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch: _finger(e.index, e.pressed)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT: _finger(-1, e.pressed)
	# SGODOT-260 Q3: a touch, a drag, a click or a key — the runtime sets the view on its next frame (view_wanted)
	if e is InputEventScreenTouch or e is InputEventScreenDrag or e is InputEventMouseButton or e is InputEventKey \
			or (e is InputEventMouseMotion and (e as InputEventMouseMotion).button_mask != 0):
		_touched = true

var _touched := false
var _shown_of: Dictionary = {}   # the session view the HUD and panels last showed (by reference)
var _shown_sig := []
var _shown_ms := -1_000_000

## SGODOT-260 Q3: whether the runtime's frame should set the view (set_view rebuilds nothing unchanged, but working that
## out every frame was most of a frame's view cost). Due when the server's view is new, when what this UI is showing
## changed under it (a drawer opened or closed, the world, the bar's action or its pick, offline), after any input,
## and otherwise at least every VIEW_FLOOR_MS — every countdown's second, and whatever moves without saying so, catch
## up within a quarter second, as Today's rows always have (_refresh_today). `server_view` is the session's own view
## (current() projects it); `now_ms` the clock.
const VIEW_FLOOR_MS := 250
func view_wanted(server_view: Dictionary, now_ms: int) -> bool:
	var sig := [modal_kind, _modal, surface, bar_mode, space, selected_seed, selected_bait, offline]
	if not _touched and is_same(server_view, _shown_of) and sig == _shown_sig and now_ms - _shown_ms < VIEW_FLOOR_MS: return false
	_touched = false
	_shown_of = server_view
	_shown_sig = sig
	_shown_ms = now_ms
	return true

func _finger(index: int, down: bool) -> void:
	if down: _fingers[index] = true
	else: _fingers.erase(index)

func fingers_up() -> bool: return _fingers.is_empty()

func _on_farm() -> bool: return space == "home" and surface == "farm"

func _tick_ask(dt: float) -> void:
	if notify == null: return
	if is_instance_valid(_ask):
		if not _on_farm() or not calm(): _put_ask_away()
		return
	if not _on_farm(): return
	_ask_left -= dt
	if _ask_left > 0.0 or _ask_rested: return
	_ask_left = _ASK_EVERY_S
	if not fingers_up() or not calm() or view.is_empty(): return
	var question := P0Notify.ask_question(view)
	if question == "" or not notify.may_ask(): return
	show_ask(question)

func show_ask(question: String) -> void:
	if is_instance_valid(_ask): _ask.queue_free()
	_ask = UiSoftPrompt.new(question)
	_ask.name = "SoftPrompt"
	_ask.theme = UiKit.theme()
	_ask.answered.connect(func(allow: bool):
		notify.answer(allow)
		_ask.go_out()
		_ask = null)
	root.add_child(_ask)
	root.move_child(_toasts, -1)
	_ask.reset_size()
	_ask.come_in(Vector2(UiTokens.SPACE_PAGE, UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + _BANNER_UNDER_HUD + safe_top()))

## The app went to the background: the soft prompt goes, unanswered (q(237) ③).
func ask_away() -> void: _put_ask_away()

## Back from the background (or a fresh launch): it may come again under its four conditions.
func ask_again() -> void:
	_ask_rested = false
	_ask_left = 0.0

func _put_ask_away() -> void:
	if not is_instance_valid(_ask): return
	_ask.go_out()
	_ask = null
	_ask_rested = true

## The top (UI px) of the card open over the world, for what keeps above it (the map's credit line, q(133) v3): INF
## with none, 0 for a page that covers the world. Only what stands on the screen's bottom edge counts: a page, a drawer
## or a card's panel (its × over it does not, nor a moment or banner shown mid-screen, 周瑜 on #309).
func modal_top() -> float:
	if _modal == null or not is_instance_valid(_modal) or _modal.get_child_count() == 0: return INF
	var content := _modal.get_child(_modal.get_child_count() - 1) as Control
	if content == null: return INF
	var screen := root.get_viewport_rect().size
	var low := func(r: Rect2) -> bool: return r.end.y >= screen.y - 2.0 and r.size.x >= screen.x * 0.5
	if content.mouse_filter == Control.MOUSE_FILTER_STOP:
		var r := content.get_global_rect()
		return r.position.y if low.call(r) else INF
	var top := INF
	for c in content.get_children():   # a card: a holder over the whole screen, its panel low in it
		if not (c is Control) or not (c as Control).visible or (c as Control).mouse_filter != Control.MOUSE_FILTER_STOP: continue
		var r := (c as Control).get_global_rect()
		if low.call(r): top = minf(top, r.position.y)
	return top

## Who speaks in the open modal (NPC-G1, #57): "keeper" under a keeper's greeting card, the resident's id under their
## dialogue bar, "" under anything else. Read from the modal itself, so a bar reached any way counts — a dish card's
## `Gift to <Name>` drawer goes back to that resident's bar without the room ever having been tapped (韩信 int9).
func speaker() -> String:
	if _modal == null: return ""
	match modal_kind:
		"greeting": return "keeper"
		"resident": return _resident
	return ""

func close_modal() -> void:
	_over_profile = false   # out to the world: what opens next is over the world
	_drop_modal()
	if not _card_queue.is_empty():
		var next: Callable = _card_queue.pop_front()
		next.call_deferred()
	else:
		_flush_held_toast()
		_flush_held_notice()

## A toast that must not be lost under the fishing presentation (layer 30, over this layer) or a result card: the
## last bait goes at the reel's settlement, while the panel still shows the landing (int5b hand test 10). Shown at
## once when nothing covers the UI, else held until the world is back from "busy" and no card is open or queued.
var _held_toast := ""
var _held_success := false   # the held toast is a Success one (toast_success_when_clear)
var _held_break := false     # … and breaks its two lines at a " · " (_break_at_dot)
var _held_after_tip := false # … and waits for a TipCard on screen to close (a request filled, q(134) ⑤)

func toast_when_clear(text: String) -> void:
	_held_toast = text
	_held_success = false
	_held_break = false
	_held_after_tip = false
	_flush_held_toast()

## The same for a Success toast: a request filled (`Pond Catch · 2/2` / `Deliver at the Stall`, q(134)) waits for the
## Caught! card and a level banner of the same catch; with after_tip also for a TipCard on screen. One slot: the latest
## held toast wins, as a new toast replaces a shown one.
func toast_success_when_clear(text: String, break_at_dot := false, after_tip := false) -> void:
	_held_toast = text
	_held_success = true
	_held_break = break_at_dot
	_held_after_tip = after_tip
	_flush_held_toast()

func _flush_held_toast() -> void:
	if _held_toast == "" or not is_node_ready(): return
	if surface == "busy" or _modal != null or not _card_queue.is_empty(): return
	if _held_after_tip and _teach != null and _teach.visible: return   # _hide_tip lets it come
	if _held_success: toast_success(_held_toast, _held_break)
	else: toast(_held_toast, 0.0, _held_break)
	_held_toast = ""
	_held_success = false
	_held_break = false
	_held_after_tip = false

## InboxNotice (BAG-5-2 / FARM-LV2-2, LOCK-14, q(87) / q(88); SGODOT-234): rewards that did not fit the bag went to the
## Inbox. The card hangs under the bell, its right edge on the bell's (top: _notice_top), for MOTION_TOAST_BASE_MS
## (BAG-5: 2 s); a tap on it opens the Inbox on Parcels, as the bell does. One at a time: a new one replaces it. Like
## toast_when_clear it waits while the world is busy or a card or drawer is up or queued (q(49), one thing at a time: a
## level-up's banner speaks first, 不知火舞 on 233); the bell's badge counts at once.
const _NOTICE_UNDER_HUD := UiTokens.SPACE_OVERLAY_BLOCK   # 12 under the HUD's two rows: y 110 of 800
const _NOTICE_UNDER_ITEM := UiTokens.SPACE_OVERLAY_BODY   # 8 under the lowest thing under the HUD
var _notice: UiInboxNotice
var _notice_left := 0.0
var _held_notice := {}

## spec: P0Logic.parcel_notice ({} says nothing).
func inbox_notice_when_clear(spec: Dictionary) -> void:
	if spec.is_empty(): return
	_held_notice = spec
	_flush_held_notice()

func _flush_held_notice() -> void:
	if _held_notice.is_empty() or not is_node_ready(): return
	if surface == "busy" or _modal != null or not _card_queue.is_empty(): return
	_show_notice(_held_notice)
	_held_notice = {}

func _show_notice(spec: Dictionary) -> void:
	if _notice == null:
		_notice = UiInboxNotice.new()
		_notice.theme = UiKit.theme()
		_notice.tapped.connect(func():
			_hide_notice()
			if _modal == null: open_inbox("parcels"))
		root.add_child(_notice)
	_notice.show_notice(spec, P0Logic.icon("parcel"))
	_notice.show()
	_place_notice(true)
	_notice_left = UiTokens.MOTION_TOAST_BASE_MS / 1000.0

func _hide_notice() -> void:
	_notice_left = 0.0
	if _notice: _notice.hide()

## Placed every frame while it shows (the HUD lays out after it first shows). `fresh`: it has just come up, so it takes
## its top as it is now; afterwards it only moves down, so a system line coming pushes it and one going does not make
## it jump back (不知火舞 on 234).
func _place_notice(fresh := false) -> void:
	var bell := hud.balances_rect()   # its right edge is the bell's
	var right := (bell.end.x - root.global_position.x) if bell.size.x > 0.0 else root.size.x - UiTokens.SPACE_PAGE
	var y := _notice_top()
	_notice.position = Vector2(roundf(right - UiInboxNotice.WIDTH), y if fresh else maxf(y, _notice.position.y))

## The card's top (不知火舞 on 234, after 刘邦 on #116): 8 under the lowest thing showing under the HUD, top to bottom
## the system line (SYS-OFFLINE / SYS-CMD-FAIL), the creel badge at the pond (full, it is the fact the player needs) and
## the mine's status line; with none of them, 12 under the HUD's two rows.
func _notice_top() -> float:
	var y := UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + _NOTICE_UNDER_HUD + safe_top()
	for c in [_sys, _creel, _status]:
		if c != null and is_instance_valid(c) and (c as Control).is_visible_in_tree():
			y = maxf(y, (c as Control).get_global_rect().end.y - root.global_position.y + _NOTICE_UNDER_ITEM)
	return roundf(y)

## The InboxNotice on screen, {} when none: its three lines (tests and the runtime read it).
func inbox_notice_shown() -> Dictionary:
	if _notice == null or not _notice.visible: return {}
	return {title = _notice.title_text(), item = _notice.item_text(), quantity = _notice.quantity_text(), line = _notice.line_text()}

## The card on screen (tests tap it), or null.
func inbox_notice_card() -> UiInboxNotice:
	return _notice if _notice != null and _notice.visible else null

## Result cards (catch, dish, level up) wait their turn instead of replacing each other.
func queue_card(show: Callable) -> void:
	if _modal == null and _card_queue.is_empty(): show.call()
	else: _card_queue.append(show)

## A card with a button must not open under the fishing presentation, whose input shield over this layer takes every
## touch (李元芳 int7: the first level-up's Use bait could not be pressed). It waits until the world is back from
## "busy", then queues like any card.
var _held_cards: Array[Callable] = []

func queue_card_when_clear(show: Callable) -> void:
	_held_cards.append(show)
	_flush_held_cards()

func _flush_held_cards() -> void:
	if _held_cards.is_empty() or not is_node_ready() or surface == "busy": return
	var cards := _held_cards.duplicate()
	_held_cards.clear()
	for c in cards: queue_card(c)

## The card queue's turn opened nothing (a held card): let the next one come.
func _next_card() -> void:
	if _modal == null and not _card_queue.is_empty(): (_card_queue.pop_front() as Callable).call_deferred()

## A modal that is not a drawer is open (a card, a sheet, a page): TipCards wait under it (_process). A drawer is content
## that is, or holds, a UiDrawer — the kitchen's wrap holds the stove drawer, the Fish-dex its own.
var _modal_drawer := false
func dialog_open() -> bool: return _modal != null and is_instance_valid(_modal) and not _modal_drawer

func _drop_modal() -> void:
	_modal_back = Callable()   # each layer sets its own way back after it opens
	if _moment_open:   # a result moment went: a waiting TipCard may come up now (q(49) ⑥)
		_moment_open = false
		if tips: tips.moment_closed()
	_bag_drag_end()   # a bag cell lifted toward the bar goes with its drawer
	undock_bar()   # before the drawer holding it goes (SGODOT-225)
	if _modal: _modal.queue_free()
	_modal = null
	_modal_veil = null
	var was_kitchen := modal_kind == "kitchen"
	modal_kind = ""
	if was_kitchen: _refresh_hud()   # back out of the farmhouse
	# Placement mode keeps the main key, the switch key and the quick bar away until it ends (q(23); 不知火舞 on 284:
	# a closed piece card brought `Till` and ⇄ back under Decorate's Done); end_placement puts them back.
	_keys.visible = surface in ACTION_SURFACES and not placing()
	_bar.visible = _bar_shown() and not placing()

func _open_modal(content: Control, dim := 0.32, hide_controls := false) -> void:
	_bar.cancel_drag()   # a drawer or card opening cancels a slot drag (LOCK-04 v1.10)
	var under := _profile_to_keep()
	_drop_modal()
	var veil := ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.184, 0.227, 0.2, dim)
	veil.gui_input.connect(func(e: InputEvent):
		if P0Ui.is_tap(e): back_modal())
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if under != null: holder.add_child(under)   # the profile stays behind the scrim (256 ⑧)
	holder.add_child(veil)
	holder.add_child(content)
	# A drawer dragged down fades its scrim with it (SGODOT-265); a drawer may sit inside the content (the Fish-dex).
	_modal_drawer = false
	for d in ([content] if content is UiDrawer else []) + content.find_children("*", "UiDrawer", true, false):
		(d as UiDrawer).scrim = veil
		_modal_drawer = true
	if surface == "map" and content is PanelContainer:
		# Over the map, translucent paper lets the map's own buttons ghost through the card.
		var sb := (content as PanelContainer).get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			sb = sb.duplicate()
			(sb as StyleBoxFlat).bg_color.a = 1.0
			content.add_theme_stylebox_override("panel", sb)
	root.add_child(holder)
	_modal_veil = veil
	if under != null: (under as P0ProfilePage).preview.set_active(true)   # moved: watch its new ancestors' visibility
	root.move_child(_toasts, -1)   # a toast stays readable over a drawer or card
	if _sys != null and is_instance_valid(_sys): root.move_child(_sys, -1)   # the system line too (SYS-OFFLINE-3)
	_modal = holder
	if hide_controls:
		_keys.visible = false
		_bar.visible = false

## Bottom system inset (gesture bar, rounded corners) in UI units; 0 on desktop.
func safe_bottom() -> float:
	if not is_inside_tree(): return 0.0   # no viewport to read yet (as safe_top: a Release engine crashes on its null)
	if not (OS.has_feature("android") or OS.has_feature("ios")): return 0.0
	return UIMetrics.safe_margins(DisplayServer.get_display_safe_area(), DisplayServer.window_get_size(),
		get_viewport().get_visible_rect().size, 0.0).w

## Bottom edge for cards that sit low (NPC greetings): on the quick bar's baseline (41 from the bottom,
## FISH-1 / NPC-G1), or clear of a taller gesture bar — never against the screen edge.
func bottom_pad() -> float:
	return maxf(41.0, safe_bottom() + 16.0)

## Bag | Gear drawer (SGODOT-225; LOCK-12 / 13, BAG-2-2 / BAG-2 · Gear): P0BagDrawer from the kit. Tapping a
## cell opens the F-07 bag card (UiInfoSheet, no Sell in the bag); the Gear side lists the tapped slot's
## candidates. No separate Tools & Gear panel and no Outfit tab (p(8)). The drawer follows the view while open.
var bag_side := "bag"
var gear_slot := "fishing"
var _bag: P0BagDrawer
var _eat_armed := ""   # dish whose partial-gain warning was shown; a second Eat eats (§7.17.1)

func open_bag(focus := "", side := "", category := "") -> void:
	if side != "": bag_side = side
	var d := P0BagDrawer.new(view, bag_side, focus)
	if category != "": d.show_category(category)   # the creel badge and a full creel's Open bag ›: the Fish page
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

## A lifted bag cell let go of without a drop (Back, the app paused): it flies back into its grid cell, as a quick
## slot does (UiQuickBar._fly_back); the gap stays until it lands. The finger's later release changes nothing.
func _bag_cancel() -> void:
	if _bag_drag.is_empty(): return
	var ghost: UiItemCell = _bag_drag.ghost
	var id := str(_bag_drag.id)
	_bag_drag.ghost = null   # _bag_drag_end leaves it to the flight
	_bag_drag_end()
	if not is_instance_valid(ghost): return
	var cell: UiItemCell = _bag.grid.cell_for(id) if _bag and is_instance_valid(_bag) else null
	if cell == null:
		ghost.queue_free()
		return
	if _bag: _bag.grid.lifted_id = id   # the dashed gap waits for the cell
	ghost.scale = Vector2.ONE
	var t := ghost.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(ghost, ^"global_position", cell.global_position, UiKit.secs(UiQuickBar.FLY_BACK_MS))
	t.tween_callback(func():
		ghost.queue_free()
		if _bag and is_instance_valid(_bag) and _bag.grid.lifted_id == id: _bag.grid.lifted_id = "")

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
	if not P0Logic.GearLogic.command_allowed({type = str(action), item = id}): return
	if id.begins_with("potion_") and action in [&"pin", &"unpin"] and not P0Logic.GearLogic.potion_actions_enabled: return
	match action:
		&"bag_room":   # BAG-5: Bag Upgrade I is a homestead matter; Show the house (or the homestead on the map)
			close_modal()
			if show_label("home", space_here(), spot_reachable(), place) == "Show": show_spot.emit("home")
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
		&"place":             # a decor piece's card in Farm Storage (STORE-DECOR): the drawer goes, Decorate picks it
			if space_here() == "home":
				close_modal()
				decor_requested.emit(id)
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
	var go := str(src.go)
	# 355 C2: a city's spot or a wild mine is a map pin (Show on map from here, Show on the map), as Today's rows go
	var label := show_label(go, space_here(), spot_reachable(), place)
	if label == "": go = ""
	var on_show := Callable() if go == "" else func():
		close_modal()
		if label == "Show": show_spot.emit(go)
		else: show_on_map.emit(map_target(go))
	var layer := UiNeedSource.popup(root, tile.get_global_rect(), str(src.text), on_show)
	layer.theme = UiKit.theme()

## Keeper greeting (KeeperGreeting 1205:83238, LOCK-16; NPC-G1 / G1-2 / G1-3 / G1-4): every keeper greets first.
## `Role · Name`, `Does it · Place`, the line (P0Logic.keeper_lines, facts from view.keepers), then Trade (the counter)
## and the question (its answer replaces the line); a Close 44 sits 8 above the card's top-right corner, as on the
## resident's bar, and a tap outside or Back closes it too (q(154), LOCK-16 复议 197 e508cd27: Joey on 296 — `Just passing
## by` took a whole row to close the card, `Trade · open the stall` a sentence for a button). role = the counter id ("tackle", "tea", "post",
## "market"); ctx = the outpost's keeper ctx {keeper, place, nearest} (SGODOT-227), passed through untouched and kept
## for the counter's keeper bar.
var _keeper_told := {}   # role → answers given this run (Gabriel's stories round, q(299))
var _priest_card: UiDialogueCard   # Gabriel's greeting while up: its Pray key and count line follow the view (q(300))
var pray_roll := func() -> float: return randf()   # Pray's draw (tests set it)
func open_keeper_greeting(role: String, ctx := {}) -> void:
	if not ctx.is_empty(): _counter_ctx[role] = ctx
	var c: Dictionary = _counter_ctx.get(role, {})
	var lines := P0Logic.keeper_lines(view, role, c)
	var who: Array = P0CounterDrawer.KEEPERS.get(role, ["", ""])
	var name := str(c.get("keeper", who[1]))
	var card := UiDialogueCard.new(P0CounterDrawer.keeper_portrait(name, true, str(c.get("look", ""))), "%s · %s" % [str(c.get("role", who[0])), name], "",
		str(lines.greet))
	card.theme = UiKit.theme()
	card.portrait_size = UiDialogueCard.KEEPER_PORTRAIT
	card.place = str(lines.line)
	if not bool(lines.get("talk_only", false)):   # Gabriel has no counter: no Trade (q(299))
		var trade := UiCommandButton.new(str(lines.trade))
		if role == "casino": trade.activated.connect(func(): _play_blackjack(c))   # Play: the table page, no counter (q(240))
		else: trade.activated.connect(func(): open_counter(role))
		card.content.add_child(trade)
	# q(272) (不知火舞 378 091a3ae9, LOCK-16 复议 197 1387e81b): a keeper away from home with a local request for the
	# player — one full-width secondary key under Trade, the question below it; none at all when they have none
	var lk := P0Locals.key(view, str(c.get("outpost", "")))
	if not lk.is_empty():
		var key := UiCommandButton.new(str(lk.text), UiCommandButton.Kind.SECONDARY)
		key.name = "LocalKey"
		key.reason = str(lk.reason)
		key.fit_text = true
		if lk.kind == "deliver":
			key.sends = true
			key.activated.connect(func():
				close_modal()
				command.emit({"type": "deliver", "request": str(lk.id)}))
		else:
			var open_card := func(): P0LocalRequest.open(self, str(lk.id), func(): open_keeper_greeting(role, c))
			key.activated.connect(open_card)
			# the gap key is grey (LOCK-10): a tap on it is unavailable_pressed, and it opens the card all the same
			key.unavailable_pressed.connect(func(_r: String): open_card.call())
		card.content.add_child(key)
	_priest_card = card if role == "church" else null
	var pray := P0Logic.priest_pray(view) if role == "church" else {}
	if not pray.is_empty():   # Gabriel's Pray (q(300) v1.2, SGODOT-445): a buff drawn at random, the card stays up
		var key := UiCommandButton.new(P0Logic.PRAY)
		key.name = "Pray"
		key.fit_text = true
		key.sends = true
		key.reason_beside = true
		key.reason = str(pray.reason)
		# the toast is the HUD's (亚瑟)
		key.activated.connect(func(): command.emit({"type": "buff", "buff": P0Logic.pray_draw(pray_roll.call())}))
		key.unavailable_pressed.connect(func(r: String): toast(r))
		card.content.add_child(key)
		var count := UiKit.label(str(pray.line), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
		count.name = "PrayCount"
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.visible = str(pray.line) != ""
		card.content.add_child(count)
	if str(lines.question) != "" and str(lines.answer) != "":
		var ask := UiCommandButton.new(str(lines.question), UiCommandButton.Kind.SECONDARY)
		var answers: Array = lines.get("answers", [lines.answer])
		ask.activated.connect(func():   # the next answer each press (Gabriel's stories, q(299)); one answer stays as it was
			var i := int(_keeper_told.get(role, 0))
			card.line = str(answers[i % answers.size()])
			_keeper_told[role] = i + 1)
		card.content.add_child(ask)
	card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	card.offset_left = UiTokens.SIZE_QUICK_BAR_X
	card.offset_right = -UiTokens.SIZE_QUICK_BAR_X
	card.offset_bottom = -bottom_pad()
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_open_modal(card, 0.0, true)
	_close_above(card, _CLOSE_ABOVE_CARD)
	modal_kind = "greeting"

## The Pray key and its count line follow the view (set_view, every 250 ms): a take counted, the limit reached at the
## 11-15 rollover, the day passing.
func _refresh_priest_keys() -> void:
	if modal_kind != "greeting" or _priest_card == null or not is_instance_valid(_priest_card): return
	var pray := P0Logic.priest_pray(view)
	var key := _priest_card.content.get_node_or_null("Pray") as UiCommandButton
	var count := _priest_card.content.get_node_or_null("PrayCount") as Label
	if pray.is_empty() or key == null or count == null: return
	if key.reason != str(pray.reason): key.reason = str(pray.reason)
	if count.text != str(pray.line): count.text = str(pray.line)
	count.visible = str(pray.line) != ""

## Lou's Play and the blackjack table (SGODOT-351): the full-screen table page (哪吒's open_blackjack(ctx), 351 d6fae42c),
## the greeting card closed first — only while view.blackjack says the table is open. A server without the table (no
## view.blackjack: 0.2.12 ahead of the server, 用户 via 奕星) or with it closed (bj_locked, P0_BJ_TABLE off) keeps the
## card up and says so in the Info toast, the same sentence however often it is tapped (不知火舞 351 bc19606c / 66d46cf9).
const BJ_NOT_OPEN := "Blackjack isn't open yet."
static func blackjack_open(v: Dictionary) -> bool:
	var bj = v.get("blackjack", null)
	return bj is Dictionary and bool(bj.get("open", false))
func _play_blackjack(ctx := {}) -> void:
	if not blackjack_open(view):
		toast(BJ_NOT_OPEN)
		return
	close_modal()
	open_blackjack(ctx)

## The tackle shop before the outposts open it with their ctx (the map's tackle pin, P0_SHOT "kai").
func open_kai_greeting() -> void:
	var o := P0Outposts.by_role("tackle")
	open_keeper_greeting("tackle", {"keeper": str(o.get("keeper", {}).get("name", "")), "place": str(o.get("name", "")),
		"nearest": {"name": tackle_place, "site": str(o.get("nearest", {}).get("site", "pond"))}})

## Counters (SGODOT-224; LOCK-15 / 16; FARM-6, NPC-2, NPC-2-2, NPC-6, NPC-7-P0): one drawer for every counter,
## P0CounterDrawer. role = the shop id ("homestead", "tackle", "market", "tea", "post"); opts: section ("buy" |
## "board" | "specialty": #14 opens the Market Board and City Specialty directly) and ctx (the outpost's keeper ctx).
## The drawer follows the view while open (set_view); its buttons come back here as commands with the shop.
var _counter: P0CounterDrawer
var _counter_ctx := {}   # role -> the last keeper ctx an outpost gave
## STALL-NEW for the visit in progress: worked out when the stall opens from the world and kept while its board sheets
## (BOARD-1 / BOARD-3 / BOARD-DROPPED) go back to it, so `◆ New for you` stays for the whole visit (亚瑟 on #77).
var _stall_visit_new: Variant = null
const _COUNTER_FLOW := ["counter", "board_request", "board_drop", "board_dropped"]

## The counter drawer while it is open, its Market Board sheets over it included (the outposts push the camera in on
## the keeper above it, #128); null otherwise.
func counter_drawer() -> P0CounterDrawer:
	return _counter if modal_kind in _COUNTER_FLOW and is_instance_valid(_counter) else null

## A counter row's › (不知火舞 on 284): its card over the counter (UiInfoSheet.layered: Back or a tap outside closes it
## first) — name, use line, the materials as NeedTiles (a tap: where it comes from, LOCK-10), the price and the row's own
## key, which does what the row's does.
func counter_info(d: P0CounterDrawer, id: String) -> UiInfoSheet:
	if d.info_card(id).is_empty() or _modal == null: return null
	var sheet := UiInfoSheet.layered(_modal, Vector2(UiTokens.SIZE_QUICK_BAR_X, UiTokens.SPACE_PAGE + safe_bottom()))
	sheet.theme = UiKit.theme()
	sheet.rules = func(_i: String, _c: StringName, _o: Dictionary) -> Dictionary: return d.info_card(id)
	sheet.action_requested.connect(func(_a: StringName, _i: String, _p: Dictionary):
		sheet.close()
		d.press_row(id))
	sheet.unavailable_requested.connect(func(_a: StringName, _i: String, reason: String): toast(reason))
	sheet.need_pressed.connect(func(item: String, tile: UiNeedTile): _show_need_source(tile, item))   # LOCK-10
	sheet.open(id, &"counter_info")
	return sheet

func open_counter(role: String, opts := {}) -> void:
	if opts.has("ctx"): _counter_ctx[role] = opts.ctx
	var ctx: Dictionary = _counter_ctx.get(role, {}).duplicate()
	# STALL-NEW-2 (E-04): this visit's rows say `◆ New for you` for what opened since the last one; they are seen once
	# the Buy shelf has been in front (a visit that only read the board leaves the stall's New for next time).
	if role == "homestead":
		if _stall_visit_new == null or not (modal_kind in _COUNTER_FLOW): _stall_visit_new = stall_new_ids()
		ctx["new"] = _stall_visit_new
	var d := P0CounterDrawer.new(view, role, ctx, str(opts.get("section", "buy")))
	d.theme = UiKit.theme()
	d.safe_bottom = safe_bottom()
	d.close_requested.connect(close_modal)
	d.action_requested.connect(func(a: StringName, id: String, p: Dictionary): _counter_action(role, a, id, p))
	d.info_requested.connect(func(id: String): counter_info(d, id))   # a row's › (不知火舞 on 284: it opened nothing)
	d.section_changed.connect(func(sec: String):
		if sec == "board": _fill_board(d)
		if sec == "buy" and role == "homestead": _mark_stall_seen())
	_open_modal(d, UiTokens.OPACITY_SCRIM_COUNTER, true)
	if role == "homestead" and d.section == "buy": _mark_stall_seen()
	if d.section == "specialty": _close_above(d, _CLOSE_ABOVE_SPECIALTY, P0CounterDrawer.SPECIALTY_PAD)   # MARKET-SPECIALTY
	_counter = d
	modal_kind = "counter"
	if d.section == "board" or d.is_short(): _fill_board(d)

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
	var seen: Array = _taught.stall_seen if _taught.stall_seen is Array else open
	return open.filter(func(id): return not seen.has(id))

func stall_has_new() -> bool: return not stall_new_ids().is_empty()

func _mark_stall_seen() -> void:
	var open: Array = (view.get("stall", {}).get("buy", []) as Array).filter(func(o): return bool(o.get("unlocked", true))).map(func(o): return str(o.id))
	_load_tips()
	var seen: Array = _taught.get("stall_seen", []) if _taught.get("stall_seen", []) is Array else []
	for id in open:
		if not seen.has(id): seen.append(id)
	_taught["stall_seen"] = seen
	_save_tips()

func _counter_action(role: String, action: StringName, id: String, payload: Dictionary) -> void:
	match action:
		&"buy": command.emit({"type": "buy", "item": id, "qty": int(payload.get("qty", 1)), "shop": role})
		# the sell card's Sell (payload qty 1) and Sell All (qty "all"): one `sell` command, its own button ids
		# (item_info_rules.json; SGODOT-358: Sell All went unanswered)
		&"sell", &"sell_all": command.emit({"type": "sell", "item": id, "qty": payload.get("qty", 1), "shop": role})
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

## The older entries now open the counter drawer (SGODOT-224). With no tab named, the stall opens where its badge points
## (q(44)): a request to hand in (✓) or one open (!) lands on the Stall Board, otherwise on Buy (a New badge's
## `◆ New for you` is on Buy).
func open_stall(tab := "") -> void:
	if tab == "": tab = "board" if P0Guide.stall_badge(view) != "" else "buy"
	open_counter("homestead", {"section": tab})

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
		card.unavailable_pressed.connect(func(r: String):   # spec ③: tracking 25, an Error toast saying what to do
			if P0Logic.blocked_toast(r) != r: toast_error(P0Logic.blocked_toast(r))
			else: toast(r))
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
	# LOCK-09: `Free to do now` closes the card — no longer opening Today on the free things (Today holds requests only,
	# 不知火舞's spec ①; §3.7.4's second half retired)
	card.free_pressed.connect(close_modal)
	card.tile_pressed.connect(func(go: String):
		close_modal()
		if go == "bag": open_bag()
		elif show_label(go, space_here(), spot_reachable(), place) == "Show": show_spot.emit(go)
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

## Rest bench sheet (FARM-7-2 482:52, q(30)): the bench is the one Rest entry. Title, state and effect (ObjectHeader),
## one fact row, then Rest (primary, the real gain when near full) or the reason it can't (grey), and Not now / Close.
func open_rest_card() -> void:
	var st := P0Logic.rest_state(view)
	var v := _kit_card()
	modal_kind = "rest"
	_rest_shown = st
	_rest_header = UiObjectHeader.new({title = "Rest bench", state = str(st.sheet_state), effect = str(st.effect)})
	_rest_note = null
	_rest_button = null
	v.add_child(_rest_header)
	v.add_child(UiFactRow.new(str(st.fact), str(st.fact_value)))
	if str(st.state) != "used":
		var b := UiCommandButton.new(str(st.button) if st.can_rest else "", UiCommandButton.Kind.PRIMARY)
		if not st.can_rest: b.reason = str(st.reason)
		b.sends = true   # rest (§10.7.1 Offline)
		b.activated.connect(func(): close_modal(); command.emit({"type": "rest"}))
		v.add_child(b)
		_rest_button = b
	var bye := UiDismissButton.new(str(st.close))
	bye.pressed.connect(close_modal)
	v.add_child(bye)
	if str(st.note) != "":
		var note := UiKit.label(str(st.note), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(note)
		_rest_note = note

## SGODOT-377: the open bench card follows the view — `Available again in 9h 12m` and the button's `+25 Energy` change
## in place (Energy ticking up near full rebuilt nothing; 周瑜 on #602); a change of state (the new day's read: Used
## today → Rest; Energy topped up: Rest → Energy full) builds the card again.
var _rest_shown := {}
var _rest_header: UiObjectHeader = null
var _rest_note: Label = null
var _rest_button: UiCommandButton = null
func _refresh_rest_card(v: Dictionary) -> void:
	if modal_kind != "rest" or not is_instance_valid(_rest_header): return
	var st := P0Logic.rest_state(v)
	if st.state != _rest_shown.get("state"):
		open_rest_card()
		return
	if st.button != _rest_shown.get("button") and is_instance_valid(_rest_button) and st.can_rest: _rest_button.label = str(st.button)
	if st.sheet_state != _rest_shown.get("sheet_state"): _rest_header.state = str(st.sheet_state)
	if st.note != _rest_shown.get("note") and is_instance_valid(_rest_note): _rest_note.text = str(st.note)
	_rest_shown = st

## A centred card in the UI kit's look (InformationSheet 932:71686: surface, card radius, 16 inset, 12 gap) for the
## phase-2 panels (the Rest bench card).
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
	if str(spec.get("action", "")) != "" and surface == "busy":
		queue_card_when_clear(func(): show_level_up(ev, first))   # Use bait waits out the fishing panel's shield
		_next_card()
		return
	show_banner(spec, func(): _banner_action(str(spec.get("action_id", ""))))

func _banner_action(id: String) -> void:
	match id:
		"show_workbench": show_spot.emit("workbench")   # Farming Lv6 (q(59) §1.6): moves the camera, opens nothing
		"use_bait":   # puts the gift bait on the hook, in place (the quick bar's bait slot, q(44))
			for s in _bag_slots():
				var bait := str(s.get("id", ""))
				if not bait.begins_with("bait_"): continue
				if selected_bait != bait:
					if bar_mode == "fish": _on_slot_tapped(bait)
					else:   # away from the water: it is on the hook for the next cast (the pond's bar shows it)
						selected_bait = bait
						toast("%s on the hook · used at the bite" % P0Logic.item_name(view, bait))
				break

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
			["mine", "pickaxe", "Mining", "Enter the mine"], ["combat", "sword", "Combat", "Enter the mine"]]:   # every mine floor fights (355 b1)
		options.append({id = it[0], name = it[2], icon = P0Logic.icon(it[1]),
			available = it[0] == bar_mode or actions_here.has(it[0]), reason = it[3]})
	_radial.options = options
	_radial.selected = bar_mode
	_radial.open()   # around the screen centre (247, LOCK-03 v2)

## q(99) (李元芳 int12-pre): the page a Today cook row's Show pointed at (`Cook it: Grilled Crucian`). The stove
## drawer's next opening selects it and spends it (P0Kitchen.open); leaving home drops it (P0Runtime.attach).
var cook_page_from_today := ""

## Today panel (§14.5, LOCK-06): at most three rows right under the HUD chips; Show only moves the camera.
## rows: Today's own (P0Logic.today_rows) unless given.
## Show / Show on map by show_label (#37): "pond:<id>", "outpost:<role>" and "map" open the map on that pin.
var _today_panel: UiTodayPanel
var _today_rows: Array = []
var _today_given: Array = []
var _today_signature := ""
var _today_refresh_ms := -1000

func open_today(given: Array = []) -> void:
	_today_given = given.duplicate(true)
	_today_signature = ""
	var panel := UiTodayPanel.new()
	panel.theme = UiKit.theme()
	panel.position = Vector2(UiTokens.SIZE_TODAY_PANEL_X, UiTokens.SIZE_TODAY_PANEL_Y + safe_top())
	panel.show_pressed.connect(_show_today_row)
	panel.row_pressed.connect(func(i: int):
		if i < 0 or i >= _today_rows.size(): return
		if bool(_today_rows[i].get("first_dig", false)):
			open_first_dig()
			return
		var gate := P0Logic.fish_gate(view, str(_today_rows[i].get("gate", "")))
		if not gate.is_empty(): open_gate_card(gate, func(): open_today(given))
		# a keeper's local request (q(272)): its card, Drop request › there; Not now / Close come back to Today
		elif str(_today_rows[i].get("local_request", "")) != "":
			P0LocalRequest.open(self, str(_today_rows[i].local_request), func(): open_today(given))
		# another city's tracked request (q(270)): its BOARD-1, to drop it from here; Back / Close come back to Today
		elif str(_today_rows[i].get("board_request", "")) != "":
			P0BoardRequest.open(self, "market", str(_today_rows[i].board_request), func(): open_today(given))
		# Pip's Homestead request (spec ③ v3): HOME-1 is its card; closing it comes back to Today
		elif bool(_today_rows[i].get("home_request", false)):
			open_home_panel(func(): open_today(given)))
	_open_modal(panel, 0.0)
	_today_panel = panel
	modal_kind = "today"
	_refresh_today()

## Open Today follows authoritative step/recover changes and locally projected countdowns. The button reads the
## same current row the player sees, never the rows captured when the panel first opened (341).
func _refresh_today(force := true) -> void:
	if modal_kind != "today" or not is_instance_valid(_today_panel): return
	var now := Time.get_ticks_msec()
	# at most four times a second; 10 ms short of it so the runtime's quarter-second view (view_wanted, its own clock read
	# in the same frame) always gets through, one gate and not two (哪吒 on #576)
	if not force and now - _today_refresh_ms < VIEW_FLOOR_MS - 10: return
	_today_refresh_ms = now
	var rows := _today_given if not _today_given.is_empty() else P0Logic.today_rows(view)
	var sig := JSON.stringify(rows) + space_here() + place + str(spot_reachable())
	if sig == _today_signature: return
	_today_signature = sig
	_today_rows = rows
	if _today_given.is_empty(): _see_today(P0Logic.today_dots(rows))
	var shown := rows.map(func(r):
		var d: Dictionary = r.duplicate()
		d.icon = P0Logic.icon(str(r.icon))
		d.action = show_label(str(r.go), space_here(), spot_reachable(), place)
		d.tap = str(r.get("gate", "")) != "" or str(r.get("board_request", "")) != "" or str(r.get("local_request", "")) != "" \
			or bool(r.get("home_request", false)) or bool(r.get("first_dig", false))
		if str(r.get("dot", "")).begins_with("guide:") and str(r.get("tail", "")) != "":
			var line := str(r.line)
			var at := line.find(" · ")
			if at < 0: at = line.length()
			d.line = line.insert(at, " · " + str(r.tail))
			d.tail = ""
		return d)
	_today_panel.set_rows(shown)

func _show_today_row(i: int) -> void:
	if i < 0 or i >= _today_rows.size(): return
	var row: Dictionary = _today_rows[i]
	close_modal()
	var go := str(row.go)
	if go == "inbox":
		open_inbox("parcels")
		return
	if go == "bag":   # S8's dish to eat in the bag (SGODOT-368): the bag on its Dishes page, wherever the player is
		open_bag("", "bag", "Dishes")
		return
	if show_label(go, space_here(), spot_reachable(), place) == "Show":
		# q(99): only remember a named recipe while the stove is free. This still only moves the camera.
		var page := str(row.get("page", ""))
		var stove_free := P0KitchenLogic.stove(view) == null and P0KitchenLogic.stove_left(view).is_empty()
		if go == "stove" and page != "" and stove_free and str(row.get("state", "")) != "done": cook_page_from_today = page
		show_spot.emit(go)
	else: show_on_map.emit(map_target(go))

## TodayRow action (不知火舞 on 197, 2026-10-08): a target in the current space reads `Show` and only moves the
## camera; a target somewhere else reads `Show on map` (the map opens on its pin). Homestead targets (plots,
## stall, stove) live on the farm; `pond:<id>` and `tackle` are map pins. "" = no target, no button. In an outpost, a
## target at that very outpost (`outpost:<its id>`, a resident's request handed in there; q(204) ⑨: Ivo's in his Mine
## Hut) reads Show and the camera goes to the resident (here_place: the place the player is in).
const HOME_TARGETS := ["plots", "stall", "stove", "board", "home", "bench", "sign", "decorate"]   # decorate: q(303), into Decorate at the wing

## A target on the homestead: the fixed ones and the Homestead sign (q(255)). The mine mouth left the farm in 355 b1,
## the gathering spots with v4q(4) ①.
static func home_target(go: String) -> bool: return go in HOME_TARGETS

static func show_label(go: String, here: String, camera_here: bool, here_place := "") -> String:
	if go == "": return ""
	if go == "inbox": return "Show"   # the Inbox opens anywhere: its Parcels page (q(254) ①, Pip's seeds)
	if go == "bag": return "Show"     # and the bag: S8's dish to eat (SGODOT-368)
	if here == "outpost" and here_place != "" and go == "outpost:" + here_place: return "Show" if camera_here else ""
	# 355 C2: a wild mine (`mine:<site>`) the player is down: nothing to show (the row stays, without a button); a
	# gathering spot (`gather:<id>`) or another mine is a map pin as any (Show on the map, Show on map elsewhere)
	if here == "mine" and here_place != "" and go == "mine:" + here_place: return ""
	# The homestead is one space: on the farm or in the farmhouse a farm target is Show (the runtime steps out of the
	# farmhouse first); anywhere else it is Show on map (亚瑟 on #37: the farmhouse used to send it to the map).
	if home_target(go) and here in ["home", "farm"]: return "Show" if camera_here else ""
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
	return "home" if home_target(go) else go

## Whether a Show can move the camera in the current world (the pond has no camera targets yet).
func spot_reachable() -> bool:
	return can_show_spot.is_valid() and bool(can_show_spot.call())

## The bell (parcels / letters). TODO(stage 4, SGODOT-234 Inbox): the Inbox drawer with its tabs and Claim. Until
## then the parcels waiting for a free slot (SGODOT-232) are listed read-only, one line each, soonest to expire first
## (奕星 on #11); `No parcels` only when there are none (LOCK-14).
## The Inbox drawer (LOCK-14, §12.5.2; SGODOT-234): the bell and the farmhouse Mailbox open this same drawer, on the
## page q(22) picks unless `tab` names one. Claims and reads go to the server from here; a claim's items float from the
## button pressed (the Bag slot is under the drawer: no ItemFly, q(49)).
var _inbox: P0InboxDrawer
var _claim_at := Vector2.INF   # the pressed Claim's centre, kept from the press: the reply rebuilds the page first

func open_inbox(tab := "") -> P0InboxDrawer:
	var d := P0InboxDrawer.new(view, tab)
	d.theme = UiKit.theme()
	d.safe_bottom = safe_bottom()
	d.close_requested.connect(close_modal)
	d.claim_requested.connect(func(cmd: Dictionary, from: Control):
		_claim_at = from.get_global_rect().get_center()
		command.emit(cmd))
	d.read_requested.connect(func(keys: Array): command.emit({"type": "read_inbox", "keys": keys}))
	d.refused.connect(func(text: String): toast_error(text))   # the server's bag_full for a claim says the same (亚瑟 on #93)
	_claim_at = Vector2.INF
	_open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	_close_above(d, _CLOSE_ABOVE_SHEET, UiTokens.SPACE_PAGE)
	_inbox = d
	modal_kind = "inbox"
	return d

## The Tackle Shop's Bite Board (SGODOT-283; plan §6.9.3, 不知火舞 e61cda10 ③): the room's board facility opens it for
## the outpost the player stands in. It follows the view while open. A pond row opens that pond's card over the room
## (open_board_pond): nothing moves by itself (LOCK: no auto-jumps).
const BiteBoardDrawer := preload("res://scenes/p0/panels/p0_bite_board_drawer.gd")
const PondCardLogic := preload("res://modules/p0/p0_pond_card.gd")
const PondsLogic := preload("res://modules/p0/p0_ponds.gd")
var _bite_board: UiDrawer

func open_bite_board(outpost: Dictionary) -> UiDrawer:
	var d: UiDrawer = BiteBoardDrawer.new(view, outpost)
	d.theme = UiKit.theme()
	d.safe_bottom = safe_bottom()
	d.close_requested.connect(close_modal)
	d.connect(&"pond_pressed", func(id: String): open_board_pond(outpost, id))
	_open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	_close_above(d, _CLOSE_ABOVE_SHEET, UiTokens.SPACE_PAGE)
	_bite_board = d
	modal_kind = "bite_board"
	return d

## The open Bite Board, or null.
func bite_board() -> UiDrawer:
	return _bite_board if is_instance_valid(_bite_board) and modal_kind == "bite_board" else null

## The Homestead Stall's Notice Board (q(164), SGODOT-284; 不知火舞's spec): from Homestead Lv5 the board by the stall
## opens it, read-only. A row closes it and the map flies to that pin (show_on_map), moving nobody (q(31), k(1)).
## The outposts' online counts are the map's (GET /p0/presence): the runtime asks on opening (notice_board_opened)
## and hands them over (set_notice_online); until then no person badge shows.
const NoticeBoardDrawer := preload("res://scenes/p0/panels/p0_notice_board_drawer.gd")
signal notice_board_opened
## Settings › Home city (SGODOT-303 PR-4): the host opens the change of home; `back` reopens Settings.
signal change_home(back: Callable)
var _notice_board: UiDrawer
var notice_online := {}   # outpost id → who is in, the last counts asked for

func open_notice_board() -> UiDrawer:
	var d: UiDrawer = NoticeBoardDrawer.new(view, notice_online)
	d.theme = UiKit.theme()
	d.safe_bottom = safe_bottom()
	d.close_requested.connect(close_modal)
	d.connect(&"place_pressed", func(go: String):
		close_modal()
		show_on_map.emit(map_target(go)))
	_open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	_close_above(d, _CLOSE_ABOVE_SHEET, UiTokens.SPACE_PAGE)
	_notice_board = d
	modal_kind = "notice_board"
	notice_board_opened.emit()
	return d

## The open Notice Board, or null.
func notice_board() -> UiDrawer:
	return _notice_board if is_instance_valid(_notice_board) and modal_kind == "notice_board" else null

## The outposts' online counts came: the open board's person badges follow.
func set_notice_online(online: Dictionary) -> void:
	notice_online = online
	if notice_board() != null: _notice_board.call("set_online", online)

## MAP-8 Nearby cities (q(159); Figma row 85, 不知火舞 on MAP-8): the map's `Nearby cities ›` pill opens it — the ten
## cities nearest home, nearest first (P0Travel.nearby), with a Close 44 six above the sheet. A row's tap calls
## `pick` with its city (the map closes this and flies there, P0Map.open_nearby_city).
const NearbyDrawer := preload("res://scenes/p0/panels/p0_nearby_drawer.gd")

func open_nearby_cities(pick: Callable) -> UiDrawer:
	var home := str(P0Clusters.get_cluster(P0Travel.home(view)).get("name", ""))
	var d: UiDrawer = NearbyDrawer.new(P0Travel.nearby(view), home)
	d.theme = UiKit.theme()
	d.safe_bottom = safe_bottom()
	d.close_requested.connect(close_modal)
	d.connect(&"city_pressed", func(cluster: String): pick.call(cluster))
	_open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	_close_above(d, _CLOSE_ABOVE_SHEET, UiTokens.SPACE_PAGE)
	modal_kind = "nearby"
	return d

## q(165) the Travel Post's Fare Board: Trip fares, read only (P0FareBoardDrawer: the seven tiers, every fare Free while
## travel is), with a Close 44 six above the sheet as MAP-8's.
const FareBoardDrawer := preload("res://scenes/p0/panels/p0_fare_board_drawer.gd")

func open_fare_board() -> UiDrawer:
	var d: UiDrawer = FareBoardDrawer.new(P0Travel.fares(view))
	d.theme = UiKit.theme()
	d.safe_bottom = safe_bottom()
	d.close_requested.connect(close_modal)
	_open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	_close_above(d, _CLOSE_ABOVE_SHEET, UiTokens.SPACE_PAGE)
	modal_kind = "fare_board"
	return d

## A pond's card from the Bite Board (the map's card: P0PondCard.info, P0PlaceSheet), its Distance from this shop. Go
## leaves the room for that pond (go_pond); Details › lists its fish; Back and a tap outside return to the board, ×
## closes both.
func open_board_pond(outpost: Dictionary, id: String) -> void:
	var pond := PondsLogic.location(id)
	if pond.is_empty(): return
	var km := P0PlaceSheet.km_between(Vector2(float(outpost.get("lat", 0.0)), float(outpost.get("lng", 0.0))), Vector2(float(pond.lat), float(pond.lng)))
	var info := PondCardLogic.info(view, id, km)
	if info.is_empty(): return
	P0PlaceSheet.open(self, P0PlaceSheet.for_here(info, false),
		func():
			close_modal()
			go_pond.emit(id),
		func(): PondCardLogic.open_fish(self, id, info, func(): open_board_pond(outpost, id)),
		Callable(), "pond_card")
	_modal_back = func(): open_bite_board(outpost)   # set after the sheet's _open_modal, which clears it

## The open Inbox drawer, or null.
func inbox() -> P0InboxDrawer:
	return _inbox if is_instance_valid(_inbox) and modal_kind == "inbox" else null

## Where a claim's floats start: the Claim (or Claim all) pressed, where it was when pressed (亚瑟 on #93: the reply
## rebuilds the rows before the floats are placed); INF with no claim waiting or the Inbox closed.
func inbox_float_at() -> Vector2:
	return _claim_at if inbox() != null else Vector2.INF

## The claim's reply has come: its floats took the spot, later items float from the player again.
func inbox_claim_done() -> void:
	_claim_at = Vector2.INF

## Resident dialogue bar (SGODOT-225, LOCK-18): greet first, then choose. Called by the outpost rooms (SGODOT-227)
## for res_pip / res_old_kai. Sends the day's `talk` (first-chat affinity, gift meal: the server decides) and
## shows the bar from P0Logic.resident_bar (SGODOT-228). Returns false when the view has no such resident.
var _resident := ""
var _reply := {}   # {id, line}: the resident's answer shown in the bubble until another resident's bar opens
var _pip_vein_line := ""   # shown before talk consumes view.pip_line; never a persistent "said" flag

func open_resident(id: String) -> bool:
	var d := P0Logic.resident_bar(view, id)
	if d.is_empty(): return false
	var new_talk := _resident != id or modal_kind != "resident"
	if new_talk: _pip_vein_line = P0Logic.GearLogic.pip_line(view, id)
	# C2/C3: keep the confirmed resend answer through this conversation's rebuilds, then let a new talk read
	# Pip's current server step. His old answer must not cover the next water/harvest instruction forever.
	if surface == "farm" and id == "res_pip" and modal_kind != "resident": _reply = {}
	if _resident != id: _reply = {}
	_resident = id
	_show_resident(d)
	# Draw first: even a synchronous talk reply may withdraw pip_line and rebuild this same bar.
	if new_talk: command.emit({"type": "talk", "resident": id})
	return true

## Whether the resident bar offers Request here: not on the player's own farm (q(222) ②, Pip as the new-player
## guide there; his newbie requests stay at the Travel Post), so the bar does not ask an open request there either.
func resident_asks_here() -> bool:
	return surface != "farm"

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

## Where a delivery's floats rise over the resident's open bar (不知火舞 on 344: the group over the bar, centred, 6 above
## its top) — over the toast when one sits on the bar (the delivery's `Request complete`), so it never hides a line;
## INF when the bar is not showing that resident.
func resident_float_at(id: String) -> Vector2:
	if modal_kind != "resident" or id != _resident or _modal == null or _modal.get_child_count() < 2: return Vector2.INF
	var bar: Control = _modal.get_child(1)
	var top := bar.global_position.y
	var t: Control = _toasts._panel if _toasts else null   # laid out: the caller asks a frame after the toast showed
	if t != null and t.is_visible_in_tree() and toast_text() != "": top = minf(top, t.get_global_rect().position.y)
	return Vector2(bar.global_position.x + bar.size.x * 0.5, top - _AFFINITY_ABOVE) - root.global_position

## The resident says `line` in the open bar's bubble (q(218): Nadia's soup recipe after A Fresh Radish), the bar redrawn
## from the view; false when the bar is not showing that resident.
func resident_say(id: String, line: String) -> bool:
	if modal_kind != "resident" or id != _resident or _modal == null: return false
	_reply = {"id": id, "line": line}
	var d := P0Logic.resident_bar(view, id)
	if not d.is_empty(): _show_resident(d)
	return true

## `+2 · first chat today`, `−2 · not a fan` (RES-KAI-TALK, RESIDENT-GIFT-MYSTERY); the other reasons are 刘邦's
## wording pending 李白 (SGODOT-225).
static func affinity_text(ev: Dictionary) -> String:
	var why := ""
	match str(ev.get("reason", "")):
		"chat": why = "first chat today"
		"request": why = "request done"
		"gift":   # q(220): a resident's first dish from you reads `+10 · first gift`, whatever its verdict; a plain one
			# `+1 · gift received` (q(18), B.9, NPC-5 — not `thanks`, which reads as the social `Say thanks`, 不知火舞)
			why = "first gift" if bool(ev.get("first", false)) else \
				{"loved": "loved it", "liked": "liked it", "received": "gift received", "not_a_fan": "not a fan"}.get(str(ev.get("verdict", "")), "")
	var n := ("%+d" % int(ev.get("delta", 0))).replace("-", "−")
	return n if why == "" else "%s · %s" % [n, why]

func _show_resident(d: Dictionary) -> void:
	var data := d.duplicate()
	data.portrait = _portrait(str(d.portrait))
	data.request = resident_asks_here()
	var ask := resident_ask(view, str(d.id)) if data.request else ""
	if ask != "": data.line = ask   # NPC-5: with a request open the bar asks it, in the request card's words (李白 q(46))
	if surface == "farm" and str(d.id) == "res_pip":
		var line = P0Guide.pip(view).get("line")
		if line is String and line != "": data.line = line
	if str(_reply.get("id", "")) == str(d.id): data.line = str(_reply.line)
	if str(d.id) == "res_pip" and _pip_vein_line != "" and not P0Guide.guide_on(view): data.line = _pip_vein_line
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
	bar.request_unavailable.connect(func(r: String): if P0Logic.blocked_toast(r) != r: toast_error(P0Logic.blocked_toast(r)))   # spec ③
	bar.identity_pressed.connect(func(): open_resident_profile(id))
	bar.meal_pressed.connect(func(): _open_todays_meal(id))
	bar.lesson_pressed.connect(func(): command.emit({"type": "learn", "resident": id}))   # §7.5.3: the server picks the page
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
## LOCK-08). What a craft shows afterwards (the card's float, the pickaxe's Moment) belongs to
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
	d.command_requested.connect(func(cmd: Dictionary):
		# A Facilities card's Build (SGODOT-241) opens placement mode in the world; nothing is sent until its Build.
		if str(cmd.get("type", "")) == "place_start": placement_requested.emit(str(cmd.get("recipe", "")))
		else: command.emit(cmd))
	d.unavailable_requested.connect(func(reason: String): toast(reason))
	d.source_requested.connect(_show_need_source)
	_open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	_close_above(d, _CLOSE_ABOVE_SHEET, UiTokens.SPACE_PAGE)
	_workbench = d
	modal_kind = _WORKBENCH_KIND
	return d

## The Compost Bin's drawer (q(118) ③, COMPOST-BIN 2231:122380): Compost 1 / Compost All send the compost command;
## a grey button toasts its words.
const _COMPOST_KIND := "compost"
var _compost: P0CompostDrawer

func open_compost_bin() -> P0CompostDrawer:
	var d := P0CompostDrawer.new(view)
	d.theme = UiKit.theme()
	d.safe_bottom = safe_bottom()
	d.close_requested.connect(close_modal)
	d.compost_requested.connect(func(id: String, qty: int): command.emit({"type": "compost", "item": id, "qty": qty}))
	d.unavailable_requested.connect(func(reason: String): toast(reason))
	_open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	_compost = d
	modal_kind = _COMPOST_KIND
	return d

## The open Compost Bin drawer, or null.
func compost_bin() -> P0CompostDrawer:
	return _compost if is_instance_valid(_compost) and modal_kind == _COMPOST_KIND else null

## The open workbench drawer, or null.
func workbench() -> P0WorkbenchDrawer:
	return _workbench if is_instance_valid(_workbench) and modal_kind == _WORKBENCH_KIND else null

## The open (not yet accepted) request's own line, e.g. Pip's `Could you catch me a fish? Any kind is fine.`; ""
## when the resident has no open request.
static func resident_ask(view_: Dictionary, id: String) -> String:
	var r: Dictionary = view_.get("residents", {}).get(id, {})
	var req = r.get("request", null)
	if not (req is Dictionary) or str(r.get("request_state", "open")) != "open": return ""
	return str(P0Logic.resident_request(id, str(req.get("id", ""))).get("text", ""))

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
	return {"face": resident_face(str(def.get("portrait", ""))),
		"name": str(bar.name), "role": str(bar.role), "stage": str(bar.stage), "stage_index": int(bar.get("stage_index", 0)),
		"friendship": ("%d/%d" % [int(bar.have), int(bar.need)]) if str(bar.get("next", "")) != "" else str(int(bar.have)),
		"likes": P0Logic.likes_text(likes), "likes_icon": P0Logic.icon(dish) if dish != "" else null, "details": false}

## A 44 Close above a bottom card or sheet, right-aligned `inset` in from its right edge and `gap` above its top
## (Close · 44 px: 6 above a sheet, 8 above the dialogue bar). It follows the content as it slides and resizes.
## on_close: what Close does (close_modal: out to the world; close_layer for a drawer over the profile).
func _close_above(content: Control, gap: float, inset := 0.0, on_close := Callable()) -> void:
	var close := UiCloseButton.new()
	close.theme = UiKit.theme()
	close.size = Vector2(UiTokens.SIZE_CLOSE, UiTokens.SIZE_CLOSE)
	var follow := func():
		if is_instance_valid(close):
			close.position = content.position + Vector2(content.size.x - inset - UiTokens.SIZE_CLOSE, -gap - UiTokens.SIZE_CLOSE)
	content.item_rect_changed.connect(follow)
	close.pressed.connect(on_close if on_close.is_valid() else close_modal)
	_modal.add_child(close)
	follow.call()

## A resident's render card (上官婉儿 #405: 300 × 660, the outfit they wear in the rooms) and its crops,
## portrait_crops.json {key: {stamp: [x, y, w, h], face: [x, y, w, h]}} in the card's own pixels.
const CARD_PATH := "res://assets/p0/art/residents/%s_card.jpg"
const CROPS_PATH := "res://assets/p0/art/residents/portrait_crops.json"

## The resident's half-body picture for the dialogue bar and the request card: their illustration where they have
## one (assets/p0/art/<key>-portrait.jpg: Pip and Kai keep theirs, 不知火舞), else their render card, else none.
static func _portrait(key: String) -> Texture2D:
	if key == "": return null
	for path in ["res://assets/p0/art/%s-portrait.jpg" % key, CARD_PATH % key]:
		if ResourceLoader.exists(path): return load(path)
	return null

## A crop of the resident's render card: `face` for the round profile face, `stamp` for the postcard stamp (上官婉儿 /
## 不知火舞 on 284: every one from the cards, Pip's and Kai's too); null without the card or its crop.
static func resident_crop(key: String, kind: String) -> Texture2D:
	var path := CARD_PATH % key
	if key == "" or not ResourceLoader.exists(path): return null
	var r = P0RoomAnchors.read_json(CROPS_PATH).get(key, {}).get(kind, null)
	if not r is Array or (r as Array).size() != 4: return null
	var crop := AtlasTexture.new()
	crop.atlas = load(path)
	crop.region = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	return crop

## The round profile face (不知火舞 on 235 B1): the card's face square.
static func resident_face(key: String) -> Texture2D: return resident_crop(key, "face")

## Request on the bar: an open request shows the card (Accept / Not now); an accepted one that is ready
## delivers. The bar's button carries the gap or the wait, so it never dead-ends (LOCK-10 / 18).
var _request_card: UiRequestCard
var _first_dig_sig := ""

func open_first_dig() -> void:
	var data := P0Logic.GearLogic.first_dig_card(view)
	if data.is_empty(): return
	data.portrait = _portrait("pip")
	var card := UiRequestCard.new(data)
	card.theme = UiKit.theme()
	card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	card.offset_left = UiTokens.SIZE_QUICK_BAR_X
	card.offset_right = -UiTokens.SIZE_QUICK_BAR_X
	card.offset_bottom = -bottom_pad()
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.dismissed.connect(func(): open_today())
	_open_modal(card, 0.0, true)
	modal_kind = "first_dig"
	_first_dig_sig = JSON.stringify(P0Logic.GearLogic.first_dig(view))
	_modal_back = func(): open_today()

func open_resident_request(id: String) -> void:
	var d := P0Logic.resident_bar(view, id)
	if d.is_empty(): return
	var cmd: Dictionary = d.get("request_cmd", {})
	if str(cmd.get("type", "")) == "deliver":
		# q(218) / 不知火舞 on 344: a request with a thanks line keeps the bar open — its floats rise over it, then the
		# resident says the line (resident_say)
		if P0Logic.request_thanks(view, str(cmd.get("request", ""))) == "": close_modal()
		command.emit(cmd)
		return
	var data := _request_card_data(view, id, d)
	data["sends"] = not cmd.is_empty()   # Accept sends; an empty one only closes
	var card := UiRequestCard.new(data)
	card.theme = UiKit.theme()
	card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	card.offset_left = UiTokens.SIZE_QUICK_BAR_X
	card.offset_right = -UiTokens.SIZE_QUICK_BAR_X
	card.offset_bottom = -bottom_pad()
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.action_pressed.connect(func():
		close_modal()
		if not cmd.is_empty(): command.emit(cmd))
	card.unavailable_pressed.connect(func(r: String): if P0Logic.blocked_toast(r) != r: toast_error(P0Logic.blocked_toast(r)))   # spec ③: only tracking 25
	card.dismissed.connect(func(): open_resident(id))
	_open_modal(card, 0.0, true)
	modal_kind = "resident_request"
	_request_card = card
	card.set_meta("resident", id)
	var req: Variant = view.get("residents", {}).get(id, {}).get("request", null)
	card.set_meta("request", str(req.get("id", "")) if req is Dictionary else "")
	_modal_back = func(): open_resident(id)

func _refresh_request_reward() -> void:
	if modal_kind != "resident_request" or not is_instance_valid(_request_card): return
	var id := str(_request_card.get_meta("resident", ""))
	var req: Variant = view.get("residents", {}).get(id, {}).get("request", null)
	if not req is Dictionary or str(req.get("id", "")) != str(_request_card.get_meta("request", "")): return
	var reward := _request_rewards(view, req, P0Logic.resident_request(id, str(req.get("id", ""))))
	_request_card.update_reward(str(reward.reward), str(reward.bonus_note))

## ResidentRequestCard data from the resident's open request (content table + view facts).
static func _request_card_data(view_: Dictionary, id: String, bar: Dictionary) -> Dictionary:
	var def: Dictionary = P0Logic.content().get("residents", {}).get(id, {})
	var req: Dictionary = view_.get("residents", {}).get(id, {}).get("request", {}) if view_.get("residents", {}).get(id, {}).get("request", null) != null else {}
	var text := ""
	var need_line := ""
	var title := "%s's request" % str(def.get("name", ""))   # only for a request the content table no longer has
	var q := P0Logic.resident_request(id, str(req.get("id", "")))
	if not q.is_empty():
		text = str(q.get("text", ""))
		need_line = str(q.get("need_line", ""))
		if str(q.get("title", "")) != "": title = str(q.title)   # ResidentRequestCard: the request's own name (`A Fresh Radish`)
	var kind := str(req.get("kind", ""))
	var item := str(req.get("item", "")) if req.get("item", null) != null else ""
	var style := str(req.get("style", "")) if req.get("style", null) != null else ""
	var need := {"name": "", "have": int(req.get("have", 0)), "need": int(req.get("qty", 1)), "icon": null}
	match kind:
		"fish":
			var rarity := int(req.get("rarity", 0)) if req.get("rarity", null) != null else 0
			need.name = (P0Logic.rarity_name(view_, rarity) + " fish") if rarity > 0 else "Fish"
			need.icon = P0Logic.icon("fish_crucian")
		"dish":
			need.name = ("%s dish" % style) if style != "" else "Any dish"
			need.icon = P0Logic.icon("pot")
		"sow":
			need.name = "Plots sown"
			need.icon = P0Logic.icon("sow")
		"crop":
			need.name = "Any crop"
			need.icon = P0Logic.icon("crop_radish")
		"material":
			need.name = "Materials"
	# P1: a request naming one item shows that item (Ivo's Clay, Theo's Carrots).
	if item != "":
		need.name = P0Logic.item_name(view_, item)
		need.icon = P0Logic.icon(item)
	# Li Bai q(46): a request's own need line wins (`1 Rare fish · Golden Koi · Pond`); the tile shows the count itself.
	if need_line != "": need.name = need_line.trim_prefix("%d " % int(need.need))
	var data := {"portrait": _portrait(str(def.get("portrait", ""))), "title": title,
		"who": "%s · %s · personal request" % [str(def.get("name", "")), str(def.get("role", ""))],
		"line": text, "needs": [need] if kind != "" else [],
		"deliver_to": _deliver_to(view_, id, str(def.get("name", ""))), "action": "Accept",
		# the bar's `Request · Requests 25/25` is the card's `Accept · Requests 25/25` (spec ③, T4)
		"reason": P0Logic.track_full_reason(view_, "Accept") if P0Logic.is_track_full(str(bar.get("request_reason", ""))) \
			else str(bar.get("request_reason", ""))}
	data.merge(_request_rewards(view_, req, q))
	return data

static func _request_rewards(view_: Dictionary, req: Dictionary, q: Dictionary) -> Dictionary:
	var reward := []
	if int(P0Logic.content().get("affinity", {}).get("request", 0)) > 0:
		reward.append("+%d Friendship" % int(P0Logic.content().affinity.request))
	var coins := int(req.get("coins", 0))
	var bonus_note := ""
	# q(262): bonus is an optional display-only difference; older servers retain the listed reward.
	var bonus := int(req.get("bonus", 0))
	var quota: Dictionary = view_.get("quotas", {}).get("request_bonus", {})
	if bonus < 0: coins -= bonus   # q(44): a hand-in floor above the listed price is still paid in full
	elif not quota.is_empty():
		var left := maxi(0, int(quota.get("cap", 0)) - int(quota.get("used", 0)))
		if left < bonus:
			coins -= bonus - left
			bonus_note = "Bonus resets in %s" % P0Logic.span(float(quota.get("resets_in", 0)))
	if int(req.get("coins", 0)) > 0 or coins > 0: reward.append("%d coins" % coins)
	# q(224) ① / q(225) ①: a request whose reward gives a recipe card ends on `New recipe`, no dish name (the delivery's
	# float names it, `New recipe · Fresh Fish Soup`); not once the page is known, as the server then gives none.
	var recipe := str(q.get("reward", {}).get("recipe", ""))
	if recipe != "" \
			and not (view_.get("cooking", {}).get("cookbook", []) as Array).any(func(pg): return str(pg.get("id", "")) == recipe and bool(pg.get("known", false))):
		reward.append("New recipe")
	if str(q.get("reward", {}).get("title", "")) != "": reward.append("New title")
	return {"reward": " · ".join(reward), "bonus_note": bonus_note}

## Residents met at every outpost of a type (§9.4.3, q(222) ①: Pip at every Travel Post; his request counts wherever
## he is met). The server places him at the home set's post only for the map (home_city.residentPlace).
const ANY_OUTPOST := {"res_pip": "Travel Post"}

## The request card's `Deliver to` (ResidentRequestCard): the resident and the outpost the player finds them in, from
## the player's home set (view.residents[id].place, `Nadia · Mission Market Square`); the name alone without one.
## One met at every outpost of a type says `any` it (`Pip · any Travel Post`, 不知火舞 344 6aeaa6a7).
static func _deliver_to(view_: Dictionary, id: String, name: String) -> String:
	if ANY_OUTPOST.has(id): return "%s · any %s" % [name, ANY_OUTPOST[id]]
	var place := str(view_.get("residents", {}).get(id, {}).get("place", ""))
	var where := str(P0Outposts.find(place).get("name", "")) if place != "" else ""
	return "%s · %s" % [name, where] if where != "" else name

## Gift on the bar, or a dish card's `Gift to <Name>` (item: that dish, selected): the gift drawer (Bag side only,
## Dishes first); the card's Gift sends `gift`.
func open_gift(id: String, item := "") -> void:
	var def: Dictionary = P0Logic.content().get("residents", {}).get(id, {})
	var likes := str(def.get("likes", ""))
	var d := P0BagDrawer.new(view, "bag", item, {"kind": "resident", "id": id, "name": str(def.get("name", "")),
		"gifted_today": bool(view.get("residents", {}).get(id, {}).get("gift_today", false)),
		"likes": ("Likes %s · 1 gift a day" % P0Logic.likes_text(likes)) if likes != "" else "1 gift a day"})
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
## The voice-match H5 (VoiceMatchLink: the Android WebView over the whole screen, the system browser elsewhere), opened
## from the profile's `Voice Profile ›` (SGODOT-349, 不知火舞 2ca37b44).
var voice_match: VoiceMatchLink

## Back belongs to the voice-match page while it is up and for the press that closed it (Godot 4.7 Android hands the
## engine that press too): every P0 world asks this first, so neither the profile nor the world under it goes.
func voice_blocks_back() -> bool:
	return voice_match != null and voice_match.blocks_back_navigation()
## A panel opened from the profile (Skills, the Fish-dex and the cards it opens) keeps the profile behind its scrim,
## not the world (int10c 256 ⑧): the same page moves under each layer of that chain, so its figure isn't built again.
## Set by the profile's buttons; cleared when the chain goes back to the profile or out to the world.
var _over_profile := false

func open_profile(look_saved := false) -> void:
	_over_profile = false
	var page := P0ProfilePage.new(view, safe_top(), look_saved, title_pending)
	page.theme = UiKit.theme()
	page.back_pressed.connect(close_modal)
	page.skill_pressed.connect(func(_skill: String):
		_over_profile = true
		open_skills(func(): open_profile()))
	page.edit_look_pressed.connect(edit_look)
	page.voice_pressed.connect(open_voice_profile)   # SGODOT-349: no transition of the game's own; q(281) ④ its age gate
	page.collection_pressed.connect(func(key: String):
		if key == "cities":
			_over_profile = true
			open_passport(func(): open_profile())
		elif key == "fish":
			_over_profile = true
			open_fishdex(func(): open_profile())
		elif can_request_panel(): request_panel("cookbook"))
	page.farm_pressed.connect(func():
		_over_profile = true
		open_home_panel(func(): open_profile()))
	page.settings_pressed.connect(func(): open_settings(func(): open_profile()))
	page.title_pressed.connect(func():
		_over_profile = true
		open_titles(func(): open_profile()))
	_open_modal(page, 0.0, true)
	_profile = page
	modal_kind = "profile"

## q(180) Titles (P0TitlesDrawer) from the title beside the name on the profile, over the profile, Close 44 above it as
## MAP-8's. A row asks the server to wear that title and goes back to the profile, which shows it at once: the pick is
## kept as pending ({id, seq}) until the server's answer moves the view past that seq (P0Titles.worn).
const TitlesDrawer := preload("res://scenes/p0/panels/p0_titles_drawer.gd")
const P0Titles := preload("res://modules/p0/p0_titles.gd")
var title_pending := {}

## The server did not put that pick on — refused, or no answer came (周瑜 on #417): the pick is dropped and the profile
## shows the title the server says is worn.
func title_not_worn(id: String) -> void:
	if str(title_pending.get("id", "")) != id: return
	title_pending = {}
	if _profile != null and is_instance_valid(_profile) and not _profile.is_queued_for_deletion():
		_profile.title_pending = {}
		_profile.refresh(view)

func open_titles(back := Callable()) -> UiDrawer:
	var d: UiDrawer = TitlesDrawer.new(P0Titles.rows(view, title_pending))
	d.theme = UiKit.theme()
	d.safe_bottom = safe_bottom()
	d.close_requested.connect(close_layer)
	d.connect(&"title_picked", func(id: String):
		title_pending = {id = id, seq = int(view.get("seq", -1))}
		command.emit({"type": "wear_title", "id": id})
		close_layer())
	_open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	_close_above(d, _CLOSE_ABOVE_SHEET, UiTokens.SPACE_PAGE, close_layer)
	modal_kind = "titles"
	_modal_back = back
	return d

## The card room's Blackjack table (SGODOT-351, q(240) §9.18.7), full screen over the room: Lou's `Play` opens it
## (后裔's entry, 351 d6fae42c). ctx {place, keeper} is accepted for the log and otherwise unused. ‹ / Back go back to
## the room with no confirm (a hand in play waits for the return); Back closes the Rules sheet first. The page reads
## this view (set_view refreshes it) and sends bj_* through `command`; P0Runtime passes it the reply's events and its
## refusals (blackjack_events / blackjack_refused).
var _blackjack: P0BlackjackPage

func blackjack() -> P0BlackjackPage:
	return _blackjack if is_instance_valid(_blackjack) and modal_kind == "blackjack" else null

func open_blackjack(_ctx := {}) -> P0BlackjackPage:
	var page := P0BlackjackPage.new(view, safe_top(), safe_bottom())
	page.theme = UiKit.theme()
	page.toast = func(t: String): toast_error(t)
	page.back_pressed.connect(close_modal)
	page.command.connect(func(cmd: Dictionary): command.emit(cmd))
	_open_modal(page, 0.0, true)
	_blackjack = page
	modal_kind = "blackjack"
	_arm_blackjack_back()
	page.opened()
	return page

func _arm_blackjack_back() -> void:
	_modal_back = func():
		if blackjack() != null and _blackjack.back_inner(): _arm_blackjack_back()
		else: close_modal()

func blackjack_events(events: Array) -> void:
	if blackjack() != null: _blackjack.on_events(events)

func blackjack_refused(code: String, detail: Dictionary) -> void:
	if blackjack() != null: _blackjack.refused(code, detail)

## Settings (q(129); P0: Legal · Licenses and Version) from the profile's gear, full screen; ‹ goes back where it came
## from (`back`), as each page under it does to the one before.
## The player id the session plays as (P0Runtime sets it): the support code's (q(281) ②).
var player_of := func() -> String: return ""

func open_settings(back := Callable(), read := true) -> void:
	var version := P0Legal.version_line(P0Session.demo_config(
		FileAccess.get_file_as_string(P0Session.DEMO_CONFIG) if FileAccess.file_exists(P0Session.DEMO_CONFIG) else ""))
	if test_accounts.is_test(): version += " · Test"
	var page := P0SettingsPage.settings(version,
		safe_top(), safe_bottom(), load("res://modules/p0/p0_home_pick.gd").settings_row(view, P0Travel.now_ms(view)),
		("On" if notify.switch_on() else "Off") if notify != null and notify.available() else "",
		(_blocked.size() if _blocked_read else P0SettingsPage.BLOCKED_UNREAD) if _privacy_shown else P0SettingsPage.BLOCKED_NONE,
		_voice_offered, LANGUAGE_NAMES.get(TranslationServer.get_locale(), "English"),   # the language on screen (不知火舞 A6), not a pick for the next start
		P0Legal.privacy_url(OS.get_name()), P0Legal.support_code(str(player_of.call())))   # q(281) (SGODOT-390)
	page.theme = UiKit.theme()
	page.back_pressed.connect(back_modal)
	page.open_pressed.connect(func(what: String):
		# Home city › (SGODOT-303 PR-4): the change; its ‹ Settings comes back here
		if what == "home": change_home.emit(func(): open_settings(back))
		elif what == "language": open_language(func(): open_settings(back))
		elif what == "test_options": open_test_options(func(): open_settings(back))
		elif what == "notifications": open_notifications(func(): open_settings(back))
		elif what == "blocked_players": open_blocked_players(func(): open_settings(back))
		elif what == "voice_chat": open_voice_chat_info(func(): open_settings(back))
		elif what == "privacy": ExternalLink.open(P0Legal.privacy_url(OS.get_name()))   # the system browser (q(281) ①)
		elif what == "support_code":   # q(281) ②: the whole row copies the code; the row itself stays as it is
			DisplayServer.clipboard_set(P0Legal.support_code(str(player_of.call())))
			toast("Support code copied")
		else: open_licenses(func(): open_settings(back)))
	_open_modal(page, 0.0, true)
	modal_kind = "settings"
	_modal_back = back
	if read: _privacy_read(func(): if modal_kind == "settings": open_settings(back, false))   # drawn again, not read again

## Settings › Blocked players (SGODOT-384; q(28) §12.1.6; 不知火舞's spec 383, BP1–BP3 row 127): the account's voice
## away from any room (P0Runtime's P0VoiceRoom without one): whether this phone is offered voice, and whom it blocked —
## now that the two never see each other in a room, the only place a block is lifted. The Privacy group shows while
## voice is offered here, or while anyone is blocked (a block outlives the switch going off, and an iPhone has none).
var voice_account: Node
var _blocked: Array = []        # [{handle, name}] as last read, the server's order
var _blocked_read := false      # read once at least this launch: before that an empty list is not `No one blocked`
var _blocked_failed := false    # and the last try failed: the Blocked page's empty state and Retry
var _privacy_shown := false
var _voice_offered := false     # this phone is offered voice (status read): Privacy's `Voice chat ›` (q(277))
var _unblocks := 0              # Unblocks sent and answered: a read overlapping one is dropped (it may hold them, 周瑜 #667)

## The server asked again; `then` when what the pages show has changed (they are opened again with it). A list that
## was not read (blocked_list null, 后裔 ed9c83b2) keeps the last one read; none read this launch, the Privacy group
## stays only while voice is offered (its row without a number) and the page shows the empty state (不知火舞 6e014af3).
func _privacy_read(then: Callable) -> void:
	if voice_account == null: return
	var unblocks := _unblocks
	await voice_account.call("fetch_status")
	var got = await voice_account.call("blocked_list")
	if unblocks != _unblocks: return
	# offered as a room's would be (P0VoiceRoom.offered) — its own Voice left unset: it never joins or leaves a call
	var phone = get_node_or_null("/root/Voice")
	var offered: bool = bool(voice_account.get("available")) and str(voice_account.get("age")) != "no" \
		and phone != null and bool(phone.call("supported"))
	var was := [_privacy_shown, _blocked, _blocked_read, _blocked_failed, _voice_offered]
	_voice_offered = offered   # a status not read reads as not offered: no `Voice chat` row (不知火舞)
	if got is Array:
		_blocked = got
		_blocked_read = true
		_blocked_failed = false
	elif not _blocked_read: _blocked_failed = true
	_privacy_shown = offered or not _blocked.is_empty()
	if was != [_privacy_shown, _blocked, _blocked_read, _blocked_failed, _voice_offered]: then.call()

## Settings › Privacy › Voice chat (q(277)): where voice goes, as the Licenses' text pages (PageHeader, Regular 13).
func open_voice_chat_info(back: Callable) -> void:
	var page := P0SettingsPage.text("Voice chat", P0Legal.VOICE_CHAT, safe_top(), safe_bottom())
	page.theme = UiKit.theme()
	page.back_pressed.connect(back_modal)
	_open_modal(page, 0.0, true)
	modal_kind = "voice_chat"
	_modal_back = back

## `read` false: drawn again with what was read, nothing asked (a failed read never loops; 后裔 on #667).
func open_blocked_players(back: Callable, read := true) -> void:
	var page := P0SettingsPage.blocked_players(_blocked, safe_top(), safe_bottom(),
		"ok" if _blocked_read else ("failed" if _blocked_failed else "reading"))
	page.theme = UiKit.theme()
	page.back_pressed.connect(back_modal)
	page.open_pressed.connect(func(what: String):
		if what == "retry":   # Retry only when tapped, nothing by itself
			_blocked_failed = false
			open_blocked_players(back)
		else: _unblock(what, back))
	_open_modal(page, 0.0, true)
	modal_kind = "blocked_players"
	_modal_back = back
	if read: _privacy_read(func(): if modal_kind == "blocked_players": open_blocked_players(back, false))

## Unblock: the page has taken the row away already (no card, no toast); a failure puts it back with the network's line.
func _unblock(handle: String, back: Callable) -> void:
	_unblocks += 1
	var ok: bool = await voice_account.call("unblock", handle)
	_unblocks += 1   # again at its answer: a read begun meanwhile may have been served before the Unblock was
	if ok:
		_blocked = _blocked.filter(func(r): return str(r.handle) != handle)
		return
	show_sys(UiSysBanner.Kind.CMD_FAIL, "Didn't go through · try again")
	if modal_kind == "blocked_players": open_blocked_players(back, false)

## The crop-ready notifications (SGODOT-350; P0Notify). Settings › Notifications: the switch, and when the system has
## said no the notice whose link opens the system's page. The page is read again whenever the phone may have changed
## (notify_changed: back from the system's page, the system dialog answered).
var notify: P0Notify
var _notif_back := Callable()

func open_notifications(back: Callable) -> void:
	_notif_back = back
	var s := notify.system()
	var page := P0SettingsPage.notifications(notify.switch_on(),
		str(s.get("app", "")) if notify.system_refused() else "", safe_top(), safe_bottom())
	page.theme = UiKit.theme()
	page.back_pressed.connect(back_modal)
	page.toggled.connect(func(_what, on: bool):
		notify.set_switch(on)
		notify_changed())
	page.open_pressed.connect(func(what: String): if what == "system_settings": notify.open_settings())
	_open_modal(page, 0.0, true)
	modal_kind = "notifications"
	_modal_back = back

## The phone's notification state may have changed: the page on screen shows it again.
func notify_changed() -> void:
	if modal_kind == "notifications" and notify != null: open_notifications(_notif_back)

## Settings › Language (0.2.21 中文版): the pick is saved for the next start (Localization.select_p0_language); the page
## shows it again with the restart line while the pick is not the language on screen.
const LANGUAGE_NAMES := {"en": "English", "zh_CN": "简体中文"}

func open_language(back: Callable) -> void:
	var page := P0SettingsPage.language(Localization.p0_language(), TranslationServer.get_locale(), safe_top(), safe_bottom())
	page.theme = UiKit.theme()
	page.back_pressed.connect(back_modal)
	page.open_pressed.connect(func(what: String):
		if not what.begins_with("language:"): return
		if Localization.select_p0_language(what.trim_prefix("language:")) != OK:
			show_sys(UiSysBanner.Kind.CMD_FAIL, "Didn't go through · try again")
			return
		open_language(back))
	_open_modal(page, 0.0, true)
	modal_kind = "language"
	_modal_back = back

func open_test_options(back: Callable) -> void:
	var page := P0SettingsPage.test_options(test_accounts.enabled(), test_accounts.is_test(), safe_top(), safe_bottom())
	page.theme = UiKit.theme()
	page.back_pressed.connect(back_modal)
	page.toggled.connect(func(_what, on: bool):
		if not test_accounts.set_enabled(on):
			var toggle := page.find_child("GuideTestToggle", true, false) as UiSettingRow
			toggle.on = test_accounts.enabled()
			show_sys(UiSysBanner.Kind.CMD_FAIL, "Didn't go through · try again"))
	page.open_pressed.connect(func(what: String):
		if what == "test_new": _confirm_test_account(back)
		elif what == "test_main": test_account_requested.emit("main"))
	_open_modal(page, 0.0, true)
	modal_kind = "test_options"
	_modal_back = back

func _confirm_test_account(back: Callable) -> void:
	var confirm = load("res://scenes/p0/panels/p0_home_move_confirm.gd").new()
	confirm.theme = UiKit.theme()
	confirm.card.find_child("Title", true, false).text = "Start a new test account?"
	confirm.card.find_child("Body", true, false).text = "Your main farm is kept."
	confirm.move.label = "Start"
	confirm.move.sends = false
	var cancel := func():
		confirm.queue_free()
		modal_kind = "test_options"
		_modal_back = back
	confirm.cancelled.connect(cancel)
	confirm.move_pressed.connect(func(): test_account_requested.emit("new"))
	_modal.add_child(confirm)   # keep the settings page behind its confirmation, not the game HUD
	modal_kind = "test_confirm"
	_modal_back = cancel

## The home pick (SGODOT-303, P0HomeFlow): a new player's first pages over no world, or the change of home from
## Settings. Back closes a layer at a time (the confirm card, the spot page); on a first pick's city page it does
## nothing (there is nowhere before it), on the change's it goes back to Settings.
## The two-row HUD is up: a view in, and no home pick open (its pages lie on the real map, PR-2b).
func _hud_shown() -> bool:
	return not view.is_empty() and not is_instance_valid(_home_flow_open)

var _home_flow_open: Control

func open_home_flow(flow: Control) -> void:
	flow.theme = UiKit.theme()
	_home_flow_open = flow
	if hud != null: hud.visible = false
	flow.tree_exited.connect(func():
		if _home_flow_open == flow: _home_flow_open = null
		if hud != null: hud.visible = _hud_shown())
	if test_accounts.is_test() and flow.change_from == "":
		flow.return_main = func(): test_account_requested.emit("main")
	flow.say.connect(func(text: String): toast(text))
	_open_modal(flow, 0.0, true)
	# the pin page over the real map (SGODOT-342 PR-2): its clear scrim lets the drags and pinches through to the map
	var veil := _modal_veil
	if flow.has_signal("map_shown"):
		flow.map_shown.connect(func(on: bool):
			if is_instance_valid(veil): veil.mouse_filter = Control.MOUSE_FILTER_IGNORE if on else Control.MOUSE_FILTER_STOP
			pad.visible = not on and surface != "map")   # no stick under the pin page: its map takes the drags
	modal_kind = "home_pick"
	_modal_back = _home_flow_back.bind(flow)

func _home_flow_back(flow: Control) -> void:
	_modal_back = _home_flow_back.bind(flow)   # first: Back to Settings opens another layer, which sets its own
	if is_instance_valid(flow): flow.back()

## SET-LICENSES: the credits (P0Legal); a row opens its full text, whose ‹ comes back here.
func open_licenses(back := Callable()) -> void:
	var page := P0SettingsPage.licenses(P0Legal.groups(), safe_top(), safe_bottom())
	page.theme = UiKit.theme()
	page.back_pressed.connect(back_modal)
	page.open_pressed.connect(func(id: String):
		# Mapbox (q(133) v3) opens Map data; every other row its full text
		if str(P0Legal.row(id).get("page", "")) == "map_data": open_map_data(func(): open_licenses(back))
		else: open_license_text(id, func(): open_licenses(back)))
	_open_modal(page, 0.0, true)
	modal_kind = "licenses"
	_modal_back = back

## Licenses › Mapbox › Map data (q(133) v3): the credits and Improve this map open in the browser; the switch is the
## map SDK's telemetry (MapUsage), on at once. Improve this map goes to the map's last view, else the home city's.
func open_map_data(back := Callable()) -> void:
	var page := P0SettingsPage.map_data(MapUsage.enabled(), safe_top(), safe_bottom())
	page.theme = UiKit.theme()
	page.back_pressed.connect(back_modal)
	page.open_pressed.connect(_open_map_data_row)
	page.toggled.connect(func(what: String, on: bool): if what == "telemetry": MapUsage.set_enabled(on))
	_open_modal(page, 0.0, true)
	modal_kind = "map_data"
	_modal_back = back

## A Map data row's address, opened in the browser (ExternalLink): the two credits and Mapbox's feedback page.
func _open_map_data_row(what: String) -> void:
	match what:
		"mapbox_site": ExternalLink.open(MapUsage.MAPBOX_CREDIT)
		"osm_site": ExternalLink.open(MapUsage.OSM_CREDIT)
		"improve":
			var c := P0Clusters.get_cluster(P0Travel.home(view))
			ExternalLink.open(MapUsage.feedback_url(Vector3(float(c.get("lat", 0.0)), float(c.get("lng", 0.0)), 12.0)))

## A credit's full text under its title (no frame; 不知火舞 on the Licenses brief).
func open_license_text(id: String, back := Callable()) -> void:
	var r := P0Legal.row(id)
	var link: Dictionary = r.get("link", {}) if r.get("link") is Dictionary else {}
	var page := P0SettingsPage.text(str(r.get("title", "")), P0Legal.full_text(r), safe_top(), safe_bottom(), link)
	page.theme = UiKit.theme()
	page.back_pressed.connect(back_modal)
	page.open_pressed.connect(func(what: String): if what == "link" and str(link.get("url", "")) != "": ExternalLink.open(str(link.url)))   # q(205) ⑥
	_open_modal(page, 0.0, true)
	modal_kind = "license_text"
	_modal_back = back

## Close on a layer of the profile chain (Skills, the Fish-dex, HOME-1 opened from the profile) closes that layer only,
## back to what is under it, as the system Back does; only the profile's own ‹ goes out to the world. Opened from the
## world, Close goes to the world as before (int11, 不知火舞 on 225).
func close_layer() -> void:
	if _over_profile: back_modal()
	else: close_modal()

## HOME-1 (§10.6.2) from the profile's farm card: over the profile; away from the homestead the upgrade is greyed with
## HOME-1's own wording (P0Logic.home_panel, 苏烈). Loaded here, not preloaded: the panel's script names P0Ui.
func open_home_panel(back := Callable()) -> void:
	load("res://scenes/p0/home/p0_home_panel.gd").open(self, space_here() == "home")
	_modal_back = back

## The profile page to move under the next layer: while a chain opened from the profile goes on (256 ⑧).
func _profile_to_keep() -> Control:
	if not _over_profile or _profile == null or not is_instance_valid(_profile) or _profile.is_queued_for_deletion(): return null
	if _profile.get_parent() != null: _profile.get_parent().remove_child(_profile)
	return _profile

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
## SKILL-1 (P0SkillsDrawer): from the profile's skill cards and the gate card's `Skills`; `back` reopens the panel it
## came from on Back or a tap outside.
func open_skills(back := Callable()) -> void:
	var d := P0SkillsDrawer.new(view)
	d.theme = UiKit.theme()
	d.safe_bottom = safe_bottom()
	d.close_requested.connect(close_layer)
	d.close_pressed.connect(close_layer)
	_open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	modal_kind = "skills"
	_modal_back = back

# ---------------------------------------------------------------- one-line teaching cards (§14.3)
const TIPS_PATH := "user://p0_tips.json"
## Where the teaching tips and "shown before" keys live (tests point it at their own file).
var tips_path := TIPS_PATH

## A one-sentence card above the quick bar, once per account on this device; tap or 7 s to dismiss.
## Never a hand animation, never moves the player (§14.3 "不画手指动画循环").
## A TipCard (q(44): the eight P0 sentences in P0Guide.TIPS, each once; shown in order through P0Guide.TipQueue,
## timed like a Toast and closed by doing what it teaches, a tap, or time). `_text` is ignored: the copy is P0Guide's.
func teach(key: String, _text := "") -> void:
	if not P0Guide.tip_allowed(view, key): return   # the new-player guide picks the tips while it is on (SGODOT-341)
	_load_tips()
	if tips == null: tips = P0Guide.TipQueue.new(_taught)
	tips.request(key)

## A TipCard is on screen or waits its turn: the pond's arrival toast comes after it (q(103), q(49)).
func tip_pending() -> bool:
	return tips != null and (tips.showing != "" or not tips.waiting.is_empty())

## Whether the TipCard on screen is this tip (the kitchen keeps its own copy of `heat` out of sight meanwhile).
func tip_showing(key: String) -> bool:
	return tips != null and tips.showing == key and _teach != null and _teach.visible

## The TipCard on screen (global rect), an empty one when none: what it must not have under it (the kitchen's countdown, 419).
func tip_rect() -> Rect2:
	return _teach.get_global_rect() if _teach != null and _teach.visible else Rect2()

## Any TipCard is on screen: the pond's fishing status card waits under it (q(49), SGODOT-376).
func tip_on_screen() -> bool:
	return _teach != null and _teach.visible

## A TipCard is on screen, or waits and comes up on the next frame (no dialog, no Moment): the first cast's tip is asked
## for in the same response that puts `Watch the float…` up, so the status card holds from that frame (SGODOT-376 ③).
func tip_up_or_coming() -> bool:
	if tip_on_screen(): return true
	return tips != null and not tips.waiting.is_empty() and tips.moments == 0 and not dialog_open() and not _tips_held()

## Keep new TipCards back for `ms` (the fishing panel renews it every frame while a bite waits for Hook: the bite takes
## the screen, SGODOT-376 ②). Self-expiring, so a panel that goes away never keeps the tips back.
var _tips_held_until_ms := 0
func hold_tips(ms: int) -> void:
	_tips_held_until_ms = Time.get_ticks_msec() + ms

func _tips_held() -> bool:
	return Time.get_ticks_msec() < _tips_held_until_ms

## Close the TipCard on screen now (a bite takes the screen, SGODOT-376 ②).
func close_tip() -> void:
	if tip_on_screen(): _hide_tip()

## The player did what the tip on screen teaches (sow / cast / cook / heat): it closes now.
func tip_did(action: String) -> void:
	if tips == null: return
	var before := tips.seen.size()
	if tips.did(action): _hide_tip(false)
	# a tip taken off the queue as done (TipQueue.did) is seen now, not at the next card: kept on disk at once, so an app
	# closed before another tip comes up never shows it again (哪吒 on #733)
	if tips.seen.size() != before:
		for k in tips.seen:
			if P0Guide.tip_text(k) != "": _taught[k] = true
		_save_tips()

func _hide_tip(close_queue := true) -> void:
	_teach_until_ms = 0
	if _teach: _teach.hide()
	if close_queue and tips: tips.close()
	_flush_held_toast.call_deferred()   # a filled request's toast waited for it (q(134) ⑤)

## Each tip's icon (P0Guide.TIPS keys) from the shared P0 icons, as the TUT-2 specimens (不知火舞 on 232 / 235-B2).
const TIP_ICONS := {"sow": "seed_radish", "creel": "fish", "cast": "energy", "meal": "energy", "cook": "pot", "heat": "pot", "map": "map", "travel": "travel"}

## TipCard (TUT-2, 235-B2): the kit card with the tip's icon; a tap on it closes it (A-03).
func _show_tip(text: String, key := "") -> void:
	for k in tips.seen:
		if P0Guide.tip_text(k) != "": _taught[k] = true   # only the tips: the store also keeps stall_seen / dex_seen lists
	_save_tips()
	if _teach == null:
		_teach = UiTipCard.new()
		_teach.theme = UiKit.theme()
		_teach.tapped.connect(func(): _hide_tip())
		root.add_child(_teach)
	_teach.show_tip(text, P0Logic.icon(str(TIP_ICONS[key])) if TIP_ICONS.has(key) else null)
	_teach.show()
	# The card is made once and kept: one made on the farm sat under a drawer opened since (the kitchen's preview card
	# covered `Tap Cook to grill your first fish`, S8, 蒙恬). Each tip comes to the front of every card, drawer and sheet
	# (不知火舞 on 341); only a dialog opened after it covers it; toasts and the system line stay over it.
	root.move_child(_teach, -1)
	if _toasts != null and _toasts.get_parent() == root: root.move_child(_toasts, -1)
	if _sys != null and is_instance_valid(_sys): root.move_child(_sys, -1)
	_place_tip()
	_teach_until_ms = Time.get_ticks_msec() + int(P0Guide.tip_seconds(text) * 1000.0)

## Where the TipCard sits (不知火舞 on 232, TUT-1-2 / TUT-3-04B / TUT-3-07B): centred; its top 120 under HUD row 2,
## clear of the joystick's centre, the main action key and the quick bar. In the kitchen (不知火舞 on 341), at x 16:
## with the stove drawer open, 8 under HUD row 2 — not on the drawer, whose preview card stands above it; watching a
## pot, 8 over the watch sheet's × (q(16)'s toast dock) — clear of the stove, the heat ring and the plate.
const TIP_BELOW_HUD := 120.0
func _place_tip() -> void:
	if _teach == null: return
	var h := _teach.get_combined_minimum_size().y
	var under_hud := hud.today_chip_rect().end.y - root.global_position.y
	var x := (root.size.x - UiTipCard.WIDTH) * 0.5
	var y := under_hud + TIP_BELOW_HUD
	if _kitchen_drawer_open():
		x = UiTokens.SPACE_PAGE
		y = under_hud + UiTokens.SPACE_OVERLAY_BODY
	elif _modal == null and _toast_over != null and is_instance_valid(_toast_over) and _toast_over.is_visible_in_tree():
		x = UiTokens.SPACE_PAGE
		y = _toast_over.get_global_rect().position.y - root.global_position.y - UiTokens.SPACE_OVERLAY_BODY - h
	_teach.position = Vector2(x, y)
	_teach.size = Vector2(UiTipCard.WIDTH, h)

## The stove drawer is on screen (the kitchen opens it inside a full-screen wrap: the drawer itself, not the wrap).
func _kitchen_drawer_open() -> bool:
	if modal_kind != "kitchen" or _modal == null: return false
	return _modal.find_children("*", "P0KitchenDrawer", true, false).any(func(d): return (d as Control).is_visible_in_tree())

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
			# Back to its content's size: a wrapped line first measured at zero width makes the card tall, and a card
			# outside a container never shrinks again on its own (李元芳 int7: the level banner reaching the bottom).
			var fit := card.get_combined_minimum_size()
			if not card.size.is_equal_approx(fit): card.size = fit
			var y := (UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + _BANNER_UNDER_HUD + safe_top()) if banner else root.size.y * _MOMENT_TOP
			card.position = Vector2(roundf((root.size.x - card.size.x) * 0.5), roundf(y))
	card.resized.connect(place)
	card.minimum_size_changed.connect(place)   # shrinking content never resizes the card by itself
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
	if spec.get("icon", null) is Texture2D: b.icon = spec.icon   # art in the disc's place (the Fish-dex badge)
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
## extras: {city_xp, energy} from the same response (P0Runtime). A kind first got from a Fish Trap: `In your trap!`, the
## rest the same (q(124) ①).
func show_catch(fish_id: String, rarity: int, first_xp: int, extras := {}, event := "Caught!") -> void:
	var m := UiRewardMoment.new()
	m.tone = UiRewardMoment.Tone.REWARD
	m.event = event
	m.icon = P0Logic.icon(fish_id)
	m.item_name = P0Logic.item_name(view, fish_id)
	if int(extras.get("qty", 1)) > 1: m.item_name += " ×%d" % int(extras.qty)   # Twin Catch: `Bluegill ×2` (q(124), q(300))
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
	# a trap's cards come one after another from one reply: each counts the kinds up to its own (extras.dex_back)
	m.note = "Fish-dex %d/%d" % [dex.filter(func(d): return int(d.get("caught", 0)) > 0).size() - int(extras.get("dex_back", 0)), dex.size()]
	show_moment(m)

## A Cookbook title (§7.6.1; 不知火舞 on 282): RewardMoment Milestone, no buttons — the title, `Cookbook 20/48`, `New title ·
## +100 coins · Recipe Stand` (P0KitchenLogic.title_card). Queued after the dish card like a level-up. A skill's Lv10
## title too (P0Logic.title_card: `Master Gardener` · `Farming Lv10` · `New title`, its skill's icon; SGODOT-275).
## Kindred (q(171) ③; KINDRED-PIP 2620:134209): RewardMoment Milestone, no buttons, folded away as a title card —
## `Kindred · Pip`, their postcard's stamp in the item's place, `Postcard from Pip`, the strip `New title · Pip's Best
## Friend` with the affinity float's heart at 14; no pills (P0Kindred.card).
const PostcardStamp := preload("res://scenes/p0/panels/p0_postcard_stamp.gd")
func show_kindred(spec: Dictionary) -> void:
	var m := UiRewardMoment.new()
	m.tone = UiRewardMoment.Tone.MILESTONE
	m.event = str(spec.get("event", ""))
	m.item_art = PostcardStamp.new(str(spec.get("resident", "")), true, PostcardStamp.CARD)
	m.item_name = str(spec.get("item_name", ""))
	m.strip = str(spec.get("strip", ""))
	m.strip_icon = UiFloatText.HEART   # the affinity float's heart, color/float-affinity, 14 (不知火舞 on 284)
	m.strip_icon_size = 14.0
	show_moment(m)

func show_title(spec: Dictionary) -> void:
	var m := UiRewardMoment.new()
	m.tone = UiRewardMoment.Tone.MILESTONE
	m.event = str(spec.get("event", ""))
	m.icon = spec.get("icon", P0Logic.icon("cookbook"))   # a skill's title (P0Logic.title_card) brings its skill's icon
	m.item_name = str(spec.get("item_name", ""))
	m.strip = str(spec.get("strip", ""))
	show_moment(m)

## A Fish-dex milestone (§6.9.2; 不知火舞 on 283): the same RewardMoment Milestone as a Cookbook title, no buttons —
## `Fish-dex 10/20` over the kind that made it; the whole dex a full MomentBanner instead (283 DEX-COMPLETE: the badge,
## `Fish-dex complete` · `20/20`, pills `+50 Energy` `+300 coins` `Badge`, ≤ 3 s, no button). P0FishDex.milestone_card.
## Queued after the catch's card like a level-up.
func show_dex_milestone(spec: Dictionary) -> void:
	if bool(spec.get("banner", false)):
		show_banner(spec)
		return
	var m := UiRewardMoment.new()
	m.tone = UiRewardMoment.Tone.MILESTONE
	m.event = str(spec.get("event", ""))
	m.icon = P0Logic.icon(str(spec.get("icon", "fish_crucian")))
	m.item_name = str(spec.get("item_name", ""))
	m.strip = str(spec.get("strip", ""))
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
		if action == &"guide": _gate_guide(str(payload.get("go", "")), func(): open_gate_card(gate, back)))
	_open_modal(sheet, 0.32, true)   # the card sits where the quick bar was; bar and keys hide under it
	modal_kind = "gate"
	sheet.open("gate", &"gate")
	_modal_back = back
	return sheet

## `again` reopens the gate card: Skills goes back to it (and on through its own way back, e.g. the Fish-dex and the
## profile behind both, 256 ⑧; 亚瑟 on #136: Back from these Skills went straight to the world).
func _gate_guide(go: String, again := Callable()) -> void:
	match go:
		"skills":
			# On to another panel through _open_modal's own drop, not close_modal: a queued card must not come up over it
			# (亚瑟 on #77). No drop of ours first: the profile under this chain moves out of the old layer before it
			# goes, not because its freeing happens to wait (亚瑟 on #137).
			open_skills(again)
		"plots", "stall", "stove", "board", "home", "bench":
			close_modal()
			if show_label(go, space_here(), spot_reachable(), place) == "Show": show_spot.emit(go)
			else: show_on_map.emit(map_target(go))
		_: request_panel(go)

## True the first time a key comes up on this device (kept with the teaching tips).
func first_time(key: String) -> bool:
	_load_tips()
	if _taught.has(key): return false
	_taught[key] = true
	_save_tips()
	return true

## A server-side reset starts a new account under the same player id (SGODOT-270: Joey's account starts over in San
## Francisco). The teaching tips, "seen" lists and quick-bar pins on this device belonged to the old account, so they go
## and the first session teaches again (with the notification prompt's answer and the Big Pot stoves, SGODOT-397).
## The account is known by its creation time (view.profile.since_ms), kept with the
## tips; a tips file written before this build kept that is judged by its age: last written before the account was made.
func _check_account(v: Dictionary) -> void:
	var since := int(v.get("profile", {}).get("since_ms", 0))
	if since <= 0: return
	_load_tips()
	var known := int(_taught.get("account_since", 0))
	if known == since: return
	var stale := known != 0
	if known == 0 and FileAccess.file_exists(tips_path):
		stale = FileAccess.get_modified_time(tips_path) * 1000 < since - 60_000   # a minute's leeway for the phone's clock
	if stale:
		_taught = {}
		_dot_keys = null   # the new account's Today dot is judged afresh, even on the same keys (亚瑟 on #201)
		tips = null
		_hide_tip()
		_quick = {}
		_save_quick()
		# v4q(2) ⑥ (SGODOT-397): the notification prompt's answer and the Big Pot stoves were the old save's too
		if notify != null: notify.forget_asked()
		P0KitchenLogic.forget_big_stoves(str(player_of.call()))
	_taught["account_since"] = since
	_save_tips()

func _load_tips() -> void:
	if _taught.is_empty() and FileAccess.file_exists(tips_path):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(tips_path))
		if saved is Dictionary: _taught = saved

func _save_tips() -> void:
	var f := FileAccess.open(tips_path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(_taught))

## The Today icon's red dot (q(107), SGODOT-271): lit while a row that can be done now has a key this device has not
## seen. Opening Today sees every such row; a key that has left the rows is forgotten, so the same thing coming back
## (the fish eaten and caught again, another crop ready) lights it again. Kept with the teaching tips (tips_path):
## on the device, not in the save.
const TODAY_SEEN := "today:"
func _today_unseen(keys: Array) -> bool:
	_load_tips()
	# a row gone is forgotten, so the same thing coming back lights again (q(107)) — but Pip's requests are seen once for
	# good (P0Logic.PIP_DOT, spec ③ v3)
	var gone := _taught.keys().filter(func(k): return str(k).begins_with(TODAY_SEEN) and not keys.has(str(k).trim_prefix(TODAY_SEEN)) \
		and not str(k).trim_prefix(TODAY_SEEN).begins_with(P0Logic.PIP_DOT))
	for k in gone: _taught.erase(k)
	if not gone.is_empty(): _save_tips()
	return keys.any(func(k): return not _taught.has(TODAY_SEEN + str(k)))

func _see_today(keys: Array) -> void:
	if keys.is_empty() or not _dot_lit: return
	_load_tips()
	for k in keys: _taught[TODAY_SEEN + str(k)] = true
	_save_tips()
	_dot_lit = false
	_hud_hash = 0
	_refresh_hud()

## FISH-6 Fish-dex (SGODOT-233, P0FishDex): from the creel badge, the profile's Fish tile and the catch cards. A cell
## opens the gate card for a silhouette its level or rod holds back (q(57)), else the fish card; either comes back to
## the dex on Back or a tap outside. Fish caught since the last visit ring once (kept with the teaching tips).
func open_fishdex(back := Callable(), animate := true) -> void:
	_load_tips()
	var caught: Array = view.get("fishing", {}).get("dex", []).filter(func(f): return int(f.get("caught", 0)) > 0).map(func(f): return str(f.id))
	var seen: Array = _taught.get("dex_seen", []) if _taught.get("dex_seen", []) is Array else []
	var fresh := caught.filter(func(id): return not seen.has(id))
	if not fresh.is_empty():
		_taught["dex_seen"] = caught
		_save_tips()
	var d := P0FishDex.new(view, fresh)
	d.theme = UiKit.theme()
	d.animate = animate
	d.safe_bottom = safe_bottom()
	d.close_requested.connect(close_layer)
	d.close_pressed.connect(close_layer)
	var again := func(): open_fishdex(back, false)
	d.cell_pressed.connect(func(id: String):
		var gate := P0Logic.fish_gate(view, id)
		if not gate.is_empty() and not P0Logic.dex_caught(view, id): open_gate_card(gate, again)
		else: open_fish_card(id, again))
	_open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	modal_kind = "fishdex"
	_modal_back = back

## The Passport (§11.9.3; PASS-POSTCARDS 2627:134311, 不知火舞 on 284): a drawer with its pages on Filter pills —
## `Cities` (cities visited, today's counted first visits, home and every city reached with its stamp; a city opens
## its page, PASS-2, whose Back comes here) and `Postcards` (q(171) ⑥). Close goes back where it was opened from (the
## profile), else closes (the Stamp Desk): the old bottom Back is Close now. `page`: "cities" or "postcards".
const PassportDrawer := preload("res://scenes/p0/panels/p0_passport_drawer.gd")
var _passport: UiDrawer

func open_passport(back := Callable(), page := "cities") -> UiDrawer:
	var spec := P0Travel.passport(view)
	for r in spec.rows:
		r["icon"] = load(str(r.stamp)) if str(r.get("stamp", "")) != "" else P0Logic.icon(str(r.icon))
		if str(r.state) != "Home":
			var cluster := str(r.cluster)
			r["pressed"] = func(): open_city_page(cluster, func(): open_passport(back))
	var d: UiDrawer = PassportDrawer.new(spec, view, page)
	d.theme = UiKit.theme()
	d.safe_bottom = safe_bottom()
	d.close_requested.connect(back_modal)
	d.connect(&"close_pressed", back_modal)
	_open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	modal_kind = "passport"
	_modal_back = back
	_passport = d
	return d

## The open Passport, or null.
func passport() -> UiDrawer:
	return _passport if is_instance_valid(_passport) and modal_kind == "passport" else null

## PASS-2 (Figma 482:431, §11.9.1): a city's three tiers and its counts.
func open_city_page(cluster: String, back := Callable()) -> void:
	if modal_kind != "": close_modal()
	var spec := P0Travel.city_page(view, cluster)
	for r in spec.rows: r["icon"] = load(str(r.stamp)) if str(r.get("stamp", "")) != "" else P0Logic.icon(str(r.icon))
	spec["dismiss"] = "Back"
	P0ArrivalCard.open(self, spec, func(): pass, "city_page")
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
	_over_profile = false   # the host's panel is not over the profile
	_drop_modal()   # the host's panel comes next; a queued card waits for it to close, not over it
	panel_requested.emit(panel)

## Whether a host opens panels this UI does not own (a read-only Cookbook). Until one does, nothing offers them:
## no dead-end placeholder (不知火舞 233 walkthrough).
func can_request_panel() -> bool: return panel_requested.get_connections().size() > 0

# ---------------------------------------------------------------- helpers
## One press = one action. Touch is emulated as a left mouse button (project default), so reacting to
## both InputEventScreenTouch and InputEventMouseButton would fire toggles and commands twice.
static func is_tap(e: InputEvent) -> bool:
	return e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT

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
		# Placement mode (SGODOT-241): one finger moves the preview; no stick, no tap, no pinch.
		if ui.placing():
			_placement_input(e)
			return
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
	# Placement mode (SGODOT-241; 不知火舞 on 241): one finger moves the preview (placement_point); two fingers pan and
	# pinch the camera as in the world (placement_pan / zoom). Touch on a phone, its emulated mouse on a desktop.
	var _place_touches := {}   # index → screen point, while placing
	var _place_two := false     # two fingers down: the camera's, the preview stays
	func _placement_input(e: InputEvent) -> void:
		var xf := get_global_transform_with_canvas()
		if e is InputEventScreenTouch:
			if e.pressed: _place_touches[e.index] = xf * e.position
			else: _place_touches.erase(e.index)
			if _place_touches.size() >= 2: _place_two = true
			elif _place_touches.is_empty():
				if _place_two: ui.zoom_end.emit()
				_place_two = false
			return
		if e is InputEventScreenDrag:
			if not _place_touches.has(e.index) or _place_touches.size() < 2: return
			var before := _centre_spread()
			_place_touches[e.index] = xf * e.position
			var after := _centre_spread()
			ui.placement_pan.emit(after.centre - before.centre, after.centre)
			if before.spread > 0.0 and after.spread > 0.0: ui.zoom.emit(before.spread / after.spread, after.centre)
			return
		if _place_two: return   # the mouse twin of a two-finger gesture moves nothing
		if e is InputEventMouse:
			var at: Vector2 = xf * (e as InputEventMouse).position
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
				ui.placement_point.emit(at, "press" if e.pressed else "release")
			elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
				ui.placement_point.emit(at, "drag")
			elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				ui.zoom.emit(0.9 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1, at)
				ui.zoom_end.emit()
	func _centre_spread() -> Dictionary:
		var pts: Array = _place_touches.values()
		if pts.size() < 2: return {centre = Vector2.ZERO, spread = 0.0}
		return {centre = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5, spread = (pts[0] as Vector2).distance_to(pts[1])}

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

# ---------------------------------------------------------------- placement mode (P1, SGODOT-241)
## The modal edit shell (plan q(23): the LOCK-01 / 02 exception) the sprinkler's Build and Move use, and later Decorate
## and Plot Marks: a press on the scene summons no stick, it moves the preview (placement_point); the HUD keeps only
## its first row; the quick bar, the main key, the switch key, the radial and world markers step aside; the bottom bar
## has Cancel and the main key (and, for decor that turns, a middle key: placement_secondary). What is placed, where it
## may stand and what the keys send belong to the caller: spec = {confirm: "Build", caption: "", reason: "",
## secondary: ""}; update them with set_placement as the preview moves.
var _place_bar: UiPlaceBar

func placing() -> bool: return _place_bar != null and is_instance_valid(_place_bar)

func begin_placement(spec: Dictionary) -> void:
	if placing(): end_placement()
	close_modal()
	if _radial.is_open(): _radial.close()
	_bar.cancel_drag()
	joystick.emit(Vector2.ZERO)
	(pad as _TouchPad).end_stick()
	_place_bar = UiPlaceBar.new()
	_place_bar.theme = UiKit.theme()
	_place_bar.safe_bottom = safe_bottom()
	_place_bar.confirmed.connect(func(): placement_done.emit(true))
	_place_bar.cancelled.connect(func(): placement_done.emit(false))
	_place_bar.secondary_pressed.connect(func(): placement_secondary.emit())
	_place_bar.unavailable.connect(func(r: String): toast(r))
	_kit.add_child(_place_bar)
	set_placement(spec)
	_keys.visible = false
	_bar.visible = false
	_creel.visible = false
	_trap_slots.visible = false
	_status.visible = false
	hud.set_row2_shown(false)
	for m in _icons.values() + _name_bars.values() + _npc_tags.values() + _badges.values(): (m as Control).visible = false

func set_placement(spec: Dictionary) -> void:
	if not placing(): return
	if spec.has("confirm"): _place_bar.confirm = str(spec.confirm)
	if spec.has("caption"): _place_bar.caption = str(spec.caption)
	if spec.has("reason"): _place_bar.reason = str(spec.reason)
	if spec.has("secondary"): _place_bar.secondary = str(spec.secondary)
	if spec.has("cancel"): _place_bar.cancel = str(spec.cancel)

## Back to the world's controls (after the main key's command is sent, or Cancel).
func end_placement() -> void:
	if not placing(): return
	(pad as _TouchPad)._place_touches.clear()
	(pad as _TouchPad)._place_two = false
	_place_bar.queue_free()
	_place_bar = null
	hud.set_row2_shown(true)
	var was := surface
	surface = ""
	set_surface(was)

## The bar's card on screen, where the scene stops taking placement touches.
func placement_bar_rect() -> Rect2:
	if not placing(): return Rect2()
	return Rect2(_place_bar.get_global_rect().position + _place_bar.card_rect().position, _place_bar.card_rect().size)

## A facility's status card (P1, SGODOT-241; q(59) §4): `Sprinkler · Waters 8 plots` and one button (Move); the
## caller highlights what it covers while the card shows (modal_kind "facility"). Sits where the quick bar was.
## spec = {title, lead, icon, facts, button, kind (&"secondary"), second, close, reason}; on_button runs after the card closes;
## button "" (with no reason) leaves the card without one (the Chef's Sign only says what it does).
## A placed decor's card (DECOR-CARD, Figma 2191:33239) has a primary Move, the text button `Store` (spec.second,
## on_second) and a ✕ over its corner (spec.close). spec.reason greys the main button with it, LOCK-10 (a greenhouse
## with crops under it: `Move · Harvest first`, 李白); a tap says why.
## In placement mode the bar steps aside while the card shows and comes back when it closes.
func open_facility_card(spec: Dictionary, on_button: Callable, on_second := Callable()) -> UiInfoSheet:
	var reason := str(spec.get("reason", ""))
	var buttons: Array = [{id = &"move", label = reason if reason != "" else str(spec.get("button", "Move")),
		kind = &"unavailable" if reason != "" else StringName(spec.get("kind", &"secondary"))}]
	if str(spec.get("button", "Move")) == "" and reason == "": buttons = []   # a card that only says (the Chef's Sign)
	if str(spec.get("second", "")) != "": buttons.append({id = &"second", label = str(spec.second), kind = &"nav", chevron = false})
	var card := {id = "facility", title = str(spec.get("title", "")), lead = str(spec.get("lead", "")),
		icon = spec.get("icon", null), facts = spec.get("facts", []), buttons = buttons}
	var sheet := UiInfoSheet.new()
	sheet.theme = UiKit.theme()
	sheet.rules = func(_id, _ctx, _o): return card
	sheet.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.offset_left = UiTokens.SPACE_PAGE
	sheet.offset_right = -UiTokens.SPACE_PAGE
	sheet.offset_bottom = -bottom_pad()
	sheet.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sheet.action_requested.connect(func(action: StringName, _id: String, _payload: Dictionary):
		close_modal()
		if action == &"second" and on_second.is_valid(): on_second.call()
		elif action != &"second": on_button.call())
	sheet.unavailable_requested.connect(func(_a: StringName, _id: String, r: String): toast(r))
	if placing():
		_place_bar.visible = false
		sheet.tree_exited.connect(func(): if placing(): _place_bar.visible = true)
	var content: Control = sheet
	if bool(spec.get("close", false)):   # DECOR-CARD: a ✕ 6 above the card's top-right corner (b706e141 ③)
		var holder := Control.new()
		holder.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(sheet)
		var close := UiCloseButton.new()
		close.pressed.connect(close_modal)
		holder.add_child(close)
		sheet.resized.connect(func():
			close.position = Vector2(sheet.position.x + sheet.size.x - UiTokens.SIZE_CLOSE, sheet.position.y - 6 - UiTokens.SIZE_CLOSE))
		content = holder
	_open_modal(content, 0.0, true)
	modal_kind = "facility"
	sheet.open("facility", &"facility")
	return sheet

# ---------------------------------------------------------------- voice (SGODOT-383, q(274); 不知火舞's spec 383 6d206dfb)
## The room's voice, from the world (an outpost's or a pond's P0VoiceRoom, Market Square's too since q(286); null with
## none — the map, the farm, a POI's room). P0Runtime hands it over every frame; the keys follow its `changed`.
const VoiceKeys := preload("res://scenes/p0/panels/p0_voice_keys.gd")
const PeopleDrawer := preload("res://scenes/p0/panels/p0_people_drawer.gd")
const AgeCard := preload("res://scenes/p0/panels/p0_age_card.gd")
const MIC_ON_TOAST := "Mic on · others here can hear you"   # q(274) 补记二 dc052823 (the longer line ran to three)
const VOICE_NOT_AVAILABLE := "Voice chat isn't available"
const REPORT_SENT := "Report sent"
const REPORT_ALREADY := "You already reported this"
const VOICE_KEYS_RIGHT := 16.0
static var _mic_toast_said := false   # the first mic on after the app opens says who hears (§2); later ones do not
var voice_room: Node
var _voice_keys: Control
var _people: UiDrawer
var _mic_was_on := false
var _mic_denied := false   # the system said no once: the key only says why from then on (§2)

func set_voice_room(r: Node) -> void:
	if r == voice_room: return
	if is_instance_valid(voice_room):
		for s in [[&"changed", _voice_refresh], [&"age_needed", open_age_card]]:
			if voice_room.is_connected(s[0], s[1]): voice_room.disconnect(s[0], s[1])
	voice_room = r if is_instance_valid(r) else null
	_mic_was_on = false
	if voice_room:
		voice_room.connect(&"changed", _voice_refresh)
		voice_room.connect(&"age_needed", open_age_card)
	if modal_kind == "people": close_modal()
	_voice_refresh()

func _voice() -> Node: return voice_room.get("voice") if voice_room else null

func _mic_on() -> bool:
	var v := _voice()
	return v != null and bool(v.call("active")) and bool(v.get("microphone"))

## The keys shown or not, the mic's state, the count, an open drawer's rows; a first mic on says who hears.
func _voice_refresh() -> void:
	var shown := voice_room != null and bool(voice_room.call("offered")) and surface != "map"
	if shown and _voice_keys == null:
		_voice_keys = VoiceKeys.new()
		_voice_keys.theme = UiKit.theme()
		_voice_keys.mic_pressed.connect(_on_mic_pressed)
		_voice_keys.people_pressed.connect(open_people)
		root.add_child(_voice_keys)
	if _voice_keys == null: return
	_voice_keys.visible = shown
	if not shown: return
	var v := _voice()
	if v != null and str(v.get("error")) == "MICROPHONE_DENIED": _mic_denied = true
	var on := _mic_on()
	_voice_keys.set_mic(on)
	var rows: Array = voice_room.call("people")
	_voice_keys.set_count(rows.size())
	var crowd = voice_room.get("online").get("crowd") if voice_room.get("online") else null
	if crowd != null and "speaking" in crowd:   # §3: a speaker's name tag goes green (not a muted or blocked one)
		var now := {}
		for r in rows: if bool(r.speaking) and not bool(r.muted) and not bool(r.blocked) and not bool(r.get("self", false)): now[int(r.peer)] = true
		crowd.set("speaking", now)
	_voice_keys.place(root.size.x - VOICE_KEYS_RIGHT, _creel.position.y)   # on the Creel pill's line, in a room too (383 V1 / V6)
	if on and not _mic_was_on and not _mic_toast_said:
		_mic_toast_said = true
		toast(MIC_ON_TOAST, 0.0, true)
	_mic_was_on = on
	if modal_kind == "people" and is_instance_valid(_people): _people.call("refresh", rows)

func _on_mic_pressed() -> void:
	if voice_room == null: return
	if _mic_denied:   # the system box comes only the first time (§2): from then on the key says why and stays off
		toast(PartyVoiceSession.error_text("MICROPHONE_DENIED"))
		return
	voice_room.call("toggle_mic")

## This layer's people (§4): the space and its layer in the title, a row each; Mute here, Block after its card, Report.
func open_people() -> void:
	if voice_room == null: return
	var layer := int(voice_room.get("online").get("room")) if voice_room.get("online") else 0
	var space := place_text().get_slice(" · ", 1) if place_text().contains(" · ") else place_text()
	var d: UiDrawer = PeopleDrawer.new("%s · Layer %d" % [space, maxi(1, layer)] if space != "" else "Layer %d" % maxi(1, layer),
		voice_room.call("people"))
	d.theme = UiKit.theme()
	d.safe_bottom = safe_bottom()
	d.close_requested.connect(close_layer)
	d.connect(&"mute_pressed", func(peer: int, on: bool): voice_room.call("set_muted", peer, on))
	d.connect(&"mute_all_pressed", func(on: bool):
		for r in voice_room.call("people"): if not bool(r.blocked) and not bool(r.get("self", false)): voice_room.call("set_muted", int(r.peer), on))
	d.connect(&"block_pressed", func(peer: int, on: bool):
		if on: _confirm_block(peer)
		else: voice_room.call("set_blocked", peer, false))   # Unblock at once, no card (§5)
	d.connect(&"report_pressed", _report)
	_open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)   # its own Close under the rows (V3), no ✕ over it
	_people = d
	modal_kind = "people"

## §5: `Block Traveller ab12?`, `You won't hear each other.` / `They won't be told.`, Block (red, V4) / Cancel (q(28)'s
## card, the confirm frame the home move uses).
func _confirm_block(peer: int) -> void:
	var who := ""
	for r in voice_room.call("people"): if int(r.peer) == peer: who = str(r.name)
	var confirm = load("res://scenes/p0/panels/p0_home_move_confirm.gd").new()
	confirm.name = "BlockConfirm"
	confirm.theme = UiKit.theme()
	confirm.card.find_child("Title", true, false).text = "Block %s?" % who
	confirm.card.find_child("Body", true, false).text = "You won't hear each other.\nThey won't be told."
	confirm.move.label = "Block"
	confirm.move.kind = UiCommandButton.Kind.DESTRUCTIVE   # V4: the red key
	confirm.move.sends = false
	var back := func():
		confirm.queue_free()
		modal_kind = "people"
		_modal_back = Callable()
	confirm.cancelled.connect(back)
	confirm.move_pressed.connect(func():
		back.call()
		voice_room.call("set_blocked", peer, true))
	_modal.add_child(confirm)   # over the drawer, which stays behind it
	modal_kind = "block_confirm"
	_modal_back = back

## §6: no reason asked; the server's word in an Info toast (sent / already; a failure as the network's).
func _report(peer: int) -> void:
	var said = await voice_room.call("report", peer)
	match str(said):
		"sent", "true": toast(REPORT_SENT)
		"already": toast(REPORT_ALREADY)
		_: show_sys(UiSysBanner.Kind.CMD_FAIL, "Didn't go through · try again")   # failed: as any command the network lost

## §7: the 13+ gate (14 by the year, the user 11-02) the first time the mic key is tapped. Old enough goes on to the
## mic (P0VoiceRoom.answer_age), not old enough hides voice on this phone with an Info toast. Nothing else is kept.
## q(281) ④ (SGODOT-390, 不知火舞 18f24a30): Voice Profile behind voice's 13+ gate, the one answer for both (the server's,
## voice_account): passed — the voice-match page as ever; not — the card stays, a tap says `Voice Profile isn't
## available`; not answered — the age card first, titled `Voice Profile`, then the page or the toast.
const VOICE_PROFILE_NOT_AVAILABLE := "Voice Profile isn't available"
func open_voice_profile() -> void:
	if voice_account == null:
		voice_match.open("solo")
		return
	if str(voice_account.get("age")) == "unknown": await voice_account.call("fetch_status")   # answered on another screen
	match voice_profile_step(str(voice_account.get("age"))):
		"open": voice_match.open("solo")
		"refuse": toast(VOICE_PROFILE_NOT_AVAILABLE)
		_:
			# over the profile, dimmed under it (帧 422:190483, 不知火舞 390 954da6ce): closed or answered, the layer goes and
			# the profile is there as it was (_over_profile, as Skills over it); then the page, or the toast on the profile
			_over_profile = true
			var d: UiDrawer = AgeCard.new(0, "Voice Profile")
			d.theme = UiKit.theme()
			d.safe_bottom = safe_bottom()
			d.close_requested.connect(close_layer)
			d.connect(&"answered", func(ok: bool):
				# kept for voice too: the one answer. voice_account is never set up for a room (no Voice of its own), so its
				# answer_age(true) does not turn a mic on: toggle_mic returns at once (后裔 on #715)
				voice_account.call("answer_age", ok)
				close_layer()
				if ok: voice_match.open("solo")
				else: toast(VOICE_PROFILE_NOT_AVAILABLE))
			_open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
			_modal_back = func(): open_profile()
			modal_kind = "age"

## What a Voice Profile tap does for voice's 13+ answer (`ok` / `no` / `unknown`): "open", "refuse" or "ask".
static func voice_profile_step(age: String) -> String:
	return "open" if age == "ok" else ("refuse" if age == "no" else "ask")

func open_age_card() -> void:
	if voice_room == null: return
	var d: UiDrawer = AgeCard.new()
	d.theme = UiKit.theme()
	d.safe_bottom = safe_bottom()
	d.close_requested.connect(close_layer)
	d.connect(&"answered", func(ok: bool):
		close_modal()
		if not ok: toast(VOICE_NOT_AVAILABLE)
		voice_room.call("answer_age", ok))
	_open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	modal_kind = "age"
