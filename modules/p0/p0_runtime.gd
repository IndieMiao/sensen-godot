class_name P0Runtime
extends Node
## Lives under the root for the whole P0 session: one P0Session and one P0Ui shared by every P0 world
## (homestead farm, map ponds, interior rooms). Worlds only draw, move and pick targets; the runtime
## routes UI input to the active world and turns server events into floats, cards and toasts, so the
## new UI flow is identical everywhere.
##
## A world implements (all optional; interiors extend P0Room): p0_surface() -> String, p0_space() -> String
## (where the player is for the server: home / pond / outpost / mine; see space_of), p0_place() -> String (the
## catalog pond id inside a pond space), p0_frame(view, dt), p0_joystick(v),
## p0_tap(screen), p0_action(cmd), p0_event(ev, view), p0_anchor() -> Vector2, p0_zoom(f, at), p0_zoom_end(),
## p0_recenter(), p0_show_spot(where), p0_energy_verb() -> String, p0_near_resident() -> String, p0_dev(step) -> bool,
## p0_until(name) -> bool.

const HomePanel = preload("res://scenes/p0/home/p0_home_panel.gd")
const MAP_SCENE := "res://scenes/p0/p0_map.tscn"
const HOME_PLACE := "Shanghai · Homestead"   # the farm's place chip (p0_farm PLACE)

static var _instance: P0Runtime

var session: P0Session
var ui: P0Ui
var world: Node
var _shot_t := 0.0
var _shot_script: Array = []
## XP / reward lines of the last state change, for worlds that show results themselves (the fishing panel).
var last_xp_lines: Array = []
## First-catch bonus of the last state change (FISH-3 gold chip); 0 when the species was caught before.
var last_first_catch_xp := 0
var last_catch_extras := {}   # the same response's New city XP and first-fish Energy, for the Caught! card
## What to do once the map is back on top (FISH-4 Go home, FISH-5 Tackle Shop): "farm" / "tackle".
var after_leave := ""
## True only while the farm's hold-to-repeat sends its next command (§14.2): the observation log's "hold" (S7).
## The press itself, even with the key still down, is a tap (刘邦, PR #23 review).
var holding_repeat := false
var _held_plants := 0   # plants harvested in the current hold (E-04's `Harvest 12 of 30 · bag full`)
# Network state (SGODOT-233, §10.7.1, WP6): one failed request → `Didn't go through · try again` for 3 s; a second in a
# row → Offline (`Offline · Reconnecting…`, Retry, the keys read Offline) with a check every PROBE_S; the first answer
# after that → `Back online` for 1.5 s. Any answer clears the count.
const PROBE_S := 5.0
const CMD_FAIL_S := 3.0
const BACK_ONLINE_S := 1.5
var _net_fails := 0
var _probe_left := 0.0

## Load timing (logcat tag godot, "P0_TIMING"): navigation start → world _ready → first drawn frame.
static var _nav_ms := 0
static func nav_started() -> void:
	_nav_ms = Time.get_ticks_msec()
static func mark(tag: String) -> void:
	print("P0_TIMING %s +%d ms" % [tag, Time.get_ticks_msec() - _nav_ms])

static func ensure() -> P0Runtime:
	if is_instance_valid(_instance): return _instance
	_instance = P0Runtime.new()
	_instance.name = "P0Runtime"
	(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_instance)
	return _instance

func src_of_press() -> String: return "hold" if holding_repeat else "tap"

func _init() -> void:
	# App copy is English-only (user rule 2026-09-04); reused old panels translate through L10n, so pin the locale.
	TranslationServer.set_locale("en")
	session = P0Session.new()
	add_child(session)
	ui = P0Ui.new()
	add_child(ui)
	ui.joystick.connect(func(v): _call("p0_joystick", [v]))
	ui.tapped.connect(func(p): _call("p0_tap", [p]))
	ui.action_pressed.connect(_on_action)
	ui.command.connect(func(cmd): session.send(cmd, P0Session.ui_key(cmd)))   # panel buttons: one submit per result
	# Observation log (S7): only the commands the farm's hold-to-repeat sends are holds; every press is a tap.
	session.src_of = src_of_press
	ui.dev_skip.connect(func(m): session.dev_skip(m); ui.toast("Clock +%dh (dev)" % (m / 60)))
	ui.zoom.connect(func(f: float, at: Vector2): _call("p0_zoom", [f, at]))
	ui.zoom_end.connect(func(): _call("p0_zoom_end", []))
	ui.recenter.connect(func(): _call("p0_recenter", []))
	ui.show_spot.connect(_show_spot)
	ui.show_on_map.connect(_show_on_map)
	ui.can_show_spot = func() -> bool: return is_instance_valid(world) and world.has_method("p0_show_spot")
	ui.near_resident = func() -> String:   # an outpost's resident within reach (Gift to <Name>, SGODOT-225)
		return str(world.call("p0_near_resident")) if is_instance_valid(world) and world.has_method("p0_near_resident") else ""
	ui.home_choice.connect(func(choice: String): _call("p0_home", [choice]))
	ui.place_pressed.connect(_on_place_pressed)
	ui.home_requested.connect(func(): _leave_then("farm"))
	ui.tackle_requested.connect(func(): _leave_then("tackle"))
	session.state_changed.connect(func(_v, _e): _net_ok())   # any answer ends a run of failures (and offline)
	session.state_changed.connect(_on_state)
	# U6: doing what the TipCard on screen teaches closes it (sow / cast / cook / heat are command types).
	session.sent.connect(func(cmd: Dictionary): ui.tip_did(str(cmd.get("type", ""))))
	session.refused.connect(func(_c, _d, _cmd): _net_ok())
	session.refused.connect(_on_refused)
	session.connection_failed.connect(func(msg: String, cmd: Dictionary):
		_net_failed(msg, cmd)
		if str(cmd.get("type", "")).begins_with("claim_parcel"): ui.inbox_claim_done()
		# A world action that did not go through ends the hold: no more sowing along the row on a dead line; the
		# player presses again (§10.7.1). Nothing was taken locally — the server's state is what the scene shows.
		if not cmd.is_empty(): ui.fab_held = false
		# The world may be waiting on that command (a cast in flight): let it recover.
		if not cmd.is_empty(): _call("p0_event", [{"kind": "send_failed", "cmd": cmd}, session.current()]))
	ui.sys_retry.connect(_probe)
	session.blocked.connect(_on_blocked)
	ui.screen_action.connect(_on_screen_action)
	ui.screen_back.connect(_on_screen_back)
	ui.lifecycle.watch(session)
	session.command_started.connect(ui.track_pressed)
	if OS.get_environment("P0_AUTO") == "1" or FileAccess.file_exists("user://p0_auto"):
		P0Fishing.auto_play = true
		P0Cooking.auto_play = true
		P0Kitchen.auto_play = true

