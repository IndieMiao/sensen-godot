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
	ui.place_pressed.connect(leave_world)
	ui.home_requested.connect(func(): _leave_then("farm"))
	ui.tackle_requested.connect(func(): _leave_then("tackle"))
	session.state_changed.connect(_on_state)
	# U6: doing what the TipCard on screen teaches closes it (sow / cast / cook / heat are command types).
	session.sent.connect(func(cmd: Dictionary): ui.tip_did(str(cmd.get("type", ""))))
	session.refused.connect(_on_refused)
	session.connection_failed.connect(func(msg: String, cmd: Dictionary):
		ui.toast(msg + " · " + session.base_url, 4.0)
		# The world may be waiting on that command (a cast in flight): let it recover.
		if not cmd.is_empty(): _call("p0_event", [{"kind": "send_failed", "cmd": cmd}, session.current()]))
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
func leave_room() -> void:
	if is_instance_valid(world) and AppRouter.top_instance() == world: AppRouter.pop_instance()

## Back to the map, then on to the homestead or Old Kai's pin (the map reads after_leave on resume).
func _leave_then(next: String) -> void:
	after_leave = next
	leave_world()

func _call(method: String, args: Array):
	if is_instance_valid(world) and world.has_method(method): return world.callv(method, args)
	return null

func _process(dt: float) -> void:
	_dev_shot(dt)
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
				if int(ev.delta) > 0 and not crafted and not iid.begins_with("seed_") and not iid.begins_with("dish_") and not iid.begins_with("fish_"):
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
			"workbench": ui.open_workbench(step[1] if step.size() > 1 else "")   # SGODOT-231 B2-06 drawer, tools / supplies
			"toasterr": ui.toast_error(step[1] if step.size() > 1 else "Need 1 more Copper Ore")   # a refusal's Error toast (233)
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
