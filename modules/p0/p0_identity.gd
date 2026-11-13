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
## The first launch's way, once hello has answered: ready / new / old_age / old_consent / old_blocked / blocked / claimed /
## offline / legacy.
var kind := ""
var terms_version := ""
var privacy_version := ""
var legacy_id := false
## claim's answer kept for the pages (its age, its consent; `linked` on claimed).
var claim_reply := {}
var _guest_token := ""   # one per first launch: a retried guest sends the same, so a lost answer makes no second save

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

## The first request of a launch. done.call(kind). An old install (an id, no token) claims inside it, so `kind` is the
## page to open when done is called.
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
		if has_token() or (legacy_id and player != ""):
			kind = "ready"
			done.call(kind)
		elif player != "":
			claim(func(_c): done.call(kind))
		else:
			kind = "new"
			done.call(kind))

## An old install's id for a token, once (contract §1). done.call(reply); `kind` follows its answer.
func claim(done: Callable) -> void:
	var t := token if has_token() else new_token()
	send.call(HTTPClient.METHOD_POST, "/p0/session/claim", {"token": t}, func(r: Dictionary):
		claim_reply = r
		var code := str(r.get("code", ""))
		if bool(r.get("ok", false)):
			_keep(str(r.get("player", player)), t, [])
			var consent = r.get("consent")
			var agreed: bool = consent is Dictionary and str(consent.get("terms", "")) == terms_version and str(consent.get("privacy", "")) == privacy_version
			var age = r.get("age")
			if age == null: kind = "old_age"
			elif not bool(age): kind = "old_blocked"
			elif not agreed: kind = "old_consent"
			else: kind = "ready"
		elif code == "unknown_player": kind = "new"
		elif code == "claimed": kind = "claimed"
		else: kind = "offline"
		done.call(r))

## session/guest (contract §1): body {age_ok, terms, privacy, name | skip, pending?}; the token is this launch's own.
func guest(body: Dictionary, done: Callable) -> void:
	if _guest_token == "": _guest_token = new_token()
	var b := body.duplicate()
	b["token"] = _guest_token
	b["request_id"] = _guest_token.substr(0, 32)
	send.call(HTTPClient.METHOD_POST, "/p0/session/guest", b, func(r: Dictionary):
		if bool(r.get("ok", false)):
			var l = r.get("linked", null)
			_keep(str(r.player), _guest_token, [l] if l is String else [])
			kind = "ready"
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
	_guest_token = ""
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
