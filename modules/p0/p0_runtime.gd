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

const P0City := preload("res://modules/p0/p0_city.gd")   # the P0 home city (SGODOT-270)
const P0Kindred := preload("res://modules/p0/p0_kindred.gd")   # Kindred's postcard and title (q(171))
const HomePanel = preload("res://scenes/p0/home/p0_home_panel.gd")
const MAP_SCENE := "res://scenes/p0/p0_map.tscn"
const FARM_SCENE := "res://scenes/p0/p0_farm.tscn"
const P0Clusters := preload("res://modules/p0/p0_clusters.gd")   # the pick map opens only over a city it knows (SGODOT-342)
const P0HomePin := preload("res://modules/p0/p0_home_pin.gd")   # the free pin (SGODOT-342): a same-city move taken
const P0Travel := preload("res://modules/p0/p0_travel.gd")   # the home city (SGODOT-303: the change of home)
static var HOME_PLACE := P0City.chip("Homestead")   # the farm's place chip (p0_farm PLACE)

static var _instance: P0Runtime

var session: P0Session
## Where the player last was (the place chip's place, LOCK-06): browsing the map keeps it. {space, place};
## the map's pond card measures Distance from here (q(48)).
var here := {"space": "home", "place": ""}
var ui: P0Ui
var world: Node
var _shot_t := 0.0
var _shot_script: Array = []
var _shot_drag := false   # a drag step's press is down (SGODOT-265 videos)
var _shot_at := Vector2.ZERO
var _shot_left := -1
var _shot_finger: Control   # a grey dot where the drag step's touch is, so videos show the finger
var _shot_ms := 0.0   # movie time: --write-movie frames run slower or faster than the wall clock
## XP / reward lines of the last state change, for worlds that show results themselves (the fishing panel).
var last_xp_lines: Array = []
## First-catch bonus of the last state change (FISH-3 gold chip); 0 when the species was caught before.
var last_first_catch_xp := 0
## A landed catch the world shows itself (the P0 pond's arc to the hand) keeps its reply's floats here until the fish is
## in the hand; the world lets them rise then (take_catch_floats; 不知火舞 on 231: `+25 XP` crossed the fish in flight).
var catch_floats: Array = []
const GuideFeedback := preload("res://modules/p0/p0_guide_feedback.gd")
var _guide_feedback := GuideFeedback.new()
## …and the toast of a request that catch filled (q(134) ⑤; 周瑜 on #302): it waits for the same hand, then for the
## catch's Caught! card (take_catch_toast).
var catch_toast := ""
## The Fish-dex milestone card a landed catch's reply held (q(49); 苏烈 on #353): the world queues it after the catch's
## Caught! card (take_catch_cards).
var catch_cards: Array = []
const TRAP_CARD_TITLE := "In your trap!"   # q(124) ①: a landed fish's card is `Caught!`
const TRAP_CARD_AFTER_S := 0.3              # after the last fish lands in the creel
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
## One scene_load per navigation (亚瑟 on #94): nav_started() arms it and the next attach takes it. A world that
## attaches again when a layer above it closes (map, farm back from the farmhouse or mine, mine, pond, rooms) has no
## navigation behind it, so it reports nothing; the first world after launch reports once as `cold`.
static var _nav_pending := false
static var _cold_done := false
static func nav_started() -> void:
	_nav_ms = Time.get_ticks_msec()
	_nav_pending = true

## A navigation that never arrived (Couldn't get there → Go back) reports nothing: the world it falls back to attaches
## again without a navigation of its own (亚瑟 on #94).
static func cancel_nav() -> void:
	_nav_pending = false

## Whether this attach reports a scene_load, and whether it is the cold first one; takes the armed navigation.
static func take_load_report() -> Dictionary:
	var out := {"report": _nav_pending or not _cold_done, "cold": not _nav_pending and not _cold_done}
	_nav_pending = false
	_cold_done = true
	return out
static func mark(tag: String) -> int:
	var ms := Time.get_ticks_msec() - _nav_ms
	print("P0_TIMING %s +%d ms" % [tag, ms])
	return ms

static func ensure() -> P0Runtime:
	if is_instance_valid(_instance): return _instance
	_instance = P0Runtime.new()
	_instance.name = "P0Runtime"
	(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_instance)
	return _instance

## Tests: a P0 world (p0_map, the farm, a pond …) brings up the singleton through ensure() and nothing frees it; with
## no server it goes offline and the static UiCommandButton.offline stays set for every later suite (the kit
## gallery's sending buttons read `Offline`). A suite that opened one ends with this; the next ensure() builds anew.
static func free_instance_for_tests() -> void:
	if is_instance_valid(_instance): _instance.queue_free()
	_instance = null
	UiCommandButton.offline = false

var _switching_test_account := false

## The user confirmed Start or pressed Return. Finish pending commands before discarding the old session, so an
## old reply cannot redraw the new account. Main credentials are backed up/read back before the active id changes.
func _switch_test_account(action: String) -> void:
	if _switching_test_account: return
	_switching_test_account = true
	while session.busy or not session._queue.is_empty():
		await get_tree().process_frame
	var ok: bool = session.test_accounts.start_test(Avatar.user_id) if action == "new" else session.test_accounts.return_main()
	if not ok:
		_switching_test_account = false
		ui.show_sys(UiSysBanner.Kind.CMD_FAIL, "Didn't go through · try again", CMD_FAIL_S)
		return
	var tree := get_tree()
	set_process(false)
	session.set_process(false)
	while AppRouter.instance_depth() > 0: AppRouter._discard_top()
	_instance = null
	UiCommandButton.offline = false
	tree.change_scene_to_file("res://scenes/p0/p0_boot.tscn")
	queue_free()

func src_of_press() -> String: return "hold" if holding_repeat else "tap"

func _init() -> void:
	# App copy is English-only (user rule 2026-09-04); reused old panels translate through L10n, so pin the locale.
	TranslationServer.set_locale("en")
	session = P0Session.new()
	add_child(session)
	ui = P0Ui.new()
	ui.test_accounts = session.test_accounts
	ui.quick_store = session.test_accounts.profile_file("p0_quickbar.json")
	ui.tips_path = session.test_accounts.profile_file("p0_tips.json")
	# Crop-ready notifications (SGODOT-350 / 356): Android's GodotNotify or iOS's LocalNotify, per account on this phone.
	ui.notify = P0Notify.new(session.test_accounts.profile_file("p0_notify.json"), P0Notify.phone())
	# a cold start is coming back too: what was set or shown while the app was gone goes (⑦; 李元芳 on #522)
	ui.notify.came_back()
	if ui.notify.available(): ui.notify.native.connect("permission", func(_granted): ui.notify_changed())
	ui.test_account_requested.connect(_switch_test_account)
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
	ui.notice_board_opened.connect(_ask_presence)   # the Notice Board's online counts (q(164))
	ui.change_home.connect(change_home)   # Settings › Home city (SGODOT-303 PR-4)
	ui.can_show_spot = func() -> bool: return is_instance_valid(world) and world.has_method("p0_show_spot")
	ui.near_resident = func() -> String:   # an outpost's resident within reach (Gift to <Name>, SGODOT-225)
		return str(world.call("p0_near_resident")) if is_instance_valid(world) and world.has_method("p0_near_resident") else ""
	ui.place_pressed.connect(_on_place_pressed)
	ui.tackle_requested.connect(func(): _leave_then("tackle"))
	ui.go_pond.connect(func(id: String): _leave_then("go:pond:" + id))   # the Bite Board's pond card: Go (SGODOT-283)
	session.state_changed.connect(func(_v, _e): _net_ok())   # any answer ends a run of failures (and offline)
	session.state_changed.connect(_on_state)
	# U6: doing what the TipCard on screen teaches closes it (sow / cast / cook / heat are command types).
	session.sent.connect(func(cmd: Dictionary): ui.tip_did(str(cmd.get("type", ""))))
	session.sent.connect(func(cmd: Dictionary): _guide_feedback.sent(cmd, ui.view))
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
		P0FishingPanel.auto_play = true
		P0Kitchen.auto_play = true

## The active world takes over input and the HUD surface; the previous one is simply forgotten.
func attach(w: Node) -> void:
	# The world being left stops where it is, and the stick ends: no walking on underneath (int5 hand test 035–039).
	if is_instance_valid(world) and world != w: _call("p0_joystick", [Vector2.ZERO])
	ui.end_stick()
	# left before a landed fish reached the hand: the request it filled still says so (q(134))
	if world != w and catch_toast != "": ui.toast_success_when_clear(take_catch_toast(), false, true)
	if world != w:   # …and a Fish-dex milestone it made still gets its card
		for c in take_catch_cards(): ui.queue_card(c)
	world = w
	session.space = space_of(w)   # before the read below, which tells the server where the player is
	if session.space in ["map", "pond", "outpost"]: ui.cook_page_from_today = ""   # left home: Today's stove page goes (q(99))
	if session.space != "map": return_to = route_of(w)
	# On the map the chip still names where the player is; the farmhouse and the mine are the homestead (MAP-1).
	elif return_to == "farm": ui.set_place(HOME_PLACE)
	ui.space = session.space
	session.place = str(w.call("p0_place")) if w.has_method("p0_place") else ""   # which pond (q(36))
	ui.place = session.place
	if session.space not in ["", "map"]: here = {"space": session.space, "place": session.place}
	# Entering a space reads fresh state, with this space: the server settles where the player is from it (#233). A read
	# still on the wire left before this space was set (the cold start's first one): read again once it is back.
	if not session.busy and not session.view.is_empty(): session.refresh()
	elif session.busy: session.refresh_after()
	var attach_ms := mark("attach " + str(w.name))
	if _spot_after_room != "" and w.has_method("p0_show_spot"):   # stepped out of the farmhouse to show a farm spot
		w.call_deferred("p0_show_spot", _spot_after_room)
		_spot_after_room = ""
	_first_frame.call_deferred(str(w.name), attach_ms, session.place if session.place != "" else session.space, take_load_report())
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

## The same timings go to the observation log as `scene_load` (int9: the vivo shows no app logcat): which world and
## place, navigation start → attach / first / second drawn frame, and the device. `cold` = no navigation started it
## (the first world after launch), so the times count from engine start.
func _first_frame(tag: String, attach_ms := -1, place := "", load := {}) -> void:
	await RenderingServer.frame_post_draw
	var first := mark("first frame " + tag)
	await RenderingServer.frame_post_draw
	var second := mark("second frame " + tag)
	if load.get("report", false): session.report(scene_load_event(tag, place, attach_ms, first, second, bool(load.get("cold", false))))

static func scene_load_event(scene: String, place: String, attach_ms: int, first_ms: int, second_ms: int, cold: bool) -> Dictionary:
	return {"kind": "scene_load", "scene": scene, "place": place, "attach_ms": attach_ms, "first_ms": first_ms,
		"second_ms": second_ms, "cold": cold, "cores": OS.get_processor_count(), "model": OS.get_model_name(),
		"gpu": RenderingServer.get_video_adapter_name()}

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
		ui.place = ""

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
		if AppRouter.instance_depth() >= depth: return   # a layer that refuses to pop stays
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

## The outposts' online counts for the Notice Board (q(164)): one GET /p0/presence, as the map polls it; a failure
## leaves the board without person badges (nobody shown is never wrong for a moment).
var _presence: P0HttpRequest
func _ask_presence() -> void:
	if not is_instance_valid(_presence):
		_presence = P0HttpRequest.new()   # its wait in live time, not stalls (SGODOT-370)
		add_child(_presence)
		_presence.request_completed.connect(_on_presence)
	if _presence.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED or session.base_url == "": return
	var headers := PackedStringArray(["x-p0-player: " + session.player_id])
	if session.access_key != "": headers.append("x-p0-key: " + session.access_key)   # the demo server's key
	_presence.send(session.base_url + "/p0/presence", headers)

func _on_presence(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200: return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary) or not (data.get("outposts") is Dictionary): return
	var online := {}
	for id in data.outposts: online[str(id)] = int(data.outposts[id].get("online", 0))
	ui.set_notice_online(online)

## Show on map: from a world, back to the map, which points at the pin on resume (p0_map.show_place); on the map
## itself the map points at it at once (蒙恬 on #44).
func _show_on_map(target: String) -> void:
	if is_instance_valid(world) and world.has_method("show_place"):
		world.call("show_place", target)
		return
	_leave_then("show:" + target)

## One level back, for a room's door and the mine's exit: the farm under the farmhouse and the mine, the map under an
## outpost. Leaving a room (the farmhouse, an outpost) or the mine: back to the world under it. One pushed straight onto the empty p0_boot
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
	var id := ""
	match space_of(w):
		"pond": id = str(w.call("p0_place")) if w.has_method("p0_place") else ""
		"outpost":
			var o = w.get("outpost")
			id = str((o as Dictionary).get("id", "")) if o is Dictionary else ""
	# A pond or outpost that does not say which one goes back to the farm (刘邦 on #92), never to "pond:".
	return "%s:%s" % [space_of(w), id] if id != "" else "farm"

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
	if what == NOTIFICATION_APPLICATION_RESUMED:
		_on_resumed()
		if ui.notify != null:   # what was set for the background goes; the phone's settings may have changed meanwhile
			ui.notify.came_back()
			ui.notify_changed()
			ui.ask_again()
	elif what == NOTIFICATION_APPLICATION_PAUSED and ui.notify != null:
		ui.ask_away()
		if not session.view.is_empty():
			ui.notify.went_away(session.current(), Time.get_unix_time_from_system() * 1000.0,
				int(Time.get_time_zone_from_system().get("bias", 0)))

