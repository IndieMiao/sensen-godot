extends GdUnitTestSuite
## 邮箱账号（SGODOT-135）：登录换身份、启动恢复、token 失效回游客、登出与删号。

const ACCOUNT := "user://test_account_session.json"

func _net(responses: Array) -> Array:
	var t := FakeTransport.new(responses)
	var n = load("res://modules/net/net_service.gd").new()
	add_child(auto_free(n))
	n.use_transport(t.callable(), "https://account.test/v1", ACCOUNT)
	return [n, t]

func before_test() -> void:
	AccountSession.new().clear(ACCOUNT)

func after_test() -> void:
	AccountSession.new().clear(ACCOUNT)

func _auth_header(request: Dictionary) -> String:
	for h in request.headers:
		if str(h).begins_with("authorization:"): return str(h)
	return ""

func test_guest_boot_is_read_only_until_sign_in() -> void:
	var pair := _net([
		{"status": 200, "json": {"player_id": "guest", "token": "guest-token"}},
		{"status": 404, "json": {"code": "NO_FARM"}},
		{"status": 401, "json": {"code": "UNAUTHENTICATED"}},
	])
	var n = pair[0]
	assert_bool(await n.boot()).is_true()
	assert_bool(n.is_guest()).is_true()
	assert_str(pair[1].requests[0].url).ends_with("/auth/anonymous")

func test_sign_in_switches_token_persists_and_loads_the_account_farm() -> void:
	var pair := _net([
		{"status": 200, "json": {"player_id": "guest", "token": "guest-token"}},
		{"status": 404, "json": {"code": "NO_FARM"}},
		{"status": 401, "json": {"code": "UNAUTHENTICATED"}},
		{"status": 200, "json": {"farm_id": "f1", "version": 2, "region_id": "shanghai", "state": {"wallet": 5}}},
	])
	var n = pair[0]
	var t: FakeTransport = pair[1]
	await n.boot()
	var changes := []
	n.account_changed.connect(func(v): changes.append(v))
	var ok: bool = await n.sign_in_with({"token": "acct-token", "user_id": "u1", "player_id": "p1", "email": "ada@example.com", "email_verified": false})
	assert_bool(ok).is_true()
	assert_bool(n.is_guest()).is_false()
	assert_str(_auth_header(t.requests[-1])).is_equal("authorization: Bearer acct-token")
	assert_bool(n.session.has_farm()).is_true()
	assert_array(changes).is_equal([true])
	var saved := AccountSession.new()
	assert_bool(saved.load_saved(ACCOUNT)).is_true()
	assert_str(saved.email).is_equal("ada@example.com")
	assert_str(saved.player_id).is_equal("p1")

func test_boot_resumes_a_saved_account_without_guest_login() -> void:
	var saved := AccountSession.new()
	saved.adopt({"token": "acct-token", "user_id": "u1", "player_id": "p1", "email": "ada@example.com"}, ACCOUNT)
	var pair := _net([
		{"status": 200, "json": {"user_id": "u1", "player_id": "p1", "email": "ada@example.com", "email_verified": true}},
		{"status": 404, "json": {"code": "NO_FARM"}},
		{"status": 200, "json": {"protocol": 1}},
	])
	var n = pair[0]
	var t: FakeTransport = pair[1]
	assert_bool(await n.boot()).is_true()
	assert_bool(n.is_guest()).is_false()
	assert_bool(n.account.email_verified).is_true()
	assert_str(t.requests[0].url).ends_with("/users/me")
	assert_str(_auth_header(t.requests[0])).is_equal("authorization: Bearer acct-token")
	for r in t.requests: assert_str(r.url).not_contains("/auth/anonymous")

func test_expired_account_token_falls_back_to_guest_and_forgets_it() -> void:
	var saved := AccountSession.new()
	saved.adopt({"token": "stale", "user_id": "u1", "player_id": "p1", "email": "ada@example.com"}, ACCOUNT)
	var pair := _net([
		{"status": 401, "json": {"code": "UNAUTHENTICATED"}},
		{"status": 200, "json": {"player_id": "guest", "token": "guest-token"}},
		{"status": 404, "json": {"code": "NO_FARM"}},
		{"status": 401, "json": {"code": "UNAUTHENTICATED"}},
	])
	var n = pair[0]
	assert_bool(await n.boot()).is_true()
	assert_bool(n.is_guest()).is_true()
	assert_str(n.client.token).is_equal("guest-token")
	assert_bool(AccountSession.new().load_saved(ACCOUNT)).is_false()

