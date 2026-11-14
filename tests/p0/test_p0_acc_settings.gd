extends GdUnitTestSuite
## Settings' account parts (SGODOT-491; 不知火舞's spec v2 §5; 720:201692 / 720:201735): the Account info row, Sign out
## for everyone signed in and its confirm card, the Delete account Danger row.

const STORE := "user://test_p0_acc_settings.json"
const P0AccSignOut := preload("res://scenes/p0/account/p0_acc_sign_out.gd")

var ui: P0Ui

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func _page(account: String) -> P0SettingsPage:
	return auto_free(P0SettingsPage.settings("0.3.11 (2026111401)", 0.0, 0.0, {}, "", P0SettingsPage.BLOCKED_NONE, false,
		"English", "", "WKRW4-9CH60", account))

func test_the_account_row_says_how_this_farm_signs_in() -> void:
	for pair in [["apple", "Signed in with Apple"], ["google", "Signed in with Google"], ["email", "Signed in with email"],
			["code", "Signed in with a test code"]]:
		var page := _page(pair[0])
		var first := page.body.get_child(0) as Label
		assert_str(first.text).is_equal("Account")
		var row := page.find_child("SignedInWith", true, false) as UiSettingRow
		assert_str((row.find_child("Title", true, false) as Label).text).is_equal(pair[1])
		assert_object(row.find_child("Chevron", true, false)).is_null()   # no ›, no sub-page
		assert_object(row.find_child("Hit", true, false)).is_null()

func test_no_account_no_account_parts() -> void:
	var page := _page("")
	for id in ["SignedInWith", "SignOut", "DeleteAccount", "End"]: assert_object(page.find_child(id, true, false)).is_null()

func test_sign_out_and_delete_account_close_the_page() -> void:
	var page := _page("email")
	var end := page.body.get_child(page.body.get_child_count() - 1)
	assert_str(end.name).is_equal("End")
	assert_object(page.body.get_child(page.body.get_child_count() - 3)).is_equal(page.find_child("SupportNote", true, false))
	var out := page.find_child("SignOut", true, false) as UiCommandButton
	assert_int(out.kind).is_equal(UiCommandButton.Kind.SECONDARY)
	var del := page.find_child("DeleteAccount", true, false) as UiSettingRow
	assert_str((del.find_child("Line", true, false) as Label).text).is_equal("Deletes your farm, items and progress")
	assert_that((del.find_child("Title", true, false) as Label).get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_DANGER)
	assert_that((del.find_child("Chevron", true, false) as Label).get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_DANGER)
	var got := []
	page.open_pressed.connect(func(w): got.append(w))
	out.activated.emit()
	(del.find_child("Hit", true, false) as Button).pressed.emit()
	assert_array(got).is_equal(["sign_out", "delete_account"])

func test_the_sign_out_card_says_how_to_come_back() -> void:
	for pair in [["apple", "You can sign in again with Apple."], ["google", "You can sign in again with Google."],
			["email", "You can sign in again with email."], ["code", "You can sign in again with your test code."]]:
		var c: Control = auto_free(P0AccSignOut.card(pair[0]))
		assert_str((c.card.find_child("Title", true, false) as Label).text).is_equal("Sign out?")
		assert_str((c.card.find_child("Body", true, false) as Label).text).is_equal(pair[1])
		assert_str(c.move.label).is_equal("Sign out")
		assert_str(c.cancel.label).is_equal("Cancel")

func _ui(account: String) -> P0Ui:
	ui = P0Ui.new()
	ui.quick_store = STORE
	ui.account_of = func() -> String: return account
	add_child(auto_free(ui))
	await await_idle_frame()
	return ui

func test_settings_sign_out_asks_then_tells_the_host() -> void:
	await _ui("google")
	var outs := []
	ui.sign_out_requested.connect(func(): outs.append(true))
	ui.open_settings(Callable(), false)
	var page := ui._modal.find_child("SignOut", true, false) as UiCommandButton
	page.activated.emit()
	assert_str(ui.modal_kind).is_equal("sign_out_confirm")
	var card := ui._modal.find_child("SignOutCard", true, false)
	assert_str((card.card.find_child("Body", true, false) as Label).text).is_equal("You can sign in again with Google.")
	ui.back_modal()   # Back: the card goes, Settings stays
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("settings")
	assert_array(outs).is_empty()
	page.activated.emit()
	(ui._modal.find_child("SignOutCard", true, false) as Control).move.activated.emit()
	assert_array(outs).is_equal([true])

func _delete_page() -> P0SettingsPage:
	var pages := ui._modal.find_children("*", "P0SettingsPage", true, false)
	return pages[0] if not pages.is_empty() else null

