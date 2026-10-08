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
## What to do once the map is back on top (FISH-4 Go home, FISH-5 Tackle Shop): "farm" / "tackle".
var after_leave := ""
## True only while the farm's hold-to-repeat sends its next command (§14.2): the observation log's "hold" (S7).
## The press itself, even with the key still down, is a tap (刘邦, PR #23 review).
var holding_repeat := false

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
	ui.show_on_map.connect(func(target: String): _leave_then("show:" + target))   # the map points at the pin (p0_map resume)
	ui.can_show_spot = func() -> bool: return is_instance_valid(world) and world.has_method("p0_show_spot")
	ui.near_resident = func() -> String:   # an outpost's resident within reach (Gift to <Name>, SGODOT-225)
		return str(world.call("p0_near_resident")) if is_instance_valid(world) and world.has_method("p0_near_resident") else ""
	ui.home_choice.connect(func(choice: String): _call("p0_home", [choice]))
	ui.place_pressed.connect(leave_world)
	ui.home_requested.connect(func(): _leave_then("farm"))
	ui.tackle_requested.connect(func(): _leave_then("tackle"))
	session.state_changed.connect(_on_state)
	session.refused.connect(_on_refused)
	session.connection_failed.connect(func(msg: String, cmd: Dictionary):
		ui.toast(msg + " · " + session.base_url, 4.0)
		# The world may be waiting on that command (a cast in flight): let it recover.
		if not cmd.is_empty(): _call("p0_event", [{"kind": "send_failed", "cmd": cmd}, session.current()]))
	if OS.get_environment("P0_AUTO") == "1" or FileAccess.file_exists("user://p0_auto"):
		P0Fishing.auto_play = true
		P0Cooking.auto_play = true

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
	if AppRouter.instance_depth() > 0: return false   # stacked on the map: AppRouter pops it
	leave_to_map()
	return true

## Show (LOCK-08, the camera only). In the farmhouse a farm target (plots, stall, bench …) steps out to the farm first,
## which shows it once it is back (attach); the stove and the room's own spots show in the room (亚瑟 on #37).
var _spot_after_room := ""