func test_offline_boot_keeps_the_saved_account() -> void:
	var saved := AccountSession.new()
	saved.adopt({"token": "acct-token", "user_id": "u1", "player_id": "p1", "email": "ada@example.com"}, ACCOUNT)
	var pair := _net([{"error": "offline"}, {"error": "offline"}])
	var n = pair[0]
	await n.boot()
	assert_bool(n.is_guest()).is_false()
	assert_str(n.client.token).is_equal("acct-token")
	assert_bool(AccountSession.new().load_saved(ACCOUNT)).is_true()

## C-110: 5xx and 429 from /users/me keep the saved account too; only 401 clears it (above).
func test_server_error_on_boot_keeps_the_saved_account() -> void:
	var saved := AccountSession.new()
	saved.adopt({"token": "acct-token", "user_id": "u1", "player_id": "p1", "email": "ada@example.com"}, ACCOUNT)
	for answer in [{"status": 503, "json": {}}, {"status": 429, "json": {"code": "RATE_LIMITED"}}]:
		var pair := _net([answer, {"error": "offline"}, {"error": "offline"}])
		var n = pair[0]
		await n.boot()
		assert_bool(n.is_guest()).is_false()
		assert_str(n.client.token).is_equal("acct-token")
		assert_str(n.restore_error).is_not_empty()
		for r in pair[1].requests: assert_str(r.url).not_contains("/auth/anonymous")
		assert_bool(AccountSession.new().load_saved(ACCOUNT)).is_true()

## C-110: the account file is written to a temporary file and then renamed over the old one.
func test_account_file_is_replaced_whole() -> void:
	var a := AccountSession.new()
	a.adopt({"token": "token-a", "user_id": "u1", "player_id": "p1", "email": "ada@example.com"}, ACCOUNT)
	assert_bool(FileAccess.file_exists(ACCOUNT + ".tmp")).is_false()
	assert_bool(JSON.parse_string(FileAccess.get_file_as_string(ACCOUNT)) is Dictionary).is_true()
	a.adopt({"token": "token-b", "display_name": "Ada"}, ACCOUNT)
	var again := AccountSession.new()
	assert_bool(again.load_saved(ACCOUNT)).is_true()
	assert_str(again.token).is_equal("token-b")
	assert_str(again.display_name).is_equal("Ada")
	assert_bool(FileAccess.file_exists(ACCOUNT + ".tmp")).is_false()

## A write cut off part-way (the app is killed before the rename) leaves the previous account readable; the
## half-written temporary file is never read and the next save replaces it.
func test_interrupted_account_write_keeps_the_previous_file() -> void:
	var a := AccountSession.new()
	a.adopt({"token": "token-a", "user_id": "u1", "player_id": "p1", "email": "ada@example.com"}, ACCOUNT)
	var before := FileAccess.get_file_as_bytes(ACCOUNT)
	var full := JSON.stringify({"token": "token-b", "user_id": "u1", "player_id": "p1"})
	assert_bool(AccountSession.write_temp(ACCOUNT + ".tmp", full.left(full.length() / 2))).is_true()
	assert_array(Array(FileAccess.get_file_as_bytes(ACCOUNT))).is_equal(Array(before))
	var reread := AccountSession.new()
	assert_bool(reread.load_saved(ACCOUNT)).is_true()
	assert_str(reread.token).is_equal("token-a")
	reread.adopt({"token": "token-c"}, ACCOUNT)
	var last := AccountSession.new()
	assert_bool(last.load_saved(ACCOUNT)).is_true()
	assert_str(last.token).is_equal("token-c")
	assert_bool(FileAccess.file_exists(ACCOUNT + ".tmp")).is_false()
	# clear() also drops a leftover temporary file.
	AccountSession.write_temp(ACCOUNT + ".tmp", "{")
	last.clear(ACCOUNT)
	assert_bool(FileAccess.file_exists(ACCOUNT)).is_false()
	assert_bool(FileAccess.file_exists(ACCOUNT + ".tmp")).is_false()

