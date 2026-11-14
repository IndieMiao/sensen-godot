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

func test_settings_delete_account_tells_the_host() -> void:
	await _ui("code")
	var asks := []
	ui.delete_account_requested.connect(func(): asks.append(true))
	ui.open_settings(Callable(), false)
	(ui._modal.find_child("DeleteAccount", true, false).find_child("Hit", true, false) as Button).pressed.emit()
	assert_array(asks).is_equal([true])