func _process(dt: float) -> void:
	_dev_shot(dt)
	_dev_mem(dt)
	_tick_screens(dt)
	if ui.offline:
		_probe_left -= dt
		if _probe_left <= 0.0: _probe()
	var v := session.current()
	if v.is_empty(): return
	if ui.view_wanted(session.view, Time.get_ticks_msec()): ui.set_view(v)   # SGODOT-260 Q3: not every frame
	_watch_day_pass(v)   # every frame: a pass runs out on the clock, not on a refresh
	_call("p0_frame", [v, dt])

## q(257) ⑤ / q(261) ⑦ (SGODOT-367): the Day Pass of the city the player is in running out says so once, an Info toast
## with the city's return fare (`Day Pass ended · Re-entry 15 Energy · 60 coins`); elsewhere it ends quietly. Said
## under a flight's cover it waits, and is said only if the player is still in that city then (P0Ui.toast_in_city).
var _pass_seen := {}   # {city, until}: the running pass of the city the player is in, last seen

func _watch_day_pass(v: Dictionary) -> void:
	if not P0Travel.away(v):
		_pass_seen = {}
		return
	var here := P0Travel.here(v)
	var until := float(v.get("travel", {}).get("passes", {}).get(here, {}).get("until", 0))
	if P0Travel.pass_left_ms(v, here) > 0.0:
		_pass_seen = {city = here, until = until}
		return
	if str(_pass_seen.get("city", "")) != here or float(_pass_seen.get("until", -1.0)) != until: return
	_pass_seen = {}
	# two lines as MAP-7-PASS-ENDED (243:176843) breaks them; a first line too wide for the toast's 232 wraps to three
	ui.toast_in_city("Day Pass ended · Re-entry\n%s" % P0Travel.fare_text(P0Travel.fare(v, here)), here)

func _on_action(cmd: Dictionary) -> void:
	if str(cmd.get("type", "")) == "energy_card":
		var verb = _call("p0_energy_verb", [])
		energy_card(int(ui.fab_state().get("need", 0)), str(verb) if verb != null else str(ui.fab_state().get("verb", "")))
		return
	if not cmd.is_empty(): _call("p0_action", [cmd])

## The Energy card for an action short of Energy (LOCK-09) and its observation-log line: the main key's (above), or a
## facility's fee button, which names its own need and verb (`Floor 2`, `Enter mine`; SGODOT-266).
func energy_card(need: int, verb: String) -> void:
	ui.open_energy_card(need, verb)
	session.report({"kind": "energy_card", "need": need})

## Seed Saver's float part for one reply's `seed_saved` events ({} when none): one kind names it, several count seeds.
static func seed_saver_line(v: Dictionary, saved: Array) -> Dictionary:
	if saved.is_empty(): return {}
	var kinds := {}
	for e in saved: kinds[str(e.id)] = int(kinds.get(str(e.id), 0)) + 1
	var one := kinds.size() == 1
	var sid: String = kinds.keys()[0]
	var what := P0Logic.item_name(v, sid) if one else "seeds"
	return {kind = "saved", key = "seed_saver", text = "Seed Saver · +%d %s" % [saved.size(), what],
		tone = UiFloatText.Tone.ITEM, icon = P0Logic.icon(sid if one else "seed_radish")}

## A trap's catch in this reply: [{id, count}] per fish kind in the order they came (one Collect, or a Take back that
## emptied it first); [] when the reply has no trap with fish in it.
static func trap_fish(events: Array) -> Array:
	if not events.any(func(e): return str(e.get("kind", "")) == "trap" and str(e.get("action", "")) in ["collected", "taken_back"] \
			and int(e.get("fish", 0)) > 0): return []
	var out: Array = []
	for e in events:
		if str(e.get("kind", "")) != "item" or not str(e.get("id", "")).begins_with("fish_") or int(e.get("delta", 0)) <= 0: continue
		var hit: Array = out.filter(func(f): return f.id == str(e.id))
		if hit.is_empty(): out.append({"id": str(e.id), "count": int(e.delta)})
		else: hit[0].count = int(hit[0].count) + int(e.delta)
	return out

## The trap's catch as item float parts, one a kind (TRAP-COLLECT-3; fish always `Name ×N`, 不知火舞 2d55f7fe, q(124) ⑦):
## float_lines joins them `Pond Crucian ×2 · Common Carp ×1`, two to a line (a third kind goes on a line above).
static func trap_parts(v: Dictionary, got: Array) -> Array:
	return got.map(func(f): return {kind = "item", key = "trap:" + str(f.id), text = "%s ×%d" % [P0Logic.item_name(v, str(f.id)), int(f.count)],
		tone = UiFloatText.Tone.ITEM, icon = P0Logic.icon(str(f.id))})

## A trap's first of a kind (q(124) ①): the Fish-dex first card as a landed fish's, titled `In your trap!`, one a new
## kind in the order the server gave them (q(49): one card at a time). The reply's `New city!` XP goes on the first card,
## a first Fine / Rare's Energy on the first card of that rarity; each card's Fish-dex count is the one it brought
## (`dex_back`: the new kinds still to come, 1/20 → 2/20 → 3/20). [{fish, rarity, xp, extras}]; [] for no new kind.
static func trap_cards(v: Dictionary, events: Array) -> Array:
	if trap_fish(events).is_empty(): return []
	var cards: Array = []
	var city_xp := 0
	var energy := {}   # rarity → Energy
	for e in events:
		match str(e.get("kind", "")):
			"first":
				var what := str(e.get("what", ""))
				if what.begins_with("catch:"):
					var fid := what.trim_prefix("catch:")
					cards.append({fish = fid, rarity = int(P0Logic.item(v, fid).get("rarity", 1)), xp = int(e.get("xp", 0)), extras = {}})
				elif what.begins_with("fishing_city:"): city_xp = int(e.get("xp", 0))
			"reward":
				if str(e.get("id", "")).begins_with("first_fish_"): energy[int(str(e.id).trim_prefix("first_fish_"))] = int(e.get("energy", 0))
	if not cards.is_empty() and city_xp > 0: cards[0].extras["city_xp"] = city_xp
	for j in cards.size():
		if j < cards.size() - 1: cards[j].extras["dex_back"] = cards.size() - 1 - j
	for r in energy:
		var hit: Array = cards.filter(func(k): return int(k.rarity) == int(r))
		if not hit.is_empty() and int(energy[r]) > 0: hit[0].extras["energy"] = int(energy[r])
	return cards

## q(134): a taken request's grown count (the server's request_progress) in words — {float: `Fresh Greens 3/5`} while it
## is short (a basket's item `Market Basket · Carrot 5/6`, a resident's plots `Five Little Plots · Plots 3/5`), {toast:
## `Fresh Greens · 5/5` / `Deliver at the Stall`, two lines as a check-in's} on the one that fills it; {} for a request
## the view no longer has.
static func progress_said(v: Dictionary, ev: Dictionary) -> Dictionary:
	var id := str(ev.get("id", ""))
	var r := P0Logic.PinReason.request_of(v, id)
	if r.is_empty(): return {}
	var title := str(r.get("title", ""))
	var qty := int(ev.get("qty", r.get("qty", 1)))
	if bool(ev.get("done", false)): return {toast = "%s · %d/%d\n%s" % [title, qty, qty, str(r.get("deliver", ""))]}
	var have := int(ev.get("have", 0))
	var item := str(ev.get("item", ""))
	if item != "": return {float = "%s · %s %d/%d" % [title, P0Logic.item_name(v, item), have, qty]}
	var taken: Array = P0Logic.PinReason.taken(v).filter(func(t): return str(t.get("id", "")) == id)
	if not taken.is_empty() and str(taken[0].get("kind", "")) == "sow":
		return {float = "%s · %s %d/%d" % [title, str(r.get("need_name", "Plots")), have, qty]}
	return {float = "%s %d/%d" % [title, have, qty]}

## A filled request's toast comes after the reply's cards (q(134) ⑤): a level-up's banner is deferred, so the toast
## waits this long, then for the cards to close. A landed fish's and a trap's wait for their own cards (_on_state).
const REQUEST_TOAST_AFTER_S := 0.55
## q(218): the resident's thanks line comes once the delivery's floats are up (不知火舞 on 344: floats first, then the line).
const THANKS_AFTER_S := 0.4

## The filled request's toast a landed catch's reply held (catch_toast), handed over once: the world shows it after the
## catch's card.
func take_catch_toast() -> String:
	var held := catch_toast
	catch_toast = ""
	return held

## The Fish-dex milestone card a landed catch's reply held (catch_cards), handed over once: the world queues it after
## the catch's Caught! card.
func take_catch_cards() -> Array:
	var held := catch_cards
	catch_cards = []
	return held

## The floats a landed catch's reply held for the world (catch_floats), handed over once: the world lets them rise.
func take_catch_floats() -> Array:
	var held := catch_floats
	catch_floats = []
	return held

func anchor() -> Vector2:
	var at = _call("p0_anchor", [])
	return at if at is Vector2 else get_viewport().get_visible_rect().size * Vector2(0.5, 0.42)

# ---------------------------------------------------------------- server results
## Energy held while a cross-city flight is in the air (q(147) ⑥): its float parts, let go on landing.
var travel_floats: Array = []

## The flight is down (landed, skipped, or cut short — the map left, suspended, the app in the background): the
## place chip and the HUD's Energy follow the view again and the held Energy floats, with the welcome (不知火舞 on 299).
func release_travel() -> void:
	ui.hold_here("")
	ui.hold_energy({})
	if travel_floats.is_empty(): return
	var parts := travel_floats
	travel_floats = []
	ui.queue_floats(parts, anchor())

## A tree pick's XP line's key (all its farming XP in one part; see tree_pick).
const TREE_XP := "tree_xp"

## A generated home's places (SGODOT-303/311), read once from the server like any city's (P0CityPlaces), so the home
## set (P0Outposts.home: names, Show on map, Today) has them; the written city's are the client's own tables.
func _read_home_places(v: Dictionary) -> void:
	var travel = load("res://modules/p0/p0_travel.gd")
	var home := str(travel.home(v))
	var places = load("res://modules/p0/p0_city_places.gd")
	if home == "" or travel.home_is_written(v) or places.has_city(home) or session == null: return
	places.fetch(session, home)

