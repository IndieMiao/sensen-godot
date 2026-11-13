class_name P0AccFlow
extends Control
## The first launch's pages in their order (SGODOT-491; 不知火舞's account spec v1.1 §1, §5; q(312)), one at a time over
## no world, on their own layer — the host (P0Runtime.run_first_launch, 后裔) puts it up when P0Session.first_run() is
## not "ready" / "legacy", and takes it down when the account is made. Nothing here talks to the server: the pages say
## what the player did and the host asks P0Session (后裔's contract v1, 11-13).
##   "new"          AGE (and consent) → NAME (with `Already have a farm? Sign in`) ⇄ Sign in ⇄ No farm found
##   "old_age"      an old player never asked: AGE → NAME without the Sign in row
##   "old_consent"  passed voice's 13+ gate: the consent card → NAME without the Sign in row
##   "old_blocked"  said no at voice's gate, "blocked" said no here before: AGE-BLOCK, and nothing more (q(312) ⑨ C)
## AGE's answer is kept on this phone (user://p0_first_run.json: {age_ok, terms, privacy, agreed_at}; a no is only
## {age_ok: false}, and every launch stops at AGE-BLOCK); the year is never kept, a no never sent. The links open the
## system browser. Back (back()): Sign in → NAME, No farm found → Sign in, Born in …? closed; anything else is the
## host's (the launch's own: to the home screen).

signal agreed(age_ok: bool)      # AGE's Yes, or the consent card's Continue (true)
signal named(name: String, skip: bool)
signal sign_in(provider: String)
signal blocked
signal failed(code: String)      # NAME's check failed (network, rate_limited): the host says so (SYS-CMD-FAIL)

const RECORD := "user://p0_first_run.json"
const VERSIONS := "res://assets/p0/legal/versions.json"   # 后裔's: the terms and privacy versions this build carries
const TERMS_URL := "https://gensen.app/terms"

var kind := "new"
var providers: Array = []
var page: Control                 # the page up now
var name_page: P0AccName          # kept: back from Sign in finds the name as it was typed
var record_path := RECORD
var _this_year := 0
var _provider := ""               # the account the sign-in went to (No farm found's line)

## `check`: NAME's name check (P0Session.name_check). `providers_`: Sign in's keys on this phone.
func _init(kind_ := "new", check := Callable(), providers_: Array = [], this_year := 0) -> void:
	kind = kind_
	providers = providers_
	_this_year = this_year
	name = "AccFlow"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	name_page = P0AccName.new(kind == "new")
	name_page.check = check
	name_page.named.connect(func(n: String, skip: bool): named.emit(n, skip))
	name_page.failed.connect(func(code: String): failed.emit(code))
	name_page.sign_in_pressed.connect(_open_sign_in)
	match kind:
		"old_blocked", "blocked": _show(_block())
		"old_consent":
			var c := P0AccConsent.new()
			c.link_pressed.connect(open_link)
			c.agreed.connect(func():
				agreed.emit(true)
				_show(name_page))
			_show(c)
		_: _show(_age())

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(name_page) and name_page.get_parent() == null: name_page.free()

func _age() -> P0AccAge:
	var a := P0AccAge.new(_this_year)
	a.link_pressed.connect(open_link)
	a.agreed.connect(func(ok: bool):
		keep(ok)
		agreed.emit(ok)
		if ok: _show(name_page)
		else:
			_show(_block())
			blocked.emit())
	return a

func _block() -> P0AccBlock:
	var b := P0AccBlock.new()
	b.link_pressed.connect(open_link)
	return b

func _show(p: Control) -> void:
	if page != null and page != p:
		if page == name_page: remove_child(name_page)   # kept for later
		else: page.queue_free()
	page = p
	if p.get_parent() == null: add_child(p)

func _open_sign_in() -> void:
	var s := P0AccSignIn.new(providers)
	s.back_pressed.connect(func(): _show(name_page))
	s.provider_pressed.connect(func(p: String):
		_provider = p
		sign_in.emit(p))
	_show(s)

## The host's: the sign-in found no farm for that account (no_farm, its pending the host's to keep).
func no_farm() -> void:
	var n := P0AccNoFarm.new(_provider if _provider != "" else "google")
	n.start_new.connect(func(): _show(name_page))
	n.try_another.connect(_open_sign_in)
	_show(n)

## The host's, after guest or a rename did not take the name: back on NAME with why — name_rejected's reason in red;
## pending_expired: the sign-in card again (the host toasts `Sign-in expired. Please sign in again.`), the name kept.
func name_refused(r: Dictionary) -> void:
	match str(r.get("code", "")):
		"name_rejected":
			_show(name_page)
			name_page.refuse(str(r.get("reason", "blocked")))
		"pending_expired": _open_sign_in()
		_: _show(name_page)

## Back: true when a page here took it.
func back() -> bool:
	if page is P0AccSignIn:
		_show(name_page)
		return true
	if page is P0AccNoFarm:
		_open_sign_in()
		return true
	if page is P0AccAge and (page as P0AccAge).confirm != null:
		(page as P0AccAge)._change()
		return true
	return false

## AGE's answer on this phone (q(312)): yes with the versions agreed to, a no alone.
func keep(ok: bool) -> void:
	var data := {"age_ok": ok}
	if ok:
		var v := versions()
		data.merge({"terms": str(v.get("terms", "")), "privacy": str(v.get("privacy", "")), "agreed_at": Time.get_unix_time_from_system() * 1000.0})
	var f := FileAccess.open(record_path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(data))

## What this phone has kept ({} before AGE).
func kept() -> Dictionary:
	if not FileAccess.file_exists(record_path): return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(record_path))
	return d if d is Dictionary else {}

static func versions() -> Dictionary:
	if not FileAccess.file_exists(VERSIONS): return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(VERSIONS))
	return d if d is Dictionary else {}

static func open_link(which: String) -> void:
	var url := TERMS_URL if which == "terms" else P0Legal.privacy_url(OS.get_name())
	if url != "": ExternalLink.open(url)
