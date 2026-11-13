class_name P0Identity extends RefCounted
## Who this install is to the server (SGODOT-488 A2; contract-accounts.md §1): the session token and its player, kept in
## user://p0_session.json (and the player in p0_player.txt too: a server rolled back still knows it, the support code
## reads it), and the first launch's way — first_run() after hello(). Requests go through `send` (P0Session's: the
## headers, the demo key, the line), so this holds no HTTP of its own and the tests drive it with a fake.
##
## Only a build that reaches an accounts server takes this way: hello answers terms_version. A 404 or no
## terms_version is an older server — "legacy": the install's own id, x-p0-player alone, no first-launch pages, as before.

const SESSION := "p0_session.json"
const PLAYER := "p0_player.txt"
const FIRST_RUN := "p0_first_run.json"   # the AGE page's record (哪吒's P0AccFlow writes it)
const TOKEN_BYTES := 32

## send.call(method: int, path: String, body: Dictionary, done: Callable): done.call(reply: Dictionary) — a reply is the
## server's JSON, or {ok: false, code: "network"} when none came. P0Session's _account_request.
var send := Callable()
var dir := "user://"
var player := ""
var token := ""
var linked: Array = []
## The first launch's way, once hello has answered (contract v1.4: AGE, then a sign-in, then NAME when no farm):
##   ready        a token held (or ids alone on a legacy_id server): the world
##   new          a new install, or an id the server does not know: AGE → Sign in
##   old_age      an old account never asked its age: AGE → Sign in (claim)
##   old_consent  an old account past voice's 13+ gate, the terms not yet agreed: the consent card → Sign in (claim)
##   old_signin   an old account with its age and the terms: Sign in (claim)
##   old_blocked  an old account that said no at voice's gate; blocked: said no on this install's AGE page
##   signed_out   this install's id is claimed (signed out, or a farm claimed on another phone): Sign in, its line
##                from legacy_linked (["apple"]; [] for a code's account)
##   offline / legacy
var kind := ""
var terms_version := ""
var privacy_version := ""
var legacy_id := false
var guest_ok := false   # the server takes a guest without a sign-in (devserver, shots): the debug build's own key
var email := false      # hello's email: Continue with email is offered
## hello's legacy for this install's id ({age, consent} or {claimed, linked}); {} when it sent none.
var legacy := {}
var legacy_linked: Array = []
var signed_out_why := ""   # "claimed" (hello, claim) or "logout": which line the Sign in page shows (hints)
## The last sign-in's ticket (no_farm, conflict, claimed, unknown_player; 10 minutes, once): guest takes it, or
## session/pending; has_farm says whether that sign-in has a farm of its own; conflict_farm the farm it holds.
var pending := ""
var has_farm := false
var conflict_farm := {}
## What the pages took this launch, for claim (an old account had no token to send them with): the terms agreed, and
## the AGE page passed by an account never asked (age_ok).
var agreed_now := false
var age_passed_now := false
var _launch_token := ""   # one per launch: a retried request sends the same, so a lost answer makes no second save

func _init(at := "user://") -> void:
	dir = at
	var s = _read_json(SESSION)
	if s is Dictionary:
		player = str(s.get("player", ""))
		token = str(s.get("token", ""))
		linked = s.get("linked", []) if s.get("linked", []) is Array else []
	if player == "": player = _read_line(PLAYER)

func has_token() -> bool: return token.length() >= TOKEN_BYTES * 2

## The AGE page said 「没过」 on this install (q(312) ⑨ C): it stays there, and nothing is sent — hello neither.
func locally_blocked() -> bool:
	var f = _read_json(FIRST_RUN)
	return f is Dictionary and f.has("age_ok") and not bool(f.age_ok)

func first_run() -> String: return kind

