class_name P0FishingPanel
extends FishingPanel
## The old polished fishing panel (one thumb button: Cast → Hook → hold to Reel, gauge beside the
## float, outcome notice) on the P0 rules. Only the backend changes: casts go out as P0 `cast`, the
## bite and hook window are timed from the server's bite_in / hook_ms, the reel minigame runs locally
## and reports `reel {landed | escaped | cancel}`; the server decides gates (broke free) and refunds.
## FishingPresentation (pose, rod, line, float, landing arc) reads the same fields.

const BREAK_MS := {2: 1500.0, 3: 2000.0, 4: 3000.0}   # §6.5.2: a gated fish breaks free this far in
## Dev playtests (P0_AUTO=1 / scripted shots): hook on the bite and keep the band on the fish.
static var auto_play := false

var rt: P0Runtime
var site_key := "pond"        # P0 site (pond / river) for the cast command
var place_name := ""
var _bite_at := 0.0
var _hook_until := 0.0
var _rarity := 1
var _breaks := false
## q(219): one of the account's first two bites (the server's cast.sure) — the hook window stays open and the reel can't
## fail; the player still hooks and reels. No words or marks: it looks like any other bite.
var _sure := false
var _play_ms := 0.0
var _last: Dictionary = {}
var _reported := false
var _reel_retries := 0
## The player's box on screen (viewport px), set by the pond each frame; the reel gauge keeps clear of it.
var player_rect := Rect2()

## The reel gauge with the walking camera (不知火舞 on 231, 2026-10-09): GAUGE_GAP from the float as before, on the
## side away from the player — on a north–south cast, the side with more room — at least GAUGE_EDGE from the screen
## sides and never over the player's box grown by GAUGE_CLEAR.
const GAUGE_GAP := 28.0
const GAUGE_EDGE := 8.0
const GAUGE_CLEAR := 8.0

func _ready() -> void:
	super._ready()
	layer = 30
	_title.visible = false   # the P0 place chip already names the pond; the close X takes the bell's corner
	# The old input shield covers the HUD below; let a tap on the place chip still mean "back to the map"
	# (the first tap reels in and closes, like the system back key, the next one leaves).
	var shield: Control = get_node("FishingInputShield")
	shield.gui_input.connect(func(e: InputEvent):
		if rt and P0Ui.is_tap(e) and rt.ui.place_chip_rect().has_point((e as InputEventMouseButton).global_position):
			rt.leave_world())

func last_result() -> Dictionary:
	return _last

## q(49) (SGODOT-376): one card at a time. This panel is canvas layer 30, over the P0 UI and its TipCard (layer 10), so
## the first cast's `Casting uses 5 Energy` came up under `Watch the float…` / `A bite!…`, half hidden. While a TipCard
## is on screen or about to come up the status card waits; when the tip closes (its time, a tap, or doing what it
## teaches) the card comes back with its latest line. A bite closes the tip at once (不知火舞 on 376): `A bite!` shows
## the same frame. Every writer of the card's visibility runs this after it.
var _held_for_tip := false
## The result put the card away (on_catch: the pond's HUD cards say the result); a held card stays away then. Other
## results with a line of their own (a reel report lost three times) come back like any card (周瑜 on #595).
var _quiet := false

func _hold_for_tip() -> void:
	if rt != null and rt.ui != null and rt.ui.tip_up_or_coming():
		_held_for_tip = true
		_message_card.visible = false
	elif _held_for_tip:
		_held_for_tip = false
		_message_card.visible = visible and not _quiet and (phase != "playing" or int(model.get("step", 0)) < 40)

func _refresh_button() -> void:
	super._refresh_button()
	_hold_for_tip()

## +1: the gauge goes right of the float, -1 left (the pond frames the float with room on that side). A float beside
## the player's box points away from it; one above or below it takes the side with more room.
static func gauge_side(float_x: float, player: Rect2, width: float) -> int:
	if player.has_area() and (float_x < player.position.x or float_x > player.end.x):
		return 1 if player.get_center().x < float_x else -1
	return 1 if width - float_x > float_x else -1

func _place_gauge() -> void:
	if not _gauge or not _root: return
	if not player_rect.has_area() or _world_anchor.is_zero_approx():
		super._place_gauge()
		return
	var origin := _root.global_position
	var anchor := _world_anchor - origin
	var body := Rect2(player_rect.position - origin, player_rect.size).grow(GAUGE_CLEAR)
	_gauge.position = gauge_spot(anchor, body, _gauge.size, _root.size.x, _gauge_rows())

