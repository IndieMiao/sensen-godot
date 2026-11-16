extends GdUnitTestSuite
const Page := preload("res://scenes/p0/account/p0_acc_test_code.gd")
const RECORD := "user://test_acc_test_code.json"

func before_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RECORD))

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RECORD))

func _page():
	var p = auto_free(Page.new())
	add_child(p)
	p.size = Vector2(360, 800)
	return p

func _type(p, text: String, caret := -1) -> void:
	p.field.input.text = text
	p.field.input.caret_column = text.length() if caret < 0 else caret
	p.field.input.text_changed.emit(text)

func _flow(kind := "old_signin", record := {}) -> P0AccFlow:
	if not record.is_empty():
		var f := FileAccess.open(RECORD, FileAccess.WRITE)
		f.store_string(JSON.stringify(record));f.close()
	var flow := P0AccFlow.new(kind, Callable(), ["google"], {}, 2026)
	flow.record_path = RECORD
	add_child(auto_free(flow))
	flow.size = Vector2(360,800)
	return flow

func _agreed() -> Dictionary:
	return P0AccFlow.versions().merged({"age_ok":true,"agreed_at":1})

func _enter(flow) -> void:
	flow.page.find_child("TestCode", true, false).pressed.emit()

func test_crockford_aliases_case_spaces_and_dashes_are_displayed_in_groups() -> void:
	var p = _page()
	_type(p, " ilOa bcdE-fgHJ ")
	assert_str(p.entered()).is_equal("110ABCDEFGHJ")
	assert_str(p.field.text).is_equal("110A-BCDE-FGHJ")
	assert_bool(p.go.disabled).is_false()
	assert_str(p.go.label).is_equal("Continue")

func test_partial_and_invalid_u_stay_grey_and_overlong_paste_is_not_truncated_to_a_new_code() -> void:
	var p = _page()
	_type(p, "ABCD")
	assert_bool(p.go.disabled).is_true()
	_type(p, "ABCD-EFGH-JKMU")
	assert_bool(p.go.disabled).is_true()
	_type(p, "ABCD-EFGH-JKMN")
	var before := str(p.field.text)
	_type(p, "0123456789ABCDE")
	assert_str(p.field.text).is_equal(before)
	assert_str(p.entered()).is_equal("ABCDEFGHJKMN")

func test_middle_insert_delete_and_backspacing_a_separator_do_not_trap_caret() -> void:
	var p = _page()
	_type(p,"ABCDE")
	assert_str(p.field.text).is_equal("ABCD-E")
	_type(p,"ABCDE",4)   # backspace on the inserted separator
	assert_str(p.field.text).is_equal("ABCE")
	assert_int(p.field.input.caret_column).is_equal(3)
	_type(p,"AB1CE",3)
	assert_str(p.field.text).is_equal("AB1C-E")
	assert_int(p.field.input.caret_column).is_equal(3)

func test_submit_and_return_send_once_and_busy_locks_input_and_back() -> void:
	var p = _page()
	var sent: Array = []
	var backs: Array = []
	p.submitted.connect(func(code): sent.append(code))
	p.back_pressed.connect(func(): backs.append(true))
	_type(p,"ABCD-EFGH-JKMN")
	p.field.submitted.emit(p.field.text)
	p.go.activated.emit()
	p.back_key.pressed.emit()
	assert_array(sent).is_equal(["ABCDEFGHJKMN"])
	assert_array(backs).is_empty()
	assert_bool(p.busy).is_true()
	assert_bool(p.go.disabled).is_true()
	assert_bool(p.field.input.editable).is_false()

func test_bad_code_needs_effective_edit_alias_or_format_does_not_unlock() -> void:
	var p = _page()
	_type(p,"11OA-BCDE-FGHJ")
	p.refuse({"code":"bad_code"})
	assert_bool(p.go.disabled).is_true()
	assert_str(p.field.error).is_equal(Page.BAD)
	_type(p,"iloa bcde fghj")
	assert_bool(p.go.disabled).is_true()
	assert_str(p.field.error).is_equal(Page.BAD)
	_type(p,"110A-BCDE-FGHK")
	assert_bool(p.go.disabled).is_false()
	assert_str(p.field.error).is_empty()