## The first request of a launch. done.call(kind): the page to open. Nothing is claimed here any more (v1.4: a claim
## carries a sign-in's credentials, so it follows the Sign in page).
func hello(done: Callable) -> void:
	if locally_blocked():
		kind = "blocked"
		done.call(kind)
		return
	send.call(HTTPClient.METHOD_GET, "/p0/hello", {}, func(r: Dictionary):
		if str(r.get("code", "")) == "network":
			kind = "offline"
			done.call(kind)
			return
		if not r.has("terms_version"):
			kind = "legacy"
			done.call(kind)
			return
		terms_version = str(r.terms_version)
		privacy_version = str(r.get("privacy_version", ""))
		legacy_id = bool(r.get("legacy_id", false))
		guest_ok = bool(r.get("guest_ok", false))
		email = bool(r.get("email", false))
		legacy = r.get("legacy", {}) if r.get("legacy") is Dictionary else {}
		if has_token() or (legacy_id and player != ""): kind = "ready"
		elif player == "" or legacy.is_empty(): kind = "new"
		elif bool(legacy.get("claimed", false)): signed_out(legacy.get("linked", []))
		else: kind = _old_kind(legacy)
		done.call(kind))

## An old account's page from hello's legacy {age, consent}.
func _old_kind(l: Dictionary) -> String:
	var age = l.get("age")
	if age == null: return "old_age"
	if not bool(age): return "old_blocked"
	return "old_signin" if agreed(l.get("consent")) else "old_consent"

## A consent record of this server's versions.
func agreed(consent) -> bool:
	return consent is Dictionary and str(consent.get("terms", "")) == terms_version and str(consent.get("privacy", "")) == privacy_version

func signed_out(l, why := "claimed") -> void:
	kind = "signed_out"
	legacy_linked = l if l is Array else []
	signed_out_why = why

## The Sign in page's line on signed_out (哪吒's P0AccFlow hints): {line: farm_uses | last_time, with: apple | google |
## email | code} — a farm linked to none is a code's.
func hints() -> Dictionary:
	if kind != "signed_out": return {}
	return {"line": "last_time" if signed_out_why == "logout" else "farm_uses",
		"with": str(legacy_linked[0]) if not legacy_linked.is_empty() else "code"}

## The pages' answers this launch (P0Runtime on P0AccFlow.agreed): the terms agreed; `age` when it was the AGE page.
func agree(age: bool) -> void:
	agreed_now = true
	if age: age_passed_now = true

## Sign in with a phone's account: session/apple | google | email (contract §2, v1.5). creds: P0SignIn's {id_token,
## nonce, auth_code?} or {email, code}. done.call(reply): ok — signed in, ready; no_farm — `pending` kept for NAME.
func sign_in(provider: String, creds: Dictionary, done: Callable) -> void:
	var t := _token_for_launch()
	send.call(HTTPClient.METHOD_POST, "/p0/session/" + provider, _creds(creds, t), func(r: Dictionary):
		_took(r, t, provider)
		done.call(r))

## An old install's id claimed with a sign-in (v1.4: one step, the claim and the link), the consent and the age the
## pages took on the way. done.call(reply): ok — ready; conflict / claimed / unknown_player carry `pending` and
## has_farm (v1.6 ①): never a second sheet for the same sign-in.
func claim(provider: String, creds: Dictionary, done: Callable) -> void:
	var t := _token_for_launch()
	var b := _creds(creds, t)
	b["provider"] = provider
	if agreed_now: b["consent"] = {"terms": terms_version, "privacy": privacy_version}
	if age_passed_now: b["age_ok"] = true
	send.call(HTTPClient.METHOD_POST, "/p0/session/claim", b, func(r: Dictionary):
		match str(r.get("code", "")):
			"claimed": signed_out(r.get("linked", []))
			"unknown_player":
				# the server has no farm of this id: this install is a new one (v1.6 ①)
				player = ""
				DirAccess.remove_absolute(dir.path_join(PLAYER))
				kind = "new"
		_took(r, t, provider)
		done.call(r))

## session/pending (v1.6 ①): the sign-in a claim or guest already checked, its farm entered — or no_farm with a new
## ticket. done.call(reply).
func sign_in_pending(done: Callable) -> void:
	var t := _token_for_launch()
	send.call(HTTPClient.METHOD_POST, "/p0/session/pending", {"pending": pending, "token": t}, func(r: Dictionary):
		_took(r, t, "")
		done.call(r))

## A test code (contract v1.4 §4): its account signed in, never a second phone's signed out. done.call(reply).
func sign_in_code(code: String, done: Callable) -> void:
	var t := _token_for_launch()
	send.call(HTTPClient.METHOD_POST, "/p0/session/code", {"code": code, "token": t}, func(r: Dictionary):
		_took(r, t, "")
		done.call(r))

