extends GdUnitTestSuite
## Sign in with Apple 原生桥协议（SGODOT-135）。

func test_parses_success_with_optional_name_and_email() -> void:
	var r := AppleSignIn.parse_reply("APPLE_OK|eyJ.a.b|Avery|Lee|x@privaterelay.appleid.com\n")
	assert_bool(r.ok).is_true()
	assert_str(r.identity_token).is_equal("eyJ.a.b")
	assert_str(r.given_name).is_equal("Avery")
	assert_str(r.family_name).is_equal("Lee")
	assert_str(r.email).is_equal("x@privaterelay.appleid.com")
	var later := AppleSignIn.parse_reply("APPLE_OK|eyJ.a.b|||")
	assert_bool(later.ok).is_true()
	assert_str(later.given_name).is_empty()

func test_parses_errors_and_garbage() -> void:
	assert_str(AppleSignIn.parse_reply("APPLE_ERR|canceled").code).is_equal("APPLE_CANCELED")
	assert_str(AppleSignIn.parse_reply("APPLE_ERR|not_handled").code).is_equal("APPLE_NOT_HANDLED")
	assert_str(AppleSignIn.parse_reply("APPLE_OK|").code).is_equal("APPLE_UNKNOWN")
	assert_str(AppleSignIn.parse_reply("hello").code).is_equal("APPLE_UNKNOWN")

func test_native_side_only_sees_the_nonce_hash() -> void:
	var nonce := AppleSignIn.new_nonce()
	assert_int(nonce.length()).is_equal(64)
	assert_str(AppleSignIn.new_nonce()).is_not_equal(nonce)
	var seen := []
	var r := await AppleSignIn.authorize(nonce, func(hash: String) -> String:
		seen.append(hash)
		return "APPLE_OK|tok|||")
	assert_bool(r.ok).is_true()
	assert_array(seen).is_equal([nonce.sha256_text()])

func test_errors_have_player_facing_text() -> void:
	assert_str(AccountSession.describe("APPLE_CANCELED")).is_empty()
	assert_str(AccountSession.describe("APPLE_TOKEN_BAD_NONCE")).is_equal("Sign in with Apple failed. Please try again.")
	assert_str(AccountSession.describe("EMAIL_IN_USE")).contains("Sign in with your email")
