extends GdUnitTestSuite
## P0AccFlow (SGODOT-491; q(321) sign-in a must; spec v2; 后裔's contract v1.6.3): each first_run() kind's pages in order,
## what the phone keeps, the host's answers (no_farm / conflict / claimed / name_refused) and Back.

const RECORD := "user://test_p0_acc_flow.json"

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RECORD))
	P0SignIn.force = []

func _flow(kind := "new", providers: Array = ["apple", "google", "email"], hints := {}) -> P0AccFlow:
	var f := P0AccFlow.new(kind, Callable(), providers, hints, 2026)
	f.record_path = RECORD
	add_child(auto_free(f))
	f.size = Vector2(360, 800)
	if f.page is P0AccAge: (f.page as P0AccAge).wheel.animate = false
	return f

func _answer(f: P0AccFlow, year: int) -> void:
	var a := f.page as P0AccAge
	a.wheel.pick(year)
	a.consent.checked = true
	a.consent.toggled.emit(true)
	a.go.activated.emit()
	a.confirm.move.activated.emit()

func _title(p: Control) -> String:
	return (p.find_child("Title", true, false) as Label).text

func test_a_new_phone_answers_age_then_signs_in() -> void:
	var f := _flow()
	var said: Array = []
	var ways: Array[String] = []
	f.agreed.connect(func(ok: bool): said.append(ok))
	f.sign_in.connect(func(p: String): ways.append(p))
	assert_object(f.page).is_instanceof(P0AccAge)
	_answer(f, 2001)
	assert_array(said).is_equal([true])
	assert_object(f.page).is_same(f.sign_in_page)
	assert_str(_title(f.page)).is_equal("Sign in to play")
	assert_bool(f.kept().age_ok).is_true()
	(f.page.find_child("Google", true, false) as Button).pressed.emit()
	assert_array(ways).is_equal(["google"])
	assert_bool(f.back()).is_false()   # no ‹ on the sign-in page: Back is the launch's (the home screen)

func test_too_young_stops_at_age_block_and_keeps_only_the_no() -> void:
	var f := _flow()
	_answer(f, 2013)
	assert_object(f.page).is_instanceof(P0AccBlock)
	assert_dict(f.kept()).is_equal({"age_ok": false})
	assert_object(_flow("old_blocked").page).is_instanceof(P0AccBlock)
	assert_object(_flow("blocked").page).is_instanceof(P0AccBlock)

func test_old_farms_go_to_keep_your_farm() -> void:
	var asked := _flow("old_age")
	assert_object(asked.page).is_instanceof(P0AccAge)
	_answer(asked, 1990)
	assert_str(_title(asked.page)).is_equal("Keep your farm")
	var passed := _flow("old_consent")
	var c := passed.page as P0AccConsent
	c.consent.checked = true
	c.consent.toggled.emit(true)
	c.go.activated.emit()
	assert_str(_title(passed.page)).is_equal("Keep your farm")
	assert_str(_title(_flow("old_signin").page)).is_equal("Keep your farm")

func test_signed_out_asks_age_only_if_this_phone_never_kept_a_yes() -> void:
	var f := _flow("signed_out", ["google"], {"line": "last_time", "with": "google"})
	assert_object(f.page).is_instanceof(P0AccAge)
	_answer(f, 1999)
	var again := _flow("signed_out", ["google"], {"line": "last_time", "with": "google"})
	assert_object(again.page).is_same(again.sign_in_page)
	assert_str(_title(again.page)).is_equal("Sign in to play")
	assert_str(again.sign_in_page.hint.text).is_equal("You signed in with Google last time.")

