class_name P0AccFlow
extends Control
## The first launch's pages in their order (SGODOT-491; the user's q(321) — sign-in a must; 不知火舞's spec v2; 后裔's
## contract v1.6.3), one at a time over no world, on their own layer — the host (P0Runtime's glue, 后裔) puts it up when
## P0Session.first_run() asks and takes it down when the player is in. Nothing here talks to the server: the pages say
## what the player did, the host asks P0Session and answers back.
##   "new"            AGE (and consent) → sign-in (`Sign in to play`)
##   "old_age"        an old farm here, never asked: AGE → sign-in (`Keep your farm`)
##   "old_consent"    an old farm here, passed voice's 13+ gate: the consent card → sign-in (`Keep your farm`)
##   "old_signin"     an old farm here with its age and consent: sign-in (`Keep your farm`)
##   "old_blocked", "blocked"   AGE-BLOCK, nothing more (q(312) ⑨ C)
##   "signed_out"     signed out, or a token the server no longer knows: AGE first if this phone never kept a yes, then
##                    sign-in (`Sign in to play`, `hints`' line)
##   "no_google"      email sign-in off and no Google Play services: ACC-NO-GMS
## After sign-in the host answers: in (it takes the flow down), no_farm(fresh) → NAME, conflict(farm, provider) → the
## choose card, claimed(linked) → the sign-in page's line, sign_in_settled() for a cancelled or failed one (the keys are
## grey from the tap till one of these). AGE's answer is kept on this phone (user://p0_first_run.json:
## {age_ok, terms, privacy, agreed_at}; a no is only {age_ok: false}); the year is never kept, a no never sent. Back
## (back()): the choose card or Born in …? closed, NAME → sign-in for a new player; anything else is the host's (the
## launch's own: to the home screen).

signal agreed(age_ok: bool)      # AGE's Yes, or the consent card's Continue (true)
signal sign_in(provider: String)  # "apple" / "google" / "email"
signal named(name: String, skip: bool)
signal sign_in_again             # Try another account (NAME's or the choose card's): the host drops its pending
signal switch_farm               # the choose card's Switch to that farm
signal test_code                 # Compatibility notification; the flow now opens ACC-TESTCODE itself.
signal code_entered(code: String) # Host calls P0Session.sign_in_code, then code_refused on failure.
signal code_consent_agreed       # Existing age is trusted; only consent was answered now.
signal code_left(authenticated: bool)
signal blocked
signal failed(code: String)      # NAME's check failed (network, rate_limited): the host says so (SYS-CMD-FAIL)
signal consent_renewed           # the updated-terms card's Continue: the host sends again what consent_outdated refused

const RECORD := "user://p0_first_run.json"
const VERSIONS := "res://assets/p0/legal/versions.json"   # 后裔's: the terms and privacy versions this build carries
const TERMS_URL := P0Legal.TERMS_URL
const OLD_KINDS := ["old_age", "old_consent", "old_signin"]

var kind := "new"
var providers: Array = []
var hints := {}
var page: Control                 # the page up now
var sign_in_page: P0AccSignIn     # kept: the choose card and NAME's way back find it as it was
var name_page: P0AccName
var choose: Control               # the choose card while it is up
const TestCode := preload("res://scenes/p0/account/p0_acc_test_code.gd")
var code_page: TestCode
## Current hello policy/legacy facts, supplied by the host before ready; not a fabricated local AGE answer.
var code_context := {}
var _code_origin := ""
var record_path := RECORD
var _check := Callable()
var _this_year := 0
var _provider := ""
var _toasts: ToastLayer           # the flow's own: P0Ui's banner and toasts are on a layer under this one
var renew: P0AccConsent          # the updated-terms card while it is up
var _renew_versions := {}         # the versions it asks for: the latest consent_outdated's