## The active world takes over input and the HUD surface; the previous one is simply forgotten.
func attach(w: Node) -> void:
	# The world being left stops where it is, and the stick ends: no walking on underneath (int5 hand test 035–039).
	if is_instance_valid(world) and world != w: _call("p0_joystick", [Vector2.ZERO])
	ui.end_stick()
	world = w
	session.space = space_of(w)   # before the read below, which tells the server where the player is
	if session.space != "map": return_to = route_of(w)
	# On the map the chip still names where the player is; the farmhouse and the mine are the homestead (MAP-1).
	elif return_to == "farm": ui.set_place(HOME_PLACE)
	ui.space = session.space
	session.place = str(w.call("p0_place")) if w.has_method("p0_place") else ""   # which pond (q(36))
	if not session.busy and not session.view.is_empty(): session.refresh()   # entering a space reads fresh state
	mark("attach " + str(w.name))
	if _spot_after_room != "" and w.has_method("p0_show_spot"):   # stepped out of the farmhouse to show a farm spot
		w.call_deferred("p0_show_spot", _spot_after_room)
		_spot_after_room = ""
	_first_frame.call_deferred(str(w.name))
	ui.set_surface(str(w.call("p0_surface")) if w.has_method("p0_surface") else "farm")
	if w.has_method("p0_surface") and str(w.call("p0_surface")) == "map": ui.teach("map")   # Browse the map for free…
	_end_launch()   # the first answer may have come before the first world
	_begin_arrival(w)

## The space a world puts the player in, for the server (q(41)): its p0_space() when it has one (the farmhouse
## says home, outposts say outpost), else from its surface — farm is home, pond and map as named, anything else
## unknown (""), which the server ignores. Read once on attach, never from the per-frame surface ("busy").
static func space_of(w: Object) -> String:
	if w.has_method("p0_space"): return str(w.call("p0_space"))
	var surface := str(w.call("p0_surface")) if w.has_method("p0_surface") else "farm"
	return str({"farm": "home", "pond": "pond", "map": "map"}.get(surface, ""))

func _first_frame(tag: String) -> void:
	await RenderingServer.frame_post_draw
	mark("first frame " + tag)
	await RenderingServer.frame_post_draw
	mark("second frame " + tag)

func detach(w: Node) -> void:
	if world == w:
		_call("p0_joystick", [Vector2.ZERO])
		ui.end_stick()
		world = null
		ui.close_modal()
		ui.set_surface("map")
		session.space = "map"
		ui.space = "map"
		session.place = ""

## Back to the map (the place chip, LOCK-06): every P0 world stacked above it closes, the farm under the
## farmhouse included. Back locks still apply (a line in the water is reeled in first); a room's own Back
## (walking out through the door) is not one of them.
func leave_world() -> void:
	if not is_instance_valid(world): return
	if AppRouter.instance_depth() > 0 and AppRouter.top_instance() != world: return
	if not (world is P0Room) and AppRouter.scene_locks_back_navigation(world): return
	leave_to_map()

## Pop every P0 layer down to the map; a world booted as the root scene (the first session lands on the farm,
## p0_boot q(44)) has no map under it, so the root is swapped for the map. No back locks are asked here.
func leave_to_map() -> void:
	while AppRouter.instance_depth() > 0:
		var depth := AppRouter.instance_depth()
		AppRouter.pop_instance()
		if AppRouter.instance_depth() >= depth: return   # a locked layer (a committed relocation map) stays
	var root := get_tree().current_scene
	if root == null or root.scene_file_path != MAP_SCENE: swap_root.call()

## The scene change behind leave_to_map (tests replace it).
var swap_root := func(): get_tree().change_scene_to_file(MAP_SCENE)

## Android Back for a world with its own back lock (farm, pond), after its own layers: AppRouter ignores Back on a
## P0 world that is the root scene, so with nothing left to close such a world leaves for the map itself (int5b
## hand test 2: Inbox closed on the first Back, the second did nothing). True when it handled Back.
func root_back() -> bool:
	if not leaves_itself(AppRouter.instance_depth(), _root_is_map()): return false   # AppRouter pops it
	leave_to_map()
	return true

## Whether Back with nothing left to close must take a world to the map itself: a root world (no map under it,
## p0_boot q(44)), or one stacked on a root that is not the map — the dev entry pond:<id> pushes the pond on the
## empty p0_boot, and popping it would leave a blank screen (刘邦 on #40). Stacked on the map: AppRouter pops it.
static func leaves_itself(depth: int, root_is_map: bool) -> bool:
	return depth == 0 or (depth == 1 and not root_is_map)

func _root_is_map() -> bool:
	var root := get_tree().current_scene if is_inside_tree() else null
	return root != null and root.scene_file_path == MAP_SCENE

## Show (LOCK-08, the camera only). In the farmhouse a farm target (plots, stall, bench …) steps out to the farm first,
## which shows it once it is back (attach); the stove and the room's own spots show in the room (亚瑟 on #37).
var _spot_after_room := ""

func _show_spot(where: String) -> void:
	if world is P0Room and session.space == "home" and not bool(_call("p0_has_spot", [where])):
		# Only when the farmhouse really steps out (it is on top); else nothing waits to jump the camera later (亚瑟 on #37).
		if AppRouter.top_instance() != world: return
		_spot_after_room = where
		leave_room()
		return
	_call("p0_show_spot", [where])

## Show on map: from a world, back to the map, which points at the pin on resume (p0_map.show_place); on the map
## itself the map points at it at once (蒙恬 on #44).
func _show_on_map(target: String) -> void:
	if is_instance_valid(world) and world.has_method("show_place"):
		world.call("show_place", target)
		return
	_leave_then("show:" + target)

## One level back, for a room's door: the farm under the farmhouse, the map under an outpost.
## Leaving a room (the farmhouse, an outpost): back to the world under it. One pushed straight onto the empty p0_boot
## (the dev entry outpost:<id>) has only a blank screen under it: it leaves for the map instead (李元芳 int8).
func leave_room() -> void:
	if not (is_instance_valid(world) and AppRouter.top_instance() == world): return
	if room_leaves_for_map(AppRouter.instance_depth(), _root_is_world()): leave_to_map()
	else: AppRouter.pop_instance()

## Whether leaving a room must go to the map: it is the only layer, on a root that is no world (the empty p0_boot).
## Over the farm root (the first session's farmhouse) or over the map it just pops.
static func room_leaves_for_map(depth: int, root_is_world: bool) -> bool:
	return depth <= 1 and not root_is_world

func _root_is_world() -> bool:
	var root := get_tree().current_scene if is_inside_tree() else null
	return root != null and root.has_method("p0_surface")

## Where the player is while the map is up (MAP-1, §10.6.1): the place chip keeps naming it, and a tap on the chip
## goes back there. Set by every world but the map: "farm" for the farm, its farmhouse and the mine (they are the
## homestead), "pond:<id>", "outpost:<id>".
var return_to := "farm"

## The route back to world `w` from the map, as return_to holds it.
static func route_of(w: Object) -> String:
	match space_of(w):
		"pond": return "pond:" + (str(w.call("p0_place")) if w.has_method("p0_place") else "")
		"outpost":
			var o = w.get("outpost")
			return "outpost:" + (str((o as Dictionary).get("id", "")) if o is Dictionary else "")
	return "farm"

## The location chip: from a world, to the map; on the map, back to where the player is (MAP-1).
func _on_place_pressed() -> void:
	if is_instance_valid(world) and str(_call("p0_surface", [])) == "map": _call("p0_return", [return_to])
	else: leave_world()

## Back to the map, then on to the homestead or Old Kai's pin (the map reads after_leave on resume).
func _leave_then(next: String) -> void:
	after_leave = next
	leave_world()

func _call(method: String, args: Array):
	if is_instance_valid(world) and world.has_method(method): return world.callv(method, args)
	return null