func test_no_farm_names_a_new_player_with_a_way_back_and_an_old_farm_without() -> void:
	var f := _flow()
	_answer(f, 2001)
	var named: Array = []
	var agains: Array[int] = []
	f.named.connect(func(n: String, s: bool): named.append([n, s]))
	f.sign_in_again.connect(func(): agains.append(1))
	f.no_farm()
	assert_object(f.page).is_same(f.name_page)
	assert_bool(f.name_page.another_row.visible).is_true()
	f.name_page.prefill("Mira")
	assert_bool(f.back()).is_true()   # Back on a new player's NAME: Try another account
	assert_object(f.page).is_same(f.sign_in_page)
	assert_array(agains).is_equal([1])
	f.no_farm()
	assert_str(f.name_page.field.text).is_empty()   # a name typed for one account is not another's
	f.name_page.skip.pressed.emit()
	assert_array(named).is_equal([["", true]])
	f.no_farm(false)   # a claimed old farm, a test code: no way back
	assert_bool(f.name_page.another_row.visible).is_false()
	assert_bool(f.back()).is_false()

func test_the_choose_card_on_sign_in_keeps_the_old_farm_lines_on_name_none() -> void:
	var f := _flow("old_signin")
	var switches: Array[int] = []
	var agains: Array[int] = []
	f.switch_farm.connect(func(): switches.append(1))
	f.sign_in_again.connect(func(): agains.append(1))
	(f.page.find_child("Google", true, false) as Button).pressed.emit()
	f.conflict({"name": "Mia", "home_level": 6, "last_played_at": Time.get_unix_time_from_system() * 1000.0 - 3 * 86400000.0})
	assert_str((f.choose.find_child("Title", true, false) as Label).text).is_equal("This Google account already has a farm")
	assert_str((f.choose.find_child("Body", true, false) as Label).text).is_equal("Home Lv6 · Last played 3 days ago")
	assert_object(f.choose.find_child("Keep", true, false)).is_not_null()
	f.choose.move.activated.emit()
	assert_array(switches).is_equal([1])
	assert_object(f.choose).is_null()
	var g := _flow()
	_answer(g, 2001)
	g.sign_in_again.connect(func(): agains.append(1))
	(g.page.find_child("Apple", true, false) as Button).pressed.emit()
	g.no_farm()
	g.conflict({"home_level": 2, "last_played_at": 0.0})   # the guest race, on NAME
	assert_object(g.choose.find_child("Keep", true, false)).is_null()   # no old farm here to keep
	assert_str((g.choose.find_child("Title", true, false) as Label).text).is_equal("This Apple account already has a farm")
	g.choose.cancel.activated.emit()
	assert_object(g.page).is_same(g.sign_in_page)
	assert_array(agains).is_equal([1])

func test_claimed_says_the_farms_way_in_and_a_refused_name_comes_back() -> void:
	var f := _flow("old_signin")
	f.claimed(["apple"])
	assert_str(f.sign_in_page.hint.text).is_equal("This farm uses Apple sign-in." if OS.get_name() != "Android" else "This farm uses Apple sign-in, which isn't on Android yet.")
	f.claimed([])
	assert_str(f.sign_in_page.hint.text).is_empty()   # a test code's farm: no such line in §1.3 (the code page says it)
	f.no_farm(false)
	f.name_refused({"ok": false, "code": "name_rejected", "reason": "blocked"})
	assert_str(f.name_page.field.helper_line.text).is_equal("That name isn't allowed")
	f.name_refused({"ok": false, "code": "pending_expired"})
	assert_object(f.page).is_same(f.sign_in_page)

func test_no_google_services_and_email_off() -> void:
	var f := _flow("no_google", [])
	var codes: Array[int] = []
	f.test_code.connect(func(): codes.append(1))
	assert_object(f.page).is_instanceof(P0AccNoGms)
	(f.page.find_child("TestCode", true, false) as Button).pressed.emit()
	assert_array(codes).is_equal([1])
	assert_bool(f.back()).is_false()