## `check`: NAME's name check (P0Session.name_check). `providers_`: the sign-in page's keys (P0AccSignIn). `hints_`:
## {line: "farm_uses" | "last_time", with: …} for the sign-in page's line.
func _init(kind_ := "new", check := Callable(), providers_: Array = [], hints_ := {}, this_year := 0) -> void:
	kind = kind_
	providers = providers_
	hints = hints_
	_check = check
	_this_year = this_year
	name = "AccFlow"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

## What the host (后裔's glue) builds the flow with after hello, Google Play services asked before AGE (诸葛亮 v3;
## 亚瑟's P0SignIn.google_ready(), #1042): {kind, providers}. A phone that can't do Google gets NO-GMS up front in place
## of any page leading to sign-in when the server has no email sign-in (`email_on`: hello.email) — AGE-BLOCK stays — and
## with email on, the sign-in page's keys lose Google: "no_google" stands in its place (the page's small line), email
## stays. iOS always can (google_ready is true there); providers are P0SignIn.providers() plus "email" when on.
static func entry(kind_: String, email_on: bool, google_ok := P0SignIn.google_ready(), os_providers := P0SignIn.providers()) -> Dictionary:
	var keys: Array = []
	for p in os_providers:
		keys.append(p if google_ok or p != P0SignIn.GOOGLE else "no_google")
	if email_on: keys.append("email")
	if not google_ok and not email_on and not kind_ in ["blocked", "old_blocked"]: kind_ = "no_google"
	return {"kind": kind_, "providers": keys}

## The first page, once in the tree (the phone's record read where record_path says by then).
func _ready() -> void:
	if page != null: return
	match kind:
		"old_blocked", "blocked": _show(_block())
		"no_google": _open_no_google()
		"old_consent":
			var c := P0AccConsent.new()
			c.link_pressed.connect(open_link)
			c.agreed.connect(func():
				agreed.emit(true)
				_open_sign_in())
			_show(c)
		"old_signin": _open_sign_in()
		"signed_out":
			if bool(kept().get("age_ok", false)): _open_sign_in()
			else: _show(_age())
		_: _show(_age())

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE: return
	for p in [sign_in_page, name_page]:   # kept off the tree while another page is up
		if is_instance_valid(p) and p.get_parent() == null: p.free()

func _age(after := Callable()) -> P0AccAge:
	var a := P0AccAge.new(_this_year)
	a.link_pressed.connect(open_link)
	a.agreed.connect(func(ok: bool):
		keep(ok)
		agreed.emit(ok)
		if ok:
			if after.is_valid(): after.call()
			else: _open_sign_in()
		else:
			_show(_block())
			blocked.emit())
	return a

func _block() -> P0AccBlock:
	var b := P0AccBlock.new()
	b.link_pressed.connect(open_link)
	return b

func _show(p: Control) -> void:
	_drop_choose()
	if page != null and page != p:
		if page == sign_in_page or page == name_page: remove_child(page)   # kept for later
		else: page.queue_free()
	page = p
	if p.get_parent() == null: add_child(p)
	_lines_on_top()

func _open_sign_in() -> void:
	if sign_in_page == null:
		sign_in_page = P0AccSignIn.new(providers, kind in OLD_KINDS, hints)
		sign_in_page.provider_pressed.connect(func(p: String):
			if sign_in_page.busy: return
			_provider = p
			sign_in_page.busy = p != "email"   # email opens its own page (盘古's), no system sheet over this one
			sign_in.emit(p))
		sign_in_page.test_code_pressed.connect(_test_code_pressed)
	_show(sign_in_page)

func _open_no_google() -> void:
	var n := P0AccNoGms.new()
	n.test_code_pressed.connect(_test_code_pressed)
	_show(n)

