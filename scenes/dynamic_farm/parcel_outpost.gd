extends "res://scenes/p0/p0_outpost.gd"
## The dynamic farm's one 3D space (C-115; the owner on C-103#17: "在旧金山放一个固定3D空间入口,形式与交互都参考
## farm-dev"): farm-dev's Travel Post room (its post_office kit, post anchors, door, camera and walking;
## P0Outpost read only) with Jasmine (Market) behind the counter and Scott (Carpenter) where Sam stands. It opens from
## the map's Washington Square pin (town_entry.gd) and runs without the P0 runtime (use_runtime = false): no P0Runtime,
## P0Ui, session, online room or voice. It drives the room itself: the scene touchpad (GestureArbiter, as P0Ui's), the
## world prompts (names only, one open at a time, LOCK-07 v2) and p0_frame.
## Tapping Jasmine or her counter walks to the counter and opens her greeting, Sell her counter (LOCK-16); tapping Scott
## walks to him and opens his greeting (C-59's parcel_town.gd: the same lines, keys, save and commands). The door, or
## Back, returns to the map. Trades go through the player's own parcel save (`store`), as from the map before.
## Lock scope (C-115#9): LOCK-07 and LOCK-16 apply as on the main farm; Scott is no resident (no dialogue bar,
## LOCK-18) and the room holds two roles (LOCK-19 is for the main farm's outposts).

const Town := preload("res://scenes/dynamic_farm/parcel_town.gd")
const Entry := preload("res://scenes/dynamic_farm/town_entry.gd")
## farm-dev's Union Square Travel Post (assets/p0/p0_outposts.json): its kit and anchors. The room's name (its top
## bar) is the map pin's: Washington Square Travel Post since C-115#30.
const OUTPOST_ID := "sh_post_1"
## Who stands at which npc_ anchor, by parcel_town role.
const CAST := {"npc_keeper": Town.MARKET, "npc_sam": Town.CARPENTER}
## The anchors a tap may take: the keeper and the counter (one, LOCK-16), Scott, the door. The kit's Stamp Desk and
## Fare Board are the main farm's (passport, fares) and stay scenery here.
const TAPPABLE := ["npc_keeper", "use_counter", "npc_sam", "exit"]
## The top bar's second line: the city (farm-dev's chip reads `San Francisco · <place>`).
const CITY := "San Francisco"

## store answers read() / send() for the player's parcel (parcel_farm_remote_store.gd or the local stand-in).
var store: RefCounted
var parcel_id := ""
var met_path := Town.MET_PATH
## The parcel save the last greeting saw ({} before one opened): the map reads its own on return.
var farm := {}
var town: Control

var _hud: CanvasLayer
var _pad: Control
var _markers_root: Control
var _town_root: Control
var _top: HBoxContainer
var _tags := {}       # anchor name → UiNpcNameTag
var _icons := {}      # anchor name → UiWorldIconButton
var _bars := {}       # anchor name → UiWorldNameBar
var _pending_pop := false

func setup(args: Dictionary) -> void:
	use_runtime = false
	super.setup({"outpost_id": OUTPOST_ID})
	outpost = outpost.duplicate(true)
	outpost["name"] = Entry.TITLE
	place_name = Entry.TITLE
	outpost["residents"] = []   # nobody else of the main farm's cast (Sigrid, Pip, Sam) stands here
	store = args.get("store") as RefCounted
	parcel_id = str(args.get("parcel_id", ""))
	met_path = str(args.get("met_path", Town.MET_PATH))

func _room_ready() -> void:
	super._room_ready()
	_build_hud()

func _process(dt: float) -> void:
	p0_frame({}, dt)

# ---------------------------------------------------------------- cast
## Jasmine and Scott at their anchors, built as P0Outpost builds its keepers (merged rig, idle, the room's long
## activity distances), in their C-59 looks; the name rides over the head as the kit's NpcNameTag (_markers_frame).
func _spawn_npcs() -> void:
	for n in CAST:
		var spot := anchor(n)
		if spot == null: continue
		var data := Town.npc(str(CAST[n]))
		var root := Node3D.new()
		root.name = "Npc_" + str(data.name)
		spot.add_child(root)
		var rig := Avatar.create_rig()
		rig.assembler = AvatarAssemblerMerged.new()
		rig.rotation.y = PI   # the rig faces +Z; the anchor's yaw is where the NPC faces
		for child in rig.get_children():
			if child is RigActivity:
				child.reduced_distance = 50
				child.sleep_distance = 80
		root.add_child(rig)
		rig.config_applied.connect(func(_c): rig.play_motion("idle"))
		rig.apply_config(OnlineAppearance.config({"version": 1, "slots": data.slots}, true))
		npcs[n] = {"id": str(CAST[n]), "name": str(data.name), "root": root}

func _tappable() -> PackedStringArray:
	var out := PackedStringArray()
	for n in super._tappable():
		if TAPPABLE.has(n): out.append(n)
	return out

