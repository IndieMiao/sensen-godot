extends GdUnitTestSuite
## q(281) (SGODOT-390; 不知火舞's spec 302 e92f4ff9 + 18f24a30, row 131 421:190359): Settings › Legal's Privacy Policy
## row (by platform, only once the pages are up) and Support code row (copies; no ›) with the line under the card; no
## Voice Profile on an iPhone; Android's Voice Profile behind voice's 13+ answer.

## The vectors the server's function is checked against too (后裔, privacy-server-2026-11-03 ①): SHA-256 of
## `p0-support/v1/` + id (UTF-8), its first 50 bits in Crockford Base32. Worked out apart from this code (Python hashlib).
const VECTORS := {
	"p0-0123456789abcdef0123456789abcdef": "SYYBF-YAXKP",
	"p0-shot-nezha": "WKRW4-9CH60",
	"test-1": "55YF1-3C0J8",
	"玩家-一": "T2ZBB-SGCZ1",
}

func test_the_support_code_is_the_shared_function_of_the_id() -> void:
	for id in VECTORS: assert_str(P0Legal.support_code(id)).override_failure_message(id).is_equal(VECTORS[id])
	assert_str(P0Legal.support_code("")).is_equal("")
	for c in P0Legal.support_code("p0-shot-nezha").replace("-", ""):
		assert_bool(c in "ILOU").override_failure_message(c).is_false()

func test_the_privacy_policy_opens_by_platform_once_live() -> void:
	assert_str(P0Legal.privacy_url("iOS")).is_equal("https://gensen.app/privacy")   # PRIVACY_LIVE: the pages are up
	assert_str(P0Legal.privacy_url("iOS", false)).is_equal("")   # not live: no row
	assert_str(P0Legal.privacy_url("iOS", true)).is_equal("https://gensen.app/privacy")
	assert_str(P0Legal.privacy_url("Android", true)).is_equal("https://gensen.app/privacy-android")

func _names(page: P0SettingsPage) -> Array:
	var card := page.body.get_child(page.body.get_child_count() - 2)   # Legal's card (the note after it)
	return card.find_children("*", "UiSettingRow", true, false).map(func(r): return str(r.name))

func test_legal_reads_privacy_policy_licenses_version_support_code_and_the_note() -> void:
	var page: P0SettingsPage = auto_free(P0SettingsPage.settings("0.2.24 (2026110501)", 0.0, 0.0, {}, "", P0SettingsPage.BLOCKED_NONE,
		false, "", "https://gensen.app/privacy-android", "WKRW4-9CH60"))
	assert_array(_names(page)).is_equal(["PrivacyPolicy", "Licenses", "Version", "SupportCode"])
	var code := page.find_child("SupportCode", true, false) as UiSettingRow
	assert_object(code.find_child("Chevron", true, false)).is_null()   # it copies, it goes nowhere
	assert_str((code.find_child("Value", true, false) as Label).text).is_equal("WKRW4-9CH60")
	assert_str((code.find_child("Line", true, false) as Label).text).is_equal("Tap to copy")
	assert_object(page.find_child("PrivacyPolicy", true, false).find_child("Chevron", true, false)).is_not_null()
	var note := page.body.get_child(page.body.get_child_count() - 1) as Label
	assert_str(note.text).is_equal("Send this code with any request about your data.")
	var got := []
	page.open_pressed.connect(func(w): got.append(w))
	(code.find_child("Hit", true, false) as Button).pressed.emit()
	(page.find_child("PrivacyPolicy", true, false).find_child("Hit", true, false) as Button).pressed.emit()
	assert_array(got).is_equal(["support_code", "privacy"])
	# none of the two (the pages not up, no id): Legal as it was, no note
	var before: P0SettingsPage = auto_free(P0SettingsPage.settings("dev"))
	assert_array(_names_last(before)).is_equal(["Licenses", "Version"])
	assert_object(before.find_child("SupportNote", true, false)).is_null()

func _names_last(page: P0SettingsPage) -> Array:
	var card := page.body.get_child(page.body.get_child_count() - 1)
	return card.find_children("*", "UiSettingRow", true, false).map(func(r): return str(r.name))

func test_voice_profile_is_androids_and_goes_by_voices_age_answer() -> void:
	assert_bool(P0ProfilePage.voice_profile_shown("Android")).is_false()   # off in every build (second batch #7)
	P0ProfilePage.voice_profile_enabled = true
	assert_bool(P0ProfilePage.voice_profile_shown("iOS")).is_false()
	assert_bool(P0ProfilePage.voice_profile_shown("Android")).is_true()
	P0ProfilePage.voice_profile_enabled = false
	assert_array(["ok", "no", "unknown"].map(func(a): return P0Ui.voice_profile_step(a))).is_equal(["open", "refuse", "ask"])
	var card = auto_free(P0Ui.AgeCard.new(2026, "Voice Profile"))
	assert_bool(card.find_children("*", "Label", true, false).any(func(l): return l.text == "Voice Profile")).is_true()
	var voice_card = auto_free(P0Ui.AgeCard.new(2026))
	assert_bool(voice_card.find_children("*", "Label", true, false).any(func(l): return l.text == "Voice chat")).is_true()
