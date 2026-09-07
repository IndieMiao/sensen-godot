extends GdUnitTestSuite
## FirebaseAuth：URL / 请求体形状、成功与失败映射、securetoken 刷新契约、未配置短路。

const KEY := "test-key"

func _fb(t: FakeTransport) -> FirebaseAuth:
	return FirebaseAuth.new(KEY, t.callable())

func _session_json(extra := {}) -> Dictionary:
	var d := {"localId": "uid-1", "email": "a@b.co", "idToken": "id-1", "refreshToken": "rt-1", "expiresIn": "3600"}
	d.merge(extra, true)
	return d

func test_unconfigured_client_short_circuits_without_transport_calls() -> void:
	var t := FakeTransport.new([{"status": 200}])
	var fb := FirebaseAuth.new("", t.callable())
	assert_bool(fb.configured()).is_false()
	var r: Dictionary = await fb.sign_in_with_password("a@b.co", "secret1")
	assert_bool(r.ok).is_false()
	assert_str(r.code).is_equal("NOT_CONFIGURED")
	var rf: Dictionary = await fb.refresh("rt")
	assert_bool(rf.ok).is_false()
	assert_bool(rf.fatal).is_false()
	assert_int(t.requests.size()).is_equal(0)

func test_sign_in_with_password_builds_request_and_maps_session() -> void:
	var t := FakeTransport.new([{"status": 200, "json": _session_json()}])
	var r: Dictionary = await _fb(t).sign_in_with_password("a@b.co", "secret1")
	assert_str(t.requests[0].method).is_equal("POST")
	assert_str(t.requests[0].url).is_equal("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=test-key")
	assert_str(t.requests[0].body.email).is_equal("a@b.co")
	assert_str(t.requests[0].body.password).is_equal("secret1")
	assert_bool(t.requests[0].body.returnSecureToken).is_true()
	assert_bool(r.ok).is_true()
	assert_str(r.user_id).is_equal("uid-1")
	assert_str(r.email).is_equal("a@b.co")
	assert_str(r.id_token).is_equal("id-1")
	assert_str(r.refresh_token).is_equal("rt-1")
	assert_int(r.expires_in_s).is_equal(3600)

func test_sign_up_uses_signup_endpoint_and_flags_new_user() -> void:
	var t := FakeTransport.new([{"status": 200, "json": _session_json({"isNewUser": true})}])
	var r: Dictionary = await _fb(t).sign_up("a@b.co", "secret1")
	assert_bool(str(t.requests[0].url).contains("accounts:signUp?key=")).is_true()
	assert_bool(r.is_new_user).is_true()

func test_error_body_maps_to_code_and_weak_password_is_trimmed() -> void:
	var t := FakeTransport.new([
		{"status": 400, "json": {"error": {"code": 400, "message": "INVALID_PASSWORD"}}},
		{"status": 400, "json": {"error": {"code": 400, "message": "WEAK_PASSWORD : Password should be at least 6 characters"}}},
		{"status": 500, "json": {}},
		{"error": "timeout"},
	])
	var fb := _fb(t)
	assert_str((await fb.sign_in_with_password("a@b.co", "x")).code).is_equal("INVALID_PASSWORD")
	assert_str((await fb.sign_up("a@b.co", "x")).code).is_equal("WEAK_PASSWORD")
	assert_str((await fb.sign_up("a@b.co", "x")).code).is_equal("HTTP_500")
	assert_str((await fb.sign_up("a@b.co", "x")).code).is_equal("timeout")

func test_idp_sign_in_encodes_post_body_with_provider_and_nonce() -> void:
	var t := FakeTransport.new([{"status": 200, "json": _session_json()}])
	var r: Dictionary = await _fb(t).sign_in_with_idp("apple.com", "tok en", "n0nce")
	assert_bool(r.ok).is_true()
	assert_bool(str(t.requests[0].url).contains("accounts:signInWithIdp")).is_true()
	assert_str(t.requests[0].body.postBody).is_equal("id_token=tok%20en&providerId=apple.com&nonce=n0nce")
	assert_str(t.requests[0].body.requestUri).is_equal("http://localhost")
	assert_bool(t.requests[0].body.returnSecureToken).is_true()

func test_oob_codes_for_verification_and_reset() -> void:
	var t := FakeTransport.new([{"status": 200, "json": {"email": "a@b.co"}}, {"status": 200, "json": {"email": "a@b.co"}}])
	var fb := _fb(t)
	assert_bool((await fb.send_verification_email("id-1")).ok).is_true()
	assert_str(t.requests[0].body.requestType).is_equal("VERIFY_EMAIL")
	assert_str(t.requests[0].body.idToken).is_equal("id-1")
	assert_bool((await fb.send_password_reset("a@b.co")).ok).is_true()
	assert_str(t.requests[1].body.requestType).is_equal("PASSWORD_RESET")
	assert_str(t.requests[1].body.email).is_equal("a@b.co")