func _on_state(v: Dictionary, events: Array) -> void:
	var before: Dictionary = ui.view
	var guide_feedback := _guide_feedback.take(before, v, events)
	ui.set_view(v)   # cards built below read the fresh view (Fish-dex, creel, meals)
	if before.get("energy", {}).has("value") and events.any(func(e): return str(e.get("kind", "")) == "homestead" and int(e.get("energy", 0)) > 0):
		ui.hud.roll_energy_from(int(before.energy.value))
	ui.blackjack_events(events)   # the Blackjack table plays its deal / cards / result itself (SGODOT-351)
	_read_home_places(v)
	for ev in events: ui.teach(P0Guide.tip_for_event(ev, before, v))   # first cast / fire / meal (TUT-2; a level-up teaches in its banner)
	# §14.2 minutes 16 / 22: an item new to the bag (lettuce seeds in reach, a level gift's Worm Bait) flashes its
	# quick-bar slot once (UiQuickBar.flash: QuickSlot State=new, 600 ms). Not on the first view after starting.
	if not before.is_empty():
		for id in P0Guide.new_items(before, v): ui.quick_bar_node().flash(str(id))
	var at := anchor()
	# A trap's catch (SGODOT-289 TRAP-COLLECT-2 / -3, 69442ef6): its fish say themselves over the cage in one line,
	# `Pond Crucian ×2 · Common Carp ×1`, any XP under it as one `+N XP` (§6.8: half the catch XP, often 0 — then none;
	# 李白 on 289), and each kind flies into the creel badge (trap_flights). Nothing per fish.
	var trap_got := trap_fish(events)
	var trap_cards_now := trap_cards(v, events)   # its new kinds' In your trap! cards (q(124) ①), shown once they land
	if not trap_got.is_empty():
		var mark = _call("p0_trap_anchor", [])
		if mark is Vector2: at = mark
	# A claim in the Inbox (SGODOT-234): what came out floats from the button pressed, even seeds, dishes and fish (the
	# Bag slot is under the drawer). Only the reply that brings items: a state push before it leaves the spot waiting.
	var claimed := ui.inbox_float_at().is_finite() and events.any(func(e): return str(e.get("kind", "")) == "item" and int(e.get("delta", 0)) > 0)
	if claimed:
		at = ui.inbox_float_at()
		ui.inbox_claim_done()
	var floats: Array = []   # this reply's float parts: one float_lines call orders, merges and caps them (q(49) ①)
	if not guide_feedback.fish.is_empty(): floats.append(guide_feedback.fish)
	# q(218) A Fresh Radish (不知火舞 on 344, 812e77be): handed in on the resident's open bar, the reply floats one group over
	# the bar — `+20 coins`, `+5 Friendship`, `New recipe · Fresh Fish Soup` — and the resident says the thanks line after.
	var thanks := {}   # {resident, line}
	for e in events:
		if str(e.get("kind", "")) == "request" and str(e.get("status", "")) == "done":
			var line := P0Logic.request_thanks(v, str(e.get("id", "")))
			if line != "": thanks = {resident = P0Logic.request_owner(str(e.id)), line = line}
	var over_bar := ui.resident_float_at(str(thanks.get("resident", ""))) if not thanks.is_empty() else Vector2.INF
	if over_bar.is_finite(): at = over_bar
	# Arriving by air (q(147) ⑥, 不知火舞 on 299): the arrival's Energy — its float and the HUD's value — waits for the
	# flight to land (release_travel), with its welcome; so does any Energy that comes while it flies, and the HUD's
	# coins stay what they were too (q(261) ④).
	var by_air := world != null and world.has_method("on_arrival") \
		and (events.any(func(e): return str(e.get("kind", "")) == "arrival") or bool(_call("travelling", [])))
	if by_air and not before.is_empty() and not ui.energy_held(): ui.hold_energy(before.get("energy", {}), int(before.get("coins", -1)))
	var xp_lines: Array = []
	last_first_catch_xp = 0
	last_catch_extras = {}
	var settles_catch := events.any(func(e): return str(e.get("kind", "")) == "catch")
	var world_lands := false   # the world shows this reply's landed fish: its floats wait for the hand
	var filled_toast := ""     # a request this reply filled (q(134)): said after the reply's cards, below
	var dex_cards: Array = []  # a Fish-dex milestone's card: after the catch's own card (q(49)), below
	# A first's bonus XP is said by its own line, not added into the XP float: the first cook's and catch's on their
	# card's strip (Li Bai, int6 C11), the first harvest's as `First harvest! +10 XP · Radish` (§4.8.6).
	var first_cook_xp: Array = []
	var card_energy: Array = []   # a trap's first-fish Energy events its card says (q(124) ①); a Cookbook title's too
	var card_coins: Array = []    # a Cookbook title's coins, said on its card (+100 coins)
	# Harvest ×N's first harvest goes into its XP line (`+20 XP · 5 plants · First harvest`, q(124) ②), no line of its own.
	var folded_first: Array = []   # those firsts' xp events
	# …the first cook's only when that card comes (a normal serve at the stove); a Queue ×2 turn-over or a pot kept on its
	# own has none, so it floats a line of its own, `First cooked · +20 Cooking XP` (q(85)). A world without the hook
	# gives null.
	var cook_card: bool = _call("p0_cook_card_coming", [events]) == true
	# Away from the kitchen a pot Queue ×2 kept on its own floats and toasts nothing, its first-cook line, Energy rewards
	# and XP included (不知火舞 on 226): it is silent there (q(46) / q(71)) and floats rise from their object (q(34)),
	# which is not on screen. The XP still counts, the Cookbook still marks the page, a level-up keeps its banner.
	var at_stove: bool = world != null and world.has_method("p0_cook_card_coming")
	var quiet: Array = [] if at_stove else P0KitchenLogic.auto_kept_events(events)
	var hushed := func(e: Dictionary) -> bool: return quiet.any(func(q): return is_same(q, e))
	# A harvest reply's XP counts its plants, so a held harvest reads `+40 XP · 20 plants` (§4.8.3).
	var plants := events.filter(func(e): return str(e.get("kind", "")) == "item" and str(e.get("id", "")).begins_with("crop_") \
		and int(e.get("delta", 0)) > 0).size()
	if plants > 0: _held_plants = (_held_plants if ui.fab_held else 0) + plants
	# A tree's pick (不知火舞 on 286 6e15f758, q(124) ②'s two lines; q(195)): `+2 Apple` over one XP line, no plant count.
	# The first pick puts the planting's locked XP, the pick's own and the First harvest together, at different
	# percentages, so its line writes the total only, `+19 XP · First harvest`; a later pick has one, `+1 XP · 50%`.
	var tree_pick := plants == 1 and events.any(func(e): return str(e.get("kind", "")) == "item" and int(e.get("delta", 0)) > 0 \
		and P0Logic.crop(v, str(e.get("id", ""))).get("perennial", false) == true)
	var tree_total := tree_pick and (events.any(func(e): return str(e.get("kind", "")) == "first" and str(e.get("what", "")).begins_with("harvest:")) \
		or events.filter(func(e): return str(e.get("kind", "")) == "xp" and str(e.get("skill", "")) == "farming").size() > 1)
	var good_pot := events.any(func(e): return str(e.get("kind", "")) == "dish" and int(e.get("quality", 0)) >= 1)
	# A craft's output is said by the workbench (`+2 Torch` on its card, the pickaxe's Moment; SGODOT-231 B2-06).
	var crafted := events.any(func(e): return str(e.get("kind", "")) == "craft")
	for i in events.size():
		var ev: Dictionary = events[i]
		if hushed.call(ev): continue
		match str(ev.get("kind", "")):
			"xp":
				# The server emits a first-time bonus as `first` immediately followed by its `xp`.
				var bonus: bool = i > 0 and str(events[i - 1].get("kind", "")) == "first" and int(events[i - 1].xp) == int(ev.amount)
				var what := str(events[i - 1].get("what", "")) if bonus else ""
				# (a trap's New city! too when a card says it, not the trap's `+N XP`, q(124) ①; with no new kind there is no
				# card, so it stays in that XP, as a rod's catch of a known kind does — 苏烈 on #290)
				if bonus and (str(ev.skill) == "cooking" or what.begins_with("catch:") or what.begins_with("harvest:") \
						or (not trap_cards_now.is_empty() and what.begins_with("fishing_city:"))):
					first_cook_xp.append(ev)
				if what.begins_with("cook:") and not cook_card:
					floats.append({kind = "first", key = what, text = "First cooked · +%d Cooking XP" % int(ev.amount), tone = UiFloatText.Tone.XP})
				if what.begins_with("harvest:") and (plants > 1 or tree_pick): folded_first.append({amount = int(ev.amount), what = what})
				elif what.begins_with("harvest:"):
					var crop := what.trim_prefix("harvest:")
					floats.append({kind = "first", key = what, text = "First harvest! +%d XP · %s" % [int(ev.amount),
						P0Logic.item_name(v, crop)], tone = UiFloatText.Tone.XP})
				if int(ev.amount) > 0 and not bonus:
					xp_lines.append("+%d %s XP" % [int(ev.amount), str(ev.skill).capitalize()] + ("" if int(ev.percent) >= 100 else " · %d%%" % int(ev.percent)))
			"reward":
				if int(ev.energy) > 0: xp_lines.append(P0Logic.reward_line(str(ev.id), int(ev.energy)))
				# a trap's first Fine / Rare: its Energy is on its In your trap! card, not floated too (the float group stays in
				# q(49)'s three lines: the trap's XP and its fish)
				if str(ev.id).begins_with("first_fish_") and i > 0 and str(events[i - 1].get("kind", "")) == "energy" \
						and trap_cards_now.any(func(k): return int(k.extras.get("energy", 0)) > 0):
					card_energy.append(events[i - 1])
				if str(ev.id).begins_with("first_fish_"): last_catch_extras["energy"] = int(ev.energy)
				# Home Cook's +50 Energy is on its title card (不知火舞 on 282), a Fish-dex milestone's on its card (283), not floated
				# too: grantOnce puts its own Energy just before it (reason reward, the same amount); at the cap it puts none, so
				# the event before is another's
				if (str(ev.id).begins_with("cookbook_") or str(ev.id).begins_with("fishdex_")) and int(ev.energy) > 0 and i > 0 \
						and str(events[i - 1].get("kind", "")) == "energy" and str(events[i - 1].get("reason", "")) == "reward" \
						and int(events[i - 1].get("delta", 0)) == int(ev.energy):
					card_energy.append(events[i - 1])
				if str(ev.id).begins_with("fishdex_"): _dex_energy[str(ev.id)] = int(ev.energy)
			"milestone":
				# a Cookbook title's coins (Line Cook +100) and a Fish-dex milestone's (+100 at 10 kinds) are on its card:
				# noteMilestones / noteFishdex put them just before it
				if int(ev.get("coins", 0)) > 0 and i > 0 \
						and str(events[i - 1].get("kind", "")) == "coins" and int(events[i - 1].get("delta", 0)) == int(ev.coins):
					card_coins.append(events[i - 1])
			"first":
				var what := str(ev.what)
				if what.begins_with("catch:"):
					_dex_fish = what.trim_prefix("catch:")   # a new kind: the one a Fish-dex milestone's card names
					xp_lines.append("First catch! +%d XP" % int(ev.xp))
					last_first_catch_xp = int(ev.xp)
				elif what.begins_with("cook:"): xp_lines.append("New recipe! · First cooked · +%d Cooking XP" % int(ev.xp))
				elif what == "landed": xp_lines.append("First fish landed · +%d XP" % int(ev.xp))
				elif what == "cast": xp_lines.append("First cast · +%d XP" % int(ev.xp))
				elif what.begins_with("fishing_city:"):   # v5 keys are cluster ids: the event names the city (#206)
					var city := str(ev.get("name", what.trim_prefix("fishing_city:").capitalize()))
					xp_lines.append("First catch in %s · +%d XP" % [city, int(ev.xp)])
					last_catch_extras["city_xp"] = int(ev.xp)
	last_xp_lines = xp_lines
	var parcels_said := false
	# A level-up's banner speaks first (q(49): one thing at a time): the reply's Sent to Inbox card waits until it
	# closes, at the stove or away (不知火舞 on 226 / 233); the bell counts the parcels at once from the view.
	var levelled := events.any(func(e): return str(e.get("kind", "")) == "level")
	var parcel_notice := {}
	var first_level := not before.is_empty() and ["farming", "fishing", "cooking"].all(func(k):
		return int(before.get("skills", {}).get(k, {}).get("level", 1)) <= 1)
	for ev in events:
		# a title keeps its card away from the kitchen too, as a level-up keeps its banner
		if hushed.call(ev) and str(ev.get("kind", "")) not in ["level", "first", "mishap", "queue", "pot", "cabinet", "plate", "milestone", "reward"]: continue
		match str(ev.get("kind", "")):
			"arrival": _call("on_arrival", [ev])   # SGODOT-275: the map flies there and welcomes (q(108))
			"energy":
				if card_energy.any(func(x): return is_same(x, ev)): continue
				if str(ev.get("reason", "")) == "homestead": continue   # q(247): the HOME-2 banner already says the gain
				var dlt := int(ev.delta)
				# A catch's refund is said by its own float or card ("3 Energy back"), not twice.
				if settles_catch and str(ev.get("reason", "")) in ["refund", "line_in"]: continue
				# Inside the mine a floor fee is said by the mine's own float ("Floor 2 · −2 Energy", q(46)), not twice.
				if str(ev.get("reason", "")) == "mine_floor" and str(_call("p0_surface", [])) == "mine": continue
				var part := {kind = "energy", key = "energy", amount = dlt, fmt = "%s Energy"}
				if by_air:
					# a fare's `−30 Energy` and a first visit's `+10 Energy` are lines of their own, the +10 over the fare's
					# coins: `−30 Energy` · `−120 coins` · `+10 Energy` from the bottom (q(261) ④, 不知火舞 on 367 ec5f2daa ⑤)
					if str(ev.get("reason", "")) == "first_visit": part.merge({kind = "energy_bonus", key = "energy_bonus"}, true)
					travel_floats.append(part)
					continue
				# Row Hoe's Sow ×3 says its beds: `−6 Energy · 3 plots` (q(124) ③); the seeds it took count them
				if str(ev.get("reason", "")) == "sow":
					var beds: int = -events.filter(func(e): return str(e.get("kind", "")) == "item" and str(e.get("id", "")).begins_with("seed_")) \
						.reduce(func(n, e): return n + mini(0, int(e.get("delta", 0))), 0)
					if beds > 1: part.merge({unit = "plots", count = beds})
				floats.append(part)
			"xp":
				var cook := str(ev.skill) == "cooking"
				var nth := int(ev.get("nth", 0))   # a pot's place among today's pots of its page (q(94))
				if cook and nth >= 3 and int(ev.amount) <= 0:   # the 3rd pot of a page on: no XP, and the float says why
					floats.append({kind = "xp", key = "cook_nth", text = "No XP · %s today" % P0KitchenLogic.ordinal(nth), tone = UiFloatText.Tone.MUTED})
				elif int(ev.amount) > 0 and not trap_got.is_empty() and str(ev.skill) == "fishing":
					# the collect's own XP (§6.8); a first's bonus is on its In your trap! card (q(124) ①)
					if not first_cook_xp.any(func(x): return is_same(x, ev)):
						floats.append({kind = "xp", key = "trap_xp", amount = int(ev.amount), fmt = "%s XP", tone = UiFloatText.Tone.XP})
				elif int(ev.amount) > 0 and not first_cook_xp.any(func(x): return is_same(x, ev)):
					# A pot's own XP names its track and a Good / Perfect pot's star: +5 Cooking XP ★ (§4.8.6 / §7.2.2);
					# the 2nd pot of a page today says so instead of a percentage: +10 Cooking XP ★ · 2nd today (q(94)).
					var fmt := ("%s Cooking XP" + (" ★" if good_pot else "")) if cook else "%s XP"
					if cook and nth == 2: fmt += " · 2nd today"
					elif int(ev.percent) < 100 and not (tree_total and str(ev.skill) == "farming"): fmt += " · %d%%%%" % int(ev.percent)
					var part := {kind = "xp", key = fmt, amount = int(ev.amount), fmt = fmt, tone = UiFloatText.Tone.XP}
					# one plant per farming XP event: Harvest All's reply has one a plant, and the parts add up (3, not 3 × 3)
					if tree_pick and str(ev.skill) == "farming": part.key = TREE_XP   # one line for the tree's XP, uncounted
					elif plants > 0 and str(ev.skill) == "farming": part.merge({unit = "plants", count = 1})
					floats.append(part)
			"item":
				var iid := str(ev.id)
				if P0Decor.is_decor(iid) and int(ev.delta) > 0:   # bought at the stall, into Farm Storage (SGODOT-284)
					ui.toast_decor_bought(iid)
					continue
				# where a collected dish went (the kitchen's Keep toast); what a pot took (Cook All floats it, q(124))
				if iid.begins_with("dish_") or int(ev.delta) < 0: _call("p0_event", [ev, v])
				if int(ev.delta) > 0 and (claimed or (not crafted and not iid.begins_with("seed_") and not iid.begins_with("dish_") and not iid.begins_with("fish_"))):
					var part := {kind = "item", key = iid, amount = int(ev.delta), fmt = "%s " + P0Logic.item_name(v, iid),
						tone = UiFloatText.Tone.ITEM, icon = P0Logic.icon(iid)}
					if not P0Logic.fast_crop(v, iid).is_empty(): part.fmt_plural = "%s " + P0Logic.plural(P0Logic.item_name(v, iid))
					floats.append(part)
			"reward", "milestone":
				# Cookbook titles (§7.6.1): a card after the dish card, as a level-up's banner (deferred: COOK-4 first);
				# a Fish-dex milestone is 周瑜's (SGODOT-283).
				if str(ev.get("kind", "")) == "milestone" and str(ev.get("id", "")).begins_with("fishdex_"):
					var dex_card := _fishdex_card(ev, v)
					if dex_card.is_valid(): dex_cards.append(dex_card)
					continue
				var title := P0KitchenLogic.title_card(v, ev)
				if not title.is_empty(): ui.queue_card.call_deferred(func(): ui.show_title(title))
			"coins":
				if card_coins.any(func(x): return is_same(x, ev)): continue
				if ui.modal_kind == "blackjack": continue   # the table floats its own wins over the hand (q(240))
				# A request delivered from the counter drawer: its row floats the coins from its button (BOARD-DONE).
				if ui.modal_kind == "counter" and events.any(func(e): return str(e.get("kind", "")) == "request" and str(e.get("status", "")) == "done"): continue
				var coin_part := {kind = "coins", key = "coins", amount = int(ev.delta), fmt = "%s coins", tone = UiFloatText.Tone.COINS}
				if by_air:   # a fare's `−120 coins` (q(256)): with the landing, after `−30 Energy`, before `+10 Energy` (q(261) ④)
					travel_floats.append(coin_part)
					continue
				floats.append(coin_part)
			"parcel":
				if not guide_feedback.fresh and str(ev.get("key", "")).begins_with("guide_resend:"): continue
				# LOCK-14: rewards that did not fit the bag wait in the Inbox; one InboxNotice card under the bell for the
				# whole reply (BAG-5-2, q(87)).
				if not parcels_said:
					parcels_said = true
					var notice := P0Logic.parcel_notice(v, events.filter(func(e): return not hushed.call(e)))
					if levelled: parcel_notice = notice
					else: ui.inbox_notice_when_clear(notice)
			"catch":
				# A world that shows the catch itself (the open fishing panel) returns true; none at all gives null.
				if _call("p0_event", [ev, v]) == true: world_lands = str(ev.get("result", "")) == "landed"
				else: _on_catch(ev, xp_lines)
			"cast", "pot", "cabinet", "plate", "first", "mishap", "queue":
				_call("p0_event", [ev, v])
			"facility":   # Homestead Lv7's new beds took the Compost Bin's cell: it moved beside the workbench (q(172) ③)
				if str(ev.get("reason", "")) == "plots":
					var fname := str(P0Logic.content().get("facilities", {}).get("kinds", {}).get(str(ev.get("facility_kind", "")), {}).get("name", ""))
					ui.toast_success("%s · moved beside the Workbench" % fname, true)
			"decor":   # Decorate (SGODOT-284, b706e141 ④): a piece stored says where it went, as a purchase does
				if str(ev.get("action", "")) == "stored": ui.toast_success("%s · back in Farm Storage" % P0Decor.name_of(str(ev.get("item", ""))), true)
			"trap":   # Fish Trap (SGODOT-283): the pond redraws its float; set / some left / taken back say so
				_call("p0_event", [ev, v])
				var said := P0Logic.P0Trap.event_toast(ev)
				if said != "": ui.toast_success(said)
			"dish":
				# The farmhouse stove shows its own result card (COOK-4 / 6 / P0-9) or toast. Anywhere else no card pops
				# up (§7.2.7 step 7, q(46)). A pot Queue ×2 kept on its own says nothing away from the kitchen (§7.2.7,
				# q(46) / q(71); 不知火舞 on 226): Today and the stove's sign show it. A collect answered after the player
				# left says where the dish went. A world without p0_event (farm, map, outpost) gives null, so compare
				# instead of bool() (PR #54 review).
				if _call("p0_event", [ev, v]) != true and not bool(ev.get("auto", false)):
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
					ui.toast("Full belly · Meals reset in " + P0Logic.span(float(v.get("meals", {}).get("resets_in", 0))) if int(ev.counted) <= 0 and int(ev.nominal) > 0 else "Same dish · no Energy today")
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
				# a title the level brings (Farming Lv10 Master Gardener, §4.8.3): its card after the banner (SGODOT-275)
				for t in P0Logic.level_titles(str(lv.skill), int(lv.level)):
					var card := P0Logic.title_card(str(lv.skill), int(lv.level), str(t))
					ui.queue_card.call_deferred(func(): ui.show_title(card))
			"affinity":   # SGODOT-225 / 228: first chat of the day, gifts, requests
				if not guide_feedback.fresh and str(ev.get("resident", "")) == "res_pip" and events.any(func(e):
					return str(e.get("kind", "")) == "guide" and str(e.get("action", "")) == "resend"): continue
				var reply := P0Logic.resident_reply(str(ev.get("resident", "")), str(ev.get("verdict", "")))
				# A thanks delivery's +5 joins its float group over the bar, `+5 Friendship` (不知火舞 on 344)
				if over_bar.is_finite() and str(ev.get("reason", "")) == "request" and str(ev.get("resident", "")) == str(thanks.resident):
					floats.append({kind = "affinity", key = str(ev.resident), text = "%+d Friendship" % int(ev.get("delta", 0)), tone = UiFloatText.Tone.AFFINITY})
				elif not guide_feedback.resends.is_empty() and str(ev.get("resident", "")) == "res_pip":
					# A first chat and a resend can share one reply. Group them over the same bar, not two overlapping pills.
					if int(ev.get("delta", 0)) != 0:
						guide_feedback.resends[0].affinity.append({kind = "affinity", key = "res_pip", text = P0Ui.affinity_text(ev), tone = UiFloatText.Tone.AFFINITY})
				# On the resident's open bar: the Affinity pill over it and the answer in the bubble (RES-KAI-TALK).
				elif not ui.resident_affinity(ev, reply):
					if int(ev.get("delta", 0)) != 0:
						floats.append({kind = "affinity", key = str(ev.get("resident", "")), text = P0Ui.affinity_text(ev),
							tone = UiFloatText.Tone.AFFINITY})   # the tone draws the heart
					if reply != "": ui.toast(reply)
			"gift_meal":
				var who := str(P0Logic.content().get("residents", {}).get(str(ev.get("resident", "")), {}).get("name", ""))
				# SGODOT-232: with the bag full the meal waits in the Inbox (to: parcel), gone at 04:00 like any gift meal;
				# it is said by the Sent to Inbox card, `From Pip · Expires in 9h 12m` (q(88)), after a level-up's banner.
				if str(ev.get("to", "")) == "parcel":
					var meal := P0Logic.gift_meal_notice(v, ev, events)
					if levelled: parcel_notice = meal
					else: ui.inbox_notice_when_clear(meal)
				elif bool(ev.get("given", false)): ui.toast_success("%s gave you %s · in your bag" % [who, P0Logic.item_name(v, str(ev.get("dish", "")))])
			"recipe":   # a page turned Tasted (§7.5.3): a resident's lesson, a story request, a Recipe Card (哪吒's from: card)
				# Appendix wording: `Learned · Herb Grilled Fish` / `Recipe Card · Pumpkin Fish Stew`; on the open bar the
				# resident says the lesson's line. Cooking it once still makes it the player's own.
				var page := P0Logic.item_name(v, str(ev.get("page", "")))
				if str(ev.get("from", "")) == "taught":
					ui.resident_affinity({"resident": str(ev.get("resident", "")), "delta": 0}, "Let me show you a dish.")
				# q(218) ①: a teaching request's page is the third line of its float group, `New recipe · Fresh Fish Soup` with
				# the recipe-card icon — not a toast, which the delivery's own toast would replace (不知火舞 on 344), and never
				# RESIDENT-TEACH
				if str(ev.get("from", "")) == "request" and P0Logic.is_intro_request(str(ev.get("resident", "")), str(ev.get("request", ""))):
					floats.append({kind = "result", key = "recipe:" + str(ev.page), text = "New recipe · %s" % page, tone = UiFloatText.Tone.ITEM,
						icon = P0Logic.icon("recipe_card")})
				else: ui.toast_success(("Recipe Card · %s" if str(ev.get("from", "")) == "card" else "Learned · %s") % page)
			"request_progress":   # q(134): a taken request's count grew — its line over the items, or the toast when full
				var said := progress_said(v, ev)
				if said.has("float"):
					floats.append({kind = "request", key = "request:%s:%s" % [str(ev.get("id", "")), str(ev.get("item", ""))],
						text = str(said.float), tone = UiFloatText.Tone.ITEM})
				elif said.has("toast"): filled_toast = str(said.toast)
			"visit":   # Stamp Run checked in (不知火舞 / 李白 on #224): once, after the entry's cover and a keeper's greeting
				ui.toast_success_when_clear(P0Logic.visit_toast(v, str(ev.get("id", ""))))
			"title":   # a story request's title (§9.4.4 Trusted)
				ui.toast_success("New title · %s" % str(ev.get("id", "")))
			"kindred":   # q(171) ③: their postcard and title, a Milestone card after the affinity float (end of the frame)
				var kc := P0Kindred.card(v, ev)
				ui.queue_card.call_deferred(func(): ui.show_kindred(kc))
			"homestead":
				# HOME-2 (SGODOT-228): HOME-1 closes, the MomentBanner says what changed; the farm swaps the fence.
				if ui.modal_kind == "homestead": ui.close_modal()
				var home := P0Logic.home_moment(v, ev)
				ui.queue_card(func(): HomePanel.moment(ui, home))   # one moment at a time (q(49) ④)
				# LOOK-PICK (SGODOT-282, 49498df6): a look level's two looks rise after the banner, over the farm.
				var stage := str(ev.get("look", ""))
				if stage != "": ui.queue_card(func(): P0LookPick.open(ui, stage, true))
	# After the loop, so it is queued behind the level-up banner (itself deferred) even when the parcel came first.
	if not parcel_notice.is_empty(): ui.inbox_notice_when_clear.call_deferred(parcel_notice)
	# Seed Saver (Farming Lv10, q(118)): the seeds this reply gave back, on a line of their own after the harvest's items
	# (seeds otherwise float nothing): `Seed Saver · +1 Radish Seeds`, or `Seed Saver · +2 seeds` for different kinds.
	var saved := seed_saver_line(v, events.filter(func(e): return str(e.get("kind", "")) == "seed_saved" and not hushed.call(e)))
	if not saved.is_empty(): floats.append(saved)
	# Harvest All with a nearly full bag (q(123)): what fitted went in, the rest stays ripe. The row's result is a line
	# of its own over the XP and the crops (`Harvest 3 of 5 · bag full` / `+3 Radish` / `+6 XP · 3 plants`, E-04 and
	# 289 HARVEST-ROW-3; 不知火舞 on #269), and the hold stops.
	if not folded_first.is_empty():   # onto the row's first farming XP part, which the others merge into
		var on = null
		for p in floats:
			if str(p.get("kind", "")) == "xp" and (str(p.get("unit", "")) == "plants" or str(p.get("key", "")) == TREE_XP):
				on = p
				break
		if on != null:
			on.amount = int(on.amount) + folded_first.reduce(func(n, f): return n + int(f.amount), 0)
			on.tail = "First harvest"
		else:   # the row's own XP is 0 (crops far under the level): no line to ride on, so a single plot's line (哪吒 on #291)
			for f in folded_first:
				floats.append({kind = "first", key = f.what, text = "First harvest! +%d XP · %s" % [int(f.amount),
					P0Logic.item_name(v, str(f.what).trim_prefix("harvest:"))], tone = UiFloatText.Tone.XP})
	# Harvest ×N (289): the crops pop along the row first; its lines, its flights and the bag-full toast wait for that.
	var wave_at = _call("p0_harvest_wave", [events])
	var wave_s := float(wave_at) if wave_at != null else 0.0
	var short: Array = events.filter(func(e): return str(e.get("kind", "")) == "harvest_short")
	if not short.is_empty():
		floats.append(harvest_result(int(short[0].get("got", 0)), int(short[0].get("of", 0))))
		ui.fab_held = false
		if wave_s > 0.0: get_tree().create_timer(wave_s).timeout.connect(func(): _harvest_stopped(session.view))
		else: _harvest_stopped(v)
	if not trap_got.is_empty():
		floats.append_array(trap_parts(v, trap_got))
		for e in events:   # a partial collect: `1 left in the trap` over it (q(124) ①; the result's place, q(124) ⑦)
			var left := P0Logic.P0Trap.left_line(e) if str(e.get("kind", "")) == "trap" else ""
			if left != "": floats.append({kind = "result", key = "trap_left", text = left, tone = UiFloatText.Tone.ITEM})
		_call("p0_trap_flights", [trap_got.slice(0, UiItemFly.MAX_PER_BATCH)])
		# a new kind's In your trap! card once its fish are in the creel (the flights' length), one at a time (q(49))
		var cards := trap_cards_now
		if not cards.is_empty():
			var landed_s := UiItemFly.FLIGHT_S + UiItemFly.DELAY_STEP_S * (mini(trap_got.size(), UiItemFly.MAX_PER_BATCH) - 1)
			var toast := filled_toast   # a request the trap filled: after its cards (周瑜 on #302)
			filled_toast = ""
			var dex := dex_cards        # a Fish-dex milestone the trap made: after its In your trap! cards (苏烈 on #353)
			dex_cards = []
			get_tree().create_timer(landed_s + TRAP_CARD_AFTER_S).timeout.connect(func() -> void:
				for k in cards: ui.queue_card(ui.show_catch.bind(str(k.fish), int(k.rarity), int(k.xp), k.extras, TRAP_CARD_TITLE))
				for c in dex: ui.queue_card(c)
				if toast != "": ui.toast_success_when_clear(toast, false, true))
	# Any catch resets what is held: a player who left the pond mid-arc never let the last fish's floats rise, and an
	# escape after that must not float them (刘邦 on #154).
	if by_air and not bool(_call("travelling", [])): release_travel()   # no flight took off after all: nothing waits
	if settles_catch: catch_floats = floats if world_lands else []
	if world_lands: floats = []
	# A request this reply filled says so after the reply's cards (q(134) ⑤; 周瑜 on #302): a landed fish's after its
	# Caught! card (held with its floats: the pond lets it go, take_catch_toast), a trap's after its In your trap! cards
	# (their timer, above), anything else REQUEST_TOAST_AFTER_S on (a level-up's banner comes deferred). Bound to the UI
	# (哪吒 on #188): a world left within the wait still gets it; held, it waits for a TipCard on screen too.
	if settles_catch: catch_toast = filled_toast if world_lands else ""
	# A Fish-dex milestone (q(49); 苏烈 on #353): a landed fish's after its Caught! card (held for the world's settle, as
	# the toast), a trap's after its In your trap! cards (their timer, above), anything else at the end of the frame — after
	# the Caught! card a fish the world does not show queues in this loop (_on_catch) and a level-up's deferred banner.
	if settles_catch:
		for c in take_catch_cards(): ui.queue_card(c)   # one a fish left in the air still comes
		if world_lands:
			catch_cards = dex_cards
			dex_cards = []
	for c in dex_cards: ui.queue_card.call_deferred(c)
	if filled_toast != "" and not world_lands:
		get_tree().create_timer(REQUEST_TOAST_AFTER_S).timeout.connect(ui.toast_success_when_clear.bind(filled_toast, false, true))
	if wave_s > 0.0:
		var lines := floats
		get_tree().create_timer(wave_s).timeout.connect(func(): ui.queue_floats(lines, at))
	elif over_bar.is_finite():
		# a thanks delivery's group starts over the bar and over the reply's toast, read once that toast is laid out
		var lines := floats
		var who := str(thanks.resident)
		get_tree().process_frame.connect(func():
			var spot := ui.resident_float_at(who)
			ui.queue_floats(lines, spot if spot.is_finite() else at), CONNECT_ONE_SHOT)
	else: ui.queue_floats(floats, at)   # with the world's own lines of this reply, at the end of the frame
	if not thanks.is_empty():
		var who := str(thanks.resident)
		var said := str(thanks.line)
		get_tree().create_timer(THANKS_AFTER_S).timeout.connect(func(): ui.resident_say(who, said))
	if ui.modal_kind == "counter" and events.size() > 0:
		ui.set_view(session.current())   # the counter drawer follows the view; floats say what changed
		ui.counter_events(events)
	elif ui.modal_kind == "resident" and events.size() > 0:
		ui.set_view(session.current())
		ui.open_resident(ui._resident)   # affinity, gift and request states follow the reply
	# After rebuilding the bar: the confirmed resend reply wins over the next step's Pip line (C2 e028023c).
	for resend in guide_feedback.resends: _show_guide_resend.call_deferred(resend)

