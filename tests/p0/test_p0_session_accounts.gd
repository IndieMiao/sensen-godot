extends GdUnitTestSuite
## P0Session on an accounts server (SGODOT-488 A2; contract-accounts.md §0–§1): the gate before the identity is known, the
## token beside the id, account refusals that stop everything without reading as a lost connection.
const P0Identity := preload("res://modules/p0/p0_identity.gd")

func _session() -> P0Session:
	var s := P0Session.new()   # not in the tree: _ready not run, set up by hand
	s.accounts = true
	s.player_id = "p0-aaaaaaaaaaaaaaaaaaaa"
	s.identity.token = "ab".repeat(32)
	s.identity.player = s.player_id
	return auto_free(s)

func test_nothing_leaves_before_the_identity_is_known() -> void:
	var s := _session()
	var sent: Array = []
	s.transport = func(_m: int, path: String, _b: Dictionary, _c: Dictionary): sent.append(path)
	s.refresh()
	s.report({"kind": "screen", "name": "farm"})
	s._flush_ui()
	assert_array(sent).is_empty()
	assert_array(s._ui_events).is_empty()   # not kept for later either
	s.identity_ready = true
	s.refresh()
	assert_array(sent).contains_exactly(["/p0/state"])

func test_the_token_goes_beside_the_id_with_the_platform_and_accounts_feature() -> void:
	var s := _session()
	s.channel = "play"
	var h := Array(s._headers())
	assert_array(h).contains(["x-p0-player: p0-aaaaaaaaaaaaaaaaaaaa", "authorization: Bearer " + "ab".repeat(32),
		"x-p0-platform: desktop", "x-p0-channel: play"])
	assert_bool(h.any(func(x): return str(x).begins_with("x-p0-features:") and str(x).ends_with(",accounts"))).is_true()
	s.accounts = false   # an older server: as before, no token, no accounts feature
	h = Array(s._headers())
	assert_bool(h.any(func(x): return str(x).begins_with("authorization"))).is_false()
	assert_bool(h.any(func(x): return str(x).ends_with(",accounts"))).is_false()

func test_an_account_refusal_stops_everything_and_is_no_lost_connection() -> void:
	var s := _session()
	s.identity_ready = true
	var states: Array = []
	var failed := [false]
	s.account_state.connect(func(k, d): states.append([k, d.get("until", "")]))
	s.connection_failed.connect(func(_m, _c): failed[0] = true)
	var raw := JSON.stringify({"ok": false, "code": "session_replaced"}).to_utf8_buffer()
	var out: Dictionary = s._handle(HTTPRequest.RESULT_SUCCESS, 401, raw, {})
	assert_str(str(out.code)).is_equal("session_replaced")
	assert_bool(s.identity_ready).is_false()
	assert_bool(failed[0]).is_false()
	s.identity_ready = true
	s._handle(HTTPRequest.RESULT_SUCCESS, 403, JSON.stringify({"ok": false, "code": "suspended", "until": null}).to_utf8_buffer(), {})
	assert_array(states).contains_exactly([["session_replaced", ""], ["suspended", null]])

func test_a_401_off_accounts_is_as_before() -> void:
	var s := _session()
	s.accounts = false
	assert_dict(P0Session.account_refusal(HTTPRequest.RESULT_SUCCESS, 401, JSON.stringify({"code": "bad_key"}).to_utf8_buffer())).is_empty()

func test_demo_accounts_reads_the_channel_and_the_switch() -> void:
	assert_dict(P0Session.demo_accounts('{"channel": "appstore"}')).is_equal({"channel": "appstore", "accounts": true})
	assert_dict(P0Session.demo_accounts('{"channel": "nope", "accounts": false}')).is_equal({"channel": "", "accounts": false})
	assert_dict(P0Session.demo_accounts("")).is_equal({"channel": "", "accounts": true})

func test_a_voice_reply_with_an_account_code_stops_the_session_too() -> void:
	var s := _session()
	s.identity_ready = true
	var states: Array = []
	s.account_state.connect(func(k, _d): states.append(k))
	var raw := JSON.stringify({"ok": false, "code": "account_deleted"}).to_utf8_buffer()
	assert_bool(s.take_account_refusal(HTTPRequest.RESULT_SUCCESS, 401, raw)).is_true()
	assert_bool(s.identity_ready).is_false()
	assert_array(states).contains_exactly(["account_deleted"])
	assert_bool(s.take_account_refusal(HTTPRequest.RESULT_SUCCESS, 403, JSON.stringify({"code": "AGE_GATE"}).to_utf8_buffer())).is_false()

## PR-A on farm-dev before its server is live (哪吒's 491 PR, 奕星 11-14): hello 404 / no terms_version is an older
## server — the install's own id, x-p0-player alone, the world's first read; no first-launch page, no token.
func test_an_older_server_is_the_old_way_in_with_no_pages() -> void:
	var s := _session()
	s.identity = P0Identity.new("user://test_488_legacy_%d/" % OS.get_process_id())
	s.identity.send = func(_m: int, _p: String, _b: Dictionary, done: Callable): done.call({"ok": false, "code": "not_found"})
	s.identity_ready = false
	var sent: Array = []
	s.transport = func(_m: int, path: String, _b: Dictionary, _c: Dictionary): sent.append(path)
	var pages: Array = []
	s.first_run_needed.connect(func(k): pages.append(k))
	s.hello(func(_r): pass)
	assert_bool(s.accounts).is_false()
	assert_bool(s.identity_ready).is_true()
	assert_str(s.player_id).is_not_empty()
	assert_array(pages).is_empty()
	assert_array(sent).contains(["/p0/state"])
	assert_bool(Array(s._headers()).any(func(h): return str(h).begins_with("authorization"))).is_false()
