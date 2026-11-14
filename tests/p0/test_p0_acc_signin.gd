extends GdUnitTestSuite
## ACC-SIGNIN v2 (spec v2 §1; row 164 / row 163) and ACC-NO-GMS (§4): the head by new or old, the keys 50 high in order
## with email's `@`, Google's place on a phone without its services, the test code by build, §1.3's hint lines.

func _page(providers: Array, returning := false, hint := {}, store := true) -> P0AccSignIn:
	var s := P0AccSignIn.new(providers, returning, hint, store)
	add_child(auto_free(s))
	s.size = Vector2(360, 800)
	return s

func test_the_head_and_the_keys_in_order() -> void:
	var s := _page(["apple", "google", "email"])
	await await_idle_frame()
	assert_float(s.card.position.y).is_equal(190.0)
	assert_object(s.find_child("Back", true, false)).is_null()   # no ‹
	var keys := s.keys.get_children().map(func(k): return str(k.name))
	assert_array(keys).is_equal(["Apple", "Google", "Email"])
	for k in s.keys.get_children(): assert_float((k as Control).size.y).is_equal(50.0)
	var email := s.keys.get_child(2)
	assert_array(email.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)).contains(["@", "Continue with email"])
	var old := _page(["google", "email"], true)
	assert_array([(old.find_child("Title", true, false) as Label).text, (old.find_child("Body", true, false) as Label).text]) \
		.is_equal(["Keep your farm", "Sign in to save this farm to your account."])

func test_no_google_services_take_googles_place() -> void:
	var s := _page(["no_google", "email"])
	assert_array(s.keys.get_children().map(func(k): return str(k.name))).is_equal(["NoGoogle", "Email"])
	assert_str((s.keys.get_child(0) as Label).text).is_equal("Google sign-in isn't available on this phone.")

func test_the_test_code_key_by_build() -> void:
	assert_object(_page(["google"], false, {}, true).find_child("TestCode", true, false)).is_instanceof(UiDismissButton)
	assert_object(_page(["google"], false, {}, false).find_child("TestCode", true, false)).is_instanceof(UiCommandButton)

func test_the_hint_lines() -> void:
	var s := _page(["google"])
	assert_bool(s.hint.visible).is_false()
	s.set_hint("farm_uses", "google")
	assert_str(s.hint.text).is_equal("This farm uses Google sign-in.")
	s.set_hint("farm_uses", "apple", "Android")
	assert_str(s.hint.text).is_equal("This farm uses Apple sign-in, which isn't on Android yet.")
	s.set_hint("last_time", "code")
	assert_str(s.hint.text).is_equal("You signed in with a test code last time.")
	s.set_hint("", "")
	assert_bool(s.hint.visible).is_false()

func test_no_gms_mails_us_with_the_build_and_the_phone() -> void:
	var url := P0AccNoGms.mail_url("0.3.11 (2026111401)", "Android 14")
	assert_str(url).starts_with("mailto:shaojie@gensen.app?subject=")
	assert_str(url.uri_decode()).contains("Version: 0.3.11 (2026111401)\nPhone: Android 14")
	assert_str(url.uri_decode()).not_contains("Support code")

func test_the_choose_cards_last_played() -> void:
	var now := 10.0 * 86400000.0
	for c in [[now - 30 * 60000.0, "30m ago"], [now - 5 * 3600000.0, "5h ago"], [now - 30 * 3600000.0, "1 day ago"], [now - 3 * 86400000.0, "3 days ago"]]:
		assert_str(P0AccChoose.farm_line({"home_level": 6, "last_played_at": c[0]}, now)).is_equal("Home Lv6 · Last played %s" % c[1])