func _show_spot(where: String) -> void:
	if world is P0Room and session.space == "home" and not bool(_call("p0_has_spot", [where])):
		_spot_after_room = where
		leave_room()
		return
	_call("p0_show_spot", [where])

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
	ui.set_view(v)   # cards built below read the fresh view (Fish-dex, creel, meals)
	var at := anchor()
	var dy := 0.0
	var xp_lines: Array = []
	last_first_catch_xp = 0
	var settles_catch := events.any(func(e): return str(e.get("kind", "")) == "catch")
	for i in events.size():
		var ev: Dictionary = events[i]
		match str(ev.get("kind", "")):
			"xp":
				# The server emits a first-time bonus as `first` immediately followed by its `xp`.
				var bonus: bool = i > 0 and str(events[i - 1].get("kind", "")) == "first" and int(events[i - 1].xp) == int(ev.amount)
				if int(ev.amount) > 0 and not bonus:
					xp_lines.append("+%d %s XP" % [int(ev.amount), str(ev.skill).capitalize()] + ("" if int(ev.percent) >= 100 else " · %d%%" % int(ev.percent)))
			"reward":
				if int(ev.energy) > 0: xp_lines.append(P0Logic.reward_line(str(ev.id), int(ev.energy)))
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
	last_xp_lines = xp_lines
	var parcels_said := false
	for ev in events:
		match str(ev.get("kind", "")):
			"energy":
				var dlt := int(ev.delta)
				# A catch's refund is said by its own float or card ("3 Energy back"), not twice.
				if settles_catch and str(ev.get("reason", "")) in ["refund", "line_in"]: continue
				# Inside the mine a floor fee is said by the mine's own float ("Floor 2 · −2 Energy", q(46)), not twice.
				if str(ev.get("reason", "")) == "mine_floor" and str(_call("p0_surface", [])) == "mine": continue
				ui.float_text(("%+d Energy" % dlt).replace("-", "−"), at + Vector2(0, dy), Color("d9772f") if dlt < 0 else Color("4f934b"))
			"xp":
				if int(ev.amount) > 0:
					ui.float_text("+%d XP" % int(ev.amount) + ("" if int(ev.percent) >= 100 else " · %d%%" % int(ev.percent)), at + Vector2(0, dy), Color("1e9bb0"))
			"item":
				var iid := str(ev.id)
				if int(ev.delta) > 0 and not iid.begins_with("seed_") and not iid.begins_with("dish_") and not iid.begins_with("fish_"):
					ui.float_text("+%d %s" % [int(ev.delta), P0Logic.item_name(v, iid)], at + Vector2(0, dy), Color("4f934b"))
			"coins":
				ui.float_text("%+d coins" % int(ev.delta), at + Vector2(0, dy), Color("c9962a"))
			"parcel":
				# LOCK-14: rewards that did not fit the bag wait in the Inbox; one float for the whole reply.
				if not parcels_said:
					parcels_said = true
					var line := P0Logic.parcel_toast(v, events)
					if line != "": ui.toast(line, 2.0)
			"catch":
				# A world that shows the catch itself (the open fishing panel) returns true.
				if not bool(_call("p0_event", [ev, v])): _on_catch(ev, xp_lines)
			"cast", "pot":
				_call("p0_event", [ev, v])
			"dish":
				var lines := xp_lines.duplicate()
				_call("p0_event", [ev, v])
				ui.queue_card(func(): ui.show_dish(ev, lines))
			"request":
				if str(ev.status) == "accepted": ui.toast("Tracking · it shows in Today")
				else: ui.toast("Request complete · +%d coins" % int(ev.coins))
			"meal":
				ui.teach("meal", "Energy comes back over time. A meal brings it back now.")
				if int(ev.gain) <= 0:
					ui.toast("Full belly · Meals reset in " + P0Logic.duration(float(v.get("meals", {}).get("resets_in", 0))) if int(ev.counted) <= 0 and int(ev.nominal) > 0 else "Same dish · no Energy today")
				else:
					ui.toast("+%d Energy · Meals today %d/%d" % [int(ev.gain), int(ev.meals), int(ev.cap)])
			"level":
				var lv: Dictionary = ev
				ui.queue_card(func(): ui.show_level_up(lv))
				session.report({"kind": "level_banner", "skill": str(lv.skill), "level": int(lv.level)})
			"affinity":   # SGODOT-225 / 228: first chat of the day, gifts, requests
				var reply := P0Logic.resident_reply(str(ev.get("resident", "")), str(ev.get("verdict", "")))
				# On the resident's open bar: the Affinity pill over it and the answer in the bubble (RES-KAI-TALK).
				if not ui.resident_affinity(ev, reply):
					if int(ev.get("delta", 0)) != 0:
						ui.float_text("♥ " + P0Ui.affinity_text(ev), at + Vector2(0, dy), UiTokens.COLOR_FLOAT_AFFINITY)
					if reply != "": ui.toast(reply)
			"gift_meal":
				var who := str(P0Logic.content().get("residents", {}).get(str(ev.get("resident", "")), {}).get("name", ""))
				# SGODOT-232: with the bag full the meal waits in the Inbox (to: parcel), gone at 04:00 like any gift meal.
				if str(ev.get("to", "")) == "parcel": ui.toast("Bag full · %s's meal sent to Inbox" % who)
				elif bool(ev.get("given", false)): ui.toast("%s gave you %s · in your bag" % [who, P0Logic.item_name(v, str(ev.get("dish", "")))])
			"homestead":
				# HOME-2 (SGODOT-228): HOME-1 closes, the MomentBanner says what changed; the farm swaps the fence.
				if ui.modal_kind == "homestead": ui.close_modal()
				HomePanel.moment(ui, P0Logic.home_moment(v, ev))
		dy -= 16.0
	if ui.modal_kind == "stall" and events.size() > 0:
		ui.set_view(session.current())
		ui.open_stall()   # refresh after Buy / Sell / Deliver; floats say what changed
	elif ui.modal_kind == "resident" and events.size() > 0:
		ui.set_view(session.current())
		ui.open_resident(ui._resident)   # affinity, gift and request states follow the reply
	elif ui.modal_kind == "tackle" and events.size() > 0:
		ui.open_tackle("Strung and ready — it's on your belt. Swap rods in Bag › Gear.")

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
				ui.queue_card(func(): ui.show_catch(fid, r, first))
			else:
				ui.float_text("%s · %s" % [P0Logic.item_name(v, fid), P0Logic.rarity_name(v, r)], where + Vector2(0, -22), P0Logic.rarity_text_color(r))
		"broke_free":
			var gone: Dictionary = ev
			if ui.first_time("gotaway:" + str(ev.fish)):
				ui.queue_card(func(): ui.show_got_away(gone))
				session.report({"kind": "card_shown", "card": "got_away", "fish": str(gone.get("fish", ""))})
			else:
				ui.float_text(("Got away · Lv%d" % int(ev.need_level)) if ev.has("need_level") else "Got away · rod too light", where, P0Ui.INK2)
		"escaped":
			var refund := int(ev.refund)
			var protected: bool = ev.has("protected_left") and refund >= int(v.get("fishing", {}).get("cast_energy", 5))
			ui.float_text(("It got away · Energy refunded (%d left today)" % int(ev.protected_left)) if protected
				else "It got away · %d Energy back" % refund, where, P0Ui.GREEN_D)
		"cancelled":
			ui.toast("Line in · Energy back")

