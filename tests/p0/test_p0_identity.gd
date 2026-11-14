extends GdUnitTestSuite
## P0Identity (SGODOT-488 A2; contract-accounts v1.4–v1.6.3): the first launch's way after hello (legacy's ages, a claimed
## id signed out), the sign-ins (claim with credentials, the ticket kept for guest and session/pending, a test code,
## logout), one token per launch, the session files, legacy for an older server.
const P0Identity := preload("res://modules/p0/p0_identity.gd")
var dir: String
var sent: Array = []
var replies := {}   # path → the reply to give

func before_test() -> void:
	dir = "user://test_488_identity_%d/" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	sent = []
	replies = {}

func after_test() -> void:
	var d := DirAccess.open(dir)
	if d:
		for n in d.get_files(): d.remove(n)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))

func _write(name: String, text: String) -> void:
	var f := FileAccess.open(dir + name, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _identity() -> P0Identity:
	var id := P0Identity.new(dir)
	id.send = func(method: int, path: String, body: Dictionary, done: Callable):
		sent.append({method = method, path = path, body = body})
		done.call(replies.get(path, {"ok": false, "code": "network"}))
	return id

const HELLO := {"ok": true, "terms_version": "2026-11-13", "privacy_version": "2026-11-13", "legacy_id": false}

func _hello(id: P0Identity) -> String:
	var got := [""]
	id.hello(func(k): got[0] = k)
	return got[0]

func _sent(path: String) -> Array: return sent.filter(func(x): return x.path == path)

const CREDS := {"id_token": "eyJ.apple.tok", "nonce": "n0nce", "auth_code": "c0de"}

func test_a_new_install_signs_in_with_no_farm_and_guest_takes_the_ticket() -> void:
	replies["/p0/hello"] = HELLO
	var id := _identity()
	assert_str(_hello(id)).is_equal("new")
	replies["/p0/session/google"] = {"ok": false, "code": "no_farm", "pending": "pend-1"}
	id.sign_in("google", {"id_token": "eyJ.g", "nonce": "n1"}, func(_r): pass)
	var si: Dictionary = _sent("/p0/session/google")[0].body
	assert_dict(si).contains_key_value("id_token", "eyJ.g").contains_key_value("nonce", "n1").not_contains_keys(["auth_code", "provider"])
	assert_str(id.pending).is_equal("pend-1")
	assert_bool(id.has_token()).is_false()
	replies["/p0/session/guest"] = {"ok": true, "player": "p0-aaaaaaaaaaaaaaaaaaaa", "linked": "google"}
	id.guest({"age_ok": true, "terms": "2026-11-13", "privacy": "2026-11-13", "name": "Mia"}, func(_r): pass)
	var b: Dictionary = _sent("/p0/session/guest")[0].body
	assert_str(str(b.pending)).is_equal("pend-1")
	assert_str(str(b.token)).is_equal(str(si.token))   # one token a launch
	assert_int(str(b.token).length()).is_equal(64)
	assert_str(str(b.name)).is_equal("Mia")
	assert_str(id.first_run()).is_equal("ready")
	assert_str(id.pending).is_empty()
	assert_array(id.linked).contains_exactly(["google"])
	# the files: the session and the id, read back by a new launch
	var again := P0Identity.new(dir)
	assert_str(again.player).is_equal("p0-aaaaaaaaaaaaaaaaaaaa")
	assert_str(again.token).is_equal(str(b.token))
	assert_str(FileAccess.get_file_as_string(dir + "p0_player.txt").strip_edges()).is_equal("p0-aaaaaaaaaaaaaaaaaaaa")

func test_a_sign_in_with_a_farm_is_ready() -> void:
	replies["/p0/hello"] = HELLO
	var id := _identity()
	_hello(id)
	replies["/p0/session/apple"] = {"ok": true, "player": "p0-cccccccccccccccccccc", "linked": ["apple"]}
	id.sign_in("apple", CREDS, func(_r): pass)
	assert_dict(_sent("/p0/session/apple")[0].body).contains_key_value("auth_code", "c0de")
	assert_str(id.first_run()).is_equal("ready")
	assert_str(id.player).is_equal("p0-cccccccccccccccccccc")
	assert_array(id.linked).contains_exactly(["apple"])

func test_a_retried_guest_sends_the_same_token() -> void:
	var id := _identity()
	id.guest({"age_ok": true, "skip": true}, func(_r): pass)   # no answer (network)
	id.guest({"age_ok": true, "skip": true}, func(_r): pass)
	assert_str(str(sent[0].body.token)).is_equal(str(sent[1].body.token))
	assert_bool(id.has_token()).is_false()

func test_an_old_install_s_page_comes_from_hello_and_nothing_is_claimed_there() -> void:
	var now := {"terms": "2026-11-13", "privacy": "2026-11-13"}
	for c in [[null, null, "old_age"], [false, null, "old_blocked"], [true, null, "old_consent"], [true, now, "old_signin"],
			[true, {"terms": "2026-10-01", "privacy": "2026-11-13"}, "old_consent"]]:
		after_test(); before_test()
		_write("p0_player.txt", "p0-old0000000000000001\n")
		replies["/p0/hello"] = HELLO.merged({"legacy": {"age": c[0], "consent": c[1]}}, true)
		var id := _identity()
		assert_str(_hello(id)).override_failure_message(str(c)).is_equal(c[2])
		assert_bool(id.has_token()).is_false()
		assert_int(sent.size()).is_equal(1)   # hello alone

func test_an_id_the_server_does_not_know_is_new_and_a_claimed_one_signed_out() -> void:
	_write("p0_player.txt", "p0-old0000000000000001\n")
	replies["/p0/hello"] = HELLO   # no legacy: the server has no such farm
	assert_str(_hello(_identity())).is_equal("new")
	replies["/p0/hello"] = HELLO.merged({"legacy": {"claimed": true, "linked": ["apple"]}}, true)
	var id := _identity()
	assert_str(_hello(id)).is_equal("signed_out")
	assert_dict(id.hints()).is_equal({"line": "farm_uses", "with": "apple"})
	replies["/p0/hello"] = HELLO.merged({"legacy": {"claimed": true, "linked": []}}, true)   # a code given to an old farm
	id = _identity()
	_hello(id)
	assert_dict(id.hints()).is_equal({"line": "farm_uses", "with": "code"})

func test_a_claim_carries_the_sign_in_and_what_the_pages_took() -> void:
	_write("p0_player.txt", "p0-old0000000000000001\n")
	replies["/p0/hello"] = HELLO.merged({"legacy": {"age": null, "consent": null}}, true)
	var id := _identity()
	assert_str(_hello(id)).is_equal("old_age")
	id.agree(true)   # AGE passed
	replies["/p0/session/claim"] = {"ok": true, "player": "p0-old0000000000000001", "age": true, "consent": {}}
	id.claim("apple", CREDS, func(_r): pass)
	var b: Dictionary = _sent("/p0/session/claim")[0].body
	assert_dict(b).contains_key_value("provider", "apple").contains_key_value("id_token", "eyJ.apple.tok") \
		.contains_key_value("nonce", "n0nce").contains_key_value("auth_code", "c0de").contains_key_value("age_ok", true) \
		.contains_key_value("consent", {"terms": "2026-11-13", "privacy": "2026-11-13"})
	assert_str(id.first_run()).is_equal("ready")
	assert_array(id.linked).contains_exactly(["apple"])
	# the consent card alone: the terms, no age_ok
	sent.clear()
	var other := _identity()
	_hello(other)
	other.agree(false)
	other.claim("google", {"id_token": "g", "nonce": "n"}, func(_r): pass)
	assert_dict(_sent("/p0/session/claim")[0].body).contains_keys(["consent"]).not_contains_keys(["age_ok"])

func test_a_claim_refused_keeps_its_ticket() -> void:
	_write("p0_player.txt", "p0-old0000000000000001\n")
	replies["/p0/hello"] = HELLO.merged({"legacy": {"age": true, "consent": null}}, true)
	var id := _identity()
	_hello(id)
	var farm := {"name": "Mia", "home_level": 7, "last_played_at": 1}
	replies["/p0/session/claim"] = {"ok": false, "code": "conflict", "pending": "pend-c", "has_farm": true, "farm": farm}
	id.claim("google", {"id_token": "g", "nonce": "n"}, func(_r): pass)
	assert_str(id.pending).is_equal("pend-c")
	assert_bool(id.has_farm).is_true()
	assert_dict(id.conflict_farm).is_equal(farm)
	assert_str(id.first_run()).is_equal("old_consent")   # still the old account's: another claim may follow
	replies["/p0/session/pending"] = {"ok": true, "player": "p0-dddddddddddddddddddd", "linked": ["google"]}
	id.sign_in_pending(func(_r): pass)
	assert_dict(_sent("/p0/session/pending")[0].body).contains_key_value("pending", "pend-c")
	assert_str(id.player).is_equal("p0-dddddddddddddddddddd")
	assert_str(id.first_run()).is_equal("ready")

func test_claimed_signs_out_and_unknown_player_is_a_new_install() -> void:
	_write("p0_player.txt", "p0-old0000000000000001\n")
	replies["/p0/hello"] = HELLO.merged({"legacy": {"age": true, "consent": null}}, true)
	var id := _identity()
	_hello(id)
	replies["/p0/session/claim"] = {"ok": false, "code": "claimed", "linked": ["apple"], "pending": "p2", "has_farm": false}
	id.claim("google", {"id_token": "g", "nonce": "n"}, func(_r): pass)
	assert_str(id.first_run()).is_equal("signed_out")
	assert_array(id.legacy_linked).contains_exactly(["apple"])
	assert_str(id.pending).is_equal("p2")
	assert_bool(FileAccess.file_exists(dir + "p0_player.txt")).is_true()   # kept: that farm may still be claimed later
	id = _identity()
	_hello(id)
	replies["/p0/session/claim"] = {"ok": false, "code": "unknown_player", "pending": "p3", "has_farm": false}
	id.claim("google", {"id_token": "g", "nonce": "n"}, func(_r): pass)
	assert_str(id.first_run()).is_equal("new")
	assert_str(id.player).is_empty()
	assert_bool(FileAccess.file_exists(dir + "p0_player.txt")).is_false()

func test_a_test_code_signs_in_and_logout_keeps_the_id() -> void:
	replies["/p0/hello"] = HELLO
	var id := _identity()
	_hello(id)
	replies["/p0/session/code"] = {"ok": true, "player": "p0-eeeeeeeeeeeeeeeeeeee"}
	id.sign_in_code("ABCD-EFGH-JKMN", func(_r): pass)
	assert_dict(_sent("/p0/session/code")[0].body).contains_key_value("code", "ABCD-EFGH-JKMN").contains_keys(["token"])
	assert_bool(id.has_token()).is_true()
	assert_array(id.linked).is_empty()
	replies["/p0/session/logout"] = {"ok": true}
	id.logout(func(_r): pass)
	assert_bool(id.has_token()).is_false()
	assert_bool(FileAccess.file_exists(dir + "p0_session.json")).is_false()
	assert_str(FileAccess.get_file_as_string(dir + "p0_player.txt").strip_edges()).is_equal("p0-eeeeeeeeeeeeeeeeeeee")
	assert_str(id.first_run()).is_equal("signed_out")
	assert_dict(id.hints()).is_equal({"line": "last_time", "with": "code"})

func test_a_token_is_ready_and_an_older_server_is_legacy() -> void:
	_write("p0_session.json", JSON.stringify({"v": 1, "player": "p0-x", "token": "ab".repeat(32), "linked": []}))
	replies["/p0/hello"] = HELLO
	assert_str(_hello(_identity())).is_equal("ready")
	replies["/p0/hello"] = {"ok": false, "code": "not_found"}   # an older server: no such route
	assert_str(_hello(_identity())).is_equal("legacy")
	replies.erase("/p0/hello")
	assert_str(_hello(_identity())).is_equal("offline")

func test_ids_alone_on_a_legacy_id_server_are_ready_without_a_claim() -> void:
	_write("p0_player.txt", "p0-shot000000000000001\n")
	replies["/p0/hello"] = HELLO.merged({"legacy_id": true}, true)
	assert_str(_hello(_identity())).is_equal("ready")
	assert_int(sent.size()).is_equal(1)

func test_blocked_on_this_install_sends_nothing() -> void:
	_write("p0_first_run.json", '{"age_ok": false}')
	replies["/p0/hello"] = HELLO
	assert_str(_hello(_identity())).is_equal("blocked")
	assert_array(sent).is_empty()

func test_forget_drops_the_session_and_keeps_the_age_record() -> void:
	_write("p0_first_run.json", '{"age_ok": true}')
	_write("p0_session.json", JSON.stringify({"v": 1, "player": "p0-x", "token": "ab".repeat(32)}))
	_write("p0_player.txt", "p0-x\n")
	var id := _identity()
	id.forget()
	assert_bool(FileAccess.file_exists(dir + "p0_session.json")).is_false()
	assert_bool(FileAccess.file_exists(dir + "p0_player.txt")).is_false()
	assert_bool(FileAccess.file_exists(dir + "p0_first_run.json")).is_true()
