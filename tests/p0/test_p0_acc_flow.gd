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