## Seeds only fly/float for the portion actually put in the bag. Parcels use the one ordinary InboxNotice above
## (q(229)); closing Pip before the reply never opens him again. His farm model/lifetime belongs to C2.
func _show_guide_resend(resend: Dictionary) -> void:
	if not is_inside_tree(): return
	if ui.surface == "farm": ui.resident_say("res_pip", str(resend.line))
	var n := int(resend.bagged)
	var parts: Array = resend.get("affinity", []).duplicate()
	var id := str(resend.item)
	if n > 0:
		parts.append({kind = "item", key = "guide_resend:" + id, amount = n, fmt = "%s " + P0Logic.item_name(ui.view, id),
			tone = UiFloatText.Tone.ITEM, icon = P0Logic.icon(id)})
	if parts.is_empty(): return
	# Let the rebuilt bubble settle before measuring its top.
	await get_tree().process_frame
	if not is_inside_tree(): return
	var at := ui.resident_float_at("res_pip") if ui.surface == "farm" else Vector2.INF
	if not at.is_finite(): at = anchor()
	ui.queue_floats(parts, at)
	if n <= 0: return
	var bag := ui.bag_target()
	UiItemFly.launch(ui.root, at, bag, P0Logic.icon(id), n, 0.0, func(): UiItemFly.bump(bag))

