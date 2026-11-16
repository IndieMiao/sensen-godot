extends Node
## q(315) report interaction, owned by the long-lived HUD (not by a room/peer).
## Only confirmed results enter the login-scoped handle cache. No player data is persisted here.
const Drawer := preload("res://scenes/p0/account/p0_acc_report.gd")
const SENT := "Report sent"
const ALREADY := "You already reported this"
const FAILED := "Didn't go through · try again"
const TIMEOUT := 20.0
var ui: Node
var drawer: UiDrawer
var _session: Node
var _owner := ""
var _confirmed := {}
var _generation := 0
var _request := 0
var _room: Node
var _place := ""
var _layer := 0
var _epoch := 0
var _target := ""
var _timeout: Timer

func _process(_delta: float) -> void:
	_sync_identity()
	if _showing():
		if not _same_room() or ui.get("_screen") != null: _discard()
	elif is_instance_valid(drawer) or is_instance_valid(_timeout):
		_discard()   # another modal forcibly replaced this one: discard its watchdog as well

func _showing() -> bool:
	return is_instance_valid(drawer) and not drawer.is_queued_for_deletion() \
		and ui.get("modal_kind") == "report" and ui.get("_modal") == drawer.get_parent()

func _stop_timer() -> void:
	if is_instance_valid(_timeout):
		_timeout.stop()
		_timeout.queue_free()
	_timeout = null

func _discard() -> void:
	_request += 1
	_stop_timer()
	if _showing(): ui.call("close_modal")   # forced account/world change is allowed even while submitting
	drawer = null

func _sync_identity() -> void:
	var owner := str(ui.get("player_of").call())
	if owner != _owner:
		_owner = owner
		_confirmed.clear()
		_generation += 1
		_discard()
	if is_instance_valid(_session) and bool(_session.get("accounts")) and not bool(_session.get("identity_ready")):
		if _showing() or not _confirmed.is_empty(): _identity_changed(false)

func _bind_session(room: Node) -> void:
	var next: Node = room.get("session")
	if next == _session: return
	if is_instance_valid(_session) and _session.is_connected("identity_changed", _identity_changed):
		_session.disconnect("identity_changed", _identity_changed)
	_session = next
	_confirmed.clear()
	_generation += 1
	_discard()
	if is_instance_valid(_session): _session.connect("identity_changed", _identity_changed)

func _identity_changed(ready: bool) -> void:
	if not ready:
		_confirmed.clear()
		_generation += 1
		_discard()
	_sync_identity()

func _allowed() -> bool:
	return ui.get("_screen") == null and (not is_instance_valid(_session) or not bool(_session.get("accounts")) or bool(_session.get("identity_ready")))

func open(peer: int) -> void:
	var room: Node = ui.get("voice_room")
	if not is_instance_valid(room): return
	_bind_session(room)
	_sync_identity()
	if not _allowed() or (_showing() and bool(drawer.get("busy"))): return
	var row := {}
	for person: Dictionary in room.call("people"):
		if int(person.get("peer", -1)) == peer and not bool(person.get("self", false)): row = person
	var handle := str(row.get("handle", ""))
	if handle == "":
		_fail()
		return
	if _confirmed.has(handle):
		ui.call("toast", ALREADY)
		return
	_discard()
	_room = room
	var online: Node = room.get("online")
	if not is_instance_valid(online): return
	_place = str(online.get("outpost"))
	_layer = int(online.get("room"))
	_epoch = int(online.get("epoch"))
	_target = handle
	var d := Drawer.new(str(row.get("name", "")), bool(room.call("offered")))
	d.safe_bottom = float(ui.call("safe_bottom"))
	d.height += d.safe_bottom
	d.close_requested.connect(_back)
	d.submitted.connect(_submit)
	ui.call("_open_modal", d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	drawer = d
	ui.set("modal_kind", "report")
	ui.set("_modal_back", _back)

func handle_back() -> bool:
	if not _showing(): return false
	_back()
	return true

func _back() -> void:
	if not _showing(): return
	if bool(drawer.get("busy")):
		ui.set("_modal_back", _back)   # P0Ui consumes a custom callback before invoking it: reinstall for repeat Back
		return
	_discard()

func _same_room() -> bool:
	if not is_instance_valid(_room) or ui.get("voice_room") != _room: return false
	var online: Node = _room.get("online")
	return is_instance_valid(online) and str(online.get("outpost")) == _place \
		and int(online.get("room")) == _layer and int(online.get("epoch")) == _epoch

func _submit(reason: String) -> void:
	_sync_identity()
	if not _showing() or not _allowed(): return
	var peer := -1
	if _same_room():
		for row: Dictionary in _room.call("people"):
			if str(row.get("handle", "")) == _target and not bool(row.get("self", false)): peer = int(row.peer)
	# A name/peer never identifies the target. Re-resolve the saved handle in the same membership before sending.
	if peer < 0 or not Drawer.REASONS.has(reason) or (reason == "offensive_voice" and not bool(_room.call("offered"))):
		drawer.call("set_busy", false)
		_fail()
		return
	_request += 1
	var ticket := _request
	var generation := _generation
	var target := _target
	var sent_drawer := drawer.get_instance_id()
	_timeout = Timer.new()
	_timeout.one_shot = true
	add_child(_timeout)
	_timeout.timeout.connect(_settle.bind("failed", ticket, generation, target, sent_drawer), CONNECT_ONE_SHOT)
	_timeout.start(TIMEOUT)
	var result: String = str(await _room.call("report", peer, reason))
	_settle(result, ticket, generation, target, sent_drawer)

func _settle(result: String, ticket: int, generation: int, target: String, sent_drawer: int) -> void:
	_sync_identity()
	if ticket != _request or generation != _generation or not _allowed(): return
	if not _showing() or drawer.get_instance_id() != sent_drawer: return
	if not _same_room():
		_discard()
		return
	_stop_timer()
	_request += 1   # a timeout or a response, never both; late results cannot turn failure into success
	if result in ["sent", "already"]:
		_confirmed[target] = true
		_discard()
		ui.call("toast", SENT if result == "sent" else ALREADY)
	else:
		drawer.call("set_busy", false)
		_fail()

func _fail() -> void:
	ui.call("show_sys", UiSysBanner.Kind.CMD_FAIL, FAILED)