func _test_code_pressed() -> void:
	_code_origin = "no_google" if page is P0AccNoGms else "sign_in"
	test_code.emit()
	match code_gate():
		"blocked": _show(_block())
		"age": _show(_age(_open_code_page))
		"consent":
			var c := P0AccConsent.new()
			c.link_pressed.connect(open_link)
			c.agreed.connect(func():
				keep_versions(code_versions())   # preserve the existing age or its absence; never invent a birth answer
				code_consent_agreed.emit()
				_open_code_page())
			_show(c)
		_: _open_code_page()

func code_versions() -> Dictionary:
	return code_context.get("versions", versions())

func code_gate() -> String:
	var local := kept()
	var age = code_context.get("age", null)
	var local_age = local.get("age_ok", null)
	if (local_age is bool and not local_age) or (age is bool and not age) or kind in ["blocked", "old_blocked"]: return "blocked"
	if not (local_age is bool and local_age) and not (age is bool and age): return "age"
	var required := code_versions()
	for consent in [local, code_context.get("consent", null)]:
		if consent is Dictionary and str(required.get("terms", "")) != "" and str(required.get("privacy", "")) != "" \
			and consent.get("terms") == required.terms and consent.get("privacy") == required.privacy: return "ready"
	return "consent"

func _open_code_page() -> void:
	code_page = TestCode.new()
	code_page.submitted.connect(func(code: String): code_entered.emit(code))
	code_page.back_pressed.connect(_code_back)
	_show(code_page)

func _code_back() -> void:
	if not is_instance_valid(code_page) or page != code_page or code_page.busy: return
	code_left.emit(code_page.authenticated)
	code_page = null
	var origin := _code_origin
	_code_origin = ""
	if origin == "no_google": _open_no_google()
	else: _open_sign_in()

func code_authenticated() -> void:
	if is_instance_valid(code_page) and page == code_page: code_page.mark_authenticated()

func code_refused(reply: Dictionary) -> void:
	if is_instance_valid(code_page) and page == code_page: code_page.refuse(reply)

## The host's: signed in, no farm for that account yet (a new player, `fresh`: NAME with Try another account) — or an
## old farm claimed, or a test code taken (not fresh: no way back from NAME). A new NAME each time: a name typed for
## one account is not another's.
func no_farm(fresh := true) -> void:
	sign_in_settled()
	if is_instance_valid(name_page) and name_page.get_parent() == null: name_page.free()
	name_page = P0AccName.new(fresh)
	name_page.check = _check
	name_page.named.connect(func(n: String, skip: bool): named.emit(n, skip))
	name_page.failed.connect(func(code: String): failed.emit(code))
	name_page.try_another_pressed.connect(_try_another)
	_show(name_page)

## The host's: that account already has a farm (claim's conflict on the sign-in page; guest's race on NAME). The choose
## card over the page: on the sign-in page an old farm is here (its neutral lines), on NAME none is.
func conflict(farm: Dictionary, provider := "") -> void:
	sign_in_settled()
	_drop_choose()
	var old_here := page == sign_in_page
	choose = P0AccChoose.card(farm, provider if provider != "" else _provider, old_here)
	choose.move_pressed.connect(func():
		_drop_choose()
		switch_farm.emit())
	choose.cancelled.connect(_try_another)
	add_child(choose)
	_lines_on_top()

## The host's: this phone's old farm was claimed elsewhere — the sign-in page's line, by the way it is bound
## (`linked`: ["google"]; [] a test code's).
func claimed(linked: Array) -> void:
	_open_sign_in()
	sign_in_settled()
	sign_in_page.set_hint("farm_uses", str(linked[0]) if not linked.is_empty() else "code")

