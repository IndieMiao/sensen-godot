extends GdUnitTestSuite
## Sign in with Google（Android 原生插件回包，2026-09-29）。

func test_parses_success_and_errors() -> void:
	var ok := GoogleSignIn.parse_result('{"ok":true,"id_token":"a.b.c","given_name":"Ada","family_name":"L","email":"ada@gmail.com"}')
	assert_bool(ok.ok).is_true()
	assert_str(ok.id_token).is_equal("a.b.c")
	assert_str(ok.given_name).is_equal("Ada")
	assert_str(GoogleSignIn.parse_result('{"ok":false,"code":"GOOGLE_CANCELED"}').code).is_equal("GOOGLE_CANCELED")
	assert_str(GoogleSignIn.parse_result('{"ok":true}').code).is_equal("GOOGLE_UNKNOWN")
	assert_str(GoogleSignIn.parse_result("nope").code).is_equal("GOOGLE_UNKNOWN")

func test_native_side_only_sees_the_nonce_hash() -> void:
	var nonce := AppleSignIn.new_nonce()
	var seen := []
	var r := await GoogleSignIn.authorize(nonce, func(hash: String) -> String:
		seen.append(hash)
		return '{"ok":true,"id_token":"t"}')
	assert_bool(r.ok).is_true()
	assert_array(seen).is_equal([nonce.sha256_text()])

func test_web_client_id_defaults_to_the_registered_client() -> void:
	assert_str(GoogleSignIn.web_client_id()).ends_with(".apps.googleusercontent.com")

func test_errors_have_player_facing_text() -> void:
	assert_str(AccountSession.describe("GOOGLE_CANCELED")).is_empty()
	assert_str(AccountSession.describe("GOOGLE_NO_ACCOUNT")).contains("Google account")
	assert_str(AccountSession.describe("GOOGLE_TOKEN_BAD_AUDIENCE")).is_equal("Sign in with Google failed. Please try again.")

func test_sign_in_retries_once_when_the_request_never_reached_the_server() -> void:
	var t := FakeTransport.new([{"error": "timeout"}, {"status": 201, "json": {"token": "g", "user_id": "u"}}])
	var client := ApiClient.new("https://example.test/v1", t.callable())
	var r := await AccountSession.google_sign_in(client, "id", "n".repeat(32))
	assert_bool(r.ok).is_true()
	assert_int(t.requests.size()).is_equal(2)
	# Server answers are not retried.
	var t2 := FakeTransport.new([{"status": 401, "json": {"code": "GOOGLE_TOKEN_EXPIRED"}}, {"status": 201, "json": {}}])
	var r2 := await AccountSession.google_sign_in(ApiClient.new("https://example.test/v1", t2.callable()), "id", "n".repeat(32))
	assert_str(r2.code).is_equal("GOOGLE_TOKEN_EXPIRED")
	assert_int(t2.requests.size()).is_equal(1)