func _enter_tree() -> void:
	AppRouter.loading_overlay_factory = _scene_overlay   # SYS-LOADING-SCENE for the P0 worlds AppRouter opens

func _exit_tree() -> void:
	if AppRouter.loading_overlay_factory == Callable(self, &"_scene_overlay"): AppRouter.loading_overlay_factory = Callable()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED: _on_resumed()

func _process(dt: float) -> void:
	_dev_shot(dt)
	_tick_screens(dt)
	if ui.offline:
		_probe_left -= dt
		if _probe_left <= 0.0: _probe()
	var v := session.current()
	if v.is_empty(): return
	ui.set_view(v)
	_call("p0_frame", [v, dt])

func _on_action(cmd: Dictionary) -> void:
	if str(cmd.get("type", "")) == "energy_card":
		var verb = _call("p0_energy_verb", [])
		ui.open_energy_card(int(ui.fab_state().get("need", 0)), str(verb) if verb != null else str(ui.fab_state().get("verb", "")))
		session.report({"kind": "energy_card", "need": int(ui.fab_state().get("need", 0))})
		return
	if not cmd.is_empty(): _call("p0_action", [cmd])

func anchor() -> Vector2:
	var at = _call("p0_anchor", [])
	return at if at is Vector2 else get_viewport().get_visible_rect().size * Vector2(0.5, 0.42)

# ---------------------------------------------------------------- server results
func _on_state(v: Dictionary, events: Array) -> void:
	var before: Dictionary = ui.view
	ui.set_view(v)   # cards built below read the fresh view (Fish-dex, creel, meals)
	for ev in events: ui.teach(P0Guide.tip_for_event(ev, before, v))   # first cast / fire / meal / level (TUT-2)
	# §14.2 minutes 16 / 22: an item new to the bag (lettuce seeds in reach, a level gift's Worm Bait) flashes its
	# quick-bar slot once (UiQuickBar.flash: QuickSlot State=new, 600 ms). Not on the first view after starting.
	if not before.is_empty():
		for id in P0Guide.new_items(before, v): ui.quick_bar_node().flash(str(id))
	var at := anchor()
	# A claim in the Inbox (SGODOT-234): what came out floats from the button pressed, even seeds, dishes and fish (the
	# Bag slot is under the drawer). Only the reply that brings items: a state push before it leaves the spot waiting.
	var claimed := ui.inbox_float_at().is_finite() and events.any(func(e): return str(e.get("kind", "")) == "item" and int(e.get("delta", 0)) > 0)
	if claimed:
		at = ui.inbox_float_at()
		ui.inbox_claim_done()
	var floats: Array = []   # this reply's float parts: one float_lines call orders, merges and caps them (q(49) ①)
	var xp_lines: Array = []
	last_first_catch_xp = 0
	last_catch_extras = {}
	var settles_catch := events.any(func(e): return str(e.get("kind", "")) == "catch")
	# A first's bonus XP is said by its own line, not added into the XP float: the first cook's and catch's on their
	# card's strip (Li Bai, int6 C11), the first harvest's as `First harvest! +10 XP · Radish` (§4.8.6).
	var first_cook_xp: Array = []
	# A harvest reply's XP counts its plants, so a held harvest reads `+40 XP · 20 plants` (§4.8.3).
	var plants := events.filter(func(e): return str(e.get("kind", "")) == "item" and str(e.get("id", "")).begins_with("crop_") \
		and int(e.get("delta", 0)) > 0).size()
	if plants > 0: _held_plants = (_held_plants if ui.fab_held else 0) + plants
	var good_pot := events.any(func(e): return str(e.get("kind", "")) == "dish" and int(e.get("quality", 0)) >= 1)
	# A craft's output is said by the workbench (`+2 Torch` on its card, the pickaxe's Moment; SGODOT-231 B2-06).
	var crafted := events.any(func(e): return str(e.get("kind", "")) == "craft")
	for i in events.size():
		var ev: Dictionary = events[i]
		match str(ev.get("kind", "")):
			"xp":
				# The server emits a first-time bonus as `first` immediately followed by its `xp`.
				var bonus: bool = i > 0 and str(events[i - 1].get("kind", "")) == "first" and int(events[i - 1].xp) == int(ev.amount)
				var what := str(events[i - 1].get("what", "")) if bonus else ""
				if bonus and (str(ev.skill) == "cooking" or what.begins_with("catch:") or what.begins_with("harvest:")):
					first_cook_xp.append(ev)
				if what.begins_with("harvest:"):
					var crop := what.trim_prefix("harvest:")
					floats.append({kind = "first", key = what, text = "First harvest! +%d XP · %s" % [int(ev.amount),
						P0Logic.item_name(v, crop)], tone = UiFloatText.Tone.XP})
				if int(ev.amount) > 0 and not bonus:
					xp_lines.append("+%d %s XP" % [int(ev.amount), str(ev.skill).capitalize()] + ("" if int(ev.percent) >= 100 else " · %d%%" % int(ev.percent)))
			"reward":
				if int(ev.energy) > 0: xp_lines.append(P0Logic.reward_line(str(ev.id), int(ev.energy)))
				if str(ev.id).begins_with("first_fish_"): last_catch_extras["energy"] = int(ev.energy)
			"first":
				var what := str(ev.what)
				if what.begins_with("catch:"):
					xp_lines.append("First catch! +%d XP" % int(ev.xp))
					last_first_catch_xp = int(ev.xp)
				elif what.begins_with("cook:"): xp_lines.append("New recipe! · First cooked · +%d Cooking XP" % int(ev.xp))
				elif what == "landed": xp_lines.append("First fish landed · +%d XP" % int(ev.xp))
				elif what == "cast": xp_lines.append("First cast · +%d XP" % int(ev.xp))
				elif what.begins_with("fishing_city:"):
					xp_lines.append("First catch in %s · +%d XP" % [what.trim_prefix("fishing_city:").capitalize(), int(ev.xp)])
					last_catch_extras["city_xp"] = int(ev.xp)
	last_xp_lines = xp_lines
	var parcels_said := false
	var first_level := not before.is_empty() and ["farming", "fishing", "cooking"].all(func(k):
		return int(before.get("skills", {}).get(k, {}).get("level", 1)) <= 1)
	for ev in events:
		match str(ev.get("kind", "")):
			"energy":
				var dlt := int(ev.delta)
				# A catch's refund is said by its own float or card ("3 Energy back"), not twice.
				if settles_catch and str(ev.get("reason", "")) in ["refund", "line_in"]: continue
				# Inside the mine a floor fee is said by the mine's own float ("Floor 2 · −2 Energy", q(46)), not twice.
				if str(ev.get("reason", "")) == "mine_floor" and str(_call("p0_surface", [])) == "mine": continue
				floats.append({kind = "energy", key = "energy", amount = dlt, fmt = "%s Energy"})
			"xp":
				if int(ev.amount) > 0 and not first_cook_xp.any(func(x): return is_same(x, ev)):
					# A pot's own XP names its track and a Good / Perfect pot's star: +5 Cooking XP ★ (§4.8.6 / §7.2.2).
					var cook := str(ev.skill) == "cooking"
					var fmt := ("%s Cooking XP" + (" ★" if good_pot else "")) if cook else "%s XP"
					fmt += "" if int(ev.percent) >= 100 else " · %d%%%%" % int(ev.percent)
					var part := {kind = "xp", key = fmt, amount = int(ev.amount), fmt = fmt, tone = UiFloatText.Tone.XP}
					if plants > 0 and str(ev.skill) == "farming": part.merge({unit = "plants", count = plants})
					floats.append(part)
			"item":
				var iid := str(ev.id)
				if iid.begins_with("dish_"): _call("p0_event", [ev, v])   # where a collected dish went (the kitchen's Keep toast)
				if int(ev.delta) > 0 and (claimed or (not crafted and not iid.begins_with("seed_") and not iid.begins_with("dish_") and not iid.begins_with("fish_"))):
					floats.append({kind = "item", key = iid, amount = int(ev.delta), fmt = "%s " + P0Logic.item_name(v, iid),
						tone = UiFloatText.Tone.ITEM, icon = P0Logic.icon(iid)})
			"coins":
				# A request delivered from the counter drawer: its row floats the coins from its button (BOARD-DONE).
				if ui.modal_kind == "counter" and events.any(func(e): return str(e.get("kind", "")) == "request" and str(e.get("status", "")) == "done"): continue
				floats.append({kind = "coins", key = "coins", amount = int(ev.delta), fmt = "%s coins", tone = UiFloatText.Tone.COINS})
			"parcel":
				# LOCK-14: rewards that did not fit the bag wait in the Inbox; one float for the whole reply.
				if not parcels_said:
					parcels_said = true
					var line := P0Logic.parcel_toast(v, events)
					if line != "": ui.toast(line, 2.0)
			"catch":
				# A world that shows the catch itself (the open fishing panel) returns true.
				if not bool(_call("p0_event", [ev, v])): _on_catch(ev, xp_lines)
			"cast", "pot", "cabinet", "plate", "first", "mishap", "queue":
				_call("p0_event", [ev, v])
			"dish":
				# The farmhouse stove shows its own result card (COOK-4 / 6 / P0-9). Anywhere else no card pops up
				# (§7.2.7 step 7, q(46)): a pot kept on its own (Queue ×2) or a collect answered after leaving only
				# says where the dish went. A world without p0_event (farm, map, outpost) gives null, so compare
				# instead of bool() (PR #54 review).
				if _call("p0_event", [ev, v]) != true:
					var kept := P0KitchenLogic.kept_line(v, ev, events)
					if not kept.is_empty(): ui.toast(str(kept.text))
			"request":
				match str(ev.status):
					"accepted": ui.toast("Tracking · it shows in Today")
					"dropped": ui.board_dropped(str(ev.get("id", "")))   # BOARD-DROPPED says what dropping left
					_:   # in the counter drawer the row itself turns Done (BOARD-DONE, no result card)
						if ui.modal_kind != "counter": ui.toast_success("Request complete · +%d coins" % int(ev.coins))
			"meal":
				if int(ev.gain) <= 0:
					ui.toast("Full belly · Meals reset in " + P0Logic.duration(float(v.get("meals", {}).get("resets_in", 0))) if int(ev.counted) <= 0 and int(ev.nominal) > 0 else "Same dish · no Energy today")
				else:
					ui.toast("+%d Energy · Meals today %d/%d" % [int(ev.gain), int(ev.meals), int(ev.cap)])
			"level":
				var lv: Dictionary = ev
				# Deferred, so a result card the same reply opens (the kitchen's COOK-4, itself deferred until the
				# whole reply is in) comes first and the level-up queues behind it (C16; PR #54 review).
				# The account's first level-up (no track above Lv1 before this reply) gets the teaching banner (§4.8.3).
				var first := first_level
				first_level = false
				ui.queue_card.call_deferred(func(): ui.show_level_up(lv, first))
				session.report({"kind": "level_banner", "skill": str(lv.skill), "level": int(lv.level)})
			"affinity":   # SGODOT-225 / 228: first chat of the day, gifts, requests
				var reply := P0Logic.resident_reply(str(ev.get("resident", "")), str(ev.get("verdict", "")))
				# On the resident's open bar: the Affinity pill over it and the answer in the bubble (RES-KAI-TALK).
				if not ui.resident_affinity(ev, reply):
					if int(ev.get("delta", 0)) != 0:
						floats.append({kind = "affinity", key = str(ev.get("resident", "")), text = P0Ui.affinity_text(ev),
							tone = UiFloatText.Tone.AFFINITY})   # the tone draws the heart
					if reply != "": ui.toast(reply)
			"gift_meal":
				var who := str(P0Logic.content().get("residents", {}).get(str(ev.get("resident", "")), {}).get("name", ""))
				# SGODOT-232: with the bag full the meal waits in the Inbox (to: parcel), gone at 04:00 like any gift meal.
				if str(ev.get("to", "")) == "parcel": ui.toast("Bag full · %s's meal sent to Inbox" % who)
				elif bool(ev.get("given", false)): ui.toast_success("%s gave you %s · in your bag" % [who, P0Logic.item_name(v, str(ev.get("dish", "")))])
			"homestead":
				# HOME-2 (SGODOT-228): HOME-1 closes, the MomentBanner says what changed; the farm swaps the fence.
				if ui.modal_kind == "homestead": ui.close_modal()
				var home := P0Logic.home_moment(v, ev)
				ui.queue_card(func(): HomePanel.moment(ui, home))   # one moment at a time (q(49) ④)
	ui.queue_floats(floats, at)   # with the world's own lines of this reply, at the end of the frame
	if ui.modal_kind == "counter" and events.size() > 0:
		ui.set_view(session.current())   # the counter drawer follows the view; floats say what changed
		ui.counter_events(events)
	elif ui.modal_kind == "resident" and events.size() > 0:
		ui.set_view(session.current())
		ui.open_resident(ui._resident)   # affinity, gift and request states follow the reply