## A line for the player while the flow is up, on this flow's own layer: P0Ui's banner and toasts sit under the flow's
## layer and would not be seen (哪吒 on PR-A, 11-14). `error` — a failed sign-in, check or save: the SYS-CMD-FAIL
## SysBanner (`Didn't go through · try again`), up 3 s, 16 under the safe area's top: there is no HUD here, and its
## in-game spot (under the HUD, y 100) would cover the wordmark (不知火舞 11-14, Q325-BEFORE 740:202370). Otherwise an
## Info toast at the foot (`Sign-in expired. Please sign in again.`). Kept over the page and any card.
const BANNER_TOP := 16.0
const BANNER_S := 3.0
## A notched phone (不知火舞 11-14): where the banner's foot would reach within 8 of the wordmark's top (y 84), the
## page's wordmark fades out while it is up and back after, 250 ms; with no such overlap the wordmark stays.
const MARK_CLEAR := 8.0
const MARK_FADE_S := 0.25
var safe_top := 0.0               # the host's (P0Ui.safe_top()): the banner sits under the status bar
var banner: UiSysBanner
var _banner_id := 0

func say(text: String, error := false) -> void:
	if error:
		if banner == null:
			banner = UiSysBanner.new()
			banner.name = "Banner"
			banner.theme = UiKit.theme()
			banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
			banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
			add_child(banner)
		banner.kind = UiSysBanner.Kind.CMD_FAIL
		banner.message = text
		banner.offset_left = -UiSysBanner.WIDTH * 0.5
		banner.offset_right = UiSysBanner.WIDTH * 0.5
		banner.offset_top = safe_top + BANNER_TOP
		banner.visible = true
		_banner_id += 1
		var id := _banner_id
		if is_inside_tree(): get_tree().create_timer(BANNER_S).timeout.connect(func():
			if id == _banner_id and is_instance_valid(banner):
				banner.visible = false
				_fade_mark())
	else:
		if _toasts == null:
			_toasts = ToastLayer.new()
			_toasts.name = "Toasts"
			_toasts.theme = UiKit.theme()
			add_child(_toasts)
		_toasts.show_toast(text)
	_lines_on_top()

## What say() shows now: the banner's while it is up, else the toast's ("" none).
func said() -> String:
	if banner != null and banner.visible: return banner.message
	return _toasts.current_text() if _toasts != null else ""

func _lines_on_top() -> void:
	for n in [_toasts, banner]: if n != null: move_child(n, -1)
	_fade_mark()

## Whether the banner, up now, comes within MARK_CLEAR of the wordmark's top.
func banner_over_mark() -> bool:
	return banner != null and banner.visible and safe_top + BANNER_TOP + UiSysBanner.HEIGHT > P0AccShell._MARK_TOP - MARK_CLEAR

## The page's wordmark out while the banner would touch it, back in after (250 ms; the shell's, with the keyboard's).
func _fade_mark() -> void:
	var shell := page as P0AccShell
	if shell != null and shell.mark != null: shell.hide_mark("banner", banner_over_mark())

## The host's, when a sign-in ended with nothing to show here: the sheet closed (cancelled) or it failed (its toast is
## the host's) — the sign-in page's keys back. no_farm / conflict / claimed do it themselves (后裔 11-14).
func sign_in_settled() -> void:
	if sign_in_page != null: sign_in_page.busy = false
	if is_instance_valid(code_page) and page == code_page: code_page.set_busy(false)

## The host's, after guest or a rename did not take the name: back on NAME with why (name_rejected's reason in red);
## pending_expired: the sign-in page again (the host toasts `Sign-in expired. Please sign in again.`).
func name_refused(r: Dictionary) -> void:
	match str(r.get("code", "")):
		"name_rejected":
			if name_page == null: no_farm()
			_show(name_page)
			name_page.refuse(str(r.get("reason", "blocked")))
		"pending_expired": _open_sign_in()

## Try another account: back to the sign-in page, NAME's name dropped (the host drops its pending).
func _try_another() -> void:
	_drop_choose()
	if page == name_page:
		_open_sign_in()
		name_page.free()
		name_page = null
	sign_in_again.emit()

func _drop_choose() -> void:
	if is_instance_valid(choose): choose.queue_free()
	choose = null