func test_lookup_and_delete() -> void:
	var t := FakeTransport.new([
		{"status": 200, "json": {"users": [{"localId": "uid-1", "email": "a@b.co", "emailVerified": true}]}},
		{"status": 200, "json": {}},
	])
	var fb := _fb(t)
	var info: Dictionary = await fb.lookup("id-1")
	assert_bool(info.ok).is_true()
	assert_str(info.user_id).is_equal("uid-1")
	assert_bool(info.email_verified).is_true()
	assert_bool((await fb.delete_account("id-1")).ok).is_true()
	assert_bool(str(t.requests[1].url).contains("accounts:delete")).is_true()

func test_refresh_uses_securetoken_form_body_and_matches_auth_session_contract() -> void:
	var t := FakeTransport.new([{"status": 200, "json": {"id_token": "id-2", "refresh_token": "rt-2", "expires_in": "3600", "user_id": "uid-1"}}])
	var r: Dictionary = await _fb(t).refresh("rt 1")
	assert_str(t.requests[0].url).is_equal("https://securetoken.googleapis.com/v1/token?key=test-key")
	assert_str(t.requests[0].raw).is_equal("grant_type=refresh_token&refresh_token=rt%201")
	assert_bool(str(t.requests[0].headers).contains("application/x-www-form-urlencoded")).is_true()
	assert_bool(r.ok).is_true()
	assert_str(r.id_token).is_equal("id-2")
	assert_str(r.refresh_token).is_equal("rt-2")
	assert_int(r.expires_in_s).is_equal(3600)
	assert_bool(r.fatal).is_false()

func test_refresh_failures_split_fatal_from_transient() -> void:
	var t := FakeTransport.new([
		{"status": 400, "json": {"error": {"message": "TOKEN_EXPIRED"}}},
		{"status": 400, "json": {"error": {"message": "INVALID_REFRESH_TOKEN"}}},
		{"error": "timeout"},
		{"status": 503, "json": {}},
	])
	var fb := _fb(t)
	var a: Dictionary = await fb.refresh("rt")
	assert_bool(a.ok).is_false()
	assert_bool(a.fatal).is_true()
	assert_str(a.error).is_equal("TOKEN_EXPIRED")
	assert_bool((await fb.refresh("rt")).fatal).is_true()
	var c: Dictionary = await fb.refresh("rt")
	assert_bool(c.fatal).is_false()
	assert_str(c.error).is_equal("timeout")
	assert_bool((await fb.refresh("rt")).fatal).is_false()

func test_refresh_plugs_into_auth_session() -> void:
	var t := FakeTransport.new([{"status": 200, "json": {"id_token": "id-2", "refresh_token": "rt-2", "expires_in": "1800"}}])
	# Callable 只存对象 id，不给 RefCounted 续命：临时的 FirebaseAuth 必须有变量持有，否则刷新器立刻失效。
	var fb := _fb(t)
	var s := AuthSession.new()
	s.refresher = fb.refresh
	s.complete_sign_in("uid-1", "id-1", "rt-1", 3600, "password", "a@b.co")
	assert_bool(await s.refresh()).is_true()
	assert_str(s.access_token()).is_equal("id-2")
	assert_str(s.email).is_equal("a@b.co")
	s.sign_out()

func test_describe_covers_common_codes() -> void:
	assert_str(FirebaseAuth.describe("INVALID_PASSWORD")).is_equal(FirebaseAuth.describe("EMAIL_NOT_FOUND"))
	assert_bool(FirebaseAuth.describe("HTTP_503").contains("connection")).is_true()
	assert_bool(FirebaseAuth.describe("timeout").is_empty()).is_false()
	assert_bool(FirebaseAuth.describe("SOMETHING_ODD").contains("SOMETHING_ODD")).is_true()

func test_config_prefers_user_override_then_res_file() -> void:
	var f := FileAccess.open(FirebaseConfig.USER_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"api_key": "from-user"}))
	f.close()
	assert_str(FirebaseConfig.api_key()).is_equal("from-user")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FirebaseConfig.USER_PATH))
	# 仓库只提交 example，没有 config/firebase.json 时必须是空串而不是报错。
	if not FileAccess.file_exists(FirebaseConfig.RES_PATH):
		assert_str(FirebaseConfig.api_key()).is_empty()