## Names only (LOCK-07 v2, q(62)): Jasmine and Scott their names over their heads, the door i-door + Map.
func _marker(n: String, _view: Dictionary) -> Dictionary:
	if npcs.has(n):
		return {kind = "npc", name = str(npcs[n].name), head = (npcs[n].root as Node3D).to_global(NAME_OVER_HEAD),
			talking = is_instance_valid(town) and town.who == str(npcs[n].id)}
	if n == "exit": return {kind = "facility", icon = load("res://assets/p0/icons/door.svg"), name = exit_to}
	return {}

func _on_facility(n: String) -> void:
	if n == "npc_keeper" or n == "use_counter": open_town(Town.MARKET)
	elif npcs.has(n): open_town(str(npcs[n].id))

# ---------------------------------------------------------------- the keepers' greetings (C-59 parcel_town.gd)
## Opens `who`'s greeting over the room; the room stands still under it and the prompts step aside.
func open_town(who: String) -> void:
	if is_instance_valid(town) or _leaving or store == null: return
	p0_joystick(Vector2.ZERO)
	(_pad.get("arb") as GestureArbiter).reset()
	town = Town.open(_town_root, who, store, parcel_id, met_path)
	town.closed.connect(_town_closed.bind(town))

func _town_closed(t: Control) -> void:
	if not t.farm.is_empty(): farm = t.farm.duplicate(true)
	if town == t: town = null

# ---------------------------------------------------------------- leaving
## The door, Back or the top bar's back: the room pops itself and the map comes back (AppRouter).
func leave() -> void:
	if _leaving: return
	super.leave()
	if not _pending_pop:
		_pending_pop = true
		_pop.call_deferred()

func _pop() -> void:
	var router := get_node_or_null("/root/AppRouter")
	if router != null and router.top_instance() == self: router.pop_instance()

## Android Back: an open greeting or counter closes a layer first (as on the map); otherwise farm-dev's rule, the
## player walks out through the door.
func is_back_navigation_locked() -> bool:
	if is_instance_valid(town):
		if not town.stack.back(): town.close()
		return true
	return super.is_back_navigation_locked()

func suspend() -> void:
	super.suspend()
	if _hud: _hud.hide()

func resume() -> void:
	super.resume()
	if _hud: _hud.show()

# ---------------------------------------------------------------- HUD: touchpad, prompts, top bar
func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "RoomHud"
	_hud.layer = 20
	add_child(_hud)
	var root := Control.new()
	root.theme = UiKit.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)
	_pad = TouchPad.new()
	_pad.name = "TouchPad"
	_pad.set("room", self)
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_pad)
	_markers_root = Control.new()
	_markers_root.name = "Prompts"
	_markers_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_markers_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_markers_root)
	_top = _top_bar()
	root.add_child(_top)
	_town_root = Control.new()
	_town_root.name = "Keepers"
	_town_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_town_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_town_root)