## session/logout: this phone's token withdrawn; the session goes whatever the answer (a lost one leaves the token
## unknown to this phone, nothing more), the id stays (the support code; the Sign in page's line).
func logout(done: Callable) -> void:
	send.call(HTTPClient.METHOD_POST, "/p0/session/logout", {}, func(r: Dictionary):
		drop()
		done.call(r))

## This phone's token gone (logout; unauthenticated — the key withdrawn; a replaced session's Sign in): signed_out with
## last time's account, the id kept.
func drop() -> void:
	var was := linked
	forget(true)
	signed_out(was, "logout")

## A sign-in's answer: ok keeps the session (ready); a ticket in it is kept for NAME or session/pending.
func _took(r: Dictionary, t: String, provider: String) -> void:
	if bool(r.get("ok", false)):
		var l = r.get("linked", null)
		_keep(str(r.get("player", player)), t, l if l is Array else [l] if l is String else [provider] if provider != "" else [])
		pending = ""
		kind = "ready"
		return
	if r.has("pending"): pending = str(r.pending)
	has_farm = bool(r.get("has_farm", false))
	conflict_farm = r.get("farm", {}) if r.get("farm") is Dictionary else {}

func _creds(creds: Dictionary, t: String) -> Dictionary:
	var b := {}
	for k in ["id_token", "nonce", "auth_code", "email", "code"]:
		if str(creds.get(k, "")) != "": b[k] = str(creds[k])
	b["token"] = t
	return b

func _token_for_launch() -> String:
	if _launch_token == "": _launch_token = new_token()
	return _launch_token

## session/guest (contract v1.4): body {age_ok, terms, privacy, name | skip}; the sign-in's ticket and this launch's
## token are put in here.
func guest(body: Dictionary, done: Callable) -> void:
	var t := _token_for_launch()
	var b := body.duplicate()
	if pending != "" and not b.has("pending"): b["pending"] = pending
	b["token"] = t
	b["request_id"] = t.substr(0, 32)
	send.call(HTTPClient.METHOD_POST, "/p0/session/guest", b, func(r: Dictionary):
		_took(r, t, "")
		done.call(r))

## account/consent: an old account's age and terms (only ever age_ok true: 「没过」 is never sent, q(312) ⑨ C).
func consent(body: Dictionary, done: Callable) -> void:
	send.call(HTTPClient.METHOD_POST, "/p0/account/consent", body, func(r: Dictionary):
		if bool(r.get("ok", false)): kind = "ready"
		done.call(r))

func name_check(name: String, done: Callable) -> void:
	send.call(HTTPClient.METHOD_POST, "/p0/name/check", {"name": name}, done)

func rename(name: String, done: Callable) -> void:
	send.call(HTTPClient.METHOD_POST, "/p0/account/name", {"name": name}, done)

## A 32-byte token in hex, from the system's random source.
static func new_token() -> String:
	return Crypto.new().generate_random_bytes(TOKEN_BYTES).hex_encode()

## The session kept: p0_session.json, and the player in p0_player.txt too.
func _keep(p: String, t: String, l: Array) -> void:
	player = p
	token = t
	linked = l
	_write(SESSION, JSON.stringify({"v": 1, "player": player, "token": token, "linked": linked,
		"created_at": int(Time.get_unix_time_from_system() * 1000)}))
	_write(PLAYER, player + "\n")

## Gone (account_deleted, a deletion, or Sign in from a replaced session): the token and the session file; the player's
## id file too unless `keep_id`. The AGE page's 「没过」 stays (p0_first_run.json is not this one's).
func forget(keep_id := false) -> void:
	token = ""
	linked = []
	_launch_token = ""
	pending = ""
	DirAccess.remove_absolute(dir.path_join(SESSION))
	if not keep_id:
		player = ""
		DirAccess.remove_absolute(dir.path_join(PLAYER))

func _read_json(name: String):
	var p := dir.path_join(name)
	return JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null

func _read_line(name: String) -> String:
	var p := dir.path_join(name)
	return FileAccess.get_file_as_string(p).strip_edges() if FileAccess.file_exists(p) else ""

func _write(name: String, text: String) -> void:
	var tmp := dir.path_join(name + ".tmp")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null: return
	f.store_string(text)
	f.close()
	DirAccess.rename_absolute(tmp, dir.path_join(name))
