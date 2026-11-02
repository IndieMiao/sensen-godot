class_name P0Notify
extends RefCounted
## The crop-ready local notification (q(236), SGODOT-350; Android first): when the app goes to the background, one
## notification at the soonest growing plot's time; none when nothing is growing; back in front, all cancelled. The
## phone's own, never the server's. Teaching seeds and sale-only fast crops take no part (q(236) ⑥ / q(245)).

const BODY := "Your farm is waiting."
const CHANNEL := "Crops ready"   # the Android channel, the same name as the Settings switch (⑤)
## Crops ripening within this of the soonest make the title `Crops ready to harvest` (②).
const SAME_MS := 60_000.0
## No notification from 22:00 to 08:00 phone time; one that falls there goes out at 08:00 (③).
const QUIET_FROM_H := 22
const QUIET_TO_H := 8

## The notification for a view projected to now (P0Session.current()): {at (unix ms), title, body}, or {} when no crop
## is growing. `bias_min` is the phone's offset from UTC in minutes (Time.get_time_zone_from_system().bias).
static func plan(view: Dictionary, now_ms: float, bias_min: int) -> Dictionary:
	var growing := {}   # crop → plots growing
	var ripe := {}      # crop → its soonest plot's ms from now
	for p in view.get("plots", []):
		var c := str(p.get("crop", ""))
		if str(p.get("state", "")) != "growing" or p.get("ready_in", null) == null: continue
		if not P0Logic.quick_seed(view, c).is_empty() or not P0Logic.fast_crop(view, c).is_empty(): continue
		growing[c] = int(growing.get(c, 0)) + 1
		if not ripe.has(c) or float(p.ready_in) < float(ripe[c]): ripe[c] = float(p.ready_in)
	if ripe.is_empty(): return {}
	var soonest: float = ripe.values().min()
	var due := now_ms + maxf(0.0, soonest)
	var at := after_quiet(due, bias_min)
	# Put off to 08:00, it names what is ripe by then; else what ripens within a minute of the soonest (②).
	var by := at if at > due else due + SAME_MS
	var kinds := ripe.keys().filter(func(c): return now_ms + float(ripe[c]) <= by)
	return {at = at, title = title(view, kinds, growing), body = BODY}

## `Radishes ready to harvest` — one plot of it growing says it in the singular, `Radish` (q(227) ②), an uncountable
## crop as it is (`Lettuce`, q(98)); two kinds or more, `Crops ready to harvest`.
static func title(view: Dictionary, kinds: Array, growing: Dictionary) -> String:
	if kinds.size() != 1: return "Crops ready to harvest"
	var c := str(kinds[0])
	var name := P0Logic.item_name(view, c)
	return "%s ready to harvest" % (name if int(growing.get(c, 0)) == 1 else P0Logic.plural(name))

## A time in the quiet hours (22:00–08:00 phone time) moved to the next 08:00; any other unchanged.
static func after_quiet(at_ms: float, bias_min: int) -> float:
	var local_s := int(floor(at_ms / 1000.0)) + bias_min * 60
	var day_s := posmod(local_s, 86400)
	var hour := day_s / 3600
	if hour >= QUIET_TO_H and hour < QUIET_FROM_H: return at_ms
	var to_8 := QUIET_TO_H * 3600 - day_s
	if hour >= QUIET_FROM_H: to_8 += 86400
	return float(local_s + to_8 - bias_min * 60) * 1000.0

# ---------------------------------------------------------------- the switch, the ask and the phone (q(236) ④ ⑤)
## The phone's side: GodotNotify (Android) or P0NotifyIOS (iOS, SGODOT-356) — null elsewhere, where there is no soft
## prompt and no Notifications row. `native` is it, or a test double with the same methods.
var native: Object
## Per account on this phone (TestAccounts.profile_file): `asked` — the soft prompt answered (Allow or Not now) —
## and `choice` — the player's: "on", "off", or "" never chosen. A reinstall or another phone starts unasked (q(235) ③).
var path := ""
var _saved := {}