func test_the_entry_asks_google_before_age() -> void:
	var android := [P0SignIn.GOOGLE]
	var iphone := [P0SignIn.APPLE, P0SignIn.GOOGLE]
	# Play services there: the kind as it is, Google's key on
	assert_dict(P0AccFlow.entry("new", false, true, android)).is_equal({"kind": "new", "providers": ["google"]})
	assert_dict(P0AccFlow.entry("old_age", true, true, android)).is_equal({"kind": "old_age", "providers": ["google", "email"]})
	assert_dict(P0AccFlow.entry("new", true, true, iphone)).is_equal({"kind": "new", "providers": ["apple", "google", "email"]})
	# none and email off: NO-GMS up front for every way to sign-in; AGE-BLOCK stays
	for k in ["new", "old_age", "old_consent", "old_signin", "signed_out"]:
		assert_str(P0AccFlow.entry(k, false, false, android).kind).override_failure_message(k).is_equal("no_google")
	for k in ["blocked", "old_blocked"]: assert_str(P0AccFlow.entry(k, false, false, android).kind).is_equal(k)
	# none, email on: the sign-in page with email and the no-Google line in Google's place
	assert_dict(P0AccFlow.entry("new", true, false, android)).is_equal({"kind": "new", "providers": ["no_google", "email"]})

func test_the_entry_reads_p0_sign_in_by_default() -> void:
	P0SignIn.force = ["apple"]   # Google not on: google_ready() false
	assert_str(P0AccFlow.entry("new", false).kind).is_equal("no_google")
	P0SignIn.force = ["google"]
	assert_dict(P0AccFlow.entry("new", false)).is_equal({"kind": "new", "providers": ["google"]})

func test_the_keys_are_grey_while_the_sheet_is_up_till_the_host_answers() -> void:
	var f := _flow("old_signin")
	var got := []
	f.sign_in.connect(func(p): got.append(p))
	var s := f.sign_in_page
	(s.keys.get_node("Google") as Button).pressed.emit()
	assert_bool(s.busy).is_true()
	assert_bool((s.keys.get_node("Apple") as Button).disabled).is_true()
	assert_bool((s.col.find_child("TestCode", false, false) as BaseButton).disabled).is_true()
	(s.keys.get_node("Google") as Button).pressed.emit()   # a second tap: no second sheet
	assert_array(got).is_equal(["google"])
	f.sign_in_settled()   # cancelled, or failed and toasted
	assert_bool(s.busy).is_false()
	assert_bool((s.keys.get_node("Apple") as Button).disabled).is_false()
	(s.keys.get_node("Apple") as Button).pressed.emit()
	f.claimed(["google"])   # an answer gives the keys back too
	assert_bool(s.busy).is_false()
	(s.keys.get_node("Email") as Button).pressed.emit()   # email: its own page, nothing greyed
	assert_bool(s.busy).is_false()
	assert_array(got).is_equal(["google", "apple", "email"])
	f.sign_in_settled()
	(s.keys.get_node("Google") as Button).pressed.emit()
	f.no_farm()
	assert_bool(s.busy).is_false()

func test_the_flow_says_its_own_lines_over_the_page() -> void:
	var f := _flow("old_signin")
	f.safe_top = 24.0
	assert_str(f.said()).is_equal("")
	f.say("Didn't go through · try again", true)   # a failure: the CMD-FAIL banner, under the status bar, over the wordmark
	assert_str(f.said()).is_equal("Didn't go through · try again")
	assert_int(f.banner.kind).is_equal(UiSysBanner.Kind.CMD_FAIL)
	assert_float(f.banner.offset_top).is_equal(24.0 + P0AccFlow.BANNER_TOP)
	assert_bool(f.banner_over_mark()).is_true()   # 24 + 16 + 40 = 80 comes within 8 of the wordmark's 84: it fades (周瑜 on #1052)
	assert_int(f.banner.get_index()).is_equal(f.get_child_count() - 1)   # over the page
	f.no_farm()   # a page on top later: the lines go back over it
	assert_int(f.banner.get_index()).is_equal(f.get_child_count() - 1)
	f.banner.visible = false
	f.say("Sign-in expired. Please sign in again.")   # Info: the toast at the foot
	assert_str(f.said()).is_equal("Sign-in expired. Please sign in again.")
	assert_object(f.get_node("Toasts")).is_not_null()