func _on_refused(code: String, detail: Dictionary, cmd: Dictionary) -> void:
	if str(cmd.get("type", "")) == "cast": _call("p0_event", [{"kind": "cast_refused", "code": code}, session.view])
	if code == "bag_full" and str(cmd.get("type", "")) == "reel":
		_call("p0_event", [{"kind": "fish_abort"}, session.view])
		session.send({"type": "reel", "outcome": "escaped"})
		ui.toast("Creel full · the fish slipped away")
		return
	# Mine and gathering refusals (SGODOT-231): races stay quiet, the rest say why in their own words.
	var said = P0MaterialLogic.refusal_text(code, detail, cmd)
	if said != null:
		if str(said) != "": ui.toast(str(said))
		return
	match code:
		"need_energy":
			ui.open_energy_card(int(detail.get("need", 0)), "Cast" if str(cmd.get("type", "")) == "cast" else P0MaterialLogic.energy_verb(cmd, "Sow ×1"))
			session.report({"kind": "energy_card", "need": int(detail.get("need", 0)), "refused": str(cmd.get("type", ""))})
		"locked":
			ui.toast("%s Lv%d · %d XP to go" % [str(detail.get("skill", "farming")).capitalize(), int(detail.get("level", 2)), int(detail.get("xp_to_go", 0))])
		"no_coins":
			ui.toast("Need %d more coins" % int(detail.get("need", 0)))
		"bag_full":
			ui.toast("Make room · 1 slot" if str(cmd.get("type", "")).begins_with("claim_parcel") else "Bag full · free a slot first")
		"parcel_expired", "bad_parcel":
			ui.toast("This parcel is no longer waiting")
		"rest_used":
			ui.toast("Rest used today")
		"not_home":
			ui.toast("At home only")
		"need_material", "skills_short", "max_level":
			# The shops and the workbench refuse with need_material too: only the upgrade reads HOME-1's gap.
			if str(cmd.get("type", "")) == "homestead_upgrade": ui.toast(P0Logic.home_panel(session.current()).reason)
			elif code == "need_material":
				ui.toast("Need %d more %s" % [int(detail.get("need", 0)) - int(detail.get("have", 0)),
					P0Logic.item_name(session.current(), str(detail.get("item", "")))])
			else: ui.toast("Can't do that (%s)" % code)
		"energy_full":
			ui.toast("Energy full · eat later" if str(cmd.get("type", "")) == "eat" else "Energy full")
		"not_ready":
			ui.toast("Not ready yet")
		"creel_full":
			ui.toast("Creel full · 0 free slots · Sell or cook first")
		"already_casting":
			ui.toast("Your line is already in the water")
		"no_bait":
			ui.toast("No bait left")
		"not_at_pond":
			ui.toast("Fish from a pond · open one from the map")   # the server did not get which pond (q(36))
		"too_early", "no_cast":
			_call("p0_event", [{"kind": "fish_abort"}, session.view])
		"stove_busy":
			ui.toast("The stove is busy · %s left" % P0Logic.duration(float(detail.get("ready_in", 0))))
		"needs_main":
			ui.toast("Needs a main ingredient")
		"not_for_cooking":
			ui.toast("Not for cooking")
		"missing_ingredients", "not_enough":
			ui.toast("Missing ingredients")
		"sold_out":
			ui.toast("Sold out today · %d left" % int(detail.get("left", 0)))
		"wrong_state", "bad_plot":
			pass   # the plot changed under a held repeat; the next frame shows its new state
		"stale_state":
			pass   # a retry of something the server already applied; the returned state re-renders the screen
		_:
			ui.toast("Can't do that (%s)" % code)

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
			"manual": P0Cooking.auto_play = false
			"dex": ui.open_fishdex()
			"kai": ui.open_kai_greeting()
			"tackle": ui.open_tackle()
			"gear": ui.open_gear()
			"skills": ui.open_skills()
			"profile": ui.open_profile()
			"resident": ui.open_resident(step[1] if step.size() > 1 else "res_pip")   # SGODOT-225 dialogue bar
			"resprofile": ui.open_resident_profile(ui._resident)                     # its name → profile sheet
			"today": ui.open_today()
			"energypanel": ui.open_energy_panel()
			"inbox": ui.open_inbox()
			"radial": ui.open_radial()
			"kitchen": ui.open_kitchen(step[1] if step.size() > 1 else "cookbook")
			"put":
				ui._exp_slots.append(step[1])
				ui.open_kitchen("experiment")
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