## FISH-3 / FISH-5 (§6.6, 16 · FISH-2 → 3 / 5): the first catch of a species gets the catch card, later
## ones a float; a gate break-free gets the four-line card once per species, then "Got away · Lv4";
## a plain escape is a float ("It got away · 3 Energy back", or the protection wording). `at` is where
## floats rise (over the player's head for a landed fish, the cast point for an escape, when the pond knows
## them); `card_after` holds the Caught! card that long after the reply's floats there (不知火舞 on 231 / #154).
func _on_catch(ev: Dictionary, _xp_lines: Array, at := Vector2.INF, card_after := 0.0) -> void:
	var where := at if at.is_finite() else anchor()
	var v := session.current()
	match str(ev.result):
		"landed":
			var fid := str(ev.fish)
			var r := int(ev.rarity)
			if last_first_catch_xp > 0:
				var first := last_first_catch_xp
				var extras := last_catch_extras.duplicate()
				var card := func(): ui.queue_card(func(): ui.show_catch(fid, r, first, extras))
				if card_after > 0.0: get_tree().create_timer(card_after).timeout.connect(card)
				else: card.call()
			else:   # a repeat species: no card, `Pond Crucian ×1` beside its +XP (§4.8.6) — one group, Energy → XP → items
				ui.queue_floats([{kind = "item", key = "catch:" + fid, text = "%s ×1" % P0Logic.item_name(v, fid),
					tone = UiFloatText.Tone.ITEM, icon = P0Logic.icon(fid)}], where)
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

## A Fish-dex milestone (`milestone` event, id fishdex_N; SGODOT-283, §6.9.2; 不知火舞 on 283): a RewardMoment Milestone
## after the catch's own card and floats (q(49)) — `Fish-dex 10/20` over the kind that made it, `+30 Energy · +100 coins`;
## at 20 `Fish-dex complete` · `20/20` · `+50 Energy · +300 coins · Badge`. Its Energy and coins are on it, not floated.
## The card to queue (bound to the UI: a world left before its turn still shows it), or an empty Callable.
var _dex_fish := ""            # the reply's newest kind (its first catch), for the card's name
var _dex_energy := {}          # fishdex_N → the Energy its reward granted
func _fishdex_card(ev: Dictionary, v: Dictionary) -> Callable:
	var id := str(ev.get("id", ""))
	var spec := P0FishDex.milestone_card(v, id, _dex_fish, int(_dex_energy.get(id, 0)), int(ev.get("coins", 0)), str(ev.get("title", "")))
	_dex_energy.erase(id)
	return Callable() if spec.is_empty() else ui.show_dex_milestone.bind(spec)

func _on_refused(code: String, detail: Dictionary, cmd: Dictionary) -> void:
	if str(cmd.get("type", "")).begins_with("bj_"):   # the Blackjack table says it in its own keys (SGODOT-351)
		ui.blackjack_refused(code, detail)
		return
	if str(cmd.get("type", "")) == "wear_title": ui.title_not_worn(str(cmd.get("id", "")))   # q(180): back to the server's
	if str(cmd.get("type", "")).begins_with("claim_parcel"): ui.inbox_claim_done()   # no items come: none float from it (亚瑟 on #93)
	# The farmhouse kitchen waits on cook / collect (its Cook buttons, the plate being served): let it recover.
	if str(cmd.get("type", "")) in ["cook", "batch_cook", "collect"]: _call("p0_event", [{"kind": "refused", "code": code, "cmd": cmd}, session.view])
	if str(cmd.get("type", "")) == "cast": _call("p0_event", [{"kind": "cast_refused", "code": code}, session.view])
	if str(cmd.get("type", "")) == "harvest": _call("p0_harvest_refused", [])   # a refused row: its wave never comes
	if code == "bag_full" and str(cmd.get("type", "")) == "reel":
		_call("p0_event", [{"kind": "fish_abort"}, session.view])
		session.send({"type": "reel", "outcome": "escaped"})
		ui.toast_error("Creel full · the fish slipped away")
		return
	# Decorate (SGODOT-284): a spot the server would not take says why in the bar's words; the cap, the cap line.
	if str(cmd.get("type", "")) in ["place_decor", "move_decor"]:
		if P0Decor.REASONS.has(code):
			ui.toast_error(str(P0Decor.REASONS[code]))
			return
		if code == "decor_cap":
			ui.toast(P0Decor.cap_line(session.view))
			return
	var trap_said = P0Logic.P0Trap.refusal_text(cmd, code, detail)   # Fish Trap (SGODOT-283)
	if trap_said != null:
		if str(trap_said) != "": ui.toast_error(str(trap_said))
		return
	# Mine and gathering refusals (SGODOT-231): races stay quiet, the rest say why in their own words.
	var said = P0MaterialLogic.refusal_text(code, detail, cmd)
	if said != null:
		if str(said) != "": ui.toast_error(str(said))
		return
	match code:
		"not_enough_coins", "not_enough_energy":   # a fare the server would not take (q(261) ⑤): the gap, once called back
			if str(cmd.get("type", "")) == "travel":
				# coins: the gap (fare + floor − wallet); Energy: the fare, as Fly's amber key says it (不知火舞 on 367 e0efcc15)
				if code == "not_enough_coins": ui.toast_error("Need %d more coins" % int(detail.get("need", 0)))
				else: ui.toast_error("Need %d Energy" % int(detail.get("cost", detail.get("need", 0))))
			else: ui.toast_error("Can't do that (%s)" % code)
		# SGODOT-275: a place in a city without a pass — its travel card (q(108)); travel_required (q(256) ④): a pass,
		# but the player is not in that city — the same card, at the return fare
		"pass_required", "trip_expired", "travel_required":
			var preview: Dictionary = detail.get("preview", {})
			if is_instance_valid(world) and world.has_method("open_travel"): world.open_travel(str(preview.get("cluster", "")), preview)
			else: ui.toast_error("Travel to %s first" % str(preview.get("name", "that city")))   # fares (q(256)): not free now
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
			# The upgrade away from home says what HOME-1's grey button says (不知火舞 / 李白, #150); other commands stay short.
			ui.toast_error(P0Logic.HOME_AWAY_TAP if str(cmd.get("type", "")) == "homestead_upgrade" else "At home only")
		"need_material", "skills_short", "max_level":
			# The shops and the workbench refuse with need_material too: only the upgrade reads HOME-1's gap — from where the
			# player is, and from the server's detail when the fresh view has no gap left to name (后裔 on #150).
			var gap := _home_gap() if str(cmd.get("type", "")) == "homestead_upgrade" else ""
			if gap != "": ui.toast_error(gap)
			elif code == "need_material":
				ui.toast_error("Need %d more %s" % [int(detail.get("need", 0)) - int(detail.get("have", 0)),
					P0Logic.item_name(session.current(), str(detail.get("item", "")))])
			elif code == "skills_short":   # HOME-1's own wording (appendix B), never the code (后裔 on #152)
				ui.toast_error("Skills total %d needed · now %d" % [int(detail.get("need", 0)), int(detail.get("have", 0))])
			elif code == "max_level": ui.toast_error("Highest level for now")
			else: ui.toast_error("Can't do that (%s)" % code)
		"energy_full":
			ui.toast_error("Energy full · eat later" if str(cmd.get("type", "")) == "eat" else "Energy full")
		"not_ready":
			ui.toast_error("Not ready yet")
		"creel_full":
			ui.toast_creel_full()   # FISH-4, §4.8.6, q(83)
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
		"limit_reached":   # a day's allowance used (the Compost Bin, a counter's buy-back): q(121)'s words (哪吒 on #286)
			ui.toast_error("Limit reached · %s" % P0Logic.span(float(detail.get("resets_in", 0))))
		"wrong_state", "bad_plot":
			pass   # the plot changed under a held repeat; the next frame shows its new state
		"stale_state", "guide_not_now":
			pass   # a retry of something the server already applied; the returned state re-renders the screen
		_:
			ui.toast_error("Can't do that (%s)" % code)

## HOME-1's line for a refused upgrade: the tap line away from home, else the first gap; "" when the view shows none.
func _home_gap() -> String:
	var hp := P0Logic.home_panel(session.current(), ui.space_here() == "home")
	return str(hp.tap) if str(hp.tap) != "" else str(hp.reason)

## P0_SHOT counters away from the outposts: the keeper ctx the outpost would pass (assets/p0/p0_outposts.json, SGODOT-227).
static func _dev_ctx(role: String) -> Dictionary:
	var o := P0Outposts.by_role(role)
	if o.is_empty(): return {}
	var ctx := {"keeper": str(o.get("keeper", {}).get("name", "")), "place": str(o.get("name", ""))}
	if o.has("nearest"): ctx["nearest"] = o.nearest
	return ctx

## FARM-3-RESULT-2 (E-04): the bag filled during a harvest. What went in stays in, the rest stays ready on the field;
## the run says how far it got (`Harvest 12 of 30 · bag full`, of the plants ready when it started) and the Error toast
## points at the stall with `Open bag ›`; the hold stops (a refusal ends the run).
func _harvest_bag_full() -> void:
	var v := session.current()
	var ready := (v.get("plots", []) as Array).filter(func(p): return str(p.get("state", "")) == "ready").size()
	if _held_plants > 0: ui.queue_floats([harvest_result(_held_plants, _held_plants + ready)], anchor())
	_harvest_stopped(v)