func test_delete_account_asks_twice_then_tells_the_host() -> void:
	await _ui("apple")
	ui.view = {"homestead": {"level": 6}, "coins": 230, "bag": {"slots": [{"id": "radish", "qty": 12}, {"id": "seed_radish", "qty": 7}]}}
	var asks := []
	ui.delete_account_requested.connect(func(): asks.append(true))
	ui.open_settings(Callable(), false)
	(ui._modal.find_child("DeleteAccount", true, false).find_child("Hit", true, false) as Button).pressed.emit()
	var one := _delete_page()
	assert_int(one.kind).is_equal(P0SettingsPage.Kind.DELETE)
	assert_str((one.find_child("Title", true, false) as Label).text).is_equal("Delete your account?")
	assert_str((one.find_child("Line", true, false) as Label).text).is_equal("Your farm, items, coins and progress will be deleted. This can't be undone.")
	assert_str((one.find_child("Line2", true, false) as Label).text).is_equal("Gensen will also lose access to your Apple ID.")
	var go := one.find_child("Go", true, false) as UiCommandButton
	assert_int(go.kind).is_equal(UiCommandButton.Kind.DESTRUCTIVE)
	assert_str(go.label).is_equal("Continue")
	go.activated.emit()
	await await_idle_frame()
	var two := _delete_page()
	assert_str((two.find_child("Title", true, false) as Label).text).is_equal("Delete your account for good?")
	assert_str((two.find_child("Line", true, false) as Label).text).is_equal("Your Home Lv6, 230 coins and 19 bag items will be gone.")
	var del := two.find_child("Go", true, false) as UiCommandButton
	assert_str(del.label).is_equal("Delete my account")
	assert_array(asks).is_empty()
	del.activated.emit()
	assert_array(asks).is_equal([true])
	assert_int(del.phase).is_equal(CommandLifecycle.State.PENDING)
	del.activated.emit()   # in flight: deaf
	assert_array(asks).is_equal([true])
	ui.delete_account_failed()   # the key back, Didn't go through
	assert_int(del.phase).is_equal(CommandLifecycle.State.IDLE)

func test_keep_my_account_goes_back_to_settings() -> void:
	await _ui("google")
	ui.open_settings(Callable(), false)
	(ui._modal.find_child("DeleteAccount", true, false).find_child("Hit", true, false) as Button).pressed.emit()
	assert_object(_delete_page().find_child("Line2", true, false)).is_null()   # not Apple: no Apple line
	(_delete_page().find_child("Keep", true, false) as Button).pressed.emit()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("settings")

func test_the_summary_says_only_what_the_farm_has() -> void:
	var lv := {"homestead": {"level": 3}}
	assert_str(P0SettingsPage.delete_summary(lv)).is_equal("Your Home Lv3 will be gone.")
	assert_str(P0SettingsPage.delete_summary(lv.merged({"coins": 1}))).is_equal("Your Home Lv3 and 1 coin will be gone.")
	assert_str(P0SettingsPage.delete_summary(lv.merged({"bag": {"slots": [{"id": "a", "qty": 1}]}}))).is_equal("Your Home Lv3 and 1 bag item will be gone.")
	assert_str(P0SettingsPage.delete_summary(lv.merged({"coins": 40, "bag": {"slots": [{"id": "a", "qty": 2}]}}))) \
		.is_equal("Your Home Lv3, 40 coins and 2 bag items will be gone.")
	assert_str(P0SettingsPage.delete_summary({})).is_equal("Your Home Lv1 will be gone.")

func test_legal_opens_with_terms_of_service_once_the_page_is_up() -> void:
	assert_str(P0Legal.terms_url(true)).is_equal("https://gensen.app/terms")
	assert_str(P0Legal.terms_url(false)).is_equal("")
	assert_str(P0AccFlow.TERMS_URL).is_equal(P0Legal.TERMS_URL)   # AGE's link is the same page
	var page: P0SettingsPage = auto_free(P0SettingsPage.settings("dev", 0.0, 0.0, {}, "", P0SettingsPage.BLOCKED_NONE, false,
		"", "https://gensen.app/privacy-android", "WKRW4-9CH60", "", "https://gensen.app/terms"))
	var legal := page.find_child("TermsOfService", true, false).get_parent()
	var names := legal.get_children().map(func(r): return str(r.name))
	assert_array(names.slice(0, 2)).is_equal(["TermsOfService", "PrivacyPolicy"])
	assert_object(page.find_child("TermsOfService", true, false).find_child("Chevron", true, false)).is_not_null()
	var got := []
	page.open_pressed.connect(func(w): got.append(w))
	(page.find_child("TermsOfService", true, false).find_child("Hit", true, false) as Button).pressed.emit()
	assert_array(got).is_equal(["terms"])
	var none: P0SettingsPage = auto_free(P0SettingsPage.settings("dev"))
	assert_object(none.find_child("TermsOfService", true, false)).is_null()