func _init(path_ := "", native_: Object = null) -> void:
	path = path_
	native = native_
	if path != "" and FileAccess.file_exists(path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary: _saved = data

static func phone() -> Object:
	if Engine.has_singleton("GodotNotify"): return Engine.get_singleton("GodotNotify")
	return P0NotifyIOS.new() if OS.get_name() == "iOS" else null

func available() -> bool: return native != null

## {needs_grant (Android 13+), allowed (the app's notifications and the channel on), asked (ever by the game)}.
func system() -> Dictionary:
	if native == null: return {}
	var s = JSON.parse_string(str(native.call("state")))
	return s if s is Dictionary else {}

func asked() -> bool: return bool(_saved.get("asked", false))
func choice() -> String: return str(_saved.get("choice", ""))

## `Crops ready` on: the system allows, and the player chose on — or never chose, on Android 13+ where the system's
## allowing means they said yes there (⑤).
func switch_on() -> bool:
	var s := system()
	if not bool(s.get("allowed", false)): return false
	return choice() == "on" or (choice() == "" and bool(s.get("needs_grant", false)))

## The system said no (the app's notifications off, the channel off, or the runtime grant refused): the sub-page's
## notice. Never asked on Android 13+ is not a no (不知火舞 350 7bffafd7).
func system_refused() -> bool:
	var s := system()
	if s.is_empty() or bool(s.get("allowed", false)): return false
	return not bool(s.get("needs_grant", false)) or bool(s.get("asked", false))

## The soft prompt may come (the view's conditions aside): not answered on this phone; not on Android 13+ (and iOS)
## when the system already allows (on by default) or already said no to the game's dialog (④); not before the phone
## has said which (iOS answers a moment after launch).
func may_ask() -> bool:
	if native == null or asked(): return false
	var s := system()
	if s.is_empty(): return false
	if bool(s.get("needs_grant", false)) and (bool(s.get("allowed", false)) or bool(s.get("asked", false))): return false
	return true

## The soft prompt's answer: Allow turns the switch on and asks the system (Android 13+ never asked), or opens its
## settings when it says no (Android 12 and older with the app's notifications off); Not now leaves it off. Asked.
func answer(allow: bool) -> void:
	_save({asked = true, choice = "on" if allow else "off"})
	if allow: _ask_system()

## Settings › Notifications › `Crops ready`. On: the system's dialog if never asked, else its settings when it says
## no. Off: nothing is set any more (the system's grant is left alone). Either way the soft prompt counts as asked
## (q(237) ③).
func set_switch(on: bool) -> void:
	_save({asked = true, choice = "on" if on else "off"})
	if on: _ask_system()
	elif native != null: native.call("cancel_all")

func _ask_system() -> void:
	var s := system()
	if s.is_empty() or bool(s.get("allowed", false)): return
	if bool(s.get("needs_grant", false)) and not bool(s.get("asked", false)): native.call("request_permission")
	else: native.call("open_settings")

func open_settings() -> void:
	if native != null: native.call("open_settings")

## To the background: the one notification for this view (P0Session.current()), when the switch is on.
func went_away(view: Dictionary, now_ms: float, bias_min: int) -> void:
	if native == null: return
	native.call("cancel_all")
	if not switch_on(): return
	var p := plan(view, now_ms, bias_min)
	if not p.is_empty(): native.call("schedule", float(p.at), str(p.title), str(p.body), CHANNEL)

## Back in front: nothing waits and nothing shown stays (⑦).
func came_back() -> void:
	if native != null: native.call("cancel_all")

func _save(change: Dictionary) -> void:
	_saved.merge(change, true)
	if path == "": return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(_saved))

# ---------------------------------------------------------------- when the soft prompt asks (q(235) ①, q(236) ④)
const ASK_RADISHES := "Get a ping when your radishes are ready?"
const ASK_CROPS := "Get a ping when your crops are ready?"

## The question for this view, or "" while it may not ask yet. A save that went through the guide (end done or
## timeout) asks once the guide is over and a Radish is growing; any other (legacy, a plain new player) once any crop
## but a teaching seed is. Growing is the plot's state: watered, or kept by a sprinkler or the greenhouse — sown and
## not watered is not. Being on the farm outdoors, fingers up and nothing open are the screen's (P0Ui).
static func ask_question(view: Dictionary) -> String:
	if P0Guide.guide_on(view): return ""
	var g = view.get("guide", null)
	var guided: bool = g is Dictionary and str(g.get("end", "")) in ["done", "timeout"]
	for p in view.get("plots", []):
		var c := str(p.get("crop", ""))
		if str(p.get("state", "")) != "growing": continue
		if guided and c == "crop_radish": return ASK_RADISHES
		if not guided and P0Logic.quick_seed(view, c).is_empty() and P0Logic.fast_crop(view, c).is_empty(): return ASK_CROPS
	return ""