## The harvest's result line when the bag filled: `Harvest 3 of 5 · bag full` (E-04; Harvest All's row, q(123)).
static func harvest_result(got: int, of: int) -> Dictionary:
	return {kind = "result", key = "bag_full", text = "Harvest %d of %d · bag full" % [got, of], tone = UiFloatText.Tone.ITEM}

## The bag filled: the Error toast to the stall with `Open bag ›`, and the held key lets go.
func _harvest_stopped(v: Dictionary) -> void:
	var bag: Dictionary = v.get("bag", {})
	ui.toast_error("Bag %d/%d · Sell at Homestead Stall" % [(bag.get("slots", []) as Array).size(), int(bag.get("capacity", 25))], "Open bag")
	ui.fab_held = false
	_held_plants = 0

## A request that never got an answer (8 s, a 5xx or not JSON). The server URL goes to the log, not the screen.
func _net_failed(msg: String, cmd := {}) -> void:
	push_warning("P0: %s · %s" % [msg, session.base_url])
	if str(cmd.get("type", "")) == "wear_title": ui.title_not_worn(str(cmd.get("id", "")))   # q(180): back to the server's
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

## `then(view)` once the first state is in (now, when it already is): p0_boot waits on it to know whether a new player
## picks a home first (SGODOT-303). The launch cover stays up meanwhile, Can't connect and its retries included.
func when_first_view(then: Callable) -> void:
	if not session.view.is_empty():
		then.call(session.view)
		return
	session.state_changed.connect(func(v: Dictionary, _e: Array): then.call(v), CONNECT_ONE_SHOT)

## Whether the save waits for its home to be picked (view.home.pending): it plays nothing else meanwhile (the server
## refuses every other command with home_pending).
static func home_pending(view: Dictionary) -> bool:
	var h = view.get("home", null)
	return h is Dictionary and bool((h as Dictionary).get("pending", false))

## SGODOT-303: the home pick (P0HomeFlow) in place of the launch cover; `done` once choose_home is in — the caller
## brings up the first world under a new launch cover.
func pick_home(done: Callable) -> void:
	_launch_s = -1.0
	ui.hide_screen([P0SysScreen.Kind.LAUNCH, P0SysScreen.Kind.FAIL])
	_open_home_flow("choose_home", "", done)

## Settings › Home city (SGODOT-303 PR-4, HOME-CHANGE-PICK / -CONFIRM): the change of home over whatever world is up;
## ‹ Settings goes `back`. Moved, every layer closes and the farm comes up in the new home under the launch cover,
## then `Welcome home` (q(108)'s, 不知火舞 28883acf); the chip and the map read the new home from the view.
func change_home(back: Callable) -> void:
	_open_home_flow("change_home", P0Travel.home(session.view), func():
		toast_on_arrival("Welcome home")
		while AppRouter.instance_depth() > 0:
			var depth := AppRouter.instance_depth()
			AppRouter.pop_instance()
			if AppRouter.instance_depth() >= depth: break   # a locked layer stays
		get_tree().change_scene_to_file(FARM_SCENE), back)

func _open_home_flow(type: String, change_from: String, done: Callable, back := Callable()) -> void:
	_home_flow = load("res://scenes/p0/panels/p0_home_flow.gd").new(session, ui.safe_top(), ui.safe_bottom(), change_from)
	_home_flow.open_map = _open_pick_map
	_home_flow.close_map = close_pick_map
	ResourceLoader.load_threaded_request(MAP_SCENE)   # the pin page's map, warm by the time a city is picked (亚瑟)
	_home_done = done
	if back.is_valid(): _home_flow.left.connect(back)
	_home_flow.chose.connect(func(cluster: String, lat: float, lng: float):
		var cmd: Dictionary = P0HomePin.command(type, cluster, lat, lng)   # q(216): the pin
		_home_change_to = cluster if type == "change_home" else ""
		_home_at = [lat, lng]
		_home_key = P0Session.ui_key(cmd)
		if not session.send(cmd, _home_key): _home_flow.sent(false))
	if not session.command_settled.is_connected(_home_settled): session.command_settled.connect(_home_settled)
	ui.open_home_flow(_home_flow)

var _home_flow: Control
var _pick_map: Node   # the P0 map in its pick mode, pushed for the pin page (SGODOT-342 PR-2)

## The pin page's map (亚瑟 342 6418183a, plan A): the P0 map in its pick mode pushed over whatever is up; null while a
## navigation is under way (the page keeps its flat map).
func _open_pick_map(cluster: String) -> Object:
	close_pick_map()
	# a city the client's cluster table does not know (亚瑟 on #495 ①): no street mode, so the map would open as the
	# old Journey map (a crowd, Shanghai, the location prompt) — the page keeps its flat map
	if P0Clusters.region(cluster).is_empty(): return null
	var packed: PackedScene = null
	if ResourceLoader.load_threaded_get_status(MAP_SCENE) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		packed = ResourceLoader.load_threaded_get(MAP_SCENE) as PackedScene   # waits for the preload if it is still on
	if packed == null: packed = load(MAP_SCENE) as PackedScene
	_pick_map = AppRouter.push_packed(packed, {"home_pick": {"cluster": cluster}})
	return _pick_map

## A debug build with user://p0_memlog prints the engine's memory every 2 s to the log (tag godot): the pick map's
## measurements on an emulator (亚瑟 342 6418183a ⑤: MEMORY_STATIC and the video memory, beside dumpsys's PSS).
var _mem_left := 0.0
var _mem_on := -1
func _dev_mem(dt: float) -> void:
	if _mem_on < 0: _mem_on = 1 if OS.is_debug_build() and FileAccess.file_exists("user://p0_memlog") else 0
	if _mem_on == 0: return
	_mem_left -= dt
	if _mem_left > 0.0: return
	_mem_left = 2.0
	print("P0_MEM static=%d video=%d nodes=%d stack=%d pick=%s fps=%d frame_ms=%.1f" % [Performance.get_monitor(Performance.MEMORY_STATIC),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		AppRouter.instance_depth(), str(is_instance_valid(_pick_map)), Performance.get_monitor(Performance.TIME_FPS),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])

## Every way off the pin page pops its map (亚瑟 ②: a first pick's change_scene never touches AppRouter's stack), and
## only it: something else on top stays, the map then left for the stack's own unwinding.
func close_pick_map() -> void:
	var m := _pick_map
	_pick_map = null
	if not is_instance_valid(m): return
	if AppRouter.top_instance() == m: AppRouter.pop_instance()
	else: push_warning("P0Runtime: the pick map is not on top; left to the stack")
var _home_done := Callable()
var _home_key := ""
var _home_change_to := ""
var _home_at: Array = []   # the pin sent, [lat, lng]: a same-city move is taken only once the farm stands there

## Whether a choose_home / change_home answer leaves the home picked: taken, or refused because it already is — the
## first reply was lost on the way, so a second press is refused with the view the server has (周瑜 on #451: else the
## page would refuse every go until the app restarts). A first pick: the view no longer pending. A change (`change_to`,
## the city asked for): the view's home is that city — the change is not pending before or after — and, the pin sent
## given (`at`, [lat, lng]), view.home.farm stands within a metre of it: a same-city re-pin (q(216) ⑨) is already home
## before, so a `home_set_for_good` or a request the server never had would else read as moved (周瑜 on #495). The
## server keeps the pin as sent (farm_at = [at.lat, at.lng]).
static func home_taken(ok: bool, view: Dictionary, change_to := "", at: Array = []) -> bool:
	if ok: return true
	if view.is_empty(): return false
	if change_to != "":
		if P0Travel.home(view) != change_to: return false
		if at.size() != 2: return true
		var h = view.get("home", null)
		var farm = P0HomePin.lat_lng((h as Dictionary).get("farm", null)) if h is Dictionary else null
		return farm != null and P0HomePin.km_ll(farm, at) * 1000.0 < 1.0
	return not home_pending(view)

## choose_home answered: refused or lost, the pick stays for another go (the refusal says why as any does); taken (see
## home_taken), the pick goes and the first world comes under the launch cover.
func _home_settled(key: String, ok: bool, _code: String) -> void:
	if key != _home_key or _home_key == "": return
	_home_key = ""
	ok = home_taken(ok, session.view, _home_change_to, _home_at)
	if is_instance_valid(_home_flow): _home_flow.sent(ok)
	if not ok: return
	session.command_settled.disconnect(_home_settled)
	if is_instance_valid(_home_flow): _home_flow.pick_map = null   # popped here, before the farm comes (亚瑟 ②)
	close_pick_map()
	_home_flow = null
	ui.close_modal()
	cover_launch()
	var done := _home_done
	_home_done = Callable()
	if done.is_valid(): done.call()

## The launch is over once the first answer and a world are both in: the cover (or Can't connect) goes.
func _end_launch() -> void:
	if _launch_s < 0.0 or session.view.is_empty() or not is_instance_valid(world): return
	_launch_s = -1.0
	ui.hide_screen([P0SysScreen.Kind.LAUNCH, P0SysScreen.Kind.FAIL])
	_flush_arrival_toast()   # a changed home's `Welcome home`, once the cover is gone

## Every return to the foreground reads the state (§10.7.1); a slow read gets SYS-LOADING over the place.
func _on_resumed() -> void:
	if session.view.is_empty() or _blocked != "" or _launch_s >= 0.0: return
	_resume_ms = Time.get_ticks_msec()
	if not session.busy: session.refresh()
	else: session.refresh_after()

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
			if _block_url != "": ExternalLink.open(_block_url)

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
	_flush_arrival_toast()

## A toast for the place being opened (Go home's `Welcome home`, 司空震 on 286): said once its loading cover is gone, not
## under it. Without a trip on its way it shows now; one that never arrives drops it after ARRIVE_FAIL_S.
var _arrival_toast := {}
func toast_on_arrival(text: String) -> void:
	_arrival_toast = {text = text, t0 = Time.get_ticks_msec()}
	_flush_arrival_toast.call_deferred()   # after this frame's open_instance has set its cover (or not)

func _flush_arrival_toast() -> void:
	if _arrival_toast.is_empty() or not _arrive.is_empty() or _launch_s >= 0.0: return
	if Time.get_ticks_msec() - int(_arrival_toast.t0) <= int(ARRIVE_FAIL_S * 1000.0): ui.toast(str(_arrival_toast.text))
	_arrival_toast = {}

## Couldn't get there (q(78)): an error, a 5xx without the maintenance code, or 20 s without an answer.
func _arrival_failed() -> void:
	_arrive_s = -1.0
	ui.show_screen(P0SysScreen.Kind.PLACE_FAIL, {shot = _arrive.get("shot", null)})

## Go back (and Back) on Couldn't get there: to where the player came from.
func _on_screen_back(kind: P0SysScreen.Kind) -> void:
	if kind != P0SysScreen.Kind.PLACE_FAIL: return
	cancel_nav()   # the failed navigation's timing must not land on the world we fall back to
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
## 90 minutes; update; the scene cover over the farm (named the beginner pond) and its failure.
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
			var layer := _scene_overlay("res://scenes/p0/p0_pond.tscn", {"pond_id": P0City.beginner_pond()}) as P0LoadingLayer
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
## Camera unification (用户 via 奕星, 2026-10-09): how tall the player stands on screen in this world's camera — from
## the ground under the feet (the actor's origin) to the top of the head (the HeadEnd_M bone), as a fraction of the
## screen height (resolution free) and in px of the 360 × 800 base; with the camera's pitch and orthographic size.
## Bones, not the skinned meshes' boxes: those are rest-pose bounds whose depth also projects, more at a steeper pitch.
func measure_actor() -> Dictionary:
	var a = world.get("actor") if world != null else null
	var c := get_viewport().get_camera_3d()
	if not (a is Node3D) or c == null: return {}
	var head := Vector3.INF
	for sk: Skeleton3D in (a as Node3D).find_children("*", "Skeleton3D", true, false):
		var b := sk.find_bone("HeadEnd_M")
		if b >= 0: head = sk.global_transform * sk.get_bone_global_pose(b).origin
	if head == Vector3.INF: return {}
	var view := get_viewport().get_visible_rect().size
	var frac := (c.unproject_position((a as Node3D).global_position).y - c.unproject_position(head).y) / maxf(view.y, 1.0)
	var fwd := -c.global_basis.z
	return {"frac": snappedf(frac, 0.0001), "px800": snappedf(frac * 800.0, 0.1), "pitch": snappedf(rad_to_deg(asin(-fwd.y)), 0.1),
		"size": snappedf(c.size, 0.01), "view": [view.x, view.y], "world": str(world.name)}

## One frame of a drag step, as a real touch: Godot emulates it from the mouse, so lists scroll natively and the
## drawer sees the same ScreenTouch / ScreenDrag a phone sends. True once lifted.
func _shot_drag_step(step: PackedStringArray) -> bool:
	var at := Vector2(float(step[1]), float(step[2]))
	var to := at + Vector2(float(step[3]), float(step[4]))
	var ms := float(step[5]) if step.size() > 5 else 300.0
	var hold := float(step[6]) if step.size() > 6 else 0.0
	var t := (_shot_t - 2.0) * 1000.0
	if not _shot_drag:
		Input.emulate_touch_from_mouse = true
		# Flings and long presses are timed on movie frames, as a phone would see them at 30 fps.
		for c in ui.find_children("*", "Control", true, false):
			if c is UiDrawer or c is UiItemCell: c.set(&"clock", func() -> int: return int(_shot_ms))
		_shot_drag = true
		_shot_mouse(at, true)
		return false
	var k := clampf((t - hold) / maxf(ms, 1.0), 0.0, 1.0)
	_shot_mouse(at.lerp(to, k), null)
	if t < hold + ms: return false
	_shot_mouse(to, false)
	_shot_drag = false
	return true