## FISH-3 / FISH-5 (§6.6, 16 · FISH-2 → 3 / 5): the first catch of a species gets the catch card, later
## ones a float; a gate break-free gets the four-line card once per species, then "Got away · Lv4";
## a plain escape is a float ("It got away · 3 Energy back", or the protection wording). `at` is where
## floats rise (the cast point when the pond knows it).
func _on_catch(ev: Dictionary, _xp_lines: Array, at := Vector2.INF) -> void:
	var where := at if at.is_finite() else anchor()
	var v := session.current()
	match str(ev.result):
		"landed":
			var fid := str(ev.fish)
			var r := int(ev.rarity)
			if last_first_catch_xp > 0:
				var first := last_first_catch_xp
				var extras := last_catch_extras.duplicate()
				ui.queue_card(func(): ui.show_catch(fid, r, first, extras))
			else:   # a repeat species: no card, `Pond Crucian ×1` beside its +XP (§4.8.6)
				ui.float_text("%s ×1" % P0Logic.item_name(v, fid), where, UiFloatText.Tone.ITEM, P0Logic.icon(fid))
		"broke_free":
			var gone: Dictionary = ev
			if ui.first_time("gotaway:" + str(ev.fish)):
				ui.queue_card(func(): ui.show_got_away(gone))
				session.report({"kind": "card_shown", "card": "got_away", "fish": str(gone.get("fish", ""))})
			else:   # second time on: `Got away · Lv4 · Energy refunded (8 left today)` / `Got away · Reed Rod · 3 Energy back` (q(50))
				var rod := P0Logic.rod_for(v, int(ev.get("rarity", 2)))
				var what := ("Lv%d" % int(ev.need_level)) if ev.has("need_level") else (str(rod.name) if not rod.is_empty() else "rod too light")
				ui.float_text("Got away · %s · %s" % [what, P0Logic.refund_line(v, ev).trim_prefix("+")], where, UiFloatText.Tone.ENERGY_GAIN)
		"escaped":
			ui.float_text("It got away · " + P0Logic.refund_line(v, ev).trim_prefix("+"), where, UiFloatText.Tone.ENERGY_GAIN)
		"cancelled":
			ui.toast("Line in · Energy back")

