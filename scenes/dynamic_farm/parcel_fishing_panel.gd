extends P0FishingPanel
## The pier's fishing panel (C-232): the old polished panel (one thumb button: Cast → Hook → hold to Reel, the gauge
## beside the float, the outcome notice; LOCK-24) on the parcel save. Only the backend changes, as P0FishingPanel did for
## P0: `cast_line` gets the server's line (tier, seed, bite time) back; the bite and the hook window are timed on this
## device from the server's bite time; the reel runs locally on the cast's seed (ParcelFishing.step, the server's own
## steps) and sends `reel_line` with how long after the bite it hooked and one bit per step. The server replays the bits
## and decides; the result is the save's `fishing.last`. A missed bite, a stall or Stop after the bite sends
## `cancel_line` (got away, 3 back); before the bite it gives all 5 back.
## FishingPresentation (pose, rod, line, float, landing arc) reads phase, held, model, landing and last_result().
## It extends P0FishingPanel for its look only: the gauge kept off the player's box (player_rect, set by the pier each
## frame) and the Hook key's pop; nothing of the P0 runtime (rt stays null).
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Fishing = preload("res://modules/dynamic_farm/parcel_fishing.gd")
const ParcelItems = preload("res://modules/dynamic_farm/parcel_items.gd")
## The tier names in the result line, as P0's rarity names.
const TIERS := ["Common", "Fine", "Rare"]
## Player-visible lines as PM finalised them on C-232#28 (C-45: short, no working shown).
const LINES := {
	"ready": "Cast when you are ready.",
	"casting": "Casting...",
	"watch": "Tap when a fish bites!",
	"bite": "A bite! Tap to hook!",
	"reel": "Keep the fish in the green bar.",
	"missed": "Missed the bite.",
	"escaped_line": "Reeling in…",
	"escaped": "No fish this time.",
	"escaped_head": "Fish escaped",
	"caught_head": "Fish caught!",
	"caught": "%s · %s +1",
	"saving": "Saving...",
	"stopped": "Fishing stopped.",
	"interrupted_head": "Fishing interrupted",
	"interrupted": "Cast again.",
	"no_energy": "Not enough Energy to cast.",
	"no_rod": "You need a fishing rod.",
	"no_bait": "That bait has run out.",
	"unreachable": "Couldn't reach the server. Tap Cast to retry.",
}

## The pier: send(commands) -> the store's result, farm (the save it holds), server_now() and selected_bait().
var host: Node
var _line := {}
var _bite_local := 0
var _hook_local := 0
var _hook_ms := 0

## The last settled cast for the landing arc ({outcome, fish_id, tier}).
func last_result() -> Dictionary:
	return _last

## Open at the edge and cast right away (the tap on the water was the Cast).
func open_parcel(pier: Node, target: Vector3, title: String) -> void:
	host = pier
	landing = target
	place_name = title
	site_id = "aquatic_park"
	phase = "ready"
	model = {}
	_last = {}
	_gauge.model = {}
	for n in [_message_card, _primary, _guide, _gauge]: n.visible = true
	show()
	_fit.call_deferred()
	opened.emit(site_id)
	_parcel_cast()

func _action() -> void:
	if _suppress_next_click:
		_suppress_next_click = false
		return
	if busy or phase == "playing": return
	if phase == "hook": _start_reel()
	elif phase in ["ready", "result", "error"]: _parcel_cast()

func _now() -> int: return Time.get_ticks_msec()

func _fishing() -> Dictionary:
	return Fishing.fishing_of(host.farm.get("fishing")) if host != null else Fishing.empty()

func _parcel_cast() -> void:
	busy = true
	model = {}
	_last = {}
	_reported = false
	phase = "casting"
	_show_notice(LINES.casting)
	cast_started.emit()
	_refresh_button()
	var bait = host.selected_bait()
	var commands := []
	# A line still in the water (the app closed while fishing): line it in, in the same batch, before casting again.
	if _fishing().cast != null: commands.append({"type": "cancel_line"})
	commands.append({"type": "cast_line", "bait": bait})
	var result: Dictionary = await host.send(commands)
	busy = false
	if not is_inside_tree() or not visible: return
	if not result.get("ok", false):
		phase = "ready"
		_show_notice(_refusal(result), "", "failed")
		_refresh_button()
		return
	_line = _fishing().cast if _fishing().cast is Dictionary else {}
	if _line.is_empty():
		phase = "ready"
		_show_notice(LINES.ready)
		_refresh_button()
		return
	# The bite on this device's clock: the server's bite time less its time now (carried from its last answer).
	_bite_local = _now() + int(_line.bite_at) - int(host.server_now())
	_hook_local = _bite_local + int(_line.hook_ms)
	phase = "waiting"
	_gauge.model = {}
	_show_notice(LINES.watch)
	_refresh_button()

func _refusal(result: Dictionary) -> String:
	match str(result.get("code", "")):
		"NO_ENERGY": return LINES.no_energy
		"NO_ROD": return LINES.no_rod
		"NO_BAIT": return LINES.no_bait
		"NETWORK": return LINES.unreachable
	return FishingPanel.error_text(str(result.get("code", "")))