func _shot_mouse(at: Vector2, press: Variant) -> void:
	var e: InputEventMouse
	if press == null:
		var m := InputEventMouseMotion.new()
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.relative = at - _shot_at
		e = m
	else:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = press
		b.button_mask = MOUSE_BUTTON_MASK_LEFT if press else 0
		e = b
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)   # never warp_mouse: that moves the user's own cursor
	_shot_at = at
	if _shot_finger == null:
		var layer := CanvasLayer.new()
		layer.layer = 128
		add_child(layer)
		_shot_finger = Panel.new()
		_shot_finger.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shot_finger.size = Vector2(36, 36)
		var dot := StyleBoxFlat.new()
		dot.bg_color = Color(0.1, 0.1, 0.1, 0.35)
		dot.set_corner_radius_all(18)
		dot.set_border_width_all(2)
		dot.border_color = Color(1, 1, 1, 0.8)
		_shot_finger.add_theme_stylebox_override(&"panel", dot)
		layer.add_child(_shot_finger)
	_shot_finger.position = at - _shot_finger.size * 0.5
	_shot_finger.visible = press == null or bool(press)

func _dev_shot(dt: float) -> void:
	var path := OS.get_environment("P0_SHOT")
	if path == "": return
	if _shot_t == 0.0: _shot_script = OS.get_environment("P0_SHOT_STEPS").split(",", false)
	_shot_t += dt
	_shot_ms += dt * 1000.0
	# P0_SHOT_FRAMES=<dir>: every frame of the whole viewport, for videos (run with --fixed-fps 30). --write-movie on a
	# Mac writes only the window's middle 640 px of an 800 px viewport.
	var frames := OS.get_environment("P0_SHOT_FRAMES")
	if frames != "":
		get_viewport().get_texture().get_image().save_png("%s/f%05d.png" % [frames, Engine.get_frames_drawn()])
	var limit := OS.get_environment("P0_SHOT_LIMIT_MS")
	if Time.get_ticks_msec() > int(limit if limit != "" else "30000"): get_tree().quit(2)
	if world == null and _shot_t < 6.0 and not is_instance_valid(_home_flow): return   # the home pick has no world: its steps (a drag) keep time
	if not _shot_script.is_empty() and _shot_t > 2.0:
		var step := str(_shot_script[0]).split(":")
		if _shot_script.size() != _shot_left:   # once per step: the frame a video of it starts at
			_shot_left = _shot_script.size()
			print("P0_SHOT step %s frame %d" % [_shot_script[0], Engine.get_frames_drawn()])
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
			"presscmd":   # the open card's command button (BOARD-3 Drop request → BOARD-DROPPED); presscmd:Play only that one
				if ui._modal != null:
					for b in ui._modal.find_children("*", "UiCommandButton", true, false):
						if step.size() < 2 or (b as UiCommandButton).text == step[1]: (b as UiCommandButton).activated.emit()
			"greet": ui.open_keeper_greeting(step[1], _dev_ctx(step[1]))
			"bag": ui.open_bag(step[1] if step.size() > 1 else "")
			"bagcat":   # bag drawer on one category tab, e.g. bagcat:Materials (SGODOT-225 storage stacks)
				if ui._bag != null and is_instance_valid(ui._bag):
					var i := P0BagDrawer.CATEGORIES.find(step[1])
					if i >= 0: (ui._bag._chips.get_child(i) as Button).button_pressed = true
			"counterpick":  # counterpick[:id] selects a stack in the counter's bag half: its Sell card shows (q(16) shots)
				if ui._counter != null and is_instance_valid(ui._counter) and ui._counter.grid != null and not ui._counter.grid.shown_items().is_empty():
					ui._counter.grid.select(step[1] if step.size() > 1 else str(ui._counter.grid.shown_items().front().id))
			"uitexts":   # every visible label / button text on screen (shots: check a frame by its words)
				var out: Array = []
				for c in ui.root.find_children("*", "Control", true, false):
					if not (c as Control).is_visible_in_tree(): continue
					if c is Label and (c as Label).text != "": out.append((c as Label).text)
					elif c is Button and (c as Button).text != "": out.append("[" + (c as Button).text + "]")
				print("P0_UI_TEXTS ", JSON.stringify(out))
			"bagpick":  # bagpick[:id] taps that item of the open bag drawer (none named: the last listed)
				if ui._bag != null and is_instance_valid(ui._bag) and not ui._bag.grid.shown_items().is_empty():
					ui._bag.grid.select(step[1] if step.size() > 1 else str(ui._bag.grid.shown_items().back().id))
			"energy": ui.open_energy_card(3, "Sow ×1")
			"todayshow":   # todayshow:<i | go> — Today opened and Show pressed on row i, or on the row going there (q(99) shots)
				var want := step[1] if step.size() > 1 else "0"
				var i := int(want) if want.is_valid_int() else P0Logic.today_rows(ui.view).map(func(r): return str(r.go)).find(want)
				ui.open_today()
				for c in ui.find_children("*", "Control", true, false):
					if c is UiTodayPanel and i >= 0: (c as UiTodayPanel).show_pressed.emit(i)
			"todaytap":   # todaytap:<text in the row> — Today opened and that row tapped (q(104): a fish it cannot land yet)
				ui.open_today()
				var rows := P0Logic.today_rows(ui.view).map(func(r): return str(r.line))
				var at := -1
				for k in rows.size():
					if at < 0 and rows[k].contains(":".join(step.slice(1))): at = k
				for c in ui.find_children("*", "Control", true, false):
					if c is UiTodayPanel and at >= 0: (c as UiTodayPanel).row_pressed.emit(at)
			"close": ui.close_modal()
			"auto":
				P0FishingPanel.auto_play = true
				P0Kitchen.auto_play = true
			"manual":
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
			"seedsel": ui.selected_seed = step[1]   # seedsel:<id> — the quick bar's selected item (P1 tree review shots)
			"skillsopen":   # skillsopen:fishing — the Skills drawer with that track's milestones unfolded (SGODOT-283 shots)
				ui.open_skills()
				for n in ui.find_children("*", "", true, false):
					if n.has_method("unfold"): n.unfold(step[1] if step.size() > 1 else "fishing", true)
			"profile": ui.open_profile()
			# q(180) shots: titles opens Titles from the profile's title; titlepick:<id> taps that row (ids keep their `:`)
			"titles":
				ui.open_profile()
				ui._profile.title_pressed.emit()
			"titlepick":
				var row := ui.root.find_child(("Title_" + ":".join(step.slice(1)).replace(":", "_")).validate_node_name(), true, false)
				if row is Button: (row as Button).pressed.emit()
			# Settings › Legal (q(129) shots): settings / licenses / licensetext:worldcover open them as the gear and the
			# rows do (‹ back to the profile); pagebottom scrolls the open page to its foot (SET-LICENSES-2-2).
			"settings": ui.open_settings(func(): ui.open_profile())
			# Crop-ready notifications (SGODOT-350 / 356) on a desktop: notify:<never|allowed|refused|old|ios-…> puts in a stand-in
			# phone (tools/dev) with a fresh account file; notifications opens Settings › Notifications; ask:<crops|radishes>
			# brings the soft prompt up as its conditions would.
			"notify":
				var shot_prefs := "user://p0_notify_shot.json"
				DirAccess.remove_absolute(ProjectSettings.globalize_path(shot_prefs))
				ui.notify = P0Notify.new(shot_prefs, load("res://tools/dev/p0_notify_fake_phone.gd").new(step[1] if step.size() > 1 else "never"))
			"notifications": ui.open_notifications(func(): ui.open_settings(func(): ui.open_profile()))
			"ask": ui.show_ask(P0Notify.ASK_RADISHES if step.size() > 1 and step[1] == "radishes" else P0Notify.ASK_CROPS)
			# the home pick (SGODOT-303) on a new save: homesearch:<text>, homecity[:<cluster>] (pick it, Continue),
			# homepin / homedrag / homebuild (below), homeback, homenear:<cluster>, homefail[:spots]; the change: homechange, homemove
			"homenear":   # a desktop's address is near nothing: show the page as if near <cluster> (Near you, not picked)
				if is_instance_valid(_home_flow):
					var near_row = _home_flow.cities.open_rows.filter(func(r): return str(r.id) == step[1])
					if not near_row.is_empty():
						_home_flow.cities.show_cities({"open": _home_flow.cities.open_rows, "near": near_row[0]}, "")
			# HOME-WELCOME (SGODOT-340 §4): homewelcome:<cluster> opens the pick as if the address were near it; homestart /
			# homeother press Start here / Choose another city
			"homewelcome":
				if is_instance_valid(_home_flow) and _home_flow.change_from == "":
					var open_rows: Array = _home_flow.cities.open_rows if _home_flow.cities != null else []
					var near_row = open_rows.filter(func(r): return str(r.id) == step[1])
					if not near_row.is_empty():
						# a second homewelcome builds both again (刘邦 on #476: a card left standing kept the list unbuilt)
						if _home_flow.cities != null: _home_flow.cities.queue_free()
						if _home_flow.welcome != null: _home_flow.welcome.queue_free()
						_home_flow.cities = null
						_home_flow.welcome = null
						_home_flow._cities_read({"open": open_rows, "near": near_row[0], "matches": []}, "")
			"homestart": if is_instance_valid(_home_flow) and _home_flow.welcome != null: _home_flow.welcome.start.activated.emit()
			"homeother": if is_instance_valid(_home_flow) and _home_flow.welcome != null: _home_flow.welcome.other.activated.emit()
			"homesearch":
				if is_instance_valid(_home_flow):
					_home_flow.cities.field.text = step[1]
					_home_flow.cities._typed(step[1])
			"homecity":
				if is_instance_valid(_home_flow):
					if step.size() > 1: _home_flow.cities.set_choice(step[1])
					_home_flow.cities.key.pressed.emit()
			# the pin page (SGODOT-342 PR-2): homepin:<lat>:<lng> puts the pin there; homedrag on (lifted) / off; homebuild
			# presses Build here (the confirm card over it), homestart2 the back-to-start key
			"homepin":
				if is_instance_valid(_home_flow) and _home_flow.spots != null:
					var page = _home_flow.spots
					page.map.pick_put(float(step[1]), float(step[2]), page.tip())
					page._refresh()
			"homedrag":
				if is_instance_valid(_home_flow) and _home_flow.spots != null and _home_flow.spots.map.get("dragging") != null:
					_home_flow.spots.map.dragging = step.size() < 2 or step[1] != "off"
					_home_flow.spots._refresh()
			"homebuild":
				if is_instance_valid(_home_flow) and _home_flow.spots != null:
					var b: UiCommandButton = _home_flow.spots.build
					if b.reason == "": b.activated.emit()
					else: b.unavailable_pressed.emit(b.reason)
			"homeback": if is_instance_valid(_home_flow) and _home_flow.spots != null: _home_flow.back_to_cities()
			"homechange": change_home(func(): ui.open_settings())   # Settings › Home city (PR-4)
			"homemove": if is_instance_valid(_home_flow) and _home_flow.confirm != null: _home_flow.confirm.move.pressed.emit()
			# the reading frames: the pin page's, or before it a first pick's card outline (342 8c4168ab)
			"homeloading":
				if is_instance_valid(_home_flow) and _home_flow.spots != null: _home_flow.spots.show_loading()
				elif is_instance_valid(_home_flow) and _home_flow.change_from == "" and _home_flow.loading == null:
					for page in [_home_flow.cities, _home_flow.welcome]: if page != null: page.visible = false
					_home_flow.loading = load("res://scenes/p0/panels/p0_home_welcome.gd").placeholder(ui.safe_bottom())
					_home_flow.add_child(_home_flow.loading)
			"homefail":   # the q(207) failures as their frames show them: homefail (the list), homefail:spots
				if is_instance_valid(_home_flow):
					if step.size() > 1 and _home_flow.spots != null: _home_flow.spots.show_failed()
					else: _home_flow.cities.show_failed(_home_flow.cities.query)
			"licenses": ui.open_licenses(func(): ui.open_settings(func(): ui.open_profile()))
			"mapdata": ui.open_map_data(func(): ui.open_licenses(func(): ui.open_settings(func(): ui.open_profile())))   # q(133) v3
			"licensetext": ui.open_license_text(step[1] if step.size() > 1 else "worldcover",
				func(): ui.open_licenses(func(): ui.open_settings(func(): ui.open_profile())))
			"noticeboard": ui.open_notice_board()   # the stall's Notice Board (q(164) shots)
			"noticeonline": ui.set_notice_online({"sh_market_1": 4, "sh_tea_1": 3, "sh_tackle_1": 3, "sh_post_1": 2})   # shots: who is in, as the frame
			"passport": ui.open_passport(Callable(), step[1] if step.size() > 1 else "cities")   # passport[:postcards] (q(171) shots)
			"passportpage": if ui.passport(): ui.passport().call("show_page", step[1])
			"passportclose": if ui.passport(): (ui.passport().find_child("Close", true, false) as BaseButton).pressed.emit()
			"kindredcard": ui.show_kindred(P0Kindred.card(session.current(), {"resident": step[1]}))   # kindredcard:res_pip
			"room":   # room:gn-498687~cabin0 — a generated city's outpost room, its city read first (resident shots)
				var id := str(step[1])
				load("res://modules/p0/p0_city_places.gd").fetch(session, id.get_slice("~", 0),
					func(_c): AppRouter.open_instance("res://scenes/p0/p0_outpost.tscn", {"outpost_id": id}))
			"biteboard": ui.open_bite_board(P0Outposts.by_role("tackle"))   # the home tackle shop's Bite Board (its keeper's line)
			"pagebottom":
				for sc in ui.root.find_children("*", "ScrollContainer", true, false): (sc as ScrollContainer).scroll_vertical = 100000
			"scrollto":   # scrollto:<node name> — the scroll holding that node brings it to its top (q(166) shots)
				var at := ui.root.find_child(step[1], true, false) as Control
				var sc: Node = at.get_parent() if at else null
				while sc != null and not (sc is ScrollContainer): sc = sc.get_parent()
				if sc: (sc as ScrollContainer).scroll_vertical = int(at.global_position.y - (sc.get_child(0) as Control).global_position.y)
			"editlook": ui.edit_look()   # the profile's Edit look ›: the dressing room above the current world (KEEP-P0-2)
			# 256 ⑦⑧ shots: profskill:farming / profdex tap the profile's skill card / Fish tile; profspin:120 drags
			# the outfit 120 px sideways (the spin's own gesture: press, past the slop, release).
			"profskill": if ui._profile: ui._profile.skill_pressed.emit(step[1] if step.size() > 1 else "farming")
			"profdex": if ui._profile: ui._profile.collection_pressed.emit("fish")
			"profcities": if ui._profile: ui._profile.collection_pressed.emit("cities")   # the Passport (PASS-1, SGODOT-275 shots)
			"citypage": ui.open_city_page(step[1])   # citypage:gn-1850147 — a city's page (PASS-2)
			"proffarm": if ui._profile: ui._profile.farm_pressed.emit()   # the farm card: HOME-1 over the profile (int11)
			"closelayer": ui.close_layer()   # a drawer's Close: one layer back over the profile, else the world (int11)
			"profspin":
				if ui._profile:
					var sp := ui._profile.spin
					var press := InputEventMouseButton.new()
					press.button_index = MOUSE_BUTTON_LEFT
					press.pressed = true
					sp._gui_input(press)
					for i in 12:
						var m := InputEventMouseMotion.new()
						m.button_mask = MOUSE_BUTTON_MASK_LEFT
						m.relative = Vector2(float(step[1] if step.size() > 1 else "120") / 12.0, 0)
						sp._gui_input(m)
					press = press.duplicate()
					press.pressed = false
					sp._gui_input(press)
			"resident": ui.open_resident(step[1] if step.size() > 1 else "res_pip")   # SGODOT-225 dialogue bar
			"resreq": ui.open_resident_request(step[1] if step.size() > 1 else "res_pip")   # the request card (q(104) shots)
			"creel":   # creel:0 — the creel badge's states for shots: the bag's free slots set locally (235 B1)
				var cv: Dictionary = session.view.duplicate(true)
				cv["bag"] = cv.get("bag", {}).duplicate()
				cv.bag["free"] = int(step[1])
				session.view = cv
				session.busy = true   # dev only: no answer replaces the made-up bag
				ui.set_view(session.current())
				ui.set_action(P0Logic.fish_action(session.current(), ""))
			"creeltap": ui._creel.pressed.emit()   # a tap on the creel badge
			"waitsoup":   # the first session's end, locally (A3 / q(95)): radishes and lettuce growing, the soup page known, one crucian
				var wv: Dictionary = session.view.duplicate(true)
				var plots: Array = []
				for i in 30: plots.append({"id": i, "state": "growing", "crop": "crop_radish" if i < 20 else "crop_lettuce",
					"xp_pct": 100, "ready_in": 12720000 if i < 20 else 27960000})
				wv["plots"] = plots
				wv["bag"] = wv.get("bag", {}).duplicate()
				wv.bag["slots"] = [{"id": "fish_crucian", "qty": 1}, {"id": "dish_herb_grilled_fish", "qty": 1}]
				for pg in wv.get("cooking", {}).get("cookbook", []):
					if str(pg.get("id", "")) == "dish_fish_soup":
						pg.merge({"known": true, "cooked": false, "can_cook": false, "name": "Fresh Fish Soup", "in": ["W1", "F1"]}, true)
					elif str(pg.get("id", "")) in ["dish_grilled_crucian", "dish_herb_grilled_fish"]: pg.merge({"known": true, "cooked": true}, true)
					else: pg["can_cook"] = false   # the made-up bag holds one crucian: nothing else cooks
				wv["req_done"] = [P0Guide.TUTORIAL]   # the first session is over: its guide rows are done
				if wv.get("stall", {}).get("board", {}).has("requests"):
					wv.stall.board.requests = wv.stall.board.requests.filter(func(r): return str(r.get("id", "")) != P0Guide.TUTORIAL)
				session.view = wv
				session.busy = true   # dev only: no answer replaces the made-up view
				ui.set_view(session.current())
			"restcard":   # restcard[:used] — the bench sheet (FARM-7-2); `used` marks today's rest taken, locally (q(96) shots)
				if step.size() > 1 and step[1] == "used":
					var rv: Dictionary = session.view.duplicate(true)
					rv["rest"] = rv.get("rest", {}).duplicate()
					rv.rest["used"] = int(rv.rest.get("limit", 1))
					session.view = rv
					session.busy = true   # dev only: no answer replaces the made-up rest
					ui.set_view(session.current())
				ui.open_rest_card()
			"stage":   # stage:res_pip:Trusted — a resident's affinity stage set locally from the content table (225 tone shots)
				var sv: Dictionary = session.view.duplicate(true)
				var stages: Array = P0Logic.content().get("affinity", {}).get("stages", [])
				var i := P0Logic.affinity_stage_index(step[2])
				var nxt: Variant = stages[i + 1] if i + 1 < stages.size() else null
				var r: Dictionary = sv.get("residents", {}).get(step[1], {})
				r.merge({"stage": str(stages[i][0]), "stage_from": int(stages[i][1]), "affinity": int(stages[i][1]) + 7,
					"next_stage": str(nxt[0]) if nxt != null else null, "next_at": int(nxt[1]) if nxt != null else null}, true)
				session.view = sv
				session.busy = true   # dev only: no answer replaces the made-up stage
				ui.set_view(session.current())
			"resprofile": ui.open_resident_profile(step[1] if step.size() > 1 else ui._resident)   # resprofile[:res_old_kai]
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
			"homepanel": ui.open_home_panel()   # HOME-1 at home (SGODOT-282 shots: the Looks rows)
			"homebottom":   # scroll HOME-1 to its foot (the Looks section)
				for sc in ui.root.find_children("*", "ScrollContainer", true, false): (sc as ScrollContainer).scroll_vertical = 100000
			"lookui":   # LOOK-PICK / HOME-1 Looks on screen (282 shots: check the layout by numbers)
				var out := {}
				for c in ui.root.find_children("*", "P0LookPick", true, false):
					var card := c as P0LookPick
					out["sheet"] = card.get_global_rect()
					for n in ["Title", "Subtitle"]: out[n] = [(card.find_child(n, true, false) as Label).text, (card.find_child(n, true, false) as Control).get_global_rect()]
					for k in card.options: out["option " + k] = [(card.options[k] as UiLookOption).look_name, (card.options[k] as UiLookOption).selected, (card.options[k] as Control).get_global_rect()]
					out["use"] = [card.use_button.label, card.use_button.get_global_rect()]
				for r in ui.root.find_children("Look_*", "HBoxContainer", true, false):
					var labels: Array = (r as Node).find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
					out[str(r.name)] = [labels, (r as Control).get_global_rect(), (r.get_child(1) as Label).get_theme_color(&"font_color").to_html(false)]
				print("P0_LOOK_UI ", out)
			"homeaway":   # HOME-1 from the Profile farm card away from home (At home); homeaway:tap also taps the grey button
				HomePanel.open(ui, false)
				if step.size() > 1 and ui._modal != null:
					for b in ui._modal.find_children("*", "UiCommandButton", true, false):
						(b as UiCommandButton).unavailable_pressed.emit((b as UiCommandButton).reason)
			"workbench": ui.open_workbench(step[1] if step.size() > 1 else "")   # SGODOT-231 B2-06 drawer, tools / supplies
			"toasterr": ui.toast_error(step[1] if step.size() > 1 else "Need 1 more Copper Ore")   # a refusal's Error toast (233)
			"inboxnotice":   # inboxnotice[:more|:full|:gift] — the Sent to Inbox card under the bell (BAG-5-2, q(87) / q(88); 234)
				var kind := step[1] if step.size() > 1 else ""
				if kind == "gift":   # Pip's gift meal into a full bag (q(88)): 9h 12m to 04:00
					var meal := {"kind": "gift_meal", "resident": "res_pip", "dish": "dish_grilled_crucian", "given": true, "to": "parcel"}
					ui.inbox_notice_when_clear(P0Logic.gift_meal_notice(session.current(), meal, [{"kind": "parcel",
						"id": "dish_grilled_crucian", "qty": 1, "waiting": false, "expires_in": 33120000, "gift": true}]))
				else:
					var parcel := {"kind": "parcel", "id": "seed_carrot", "qty": 5, "waiting": kind == "full"}
					var more := [{"kind": "parcel", "id": "bait_worm", "qty": 3, "waiting": kind == "full"}] if kind != "" else []
					ui.inbox_notice_when_clear(P0Logic.parcel_notice(session.current(), [parcel] + more))
			"measure": print("P0_MEASURE ", JSON.stringify(measure_actor()))   # the player's height on screen (camera unification)
			"netfail": _net_failed("dev", {"type": "dev"})   # netfail once: Didn't go through; twice: Offline (233)
			"screen": _dev_screen(step[1] if step.size() > 1 else "launch")   # screen:launch|slow|fail|maint|update|scene|placefail
			"wbtile":   # wbtile:craft_copper_pickaxe:0 taps that card's cost tile (NeedSource)
				var wb := ui.workbench()
				if wb != null and wb.card(step[1]) != null: wb.card(step[1]).tiles()[int(step[2])].pressed.emit()
			"wbicon":   # wbicon:craft_copper_pickaxe taps that card's item icon (its InfoSheet)
				var wbi := ui.workbench()
				if wbi != null and wbi.card(step[1]) != null: wbi.card(step[1]).icon_pressed.emit()
			"showmap":   # showmap:pond:pond_san_francisco_03 — what Today's Show on map does (int9 S1)
				ui.close_modal()
				ui.show_on_map.emit(":".join(step.slice(1)))
			"newrun": P0MaterialCards.open_new_run(ui, session.current(), func(c: Dictionary): session.send(c))   # MINE-P0-7
			"lockedspot": P0MaterialCards.open_locked_spot(ui, session.current(), step[1] if step.size() > 1 else "spot_clay_bank")   # MAT-3
			"showspot":   # showspot:mine — what a NeedSource's Show does (closes the layer, camera only, LOCK-08)
				ui.close_modal()
				ui.show_spot.emit(step[1])
			"radial": ui.open_radial()
			"blackjack":   # SGODOT-351 table from anywhere; blackjack:here also sends as from the card room (until 后裔's room)
				if step.size() > 1 and step[1] == "here":
					session.space = "outpost"
					session.place = "sf_card_room_1"
				ui.open_blackjack({"place": "Barbary Card Room", "keeper": "Lou"})
			"bjtap":   # bjtap:3 taps the rail's stack 3 (0 = 5 … 5 = 1K)
				if ui.blackjack() != null: ui.blackjack().tap_chip(int(step[1]))
			"bjdeal":
				if ui.blackjack() != null: ui.blackjack().deal(ui.blackjack().bet)
			"bjact":   # bjact:hit|stand|double|split|takeback|rules
				var bjp := ui.blackjack()
				if bjp != null:
					match step[1]:
						"takeback": bjp.take_back()
						"rules": bjp.open_rules()
						_: bjp.act(step[1])
			"bjdeck":   # bjdeck:AS:7D:KH:9C — the mock's next shoe (P0_BJ_MOCK only)
				if session.bj_mock != null: session.bj_mock.next_deck = Array(step.slice(1))
			"bjexpire":
				if session.bj_mock != null: session.bj_mock.expire()
			"closemodal": ui.close_modal()   # the card or sheet on top, as its ✕ (shots: a LOOK-PICK after an upgrade, 282)
			"kitchen", "put":   # the farmhouse owns the cooking drawer (P0Farmhouse.p0_dev); elsewhere there is no stove
				if not bool(_call("p0_dev", [step])): push_warning("P0_SHOT: %s works in the farmhouse only" % step[0])
			"cook": session.send({"type": "cook", "recipe": step[1]})
			"send":
				# send:type=reel|outcome=landed (commas separate steps, so no JSON here)
				var cmd := {}
				for pair in ":".join(step.slice(1)).split("|"):
					var kv := pair.split("=")
					cmd[kv[0]] = int(kv[1]) if kv[1].is_valid_int() else kv[1]
				session.send(cmd)
			"drag":   # drag:x:y:dx:dy[:ms[:hold ms]] — a touch at (x, y), held, moved by (dx, dy) over ms, lifted (SGODOT-265)
				if not _shot_drag_step(step): return
			"lvbanner":   # lvbanner:<skill>:<level> — that level-up's MomentBanner (review shots, P1 SGODOT-240)
				ui.show_level_up({"skill": step[1], "level": int(step[2]), "gifts": []})
			"wait":
				if _shot_t < 2.0 + float(step[1]): return
			"until":
				var ready := ui.has_modal() if step[1] == "modal" else bool(_call("p0_until", [step[1]]))
				if not ready and _shot_t < 40.0: return
			"skip": session.dev_skip(int(step[1]))
			"back": leave_world()
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