func _on_refused(code: String, detail: Dictionary, cmd: Dictionary) -> void:
	if str(cmd.get("type", "")).begins_with("claim_parcel"): ui.inbox_claim_done()   # no items come: none float from it (亚瑟 on #93)
	# The farmhouse kitchen waits on cook / collect (its Cook buttons, the plate being served): let it recover.
	if str(cmd.get("type", "")) in ["cook", "collect"]: _call("p0_event", [{"kind": "refused", "code": code, "cmd": cmd}, session.view])
	if str(cmd.get("type", "")) == "cast": _call("p0_event", [{"kind": "cast_refused", "code": code}, session.view])
	if code == "bag_full" and str(cmd.get("type", "")) == "reel":
		_call("p0_event", [{"kind": "fish_abort"}, session.view])
		session.send({"type": "reel", "outcome": "escaped"})
		ui.toast_error("Creel full · the fish slipped away")
		return
	# Mine and gathering refusals (SGODOT-231): races stay quiet, the rest say why in their own words.
	var said = P0MaterialLogic.refusal_text(code, detail, cmd)
	if said != null:
		if str(said) != "": ui.toast_error(str(said))
		return
	match code:
		"need_energy":
			ui.open_energy_card(int(detail.get("need", 0)), "Cast" if str(cmd.get("type", "")) == "cast" else P0MaterialLogic.energy_verb(cmd, "Sow ×1"))
			session.report({"kind": "energy_card", "need": int(detail.get("need", 0)), "refused": str(cmd.get("type", ""))})
		"locked":
			ui.toast_error("%s Lv%d · %d XP to go" % [str(detail.get("skill", "farming")).capitalize(), int(detail.get("level", 2)), int(detail.get("xp_to_go", 0))])
		"no_coins":
			ui.toast_error("Need %d more coins" % int(detail.get("need", 0)))
		"bag_full":
			if str(cmd.get("type", "")) == "harvest": _harvest_bag_full()
			else: ui.toast_error("Make room · 1 slot" if str(cmd.get("type", "")).begins_with("claim_parcel") else "Bag full · free a slot first")
		"parcel_expired", "bad_parcel":
			ui.toast_error("This parcel is no longer waiting")
		"rest_used":
			ui.toast_error("Rest used today")
		"not_home":
			ui.toast_error("At home only")
		"need_material", "skills_short", "max_level":
			# The shops and the workbench refuse with need_material too: only the upgrade reads HOME-1's gap.
			if str(cmd.get("type", "")) == "homestead_upgrade": ui.toast_error(P0Logic.home_panel(session.current()).reason)
			elif code == "need_material":
				ui.toast_error("Need %d more %s" % [int(detail.get("need", 0)) - int(detail.get("have", 0)),
					P0Logic.item_name(session.current(), str(detail.get("item", "")))])
			else: ui.toast_error("Can't do that (%s)" % code)
		"energy_full":
			ui.toast_error("Energy full · eat later" if str(cmd.get("type", "")) == "eat" else "Energy full")
		"not_ready":
			ui.toast_error("Not ready yet")
		"creel_full":
			ui.toast_error("Creel full · 0 free slots · Sell or cook first", "Open bag")   # FISH-4, §4.8.6
		"already_casting":
			ui.toast_error("Your line is already in the water")
		"no_bait":
			ui.toast_error("No bait left")
		"not_at_pond":
			ui.toast_error("Fish from a pond · open one from the map")   # the server did not get which pond (q(36))
		"too_early", "no_cast":
			_call("p0_event", [{"kind": "fish_abort"}, session.view])
		"stale_pot":
			session.refresh()   # S5: the server already kept that pot (Queue ×2); the fresh view shows where it went
		"stove_busy":
			ui.toast_error("The stove is busy · %s left" % P0Logic.duration(float(detail.get("ready_in", 0))))
		"needs_main":
			ui.toast_error("Needs a main ingredient")
		"not_for_cooking":
			ui.toast_error("Not for cooking")
		"missing_ingredients", "not_enough":
			ui.toast_error("Missing ingredients")
		"sold_out":
			ui.toast_error("Sold out today · %d left" % int(detail.get("left", 0)))
		"wrong_state", "bad_plot":
			pass   # the plot changed under a held repeat; the next frame shows its new state
		"stale_state":
			pass   # a retry of something the server already applied; the returned state re-renders the screen
		_:
			ui.toast_error("Can't do that (%s)" % code)

## P0_SHOT counters away from the outposts: the keeper ctx the outpost would pass (assets/p0/p0_outposts.json, SGODOT-227).
static func _dev_ctx(role: String) -> Dictionary:
	return {"tackle": {"keeper": "Finn", "place": "Xuhui Tackle Shop", "nearest": {"name": "Reed Pond", "site": "pond"}},
		"tea": {"keeper": "Ama", "place": "Lotus Tea House"}, "post": {"keeper": "Sigrid", "place": "Huangpu Travel Post"},
		"market": {"keeper": "Mei", "place": "Xuhui Market Square"}}.get(role, {})

## FARM-3-RESULT-2 (E-04): the bag filled during a harvest. What went in stays in, the rest stays ready on the field;
## the run says how far it got (`Harvest 12 of 30 · bag full`, of the plants ready when it started) and the Error toast
## points at the stall with `Open bag ›`; the hold stops (a refusal ends the run).
func _harvest_bag_full() -> void:
	var v := session.current()
	var ready := (v.get("plots", []) as Array).filter(func(p): return str(p.get("state", "")) == "ready").size()
	if _held_plants > 0:
		ui.queue_floats([{kind = "item", key = "bag_full", text = "Harvest %d of %d · bag full" % [_held_plants, _held_plants + ready],
			tone = UiFloatText.Tone.ITEM}], anchor())
	var bag: Dictionary = v.get("bag", {})
	ui.toast_error("Bag %d/%d · Sell at Homestead Stall" % [(bag.get("slots", []) as Array).size(), int(bag.get("capacity", 25))], "Open bag")
	ui.fab_held = false
	_held_plants = 0

## A request that never got an answer (8 s, a 5xx or not JSON). The server URL goes to the log, not the screen.
func _net_failed(msg: String, cmd := {}) -> void:
	push_warning("P0: %s · %s" % [msg, session.base_url])
	_end_resume()
	if _launch_s >= 0.0 and session.view.is_empty():
		_launch_failed()   # nothing to browse yet: Can't connect takes the screen, no banner (SYS-LOADING-FAIL)
		return
	if _arrive_s >= 0.0:
		_arrival_failed()   # getting there failed: Couldn't get there, over the Offline banner (q(78))
		return
	_net_fails += 1
	if _net_fails >= 2:
		if not ui.offline:
			ui.offline = true
			ui.show_sys(UiSysBanner.Kind.OFFLINE, "Offline · Reconnecting…")
		_probe_left = PROBE_S
	elif not cmd.is_empty():
		# Only a command says it did not go through; a background read (the 30 s refresh) that fails once is not
		# something the player did — it counts toward Offline but shows nothing (亚瑟 on #84).
		ui.show_sys(UiSysBanner.Kind.CMD_FAIL, "Didn't go through · try again", CMD_FAIL_S)

