extends GdUnitTestSuite
## The account's system states (SGODOT-491; 不知火舞's account spec v1.1 §6 + v2 §6; 后裔's contract v1.6.3 §5):
## ui.show_account_state(kind, detail) for session_replaced / account_deleted / suspended — SYS-SESSION 645:197668,
## SYS-DELETED 720:201839, ACC-SUSPENDED 645:197762 / -PERM 645:197805 — on the cream, their key back as
## account_action(kind, action), ranked by spec §6.5.

const STORE := "user://test_p0_acc_states.json"
const K := P0SysScreen.Kind
const PLAYER := "p0-shot-nezha"   # support code WKRW4-9CH60 (test_p0_privacy_ui's vectors)

var ui: P0Ui
var got: Array = []

func before_test() -> void:
	got = []
	ExternalLink.asked.clear()
	ui = P0Ui.new()
	ui.quick_store = STORE
	ui.player_of = func() -> String: return PLAYER
	ui.account_action.connect(func(k, a): got.append([k, a]))
	add_child(auto_free(ui))
	await await_idle_frame()

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	ExternalLink.asked.clear()

func _card() -> UiSystemCard: return ui.screen().card

func _lines() -> Array:
	var c := _card()
	return [c.title.text, c.body.text, c.note.text if c.note.visible else "", c.primary.label,
		c.secondary.label if c.secondary.visible else ""]

func test_signed_in_elsewhere_reads_the_designs_lines_and_signs_in() -> void:
	ui.show_account_state("session_replaced")
	assert_int(ui.screen_kind()).is_equal(K.SESSION)
	assert_array(_lines()).is_equal(["Signed in on another device", "You've been signed out here.", "", "Sign in", ""])
	assert_object(_card().icon_rect.texture).is_same(P0SysScreen.FACE)
	_card().primary.activated.emit()
	assert_array(got).is_equal([["session_replaced", "sign_in"]])

func test_deleted_says_sign_in_to_start_a_new_farm() -> void:
	ui.show_account_state("account_deleted")
	assert_int(ui.screen_kind()).is_equal(K.DELETED)
	assert_array(_lines()).is_equal(["This account was deleted", "Sign in to start a new farm.", "", "Sign in", ""])
	_card().primary.activated.emit()
	assert_array(got).is_equal([["account_deleted", "sign_in"]])

func test_suspended_with_an_end_names_the_day_and_the_support_code() -> void:
	ui.show_account_state("suspended", {"until": "2026-11-20T10:00:00.000Z"})
	assert_int(ui.screen_kind()).is_equal(K.SUSPENDED)
	var day := P0Ui.suspended_until_text("2026-11-20T10:00:00.000Z")
	assert_array(_lines()).is_equal(["Account suspended", "You can play again on %s." % day, "Support code WKRW4-9CH60", "Contact us", ""])

func test_suspended_for_good_has_no_date() -> void:
	ui.show_account_state("suspended", {"until": null})
	assert_array(_lines()).is_equal(["Account suspended", "This account can't be used anymore.", "Support code WKRW4-9CH60", "Contact us", ""])

func test_contact_us_mails_support_with_the_code_and_tells_the_host() -> void:
	ui.show_account_state("suspended", {"until": null})
	_card().primary.activated.emit()
	assert_array(got).is_equal([["suspended", "contact"]])
	assert_int(ExternalLink.asked.size()).is_equal(1)
	var mail := ExternalLink.asked[0].uri_decode()
	assert_str(mail).starts_with("mailto:shaojie@gensen.app?subject=Gensen support · WKRW4-9CH60&body=Support code: WKRW4-9CH60\nVersion: ")
	assert_str(mail).contains("\nPhone: ")
	assert_int(ui.screen_kind()).is_equal(K.SUSPENDED)   # it stays: no way out

func test_the_support_code_line_copies_the_code() -> void:
	ui.show_account_state("suspended", {"until": null})
	DisplayServer.clipboard_set("")
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = false
	_card().note.gui_input.emit(tap)
	assert_str(ui.toast_text()).is_equal("Support code copied")
	if DisplayServer.get_name() != "headless": assert_str(DisplayServer.clipboard_get()).is_equal("WKRW4-9CH60")

func test_the_end_is_the_players_own_day() -> void:
	assert_str(P0Ui.suspended_until_text("2026-11-20T18:00:00.000Z", 0)).is_equal("Nov 20")
	assert_str(P0Ui.suspended_until_text("2026-11-20T18:00:00.000Z", 8 * 60)).is_equal("Nov 21")   # UTC+8: already the 21st
	assert_str(P0Ui.suspended_until_text("2026-11-20T18:00:00Z", -5 * 60)).is_equal("Nov 20")
	for none in [null, "", "  ", "soon", 5]: assert_str(P0Ui.suspended_until_text(none, 0)).is_equal("")

func test_the_states_rank_as_the_spec_and_ignore_other_kinds() -> void:
	ui.show_account_state("claimed")   # no page any more (v1.4: the sign-in page's line)
	ui.show_account_state("unauthenticated")   # back to the sign-in page, not here
	assert_int(ui.screen_kind()).is_equal(-1)
	ui.show_account_state("session_replaced")
	ui.show_account_state("suspended", {"until": null})
	assert_int(ui.screen_kind()).is_equal(K.SUSPENDED)   # suspended outranks signed in elsewhere
	ui.show_account_state("session_replaced")
	assert_int(ui.screen_kind()).is_equal(K.SUSPENDED)
	ui.show_account_state("account_deleted")
	assert_int(ui.screen_kind()).is_equal(K.DELETED)
	ui.show_screen(K.FAIL)   # Can't connect never covers it
	assert_int(ui.screen_kind()).is_equal(K.DELETED)
	ui.show_screen(K.MAINT)   # maintenance and update do
	assert_int(ui.screen_kind()).is_equal(K.MAINT)

func test_back_does_nothing_and_the_ground_is_the_cream() -> void:
	ui.show_account_state("account_deleted")
	assert_bool(ui.close_top_layer()).is_true()
	assert_int(ui.screen_kind()).is_equal(K.DELETED)
	assert_array(got).is_empty()
	assert_bool(ui.screen().get_child(0) is ColorRect).is_true()
	assert_that((ui.screen().get_child(0) as ColorRect).color).is_equal(P0AccShell.GROUND)

func test_the_account_states_keys_do_not_reach_screen_action() -> void:
	var plain := []
	ui.screen_action.connect(func(k): plain.append(k))
	ui.show_account_state("session_replaced")
	_card().primary.activated.emit()
	assert_array(plain).is_empty()
	ui.hide_screen()
	ui.show_screen(K.MAINT)
	_card().primary.activated.emit()
	assert_array(plain).is_equal([K.MAINT])

func test_the_no_gms_mail_has_no_code() -> void:
	var url := P0Legal.support_mail_url("", "0.3.11 (2026111401)", "Android 14").uri_decode()
	assert_str(url).is_equal("mailto:shaojie@gensen.app?subject=Gensen support&body=Version: 0.3.11 (2026111401)\nPhone: Android 14\n\n")
