class_name P0FishingPanel
extends FishingPanel
## The old polished fishing panel (one thumb button: Cast → Hook → hold to Reel, gauge beside the
## float, outcome notice) on the P0 rules. Only the backend changes: casts go out as P0 `cast`, the
## bite and hook window are timed from the server's bite_in / hook_ms, the reel minigame runs locally
## and reports `reel {landed | escaped | cancel}`; the server decides gates (broke free) and refunds.
## FishingPresentation (pose, rod, line, float, landing arc, close camera) reads the same fields.

const BREAK_MS := {2: 1500.0, 3: 2000.0, 4: 3000.0}   # §6.5.2: a gated fish breaks free this far in

var rt: P0Runtime
var site_key := "pond"        # P0 site (pond / river) for the cast command
var place_name := ""
var _bite_at := 0.0
var _hook_until := 0.0
var _rarity := 1
var _breaks := false
var _play_ms := 0.0
var _last: Dictionary = {}
var _reported := false
var _reel_retries := 0

func _ready() -> void:
	super._ready()
	layer = 30
	_title.visible = false   # the P0 place chip already names the pond; the close X takes the bell's corner
	# The old input shield covers the HUD below; let a tap on the place chip still mean "back to the map"
	# (the first tap reels in and closes, like the system back key, the next one leaves).
	var shield: Control = get_node("FishingInputShield")
	shield.gui_input.connect(func(e: InputEvent):
		if rt and P0Ui.is_tap(e) and rt.ui._place_chip.get_global_rect().has_point((e as InputEventMouseButton).global_position):
			rt.leave_world())

func last_result() -> Dictionary:
	return _last

## The old layout puts the close X at the panel's safe-area top; dock it in the P0 HUD's coins/bell
## corner instead (hidden while fishing), so it never lands on the place chip on notched screens.
func _fit() -> void:
	super._fit()
	if rt == null or rt.ui._right == null: return
	var corner: Control = rt.ui._right
	var r := corner.get_global_rect()
	_close_button.global_position = Vector2(r.end.x - _close_button.size.x, r.position.y + (r.size.y - _close_button.size.y) * 0.5)

## Open at the shore and cast right away (the world's main action was the Cast press).
func open_p0(runtime: P0Runtime, water_id: String, spec: Dictionary, target: Vector3, site: String, title: String) -> void:
	rt = runtime
	site_id = water_id
	site_spec = spec
	landing = target
	site_key = site
	place_name = title
	phase = "ready"
	model = {}
	_last = {}
	_gauge.model = {}
	_title.text = title
	show()
	_fit.call_deferred()
	opened.emit(water_id)
	_p0_cast()

func _action() -> void:
	if _suppress_next_click:
		_suppress_next_click = false
		return
	if busy or phase == "playing": return
	if phase == "hook": _p0_hook()
	elif phase in ["ready", "result", "error"]: _p0_cast()

func _p0_cast() -> void:
	busy = true
	model = {}
	_last = {}
	_reported = false
	phase = "casting"
	_show_notice("Casting...")
	cast_started.emit()
	_refresh_button()
	rt.session.send({"type": "cast", "bait": rt.ui.selected_bait if rt.ui.selected_bait != "" else null, "site": site_key})

## Server accepted the cast (P0 `cast` event): the fish is drawn; we only know its rarity and gate.
func on_cast(ev: Dictionary) -> void:
	busy = false
	var now := Time.get_ticks_msec()
	_bite_at = now + float(ev.get("bite_in", 2000))
	var cast = rt.session.current().get("fishing", {}).get("cast", null)
	var hook_ms := float(cast.get("hook_ms", 2200)) if cast is Dictionary else 2200.0
	_hook_until = _bite_at + hook_ms
	_rarity = int(ev.get("rarity", 1))
	_breaks = ev.get("breaks", null) != null
	phase = "waiting"
	_gauge.model = {}
	_show_notice("Watch the float. Tap when a fish bites!")
	_refresh_button()

## The cast was refused (energy, creel, already casting): back to ready with the reason shown by the HUD.
func on_refused() -> void:
	busy = false
	phase = "ready"
	_show_notice("Cast when you are ready.")
	_refresh_button()

func _p0_hook() -> void:
	var tier: Dictionary = (FishingModel.data().tiers[str(_rarity)] as Dictionary).duplicate()
	var bonus := float(rt.session.current().get("fishing", {}).get("band_bonus", 0.0))
	tier["bar_size"] = minf(0.45, float(tier.bar_size) + bonus)   # Reed Rod +3 points (§6.5.2)
	set_meta("tier", tier)
	model = FishingModel.initial(randi())
	inputs = ""
	_accumulator = 0
	_play_ms = 0.0
	phase = "playing"
	_gauge.bar_size = float(tier.bar_size)
	_gauge.fish_texture = P0Logic.icon("fish_sil")
	_show_notice(P0Logic.rarity_name(rt.session.current(), _rarity) + " fish · Keep the fish inside the green bar.")
	_refresh_button()