## Any answer from the server: the count clears; offline ends with `Back online` (the fresh state redraws everything;
## nothing settled is replayed and no UI command is resent, §10.7.1).
func _net_ok() -> void:
	_net_fails = 0
	_end_resume()
	_end_arrival()
	_unblock()
	_end_launch()
	if ui.offline:
		ui.offline = false
		ui.show_sys(UiSysBanner.Kind.BACK_ONLINE, "Back online", BACK_ONLINE_S)

## Retry, and the check every PROBE_S while offline: one state read.
func _probe() -> void:
	_probe_left = PROBE_S
	if not session.busy: session.refresh()

# ---------------------------------------------------------------- whole-screen system states (SGODOT-233)
const LAUNCH_SLOW_S := 8.0    # SYS-LOADING-2: `Taking longer than usual…`
const LAUNCH_FAIL_S := 20.0   # no answer by then: SYS-LOADING-FAIL `Can't connect` · Retry
const MAINT_CHECK_S := 60.0   # SYS-MAINT checks again on its own (q(74))
var _launch_s := -1.0         # how long the launch cover has been up; -1 when it is not
var _blocked := ""            # "maintenance" / "update_required" while the server turns every request away
var _block_url := ""
var _maint_left := 0.0
var _resume_ms := -1          # a state read on return to the foreground is in flight since then; -1 none
## Getting to a place (q(78)): the scene cover AppRouter showed for a P0 world stays until that world's first read
## answers. {path, place, shot, t0} of the cover; `_arrive_s` counts while its read is out (-1 none).
const ARRIVE_FAIL_S := 20.0
var _arrive := {}
var _arrive_s := -1.0

## The first session's launch cover (SYS-LOADING, from p0_boot): the wordmark over the farm backdrop until the first
## answer and a world are both there. 8 s on, the spinner and `Taking longer than usual…`; 20 s without an answer —
## or a failed read with nothing yet to browse — `Can't connect` · Retry, checked again every PROBE_S.
func cover_launch() -> void:
	_launch_s = 0.0
	ui.show_screen(P0SysScreen.Kind.LAUNCH)

func _tick_screens(dt: float) -> void:
	if _launch_s >= 0.0:
		_launch_s += dt
		match ui.screen_kind():
			P0SysScreen.Kind.LAUNCH:
				if _launch_s >= LAUNCH_SLOW_S and not ui.screen().slow: ui.screen().taking_longer()
				if _launch_s >= LAUNCH_FAIL_S and session.view.is_empty(): _launch_failed()
			P0SysScreen.Kind.FAIL:
				_probe_left -= dt
				if _probe_left <= 0.0: _probe()
	if _blocked == "maintenance":
		_maint_left -= dt
		if _maint_left <= 0.0:
			_maint_left = MAINT_CHECK_S
			if not session.busy: session.refresh()
	if _arrive_s >= 0.0:
		_arrive_s += dt
		# Shown once the trip has taken MOTION_PENDING_DELAY_MS since it started: right away when AppRouter's cover
		# was already up, never for a quick one.
		if ui.screen_kind() == -1 and Time.get_ticks_msec() - int(_arrive.t0) >= UiTokens.MOTION_PENDING_DELAY_MS:
			ui.show_screen(P0SysScreen.Kind.SCENE, _arrive)
		if ui.screen_kind() == P0SysScreen.Kind.SCENE and _arrive_s >= LAUNCH_SLOW_S and not ui.screen().slow: ui.screen().taking_longer()
		if _arrive_s >= ARRIVE_FAIL_S: _arrival_failed()
	# Back from the background: the read is cheap when it is quick; past MOTION_PENDING_DELAY_MS it gets a cover.
	if _resume_ms >= 0 and ui.screen_kind() == -1 and Time.get_ticks_msec() - _resume_ms >= UiTokens.MOTION_PENDING_DELAY_MS:
		ui.show_screen(P0SysScreen.Kind.SCENE, {place = ui.place_text(), shot = P0SysScreen.blurred_screen(get_viewport())})

func _launch_failed() -> void:
	_probe_left = PROBE_S
	ui.show_screen(P0SysScreen.Kind.FAIL)

## The launch is over once the first answer and a world are both in: the cover (or Can't connect) goes.
func _end_launch() -> void:
	if _launch_s < 0.0 or session.view.is_empty() or not is_instance_valid(world): return
	_launch_s = -1.0
	ui.hide_screen([P0SysScreen.Kind.LAUNCH, P0SysScreen.Kind.FAIL])

## Every return to the foreground reads the state (§10.7.1); a slow read gets SYS-LOADING over the place.
func _on_resumed() -> void:
	if session.view.is_empty() or _blocked != "" or _launch_s >= 0.0: return
	_resume_ms = Time.get_ticks_msec()
	if not session.busy: session.refresh()

func _end_resume() -> void:
	if _resume_ms < 0: return
	_resume_ms = -1
	ui.hide_screen([P0SysScreen.Kind.SCENE])

## q(74): 426 update_required → SYS-UPDATE (Update opens the url; the card stays); 503 maintenance → SYS-MAINT,
## checked every 60 s and on Check again. Neither has a close or counts toward Offline; the outpost room is left
## while the card is up. Any answer afterwards takes it down and the player carries on where they were.
func _on_blocked(code: String, detail: Dictionary) -> void:
	_end_resume()
	_arrive = {}   # SYS-MAINT / SYS-UPDATE take over from getting there (q(78))
	_arrive_s = -1.0
	_blocked = code
	_hold_rooms(true)
	if code == "update_required":
		_block_url = str(detail.get("url", ""))
		ui.show_screen(P0SysScreen.Kind.UPDATE, {url = _block_url})
	else:
		_maint_left = MAINT_CHECK_S
		ui.show_screen(P0SysScreen.Kind.MAINT, {back_at = back_at_text(str(detail.get("back_at", "")))})

func _unblock() -> void:
	if _blocked == "": return
	_blocked = ""
	ui.hide_screen([P0SysScreen.Kind.MAINT, P0SysScreen.Kind.UPDATE])
	_hold_rooms(false)

func _hold_rooms(on: bool) -> void:
	if not is_inside_tree(): return
	for o in get_tree().root.find_children("*", "P0Online", true, false):
		if on: (o as P0Online).hold()
		else: (o as P0Online).release()

func _on_screen_action(kind: P0SysScreen.Kind) -> void:
	match kind:
		P0SysScreen.Kind.FAIL: _probe()
		P0SysScreen.Kind.PLACE_FAIL:   # Retry: the same place again, as many times as the player likes (q(78))
			if _arrive.is_empty(): return
			_arrive_s = 0.0
			ui.show_screen(P0SysScreen.Kind.SCENE, _arrive)
			if not session.busy: session.refresh()
		P0SysScreen.Kind.MAINT:
			_maint_left = MAINT_CHECK_S
			if not session.busy: session.refresh()
		P0SysScreen.Kind.UPDATE:
			if _block_url != "": OS.shell_open(_block_url)