func _start_reel() -> void:
	var f: Dictionary = ParcelFarm.rules().fishing
	var tier := Fishing.reel_tier(f, int(_line.rarity), Fishing.rod_of(f, str(_line.rod)))
	set_meta("tier", tier)
	_hook_ms = clampi(_now() - _bite_local, 0, int(_line.hook_ms))
	model = Fishing.initial(f, int(_line.seed))
	inputs = ""
	_accumulator = 0
	phase = "playing"
	_gauge.bar_size = float(tier.bar_size)
	_gauge.fish_texture = P0Logic.icon("fish_sil")
	_show_notice(LINES.reel)
	_refresh_button()

func _process(dt: float) -> void:
	if not visible or host == null or busy: return
	var now := _now()
	if phase in ["waiting", "hook"]:
		if now > _hook_local:
			_show_notice(LINES.missed, LINES.escaped_head, "failed")
			_line_in()
		elif now >= _bite_local and phase != "hook":
			phase = "hook"
			_show_notice(LINES.bite)
			Input.vibrate_handheld(80)
			_refresh_button()
		elif phase == "hook" and auto_play and now > _bite_local + 300:
			_start_reel()
	elif phase == "playing":
		if dt > 0.5:   # a stalled frame (the app hidden, a hitch): the fish gets away
			_line_in()
			return
		_accumulator += dt
		var tier: Dictionary = get_meta("tier")
		var f: Dictionary = ParcelFarm.rules().fishing
		var step_s := float(f.reel.step_ms) / 1000.0
		while _accumulator >= step_s and model.outcome == "playing":
			_accumulator -= step_s
			if auto_play: held = float(model.fish) > float(model.bar)
			inputs += "1" if held else "0"
			Fishing.step(f, model, held, tier)
		_gauge.model = model
		_gauge.queue_redraw()
		_message_card.visible = int(model.get("step", 0)) < 40
		_primary.set("progress", float(model.progress))
		_primary.set("pulling", held)
		_primary.queue_redraw()
		if model.outcome != "playing":
			phase = "settling"
			if model.outcome == "escaped": _show_notice(LINES.escaped_line, LINES.escaped_head, "failed")
			else: _show_notice(LINES.saving)
			_refresh_button()
			_send_reel()

## The reel's trace to the server; it replays it and says what came of it.
func _send_reel() -> void:
	if _reported: return
	_reported = true
	held = false
	busy = true
	var result: Dictionary = await host.send([{"type": "reel_line", "hook_ms": _hook_ms, "inputs": inputs}])
	# The trace reached the server sooner than its own clock allows (a slow first answer): once more, a moment later.
	if not result.get("ok", false) and str(result.get("code", "")) == "REEL_INPUT" and is_inside_tree():
		await get_tree().create_timer(0.4).timeout
		result = await host.send([{"type": "reel_line", "hook_ms": _hook_ms, "inputs": inputs}])
	busy = false
	if not is_inside_tree(): return
	_settled(result)

## A missed bite, a stall or Stop with a line in the water: in it comes (got away after the bite, all back before it).
func _line_in() -> void:
	if _reported: return
	_reported = true
	held = false
	busy = true
	phase = "settling"
	_refresh_button()
	var result: Dictionary = await host.send([{"type": "cancel_line"}])
	busy = false
	if not is_inside_tree(): return
	_settled(result)

func _settled(result: Dictionary) -> void:
	var last = _fishing().last
	phase = "result"
	if not result.get("ok", false) or not last is Dictionary:
		_last = {"outcome": "escaped"}
		model["outcome"] = "escaped"
		_show_notice(_refusal(result), LINES.escaped_head, "failed")
		_refresh_button()
		return
	match str(last.result):
		"landed":
			var fish := str(last.fish)
			var tier := int(ParcelFarm.rules().fishing.fish.get(fish, 1))
			_last = {"outcome": "caught", "fish_id": fish, "tier": tier}
			model["outcome"] = "caught"
			_show_notice(LINES.caught % [ParcelItems.name_of(fish), TIERS[clampi(tier - 1, 0, TIERS.size() - 1)]], LINES.caught_head, "caught")
		"cancelled":
			_last = {"outcome": "cancelled"}
			_show_notice(LINES.stopped)
		_:
			_last = {"outcome": "escaped"}
			model["outcome"] = "escaped"
			if _message_card.visible and _notice_heading.text != LINES.escaped_head: _show_notice(LINES.escaped, LINES.escaped_head, "failed")
			Input.vibrate_handheld(100)
	_refresh_button()

func _refresh_button() -> void:
	super._refresh_button()
	if phase == "result":
		_guide.visible = false

## Stop fishing: a line in the water comes in first (the server keeps none behind).
func _cancel(reason := "stopped") -> void:
	held = false
	if phase in ["waiting", "hook", "playing"] and not _reported:
		await _line_in()
	elif phase == "casting":
		return
	if reason == "interrupted": _show_notice(LINES.interrupted, LINES.interrupted_head, "failed")
	_refresh_button()

func close() -> void:
	if busy: return
	await _cancel()
	hide()
	closed.emit()