func _process(dt: float) -> void:
	if not visible or rt == null or busy: return
	var now := Time.get_ticks_msec()
	if phase in ["waiting", "hook"]:
		if now > _hook_until:
			_report("escaped")
			_show_notice("Missed the bite. Tap Hook when the float dips.", "Fish escaped", "failed")
			phase = "settling"
			_refresh_button()
		elif now >= _bite_at and phase != "hook":
			phase = "hook"
			_show_notice("A bite! Tap to hook the fish!")
			Input.vibrate_handheld(80)
			_refresh_button()
		elif phase == "hook" and P0Fishing.auto_play and now > _bite_at + 400:
			_p0_hook()
	elif phase == "playing":
		if dt > 0.5:
			_report("escaped")
			return
		_accumulator += dt
		_play_ms += dt * 1000.0
		var tier: Dictionary = get_meta("tier")
		var step_s := float(FishingModel.data().step_ms) / 1000.0
		while _accumulator >= step_s and model.outcome == "playing":
			_accumulator -= step_s
			if P0Fishing.auto_play: held = float(model.fish) > float(model.bar)
			inputs += "1" if held else "0"
			FishingModel.step(model, held, tier)
		_gauge.model = model
		_gauge.queue_redraw()
		_message_card.visible = int(model.get("step", 0)) < 40
		_primary.set("progress", float(model.progress))
		_primary.set("pulling", held)
		_primary.queue_redraw()
		if _breaks and _play_ms >= float(BREAK_MS.get(_rarity, 1500.0)):
			model.outcome = "escaped"
			phase = "settling"
			_show_notice("Saving...")
			_report("landed")   # the server answers broke_free with the gate (§6.1.2)
		elif model.outcome != "playing":
			phase = "settling"
			if model.outcome == "escaped": _show_notice("Reeling in the empty line…", "Fish escaped", "failed")
			else: _show_notice("Saving...")
			_report("landed" if model.outcome == "caught" else "escaped")
			_refresh_button()

func _report(outcome: String) -> void:
	if _reported: return
	_reported = true
	_reel_retries = 0
	held = false
	busy = true
	rt.session.send({"type": "reel", "outcome": outcome})

## The server's verdict (P0 `catch` event) with the XP / reward lines the runtime collected.
func on_catch(ev: Dictionary, lines: Array) -> void:
	busy = false
	var v := rt.session.current()
	var extra := "" if lines.is_empty() else "\n" + "\n".join(lines)
	match str(ev.get("result", "")):
		"landed":
			phase = "result"
			model["outcome"] = "caught"
			_last = {"outcome": "caught", "fish_id": str(ev.fish), "tier": int(ev.rarity)}
			_show_notice("%s · %s%s\n%s" % [P0Logic.item_name(v, str(ev.fish)), P0Logic.rarity_name(v, int(ev.rarity)), extra, P0Logic.creel_line(v)], "Fish caught!", "caught")
		"broke_free":
			phase = "result"
			model["outcome"] = "escaped"
			_last = {"outcome": "escaped"}
			var why := ("Fishing Lv%d needed" % int(ev.need_level)) if ev.has("need_level") else "Too heavy for your %s" % str(v.get("fishing", {}).get("rod", "rod"))
			_show_notice("%s · unlocks %s\n%d Energy back" % [why, P0Logic.item_name(v, str(ev.fish)), int(ev.refund)],
				"%s fish got away" % P0Logic.rarity_name(v, int(ev.rarity)), "failed")
		"escaped":
			phase = "result"
			model["outcome"] = "escaped"
			_last = {"outcome": "escaped"}
			var tail := ("\nCatch protection %d left today" % int(ev.protected_left)) if ev.has("protected_left") else ""
			_show_notice("%d Energy back%s" % [int(ev.refund), tail], "Fish escaped", "failed")
		"cancelled":
			phase = "result"
			_last = {"outcome": "cancelled"}
			_show_notice("Line in · Energy back")
	_refresh_button()

## A command never reached the server. A lost cast changes nothing server-side: back to Cast. A lost
## reel report would leave the line open there, so it is resent a few times before giving up.
func on_send_failed(cmd: Dictionary) -> void:
	match str(cmd.get("type", "")):
		"cast":
			busy = false
			phase = "ready"
			_show_notice("Couldn't reach the server · tap Cast to try again", "Not cast", "failed")
			_refresh_button()
		"reel":
			if _reel_retries < 3:
				_reel_retries += 1
				get_tree().create_timer(1.5).timeout.connect(func(): if visible and rt: rt.session.send(cmd))
			else:
				busy = false
				phase = "result"
				_show_notice("Couldn't reach the server · the line will clear in a moment", "Connection lost", "failed")
				_refresh_button()

## Something went wrong mid-cast (e.g. too early, line gone): settle back to ready.
func on_abort() -> void:
	busy = false
	phase = "ready"
	_show_notice("Cast when you are ready.")
	_refresh_button()

func _cancel(reason := "stopped") -> void:
	held = false
	if phase in ["casting", "waiting", "hook", "playing"] and rt and not _reported:
		_report("cancel")   # the server refunds in full before the bite, or counts an escape after it
	phase = "result"
	if reason == "interrupted": _show_notice("Return to the water and cast again.", "Fishing interrupted", "failed")
	_refresh_button()

func close() -> void:
	if phase in ["casting", "waiting", "hook", "playing"]: _cancel()
	busy = false
	hide()
	closed.emit()
