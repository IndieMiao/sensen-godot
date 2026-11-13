extends GdUnitTestSuite
## SGODOT-487: the native sign-in's three results (ok / cancelled / failed, 不知火舞 on 491 dffd8179) and that only the
## provider's token leaves this layer — no name, no email (q(312), 李白 ②).

const P0SignIn := preload("res://modules/p0/p0_sign_in.gd")

func after_test() -> void:
	P0SignIn.force = []

## A bridge double: answers `line`, keeping the nonce hash it was sent.
func _bridge(line: String, seen: Array) -> Callable:
	return func(nonce_hash: String) -> String:
		seen.append(nonce_hash)
		return line

func test_apple_asks_for_no_name_and_no_email() -> void:
	var line := AppleSignIn.request_line("abc", true)
	assert_str(line).is_equal("APPLE|" + "abc".sha256_text() + "|none")
	assert_str(AppleSignIn.request_line("abc")).is_equal("APPLE|" + "abc".sha256_text())   # Journey's, unchanged

func test_an_apple_token_comes_back_with_its_raw_nonce_and_nothing_else() -> void:
	var seen := []
	var r: Dictionary = await P0SignIn.apple(_bridge("APPLE_OK|tok.en|Jane|Doe|jane@example.com|c0de", seen))
	assert_str(str(r.result)).is_equal("ok")
	assert_str(str(r.provider)).is_equal("apple")
	assert_str(str(r.id_token)).is_equal("tok.en")
	assert_str(str(r.auth_code)).is_equal("c0de")
	assert_str(str(r.nonce).sha256_text()).is_equal(str(seen[0]))   # the bridge got the hash, the server gets the raw one
	for key in ["given_name", "family_name", "email", "name"]:
		assert_bool(r.has(key)).override_failure_message(key).is_false()

func test_closing_the_sheet_is_cancelled_not_failed() -> void:
	var r: Dictionary = await P0SignIn.apple(_bridge("APPLE_ERR|canceled", []))
	assert_str(str(r.result)).is_equal("cancelled")

func test_everything_else_is_failed_with_its_reason() -> void:
	for line in ["APPLE_ERR|failed", "APPLE_ERR|busy", "APPLE_ERR|not_handled", "APPLE_ERR|no_token", "garbage", "APPLE_OK|"]:
		var r: Dictionary = await P0SignIn.apple(_bridge(line, []))
		assert_str(str(r.result)).override_failure_message(line).is_equal("failed")
		assert_bool(str(r.get("reason", "")).is_empty()).override_failure_message(line).is_false()

func test_providers_by_platform() -> void:
	assert_array(P0SignIn.providers("iOS")).is_equal(["apple", "google"])
	assert_array(P0SignIn.providers("Android")).is_equal(["google"])
	assert_array(P0SignIn.providers("macOS")).is_empty()
	P0SignIn.force = ["apple"]
	assert_array(P0SignIn.providers("Android")).is_equal(["apple"])

func test_ios_google_sends_the_client_id_and_the_nonce_hash_and_keeps_the_raw_nonce() -> void:
	ProjectSettings.set_setting(P0SignIn.IOS_CLIENT_SETTING, "123-abc.apps.googleusercontent.com")
	var seen := []
	var bridge := func(line: String) -> String:
		seen.append(line)
		return "GOOGLE_OK|g.tok"
	var r: Dictionary = await P0SignIn.google(bridge, "iOS")
	ProjectSettings.set_setting(P0SignIn.IOS_CLIENT_SETTING, "")
	assert_str(str(r.result)).is_equal("ok")
	assert_str(str(r.provider)).is_equal("google")
	assert_str(str(r.id_token)).is_equal("g.tok")
	assert_str(str(seen[0])).is_equal("GOOGLE|123-abc.apps.googleusercontent.com|" + str(r.nonce).sha256_text())

func test_ios_google_without_a_client_id_fails_without_opening_a_sheet() -> void:
	ProjectSettings.set_setting(P0SignIn.IOS_CLIENT_SETTING, "")
	var opened := []
	var r: Dictionary = await P0SignIn.google(func(line: String) -> String:
		opened.append(line)
		return "GOOGLE_OK|x", "iOS")
	assert_str(str(r.result)).is_equal("failed")
	assert_str(str(r.reason)).is_equal("GOOGLE_CONFIG")
	assert_array(opened).is_empty()

func test_google_cancel_and_failures_on_both_phones() -> void:
	ProjectSettings.set_setting(P0SignIn.IOS_CLIENT_SETTING, "1-a.apps.googleusercontent.com")
	var ios_cancel: Dictionary = await P0SignIn.google(func(_l: String) -> String: return "GOOGLE_ERR|canceled", "iOS")
	var ios_fail: Dictionary = await P0SignIn.google(func(_l: String) -> String: return "GOOGLE_ERR|no_token", "iOS")
	ProjectSettings.set_setting(P0SignIn.IOS_CLIENT_SETTING, "")
	var android_cancel: Dictionary = await P0SignIn.google(func(_h: String) -> String: return '{"ok":false,"code":"GOOGLE_CANCELED"}', "Android")
	var android_ok: Dictionary = await P0SignIn.google(func(_h: String) -> String: return '{"ok":true,"id_token":"t","email":"a@b.c","given_name":"A"}', "Android")
	assert_str(str(ios_cancel.result)).is_equal("cancelled")
	assert_str(str(ios_fail.result)).is_equal("failed")
	assert_str(str(ios_fail.reason)).is_equal("GOOGLE_NO_TOKEN")
	assert_str(str(android_cancel.result)).is_equal("cancelled")
	assert_str(str(android_ok.result)).is_equal("ok")
	assert_bool(android_ok.has("email") or android_ok.has("given_name")).is_false()   # only the token leaves