## A write that cannot complete reports failure and leaves nothing behind.
func test_failed_account_write_leaves_no_file() -> void:
	var path := "user://c110_missing_dir/account.json"
	assert_bool(AccountSession.write_atomic(path, "{}")).is_false()
	assert_bool(FileAccess.file_exists(path)).is_false()
	assert_bool(FileAccess.file_exists(path + ".tmp")).is_false()

func test_sign_out_revokes_this_device_and_returns_to_guest() -> void:
	var pair := _net([
		{"status": 200, "json": {"player_id": "guest", "token": "guest-token"}},
		{"status": 404, "json": {"code": "NO_FARM"}},
		{"status": 401, "json": {"code": "UNAUTHENTICATED"}},
		{"status": 404, "json": {"code": "NO_FARM"}},
		{"status": 200, "json": {"protocol": 1}},
		{"status": 200, "json": {"ok": true}},
		{"status": 200, "json": {"player_id": "guest", "token": "guest-token-2"}},
	])
	var n = pair[0]
	var t: FakeTransport = pair[1]
	await n.boot()
	await n.sign_in_with({"token": "acct-token", "user_id": "u1", "player_id": "p1", "email": "ada@example.com"})
	await n.sign_out()
	assert_bool(n.is_guest()).is_true()
	assert_str(t.requests[4].url).ends_with("/online/status")
	assert_str(t.requests[5].method).is_equal("DELETE")
	assert_str(t.requests[5].url).ends_with("/auth/token")
	assert_str(_auth_header(t.requests[5])).is_equal("authorization: Bearer acct-token")
	assert_str(n.client.token).is_equal("guest-token-2")
	assert_bool(n.session.has_farm()).is_false()
	assert_bool(AccountSession.new().load_saved(ACCOUNT)).is_false()

func test_delete_account_sends_password_and_keeps_account_on_refusal() -> void:
	var pair := _net([
		{"status": 200, "json": {"player_id": "guest", "token": "guest-token"}},
		{"status": 404, "json": {"code": "NO_FARM"}},
		{"status": 401, "json": {"code": "UNAUTHENTICATED"}},
		{"status": 404, "json": {"code": "NO_FARM"}},
		{"status": 200, "json": {"protocol": 1}},
		{"status": 401, "json": {"code": "INVALID_CREDENTIALS"}},
		{"status": 200, "json": {"ok": true, "deleted": true}},
		{"status": 200, "json": {"player_id": "guest", "token": "guest-token-2"}},
	])
	var n = pair[0]
	var t: FakeTransport = pair[1]
	await n.boot()
	await n.sign_in_with({"token": "acct-token", "user_id": "u1", "player_id": "p1", "email": "ada@example.com"})
	var refused: Dictionary = await n.delete_account("wrong")
	assert_bool(refused.ok).is_false()
	assert_str(refused.code).is_equal("INVALID_CREDENTIALS")
	assert_bool(n.is_guest()).is_false()
	var deleted: Dictionary = await n.delete_account("correct horse")
	assert_bool(deleted.ok).is_true()
	assert_str(t.requests[6].body.password).is_equal("correct horse")
	assert_bool(n.is_guest()).is_true()

func test_error_codes_have_player_facing_sentences() -> void:
	for code in ["INVALID_EMAIL", "WEAK_PASSWORD", "EMAIL_TAKEN", "INVALID_CREDENTIALS", "CODE_INVALID", "CODE_EXPIRED",
			"CODE_LOCKED", "CODE_COOLDOWN", "RATE_LIMITED", "LOGIN_REQUIRED", "TRANSPORT", "SOMETHING_NEW"]:
		var text := AccountSession.describe(code)
		assert_str(text).is_not_empty()
		assert_str(text).is_not_equal(code)

func test_local_email_and_password_checks() -> void:
	assert_bool(AccountSession.valid_email("ada@example.com")).is_true()
	assert_bool(AccountSession.valid_email(" ada@example.com ")).is_true()
	for bad in ["", "ada", "ada@", "@example.com", "ada@example", "a da@example.com", "ada@example."]:
		assert_bool(AccountSession.valid_email(bad)).is_false()
	assert_bool(AccountSession.valid_password("12345678")).is_true()
	assert_bool(AccountSession.valid_password("1234567")).is_false()
	assert_bool(AccountSession.valid_password("        ")).is_false()
