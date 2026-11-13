extends GdUnitTestSuite
## SGODOT-483 (上架; the user 11-11): the store build (its export preset's custom feature `store`, P0Build.store()) has no
## Test options in Settings and no Voice Profile on the profile (none in any build since the second batch #7); the OSS
## test build keeps Test options. The card room is in both (the user 11-13, 「牌室 C」, D6 undone): its pin past its gate,
## its Show on map opening it.

func after_test() -> void:
	P0Build.store_override = null
	P0ProfilePage.voice_profile_enabled = false   # off in every build; a test that turned it on leaves it off (周瑜 on #1007)

func after() -> void:
	P0Runtime.free_instance_for_tests()   # the map test's runtime, not left to the next suite

func _test_options(store: bool) -> Object:
	P0Build.store_override = store
	var page: P0SettingsPage = auto_free(P0SettingsPage.settings("0.3.8 (2026111100)"))
	return page.body.find_child("TestOptions", true, false)

func test_settings_has_test_options_only_outside_the_store_build() -> void:
	assert_object(_test_options(false)).is_not_null()
	assert_object(_test_options(true)).is_null()

func test_the_card_room_is_on_the_map_in_every_build() -> void:
	var view := {"homestead": {"level": 3}}   # past its gate (Homestead Lv2, the guide over)
	var room := P0Outposts.by_role("casino")
	assert_bool(room.is_empty()).is_false()
	for store in [false, true]:
		P0Build.store_override = store
		assert_bool(P0Outposts.shown(room, view)).override_failure_message("store %s" % store).is_true()
		assert_bool(P0Outposts.shown(room, {"homestead": {"level": 1}})).is_false()   # before its gate, as ever
	for o in P0Outposts.all():   # the other places as ever
		if str(o.get("role", "")) != "casino": assert_bool(P0Outposts.shown(o, view)).override_failure_message(str(o.id)).is_true()

func test_no_resident_lives_in_the_card_room() -> void:
	assert_array(P0Outposts.by_role("casino").get("residents", [])).is_empty()

## The user 11-12 (second batch #7): no Voice Profile in any build, the Android test build too.
func test_no_build_shows_the_voice_profile() -> void:
	for os_name in ["Android", "iOS", "macOS"]:
		for store in [false, true]:
			assert_bool(P0ProfilePage.voice_profile_shown(os_name, store)).override_failure_message("%s %s" % [os_name, store]).is_false()

## Were it on again: Android's, outside the store build only.
func test_the_voice_profile_is_androids_outside_the_store_build_only() -> void:
	P0ProfilePage.voice_profile_enabled = true
	assert_bool(P0ProfilePage.voice_profile_shown("Android", false)).is_true()
	assert_bool(P0ProfilePage.voice_profile_shown("Android", true)).is_false()
	assert_bool(P0ProfilePage.voice_profile_shown("iOS", false)).is_false()
	P0Build.store_override = true
	assert_bool(P0ProfilePage.voice_profile_shown("Android")).is_false()   # its default reads the build

func test_a_development_run_is_not_the_store_build() -> void:
	assert_bool(P0Build.store()).is_false()   # no `store` feature here: the OSS build's rows and places, as before

## A Show on map for the card room opens it in the store build too; one for a place not shown yet (before its gate)
## opens no card — the pin is not there, a dead link (奕星 on 483).
func test_a_show_on_map_for_the_card_room_opens_it_in_every_build() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	var m := (load("res://scenes/p0/p0_map.tscn") as PackedScene).instantiate() as Node
	viewport.add_child(m)
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	m.rt.session.view = {"homestead": {"level": 3}}
	for store in [false, true]:
		P0Build.store_override = store
		assert_dict(m.place_for("outpost:sf_card_room_1")).override_failure_message("store %s" % store).is_not_empty()
	m.rt.session.view = {"homestead": {"level": 1}}   # not past its gate: not shown, so nothing opens
	assert_dict(m.place_for("outpost:sf_card_room_1")).is_empty()
	m.rt.session.view = {"homestead": {"level": 3}}
	assert_dict(m.place_for("outpost:sh_tea_1")).is_not_empty()   # the other places as ever
