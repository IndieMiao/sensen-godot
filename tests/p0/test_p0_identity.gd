extends GdUnitTestSuite
## P0Identity (SGODOT-488 A2; contract-accounts.md §1): the first launch's way after hello, claim's three ages, guest's one
## token per launch, the session files, legacy for an older server.
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

func test_a_new_install_is_new_and_a_guest_keeps_its_session() -> void:
	replies["/p0/hello"] = HELLO
	var id := _identity()
	assert_str(_hello(id)).is_equal("new")
	replies["/p0/session/guest"] = {"ok": true, "player": "p0-aaaaaaaaaaaaaaaaaaaa"}
	id.guest({"age_ok": true, "terms": "2026-11-13", "privacy": "2026-11-13", "name": "Mia"}, func(_r): pass)
	var b: Dictionary = sent[-1].body
	assert_int(str(b.token).length()).is_equal(64)
	assert_str(str(b.name)).is_equal("Mia")
	assert_bool(id.has_token()).is_true()
	assert_str(id.first_run()).is_equal("ready")
	# the files: the session and the id, read back by a new launch
	var again := P0Identity.new(dir)
	assert_str(again.player).is_equal("p0-aaaaaaaaaaaaaaaaaaaa")
	assert_str(again.token).is_equal(str(b.token))
	assert_str(FileAccess.get_file_as_string(dir + "p0_player.txt").strip_edges()).is_equal("p0-aaaaaaaaaaaaaaaaaaaa")

func test_a_retried_guest_sends_the_same_token() -> void:
	var id := _identity()
	id.guest({"age_ok": true, "skip": true}, func(_r): pass)   # no answer (network)
	id.guest({"age_ok": true, "skip": true}, func(_r): pass)
	assert_str(str(sent[0].body.token)).is_equal(str(sent[1].body.token))
	assert_bool(id.has_token()).is_false()

func test_an_old_install_claims_and_its_age_picks_the_page() -> void:
	for c in [[null, null, "old_age"], [false, null, "old_blocked"], [true, null, "old_consent"],
			[true, {"terms": "2026-11-13", "privacy": "2026-11-13", "at": 1}, "ready"],
			[true, {"terms": "2026-10-01", "privacy": "2026-11-13", "at": 1}, "old_consent"]]:
		after_test(); before_test()
		_write("p0_player.txt", "p0-old0000000000000001\n")
		replies["/p0/hello"] = HELLO
		replies["/p0/session/claim"] = {"ok": true, "player": "p0-old0000000000000001", "age": c[0], "consent": c[1]}
		var id := _identity()
		assert_str(_hello(id)).override_failure_message(str(c)).is_equal(c[2])
		assert_bool(id.has_token()).is_true()
		assert_str(sent[-1].path).is_equal("/p0/session/claim")

func test_claim_refused_or_unknown() -> void:
	_write("p0_player.txt", "p0-old0000000000000001\n")
	replies["/p0/hello"] = HELLO
	replies["/p0/session/claim"] = {"ok": false, "code": "claimed", "linked": ["apple"]}
	var id := _identity()
	assert_str(_hello(id)).is_equal("claimed")
	assert_array(id.claim_reply.linked).contains_exactly(["apple"])
	replies["/p0/session/claim"] = {"ok": false, "code": "unknown_player"}
	assert_str(_hello(_identity())).is_equal("new")

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