func test_back_waits_while_names_check_is_in_flight() -> void:
	var f := P0AccFlow.new("new", func(_n: String, _done: Callable): pass, ["google"], {}, 2026)   # a check that never answers
	f.record_path = RECORD
	add_child(auto_free(f))
	f.no_farm()
	var n := f.name_page
	n.field.input.text = "Mira"
	n.field.input.text_changed.emit("Mira")
	n.go.activated.emit()
	assert_bool(n._checking).is_true()
	assert_bool(f.back()).is_true()   # taken, nothing freed
	assert_object(f.name_page).is_equal(n)
	assert_object(f.page).is_equal(n)

func test_on_a_notched_phone_the_wordmark_fades_under_the_banner() -> void:
	var f := _flow("old_signin")
	f.safe_top = 0.0
	f.say("Didn't go through · try again", true)
	assert_bool(f.banner_over_mark()).is_false()   # 16–56 clears the wordmark's 84 by more than 8
	assert_float((f.page as P0AccShell).mark.modulate.a).is_equal(1.0)
	f.safe_top = 47.0
	f.say("Didn't go through · try again", true)
	assert_bool(f.banner_over_mark()).is_true()   # 63–103: into it
	await get_tree().create_timer(P0AccFlow.MARK_FADE_S + 0.1).timeout
	assert_float((f.page as P0AccShell).mark.modulate.a).is_equal_approx(0.0, 0.01)
	f.banner.visible = false
	f._fade_mark()   # the banner goes: the wordmark comes back
	await get_tree().create_timer(P0AccFlow.MARK_FADE_S + 0.1).timeout
	assert_float((f.page as P0AccShell).mark.modulate.a).is_equal_approx(1.0, 0.01)

func test_updated_terms_mid_way_ask_again_over_the_page_and_keep_the_rest() -> void:
	var f := _flow()
	_answer(f, 2000)
	f.no_farm()
	(f.name_page.field.input as LineEdit).text = "Mira"
	f.name_page.field.input.text_changed.emit("Mira")
	var renewed := []
	f.consent_renewed.connect(func(): renewed.append(true))
	f.consent_outdated({"code": "consent_outdated", "terms_version": "2026-11-20", "privacy_version": "2026-11-21"})
	var c := f.renew
	assert_object(c).is_not_null()
	assert_str((c.find_child("Title", true, false) as Label).text).is_equal("We've updated our terms")
	assert_bool((c.get_node("Surface") as CanvasItem).visible).is_false()   # over the page: the scrim, no cream
	assert_object(c.get_node("Scrim")).is_not_null()
	assert_object(f.page).is_equal(f.name_page)   # the page stays under it, the name in it
	assert_str(f.name_page.field.text).is_equal("Mira")
	assert_bool(f.back()).is_true()   # no way out
	assert_object(f.renew).is_equal(c)
	assert_bool(c.go.disabled).is_true()   # not ticked
	f.consent_outdated({"terms_version": "x"})   # a second refusal while it is up: the one card
	assert_int(f.find_children("AccRenew", "", false, false).size()).is_equal(1)
	c.consent.checked = true
	c.consent.toggled.emit(true)
	c.go.activated.emit()
	assert_array(renewed).is_equal([true])
	assert_object(f.renew).is_equal(c)   # it stays till the host's answer (§9 补)
	assert_int(c.go.phase).is_equal(CommandLifecycle.State.PENDING)
	c.go.activated.emit()   # in flight: deaf
	assert_array(renewed).is_equal([true])
	f.consent_settled(false)   # failed: the key back
	assert_int(c.go.phase).is_equal(CommandLifecycle.State.IDLE)
	c.go.activated.emit()
	assert_array(renewed).is_equal([true, true])
	f.consent_settled(true)
	assert_object(f.renew).is_null()
	var k := f.kept()
	assert_str(str(k.terms)).is_equal("2026-11-20")
	assert_str(str(k.privacy)).is_equal("2026-11-21")
	assert_bool(bool(k.age_ok)).is_true()   # the year is not asked again