## A P0 world AppRouter opened under the scene cover: the cover stays until its first read answers (q(78)). The
## launch cover has the very first world; a world that is not the one the cover was for leaves it alone.
func _begin_arrival(w: Node) -> void:
	if _arrive.is_empty(): return
	# AppRouter gives a load 30 s; a cover older than that belonged to a trip that never arrived.
	if _launch_s >= 0.0 or session.view.is_empty() or w.scene_file_path != str(_arrive.path) \
			or Time.get_ticks_msec() - int(_arrive.t0) > 35000:
		_arrive = {}
		return
	_arrive_s = 0.0

func _end_arrival() -> void:
	if _arrive.is_empty(): return
	_arrive = {}
	_arrive_s = -1.0
	ui.hide_screen([P0SysScreen.Kind.SCENE, P0SysScreen.Kind.PLACE_FAIL])

## Couldn't get there (q(78)): an error, a 5xx without the maintenance code, or 20 s without an answer.
func _arrival_failed() -> void:
	_arrive_s = -1.0
	ui.show_screen(P0SysScreen.Kind.PLACE_FAIL, {shot = _arrive.get("shot", null)})

## Go back (and Back) on Couldn't get there: to where the player came from.
func _on_screen_back(kind: P0SysScreen.Kind) -> void:
	if kind != P0SysScreen.Kind.PLACE_FAIL: return
	_end_arrival()
	if is_instance_valid(world) and AppRouter.top_instance() == world: AppRouter.pop_instance()
	else: leave_to_map()

## SYS-MAINT's time (q(74)): the player's local clock, 24 h — `14:30` today, `Oct 10, 14:30` on another day; "" (We'll
## be back soon.) when absent, unreadable or already past. `now` and `bias_min` (minutes east of UTC) are for tests.
static func back_at_text(iso: String, now := -1, bias_min := 100000) -> String:
	if iso.strip_edges() == "": return ""
	var at := Time.get_unix_time_from_datetime_string(iso.strip_edges().trim_suffix("Z"))
	if at <= 0: return ""
	var t_now := now if now >= 0 else int(Time.get_unix_time_from_system())
	if at <= t_now: return ""
	var shift := (bias_min if bias_min != 100000 else int(Time.get_time_zone_from_system().get("bias", 0))) * 60
	var d := Time.get_datetime_dict_from_unix_time(int(at) + shift)
	var today := Time.get_datetime_dict_from_unix_time(t_now + shift)
	var clock := "%02d:%02d" % [int(d.hour), int(d.minute)]
	if [d.year, d.month, d.day] == [today.year, today.month, today.day]: return clock
	const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%s %d, %s" % [MONTHS[int(d.month) - 1], int(d.day), clock]

## Desktop shots of the Inbox (234): a made-up inbox over the current view, as the INBOX-PARCELS / PARCEL-3 /
## PARCEL-5 frames show it (the next server answer replaces it).
func _dev_inbox(which: String) -> void:
	var v: Dictionary = session.view.duplicate(true)
	var at := Time.get_unix_time_from_system() * 1000.0
	var parcels := [{"key": "d1", "id": "seed_carrot", "qty": 2, "source": "Welcome gift", "left": 3_900_000.0},
		{"key": "d2", "id": "dish_grilled_crucian", "qty": 1, "source": "Pip's gift meal", "left": 18_720_000.0, "gift": {"from": "Pip"}},
		{"key": "d3", "id": "fish_perch", "qty": 7, "source": "Request reward · Stall Board", "left": 85_200_000.0}]
	var updates := [{"key": "u1", "id": "fish_perch", "qty": 7, "source": "Request reward · Stall Board", "at": at - 20_000.0, "status": "expired", "coins": 18, "read": false},
		{"key": "u2", "id": "bait_worm", "qty": 3, "source": "Fishing Lv2 reward", "at": at - 18_000_000.0, "status": "expired", "coins": 0, "read": true},
		{"key": "u3", "id": "dish_grilled_crucian", "qty": 1, "source": "Pip's gift meal", "at": at - 129_600_000.0, "status": "returned", "coins": 0, "read": true, "gift": {"from": "Pip"}}]
	var free := 0 if which == "full" else 6
	if which == "full": parcels = parcels.slice(1)
	if which in ["updates", "todo"]: parcels = []
	v["bag"] = v.get("bag", {}).duplicate()
	v.bag["free"] = free
	v["inbox"] = {"limit": 8, "waiting": 0, "claim_slots": mini(free, parcels.size()), "parcels": parcels,
		"updates": updates if which == "updates" else [], "badge": parcels.size() + (1 if which == "updates" else 0)}
	session.view = v
	session.busy = true   # dev only: Updates' read and the 30 s refresh wait, so no answer replaces the made-up inbox
	ui.set_view(session.current())
	ui.open_inbox("" if which == "full" else which)

## Desktop shots of the whole-screen states (233): the launch cover, its slow line and Can't connect; maintenance back in
## 90 minutes; update; the scene cover over the farm (named Reed Pond) and its failure.
func _dev_screen(which: String) -> void:
	match which:
		"launch", "slow", "fail":
			cover_launch()
			if which == "slow": ui.screen().taking_longer()
			if which == "fail": _launch_failed()
		"maint":
			var at := Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) + 5400) + "Z"
			_on_blocked("maintenance", {"back_at": at})
		"update": _on_blocked("update_required", {"url": "https://example.test/p0demo.apk"})
		"scene", "placefail":
			var layer := _scene_overlay("res://scenes/p0/p0_pond.tscn", {"pond_id": "pond_shanghai_05"}) as P0LoadingLayer
			add_child(layer)
			layer.screen.modulate.a = 1.0
			if which == "placefail": layer.failed()

## AppRouter.open_instance into a P0 world: SYS-LOADING-SCENE over the screen being left; anything else keeps
## AppRouter's own overlay.
func _scene_overlay(path: String, args: Dictionary) -> CanvasLayer:
	var place := P0LoadingLayer.destination(path, args)
	if place == "": return null
	var shot := P0SysScreen.blurred_screen(get_viewport())
	_arrive = {path = path, place = place, shot = shot, t0 = Time.get_ticks_msec()}
	return P0LoadingLayer.new(place, shot, path, args)

