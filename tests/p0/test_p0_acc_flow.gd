extends GdUnitTestSuite
## P0AccFlow (SGODOT-491, spec v1.1 §1 / §5, q(312) ⑨ C): the pages in their order for each first_run(), what is kept
## on the phone, Sign in ⇄ No farm found, a refused name back on NAME, and Back.

const RECORD := "user://test_p0_acc_flow.json"

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RECORD))

func _flow(kind := "new", providers: Array = ["apple", "google"]) -> P0AccFlow:
	var f := P0AccFlow.new(kind, Callable(), providers, 2026)
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

func test_a_new_phone_old_enough_goes_on_to_name_and_keeps_the_yes() -> void:
	var f := _flow()
	var said: Array = []
	f.agreed.connect(func(ok: bool): said.append(ok))
	assert_object(f.page).is_instanceof(P0AccAge)
	_answer(f, 2001)
	assert_array(said).is_equal([true])
	assert_object(f.page).is_same(f.name_page)
	assert_bool(f.name_page.sign_in_row.visible).is_true()
	var kept := f.kept()
	assert_bool(bool(kept.age_ok)).is_true()
	assert_bool(kept.has("agreed_at")).is_true()
	assert_bool(kept.has("terms") and kept.has("privacy")).is_true()

func test_too_young_stops_at_age_block_and_keeps_only_the_no() -> void:
	var f := _flow()
	var stops: Array[int] = []
	f.blocked.connect(func(): stops.append(1))
	_answer(f, 2013)
	assert_object(f.page).is_instanceof(P0AccBlock)
	assert_array(stops).is_equal([1])
	assert_dict(f.kept()).is_equal({"age_ok": false})
	assert_bool(f.back()).is_false()   # no way back: the host's (the home screen)

func test_old_players_by_their_voice_answer() -> void:
	assert_object(_flow("old_blocked").page).is_instanceof(P0AccBlock)
	assert_object(_flow("blocked").page).is_instanceof(P0AccBlock)
	var asked := _flow("old_age")
	assert_object(asked.page).is_instanceof(P0AccAge)
	_answer(asked, 1990)
	assert_bool(asked.name_page.sign_in_row.visible).is_false()   # an old account: no Sign in row (spec §5)
	var passed := _flow("old_consent")
	var said: Array = []
	passed.agreed.connect(func(ok: bool): said.append(ok))
	var c := passed.page as P0AccConsent
	assert_str(c.go.label).is_equal("Agree to continue")
	c.consent.checked = true
	c.consent.toggled.emit(true)
	c.go.activated.emit()
	assert_array(said).is_equal([true])
	assert_object(passed.page).is_same(passed.name_page)

func test_sign_in_and_no_farm_and_back() -> void:
	var f := _flow()
	_answer(f, 2001)
	var provider: Array[String] = []
	f.sign_in.connect(func(p: String): provider.append(p))
	f.name_page.prefill("Mira")
	(f.name_page.find_child("SignIn", true, false) as Button).pressed.emit()
	assert_object(f.page).is_instanceof(P0AccSignIn)
	assert_object(f.page.find_child("Apple", true, false)).is_not_null()
	assert_bool(f.back()).is_true()   # Back: NAME, the name as it was typed
	assert_object(f.page).is_same(f.name_page)
	assert_str(f.name_page.field.text).is_equal("Mira")
	(f.name_page.find_child("SignIn", true, false) as Button).pressed.emit()
	(f.page.find_child("Google", true, false) as Button).pressed.emit()
	assert_array(provider).is_equal(["google"])
	f.no_farm()
	assert_object(f.page).is_instanceof(P0AccNoFarm)
	var labels := f.page.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	assert_array(labels).contains(["This Google account has no farm yet."])
	assert_bool(f.back()).is_true()   # Back: the sign-in card
	assert_object(f.page).is_instanceof(P0AccSignIn)
	f.no_farm()
	(f.page as P0AccNoFarm).start_new.emit()
	assert_object(f.page).is_same(f.name_page)

func test_a_refused_name_comes_back_on_name_and_an_expired_sign_in_on_the_card() -> void:
	var f := _flow()
	_answer(f, 2001)
	f.name_refused({"ok": false, "code": "name_rejected", "reason": "blocked"})
	assert_object(f.page).is_same(f.name_page)
	assert_str(f.name_page.field.helper_line.text).is_equal("That name isn't allowed")
	f.name_refused({"ok": false, "code": "pending_expired"})
	assert_object(f.page).is_instanceof(P0AccSignIn)

func test_android_without_play_services_has_no_key() -> void:
	var f := _flow("new", [])
	_answer(f, 2001)
	(f.name_page.find_child("SignIn", true, false) as Button).pressed.emit()
	assert_object(f.page.find_child("Google", true, false)).is_null()
	assert_object(f.page.find_child("None", true, false)).is_not_null()

func test_back_closes_born_in_first() -> void:
	var f := _flow()
	var a := f.page as P0AccAge
	a.wheel.pick(2001)
	a.consent.checked = true
	a.consent.toggled.emit(true)
	a.go.activated.emit()
	assert_bool(f.back()).is_true()
	assert_object(a.confirm).is_null()
	assert_bool(f.back()).is_false()