func test_rate_network_and_service_failures_keep_code_and_allow_manual_retry_without_countdown() -> void:
	var p = _page()
	_type(p,"ABCD-EFGH-JKMN")
	for pair in [["rate_limited",Page.RATE],["network",Page.OFFLINE],["schema",Page.FAILED],["not_found",Page.FAILED],["provider_unavailable",Page.FAILED],["token_too_short",Page.FAILED]]:
		p.set_busy(true)
		p.refuse({"code":pair[0]})
		assert_bool(p.busy).is_false()
		assert_bool(p.go.disabled).is_false()
		assert_bool(p.back_key.disabled).is_false()
		assert_str(p.field.text).is_equal("ABCD-EFGH-JKMN")
		assert_str(p.field.error).is_equal(pair[1])

func test_signin_entry_opens_code_and_returns_to_same_signin_with_no_server_action() -> void:
	var flow = _flow("old_signin",_agreed())
	var signin = flow.page
	var sent: Array = []
	flow.code_entered.connect(func(code): sent.append(code))
	_enter(flow)
	assert_object(flow.page).is_instanceof(Page)
	assert_array(sent).is_empty()
	assert_bool(flow.back()).is_true()
	assert_object(flow.page).is_same(signin)
	_enter(flow)
	flow.code_page.back_key.pressed.emit()
	assert_object(flow.page).is_same(signin)

func test_no_gms_without_age_takes_real_age_confirmation_then_code_and_back_to_no_gms() -> void:
	var flow = _flow("no_google")
	_enter(flow)
	assert_object(flow.page).is_instanceof(P0AccAge)
	assert_dict(flow.kept()).is_empty()
	var age = flow.page
	age.wheel.animate = false
	age.wheel.pick(2000)
	age.consent.checked = true
	age.consent.toggled.emit(true)
	age.go.activated.emit()
	assert_object(age.confirm).is_not_null()
	age.confirm.move.activated.emit()
	assert_object(flow.page).is_instanceof(Page)
	assert_bool(flow.kept().age_ok).is_true()
	flow.back()
	assert_object(flow.page).is_instanceof(P0AccNoGms)
	_enter(flow)
	assert_object(flow.page).is_instanceof(Page)  # no second AGE

func test_no_gms_known_age_missing_consent_only_asks_consent_and_preserves_age_provenance() -> void:
	var flow = _flow("no_google")
	flow.code_context = {"age":true,"versions":P0AccFlow.versions()}
	var age_answers: Array = []
	var consents: Array = []
	flow.agreed.connect(func(ok): age_answers.append(ok))
	flow.code_consent_agreed.connect(func(): consents.append(true))
	_enter(flow)
	assert_object(flow.page).is_instanceof(P0AccConsent)
	var consent = flow.page
	consent.consent.checked = true
	consent.go.activated.emit()
	assert_array(age_answers).is_empty()
	assert_array(consents).is_equal([true])
	assert_bool(flow.kept().has("age_ok")).is_false()
	assert_object(flow.page).is_instanceof(Page)
	flow.back()
	_enter(flow)
	assert_object(flow.page).is_instanceof(Page)

func test_no_gms_current_versions_are_required_not_just_age_ok() -> void:
	var flow = _flow("no_google",{"age_ok":true,"terms":"old","privacy":"old"})
	flow.code_context = {"versions":{"terms":"new","privacy":"new"}}
	_enter(flow)
	assert_object(flow.page).is_instanceof(P0AccConsent)
	flow.page.consent.checked = true
	flow.page.go.activated.emit()
	assert_str(flow.kept().terms).is_equal("new")
	assert_object(flow.page).is_instanceof(Page)

func test_blocked_age_never_offers_another_answer_or_code() -> void:
	var flow = _flow("no_google",{"age_ok":false})
	_enter(flow)
	assert_object(flow.page).is_instanceof(P0AccBlock)
	assert_bool(flow.back()).is_true()
	assert_dict(flow.kept()).is_equal({"age_ok":false})

func test_wrong_typed_age_value_is_unknown_and_does_not_bypass_age() -> void:
	var flow = _flow("no_google",P0AccFlow.versions().merged({"age_ok":"yes"}))
	_enter(flow)
	assert_object(flow.page).is_instanceof(P0AccAge)

func test_flow_code_refused_releases_busy_and_keeps_page_and_then_back() -> void:
	var flow = _flow("old_signin",_agreed())
	_enter(flow)
	var p = flow.code_page
	_type(p,"ABCD-EFGH-JKMN")
	p.go.activated.emit()
	assert_bool(flow.back()).is_true()
	assert_object(flow.page).is_same(p)
	flow.code_refused({"code":"network"})
	assert_object(flow.page).is_same(p)
	assert_bool(p.go.disabled).is_false()
	flow.back()
	assert_object(flow.page).is_same(flow.sign_in_page)