## The host's, when a request mid-way came back consent_outdated (spec v2 §9; the server's {terms_version,
## privacy_version}) — a 409 on guest / a code / a rename, or a claim / sign-in that went through with
## `consent_outdated: true`: over whatever page is up, the old player's consent card titled `We've updated our terms`,
## no way to close it (scrim, Back). Its Continue keeps the new versions here (the year, NAME's name and the pending
## ticket stay as they are), greys its key in the pending look and emits consent_renewed: the host sends the refused
## request again, or account/consent for the one that went through, and answers consent_settled(ok). The card stays
## till ok (§9 补: not into the farm or NAME before the consent is kept); not ok gives the key back (the host toasts).
func consent_outdated(r: Dictionary) -> void:
	_renew_versions = {"terms": str(r.get("terms_version", "")), "privacy": str(r.get("privacy_version", ""))}
	if is_instance_valid(renew):   # the terms moved on again while it was up (the resend refused anew): the one card,
		renew.go.phase = CommandLifecycle.State.IDLE   # these versions, agreed again (周瑜 on #1063)
		renew.consent.checked = false
		renew.consent.toggled.emit(false)
		return
	renew = P0AccConsent.new(true)
	renew.name = "AccRenew"
	renew.as_overlay()
	# Q325-AFTER (740:202404): the overlay starts below NAME's title; standalone pages keep their y170.
	renew.card_top = 265.0
	renew.link_pressed.connect(open_link)
	renew.agreed.connect(func():
		if renew.go.phase != CommandLifecycle.State.IDLE: return
		keep_versions(_renew_versions)
		renew.go.phase = CommandLifecycle.State.PENDING
		consent_renewed.emit())
	add_child(renew)
	_lines_on_top()

## The host's answer after consent_renewed: ok takes the updated-terms card down; not ok gives its key back.
func consent_settled(ok: bool) -> void:
	if not is_instance_valid(renew): return
	if ok:
		renew.queue_free()
		renew = null
	else: renew.go.phase = CommandLifecycle.State.IDLE

## Back matrix (491 / 7f0e0cf5, 不知火舞 11-15): only AGE without its confirmation, idle Sign in and NO-GMS
## return false for Android home. Every other gate consumes Back; the runtime also guards complete HTTP operations.
func back() -> bool:
	if is_instance_valid(renew): return true   # the updated-terms card: no way back (spec v2 §9)
	if is_instance_valid(code_page) and page == code_page:
		_code_back()
		return true
	if sign_in_page != null and page == sign_in_page and sign_in_page.busy: return true
	if choose != null:
		_try_another()
		return true
	if page is P0AccAge and (page as P0AccAge).confirm != null:
		(page as P0AccAge)._change()
		return true
	if page == name_page and name_page != null and name_page._checking: return true   # its check in flight: Back waits (周瑜 on #1052)
	if page == name_page and name_page != null and name_page.another_row.visible:
		_try_another()
		return true
	return not (page is P0AccAge or page is P0AccSignIn or page is P0AccNoGms)

## AGE's answer on this phone (q(312)): yes with the versions agreed to, a no alone.
func keep(ok: bool) -> void:
	var data := {"age_ok": ok}
	if ok:
		var v := code_versions() if _code_origin != "" else versions()
		data.merge({"terms": str(v.get("terms", "")), "privacy": str(v.get("privacy", "")), "agreed_at": Time.get_unix_time_from_system() * 1000.0})
	var f := FileAccess.open(record_path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(data))

## The terms agreed to anew (consent_outdated): the versions and when. The age answer stays as it was kept — and stays
## missing where this phone never asked (an old farm claimed past voice's gate): AGE still comes after a sign-out (周瑜).
func keep_versions(v: Dictionary) -> void:
	var data := kept()
	data.merge({"terms": str(v.get("terms", "")), "privacy": str(v.get("privacy", "")),
		"agreed_at": Time.get_unix_time_from_system() * 1000.0}, true)
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
