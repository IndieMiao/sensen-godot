extends Node
## v1.6.10 / 491-959434ff: show after account gates, OK closes immediately, server confirmation is separate.
const Api := preload("res://modules/p0/p0_account_notices.gd")
const Card := preload("res://scenes/p0/account/p0_name_reset_card.gd")
var pending_path := "user://p0_name_notice_pending.json"
var runtime: Node
var api := Api.new()
var card: Control
var _context: Array = []
var _owner := ""
var _pending: Dictionary = {}   # sha256(server + player) -> version actually acknowledged by the player; no token
var _loaded := false
var _busy := false
var _retry_done := false
var _unread := 0
var _dismissed := 0             # current login only; never means server-confirmed
var _active := false
var _background := false

func setup(host: Node) -> void:
	runtime = host
	api.session = runtime.session
	add_child(api)

func _ready() -> void:
	if not FileAccess.file_exists(pending_path): return
	var data = JSON.parse_string(FileAccess.get_file_as_string(pending_path))
	if not data is Dictionary: return   # local loss/corruption never confirms a server notice
	for key in data:
		var v := Api.version(data[key])
		if key is String and key.length() == 64 and v > 0: _pending[key] = v

func _process(_delta: float) -> void: tick()

func _session() -> P0Session: return runtime.session
func _ui() -> P0Ui: return runtime.ui

func _sync() -> void:
	var context := _session().request_context()
	if context == _context: return
	interrupt()
	_context = context
	_owner = (_session().base_url + "\n" + _session().identity.player).sha256_text()
	_loaded = false
	_retry_done = false
	_unread = 0
	_dismissed = 0

func _eligible() -> bool:
	return not _background and _session().accounts and _session().identity_ready and _session().auth_token() != "" \
		and is_instance_valid(runtime.world) and runtime.world.is_node_ready() and not runtime.world.is_queued_for_deletion() \
		and not is_instance_valid(runtime._acc_flow) and not is_instance_valid(runtime._home_flow) \
		and _ui().screen() == null and _ui().surface != "busy"

func tick() -> void:
	_sync()
	if not _eligible():
		if _active: interrupt()
		return
	_active = true
	if is_instance_valid(card) and not showing(): card = null   # a higher-priority modal took over, not an ACK
	if not _loaded and not _busy:
		if not _retry_done:
			_retry_done = true
			var pending := int(_pending.get(_owner, 0))
			if pending > 0:
				_ack(pending, true)   # one bounded retry before the authoritative GET on this login
				return
		_read()
	if _loaded and _unread > _dismissed and not showing() and _ui()._modal == null \
			and _ui()._card_queue.is_empty() and not is_instance_valid(_ui()._ask) and not _ui().tip_on_screen():
		_show()

func _read() -> void:
	_busy = true
	api.read(func(reply: Dictionary):
		_busy = false
		_loaded = true   # even unknown: no per-frame retry storm; next login reads afresh
		var v := Api.unread(reply)
		if v >= 0:
			if v != _unread: _hide()   # a refreshed authoritative version gets its own captured OK callback
			_unread = v
		tick())

func showing() -> bool:
	return is_instance_valid(card) and not card.is_queued_for_deletion() \
		and _ui().modal_kind == "name_reset" and _ui()._modal == card.get_parent()

func _show() -> void:
	var c := Card.card()
	var seen := _unread
	c.connect("move_pressed", _ok.bind(seen, c))
	c.connect("cancelled", ignore_back)
	_ui()._open_modal(c, 0.0, false)   # the confirm component owns the scrim; retain the approved HUD behind it
	card = c
	_ui().modal_kind = "name_reset"
	_ui()._modal_back = ignore_back

func ignore_back() -> void:
	if showing(): _ui()._modal_back = ignore_back   # P0Ui consumes callbacks; reinstall for every Back/scrim

func handle_back() -> bool:
	_sync()
	if not showing(): return false
	ignore_back()
	return true

func _hide() -> void:
	if showing(): _ui().close_modal()
	card = null

func _ok(seen: int, source: Control) -> void:
	_sync()
	if not _eligible() or not showing() or card != source or seen != _unread: return
	_dismissed = maxi(_dismissed, seen)
	_pending[_owner] = maxi(int(_pending.get(_owner, 0)), seen)
	_save_pending()   # durable intent, not a durable claim that the server has acknowledged it
	_hide()           # never turn an offline notice into a game gate
	_ack(seen, false)

func _ack(seen: int, before_read: bool) -> void:
	_busy = true
	var owner := _owner
	api.acknowledge(seen, func(reply: Dictionary):
		_busy = false
		if reply.get("ok") == true and int(_pending.get(owner, 0)) <= seen:
			_pending.erase(owner)
			_save_pending()
		# Unknown/write failure keeps intent; a future version is never guessed and ACKed automatically.
		if before_read or str(reply.get("code", "")) == "notice_version_conflict":
			_loaded = false
			tick())

func interrupt() -> void:
	api.invalidate()
	_busy = false
	_active = false
	_hide()   # retain unread version and pending intent; no synthetic OK, no automatic confirmation

func set_background(value: bool) -> void:
	_background = value
	if value: interrupt()

func _save_pending() -> void:
	var temporary := pending_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return   # memory still suppresses this login; future GET remains authoritative
	file.store_string(JSON.stringify(_pending))
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK: DirAccess.rename_absolute(temporary, pending_path)