## The dynamic farm's top bar (as on the parcel, C-74): the 44 round back of ProfileTopBar and a surface chip with the
## place's name over the city, at the HUD's place.
func _top_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.name = "TopBar"
	bar.add_theme_constant_override(&"separation", UiTokens.SPACE_WITHIN)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = UiTokens.SIZE_TODAY_PANEL_X
	bar.offset_right = -UiTokens.SIZE_TODAY_PANEL_X
	bar.offset_top = UiTokens.SIZE_HUD_TOP + _safe_top()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := UiProfileTopBar._Round.new(UiProfileTopBar._Round.Glyph.BACK)
	back.name = "Back"
	back.tooltip_text = "Back"
	back.pressed.connect(func(): if not is_instance_valid(town): leave())
	bar.add_child(back)
	var chip := PanelContainer.new()
	chip.name = "Place"
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CHIP,
		UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT).with_margins(12, 5, 12, 6))
	bar.add_child(chip)
	var labels := VBoxContainer.new()
	labels.add_theme_constant_override(&"separation", 0)
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(labels)
	var title := UiKit.label(place_name, UiTokens.STYLE_C14_XB)
	title.name = "Title"
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	labels.add_child(title)
	var city := UiKit.label(CITY, UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	city.name = "City"
	labels.add_child(city)
	return bar

func _room_frame(view: Dictionary, dt: float) -> void:
	super._room_frame(view, dt)
	if _markers_root != null: _markers_frame()

## The world prompts as P0Ui draws them for a room (P0Room._markers): an NPC's name over the head, highlighted while it
## is the one in reach; the door's i-door button, opened into its `Map` strip while it is the one in reach. While a
## greeting is up none show (P0Ui hides markers under a modal).
func _markers_frame() -> void:
	var marks := {}
	if not is_instance_valid(town):
		for n in _tappable():
			var m := _marker(n, {})
			if not m.is_empty(): marks[n] = m
	var open := card_pick(marks) if not marks.is_empty() else ""
	var area := Rect2(Vector2.ZERO, _view())
	for n in marks:
		var m: Dictionary = marks[n]
		if str(m.kind) == "npc":
			var tag: UiNpcNameTag = _tags.get(n)
			if tag == null:
				tag = UiNpcNameTag.new()
				tag.name = "Tag_" + n
				_markers_root.add_child(tag)
				_tags[n] = tag
			var head := cam.unproject_position(m.head)
			tag.visible = area.has_point(head)
			tag.text = str(m.name)
			tag.highlight = n == open
			tag.place_over(head)
			continue
		var at := _prompt_point(n)
		var bar: UiWorldNameBar = _bars.get(n)
		var icon: UiWorldIconButton = _icons.get(n)
		if icon == null:
			icon = UiWorldIconButton.new()
			icon.name = "Icon_" + n
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_markers_root.add_child(icon)
			_icons[n] = icon
			bar = UiWorldNameBar.new()
			bar.name = "Strip_" + n
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.visible = false
			_markers_root.add_child(bar)
			_bars[n] = bar
		icon.icon = m.icon
		icon.place_at(at)
		var on := area.has_point(at)
		if n == open and on:
			bar.icon = m.icon
			bar.text = str(m.name)
			bar.anchor_at(at)
			if not bar.visible:
				bar.set_openness(0.0)
				bar.visible = true
				bar.expand()
			icon.visible = false
		else:
			bar.visible = false
			icon.visible = on
	for n in _tags: if not marks.has(n): (_tags[n] as Control).visible = false
	for n in _icons:
		if not marks.has(n):
			(_icons[n] as Control).visible = false
			(_bars[n] as Control).visible = false

## Where a facility's prompt sits on screen: its badge_ point (the door's over the threshold), else over its anchor.
func _prompt_point(n: String) -> Vector2:
	var obj := P0RoomAnchors.object_of(n)
	var badge := anchor("badge_" + (obj if obj != "" else n))
	return cam.unproject_position(badge.global_position if badge else anchor(n).global_position + _hit_lift(n) * 1.1)

## The prompt under a screen point (a name tag or the door's button / strip), as P0Ui._tap_at reads them; "".
func prompt_at(screen: Vector2) -> String:
	for n in _bars: if (_bars[n] as Control).visible and (_bars[n] as UiWorldNameBar).hit_rect().has_point(screen): return n
	for n in _icons: if (_icons[n] as Control).visible and (_icons[n] as UiWorldIconButton).hit_rect().has_point(screen): return n
	for n in _tags: if (_tags[n] as Control).visible and (_tags[n] as UiNpcNameTag).hit_rect().has_point(screen): return n
	return ""

## A tap on the scene (P0Ui._tap_at for a room): a prompt walks to its own anchor; a double tap recenters; anything
## else is the room's own tap (P0Room.pick: the nearest facility to the point). Returns whether something was hit.
func tap_scene(screen: Vector2, double := false) -> bool:
	if is_instance_valid(town) or _leaving: return false
	var n := prompt_at(screen)
	if n == "": n = pick(screen)
	if n != "":
		walk_to(n)
		return true
	if double: p0_recenter()
	return false

## The scene band (P0Ui._TouchPad, read only): a press-and-drag is the floating joystick, a short tap picks, a double
## tap recenters, two fingers pinch; GestureArbiter keeps farm-dev's thresholds.
class TouchPad extends Control:
	var room: Node
	var arb := GestureArbiter.new(GestureArbiter.Mode.SCENE)
	func _ready() -> void: mouse_filter = Control.MOUSE_FILTER_STOP
	func _notification(what: int) -> void:
		if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
			var pinching := arb.is_pinching()
			arb.reset()
			queue_redraw()
			if room != null:
				room.p0_joystick(Vector2.ZERO)
				if pinching: room.p0_zoom_end()
	func _gui_input(e: InputEvent) -> void:
		if room == null: return
		if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			room.p0_zoom(0.9 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1, get_global_transform_with_canvas() * e.position)
			room.p0_zoom_end()
			return
		for o in arb.feed(e, Time.get_ticks_msec()):
			match o.kind:
				&"joystick_move":
					room.p0_joystick(o.vector)
					queue_redraw()
				&"joystick_end":
					room.p0_joystick(Vector2.ZERO)
					queue_redraw()
				&"tap":
					if room.tap_scene(get_global_transform() * o.pos, bool(o.double)): arb.consume_tap()
				&"pinch": room.p0_zoom(o.factor, get_global_transform_with_canvas() * o.center)
				&"pinch_end": room.p0_zoom_end()
	func _draw() -> void:
		var start := arb.origin()
		var now := arb.position()
		if not arb.is_steering() or now.distance_to(start) < GestureArbiter.TAP_SLOP: return
		var radius := arb.stick_radius
		draw_circle(start, radius, Color(1, 1, 1, 0.35))
		draw_arc(start, radius, 0, TAU, 48, Color(0.37, 0.66, 0.35, 0.7), 2.0)
		var k := start + ((now - start).limit_length(radius))
		draw_circle(k, radius * 0.45, Color(0.98, 0.97, 0.94, 0.95))
		draw_circle(k, radius * 0.3, Color(0.5, 0.78, 0.42))