# ---------------------------------------------------------------- dev: scripted desktop screenshots
## P0_SHOT=/abs/path.png P0_SHOT_STEPS="walk:1:0:1.5,act,..." — run scripted inputs, save one frame, quit.
## Generic UI steps live here; world steps (goto, stove, until:bite …) go to world.p0_dev / p0_until.
func _dev_shot(dt: float) -> void:
	var path := OS.get_environment("P0_SHOT")
	if path == "": return
	if _shot_t == 0.0: _shot_script = OS.get_environment("P0_SHOT_STEPS").split(",", false)
	_shot_t += dt
	var limit := OS.get_environment("P0_SHOT_LIMIT_MS")
	if Time.get_ticks_msec() > int(limit if limit != "" else "30000"): get_tree().quit(2)
	if world == null and _shot_t < 6.0: return
	if not _shot_script.is_empty() and _shot_t > 2.0:
		var step := str(_shot_script[0]).split(":")
		match step[0]:
			"walk":
				_call("p0_joystick", [Vector2(float(step[1]), float(step[2]))])
				if _shot_t < 2.0 + float(step[3] if step.size() > 3 else "1.0"): return
				_call("p0_joystick", [Vector2.ZERO])
			"act": ui._fab_pressed()
			"hold":
				ui.fab_held = true
				ui._fab_pressed()
			"release": ui.fab_held = false
			"stall": ui.open_stall(step[1] if step.size() > 1 else "")
			"counter": ui.open_counter(step[1], {"section": step[2] if step.size() > 2 else "buy", "ctx": _dev_ctx(step[1])})
			"boardreq": ui.open_board_request(step[1], step[2])   # boardreq:<role>:<request id> — BOARD-1
			"dropconfirm": P0BoardRequest.confirm_drop(ui, step[1], step[2])   # dropconfirm:<role>:<request id> — BOARD-3
			"boardinfo": P0BoardRequest.info(ui, step[1])   # boardinfo:<item> — Details over the open request sheet
			"presscmd":   # the open card's command button (BOARD-3 Drop request → BOARD-DROPPED)
				if ui._modal != null:
					for b in ui._modal.find_children("*", "UiCommandButton", true, false): (b as UiCommandButton).activated.emit()
			"greet": ui.open_keeper_greeting(step[1], _dev_ctx(step[1]))
			"bag": ui.open_bag(step[1] if step.size() > 1 else "")
			"bagcat":   # bag drawer on one category tab, e.g. bagcat:Materials (SGODOT-225 storage stacks)
				if ui._bag != null and is_instance_valid(ui._bag):
					var i := P0BagDrawer.CATEGORIES.find(step[1])
					if i >= 0: (ui._bag._chips.get_child(i) as Button).button_pressed = true
			"counterpick":  # counterpick[:id] selects a stack in the counter's bag half: its Sell card shows (q(16) shots)
				if ui._counter != null and is_instance_valid(ui._counter) and ui._counter.grid != null and not ui._counter.grid.shown_items().is_empty():
					ui._counter.grid.select(step[1] if step.size() > 1 else str(ui._counter.grid.shown_items().front().id))
			"bagpick":  # tap the first listed item of the open bag drawer
				if ui._bag != null and is_instance_valid(ui._bag) and not ui._bag.grid.shown_items().is_empty():
					ui._bag.grid.select(str(ui._bag.grid.shown_items().back().id))
			"energy": ui.open_energy_card(3, "Sow ×1")
			"close": ui.close_modal()
			"auto":
				P0Fishing.auto_play = true
				P0Cooking.auto_play = true
				P0Kitchen.auto_play = true
			"manual":
				P0Cooking.auto_play = false
				P0Kitchen.auto_play = false
			"dex": ui.open_fishdex()
			"dexcell":   # dexcell:fish_koi — a Fish-dex cell tap (gate card or fish card, SGODOT-233)
				for d in ui.find_children("*", "P0FishDex", true, false): (d as P0FishDex).cell_pressed.emit(step[1])
			"gate":   # gate:farming:2:Carrot Seeds:seed_carrot — the four-things gate card (§4.8.7)
				ui.open_gate_card({"skill": step[1], "level": int(step[2]), "what": step[3] if step.size() > 3 else "",
					"icon": step[4] if step.size() > 4 else ""})
			"kai": ui.open_kai_greeting()
			"tackle": ui.open_tackle()
			"gear": ui.open_gear()
			"skills": ui.open_skills()
			"profile": ui.open_profile()
			"resident": ui.open_resident(step[1] if step.size() > 1 else "res_pip")   # SGODOT-225 dialogue bar
			"resprofile": ui.open_resident_profile(ui._resident)                     # its name → profile sheet
			# SGODOT-233 result moments, shown directly: catchcard:<fish>, gotaway:<fish>:level|rod
			"catchcard": ui.show_catch(step[1], int(P0Logic.item(session.current(), step[1]).get("rarity", 1)), 15, {"energy": 20})
			"gotaway":
				var gone := {"fish": step[1], "rarity": int(P0Logic.item(session.current(), step[1]).get("rarity", 3)), "refund": 5, "protected_left": 8}
				if step.size() < 3 or step[2] == "level": gone["need_level"] = 4
				ui.show_got_away(gone)
			"today": ui.open_today()
			"energypanel": ui.open_energy_panel()
			"inbox": ui.open_inbox()
			"inboxdemo": _dev_inbox(step[1] if step.size() > 1 else "parcels")   # inboxdemo:parcels|full|updates|todo (234)
			"workbench": ui.open_workbench(step[1] if step.size() > 1 else "")   # SGODOT-231 B2-06 drawer, tools / supplies
			"toasterr": ui.toast_error(step[1] if step.size() > 1 else "Need 1 more Copper Ore")   # a refusal's Error toast (233)
			"netfail": _net_failed("dev", {"type": "dev"})   # netfail once: Didn't go through; twice: Offline (233)
			"screen": _dev_screen(step[1] if step.size() > 1 else "launch")   # screen:launch|slow|fail|maint|update|scene|placefail
			"wbtile":   # wbtile:craft_copper_pickaxe:0 taps that card's cost tile (NeedSource)
				var wb := ui.workbench()
				if wb != null and wb.card(step[1]) != null: wb.card(step[1]).tiles()[int(step[2])].pressed.emit()
			"wbicon":   # wbicon:craft_copper_pickaxe taps that card's item icon (its InfoSheet)
				var wbi := ui.workbench()
				if wbi != null and wbi.card(step[1]) != null: wbi.card(step[1]).icon_pressed.emit()
			"showspot":   # showspot:mine — what a NeedSource's Show does (closes the layer, camera only, LOCK-08)
				ui.close_modal()
				ui.show_spot.emit(step[1])
			"radial": ui.open_radial()
			"kitchen", "put":
				# The farmhouse owns the cooking drawer; elsewhere the interim panel opens.
				if not bool(_call("p0_dev", [step])):
					if step[0] == "put": ui._exp_slots.append(step[1])
					ui.open_kitchen(step[1] if step[0] == "kitchen" and step.size() > 1 else ("experiment" if step[0] == "put" else "cookbook"))
			"cook": session.send({"type": "cook", "recipe": step[1]})
			"send":
				# send:type=reel|outcome=landed (commas separate steps, so no JSON here)
				var cmd := {}
				for pair in ":".join(step.slice(1)).split("|"):
					var kv := pair.split("=")
					cmd[kv[0]] = int(kv[1]) if kv[1].is_valid_int() else kv[1]
				session.send(cmd)
			"wait":
				if _shot_t < 2.0 + float(step[1]): return
			"until":
				var ready := ui.has_modal() if step[1] == "modal" else bool(_call("p0_until", [step[1]]))
				if not ready and _shot_t < 40.0: return
			"skip": session.dev_skip(int(step[1]))
			"back": leave_world()
			"gohome": ui.home_requested.emit()
			"tackleshop": ui.tackle_requested.emit()
			_:
				if not bool(_call("p0_dev", [step])): push_warning("P0_SHOT: unknown step " + step[0])
		_shot_script.pop_front()
		_shot_t = 1.2
		return
	if _shot_script.is_empty() and _shot_t > 1.6:
		var img := get_viewport().get_texture().get_image()
		img.save_png(path)
		print("P0_SHOT saved ", path)
		get_tree().quit()