## Where the gauge goes (panel coordinates): beside the float on its preferred side, then beside it on the other, and
## only then above or below the player's box — so it doesn't jump when the bite notice folds away mid-reel and frees
## the rows above; the preferred spot when nothing clears it.
static func gauge_spot(anchor: Vector2, body: Rect2, size: Vector2, width: float, rows: Vector2) -> Vector2:
	var side := gauge_side(anchor.x, body, width)
	var y := clampf(anchor.y - size.y * 0.55, rows.x, rows.y)
	var spots: Array[Vector2] = []
	for row in [y, body.position.y - size.y, body.end.y]:
		for s in [side, -side]:
			var x := anchor.x + GAUGE_GAP if s > 0 else anchor.x - GAUGE_GAP - size.x
			spots.append(Vector2(clampf(x, GAUGE_EDGE, maxf(GAUGE_EDGE, width - GAUGE_EDGE - size.x)), clampf(row, rows.x, rows.y)))
	for at in spots:
		if not Rect2(at, size).intersects(body): return at
	return spots[0]

## The old layout puts the close X at the panel's safe-area top; dock it in the P0 HUD's coins/bell
## corner instead (hidden while fishing), so it never lands on the place chip on notched screens.
func _fit() -> void:
	super._fit()
	if rt == null or rt.ui.hud == null: return
	var r: Rect2 = rt.ui.hud_corner_rect()
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
	for n in [_message_card, _primary, _guide, _gauge]: n.visible = true
	_quiet = false
	_hold_for_tip()
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
	_quiet = false
	busy = true
	model = {}
	_last = {}
	_reported = false
	phase = "casting"
	_show_notice("Casting...")
	cast_started.emit()
	_refresh_button()
	var bait := rt.ui.selected_bait if rt.ui.selected_bait.begins_with("bait_") else ""   # the Fish Trap is not bait
	rt.session.send({"type": "cast", "bait": bait if bait != "" else null, "site": site_key})

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
	_sure = cast is Dictionary and bool(cast.get("sure", false)) and not _breaks
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
	var fishing: Dictionary = rt.session.current().get("fishing", {})
	tier["bar_size"] = minf(0.45, float(tier.bar_size) + float(fishing.get("band_bonus", 0.0)))   # Reed +3 / Carbon +5 points (§6.5.2)
	tier["loss"] = maxf(0.04, float(tier.loss) * float(fishing.get("loss_mult", 1.0)))   # Carbon Rod −10%, floor 4 % / s
	tier["sure"] = _sure   # q(219): progress never drops to zero, no 30 s timeout
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
	if visible and rt != null and rt.ui != null and phase == "hook": rt.ui.hold_tips(1500)   # a bite takes the screen
	_hold_for_tip()
	if not visible or rt == null or busy: return
	var now := Time.get_ticks_msec()
	if phase in ["waiting", "hook"]:
		if now > _hook_until and not _sure:   # q(219): a sure bite's float stays down until the player hooks
			_report("escaped")
			_show_notice("Missed the bite. Tap Hook when the float dips.", "Fish escaped", "failed")
			phase = "settling"
			_refresh_button()
		elif now >= _bite_at and phase != "hook":
			phase = "hook"
			_show_notice("A bite! Tap to hook the fish!")
			rt.ui.hold_tips(1500)   # the bite takes the screen (SGODOT-376 ②): the tip on screen closes, none comes up
			rt.ui.close_tip()
			_hold_for_tip()
			Input.vibrate_handheld(80)
			_refresh_button()
		elif phase == "hook" and auto_play and now > _bite_at + 400:
			_p0_hook()
	elif phase == "playing":
		if dt > 0.5:
			if not _sure: _report("escaped")   # q(219): a sure bite just skips the stalled frame
			return
		_accumulator += dt
		_play_ms += dt * 1000.0
		var tier: Dictionary = get_meta("tier")
		var step_s := float(FishingModel.data().step_ms) / 1000.0
		while _accumulator >= step_s and model.outcome == "playing":
			_accumulator -= step_s
			if auto_play: held = float(model.fish) > float(model.bar)
			inputs += "1" if held else "0"
			FishingModel.step(model, held, tier)
		_gauge.model = model
		_gauge.queue_redraw()
		_message_card.visible = int(model.get("step", 0)) < 40 and not _held_for_tip
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

## The server's verdict (P0 `catch` event). Results are the pond HUD's cards (FISH-3 / FISH-5), not this
## panel's: hide the old notice and thumb button, hold the result phase so FishingPresentation plays
## the landing arc (or leaves the ripples), and return how long the pond should wait before closing.
func on_catch(ev: Dictionary) -> float:
	busy = false
	phase = "result"
	var landed := str(ev.get("result", "")) == "landed"
	model["outcome"] = "caught" if landed else "escaped"
	_last = {"outcome": "caught", "fish_id": str(ev.fish), "tier": int(ev.rarity)} if landed else {"outcome": "escaped"}
	_quiet = true
	for n in [_message_card, _primary, _guide, _gauge]: n.visible = false
	match str(ev.get("result", "")):
		"landed": return 1.3     # FishingPresentation lifts the fish over 1.25 s
		"cancelled": return 0.15
	return 0.7                   # the float sinks and the ripples fade

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
