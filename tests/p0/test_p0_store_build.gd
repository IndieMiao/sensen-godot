extends GdUnitTestSuite
## SGODOT-483 (上架; the user 11-11): the store build (its export preset's custom feature `store`, P0Build.store()) has no
## Test options in Settings, no card room on the map (nor so its blackjack), and no Voice Profile on the profile; the OSS
## test build keeps all three. The card room's pin is its only way in (no resident lives there, no request, postcard,
## Today row or guide step names it, and generated cities have none), so nothing else is left pointing at it.

func after_test() -> void:
	P0Build.store_override = null

func after() -> void:
	P0Runtime.free_instance_for_tests()   # the map test's runtime, not left to the next suite

func _test_options(store: bool) -> Object:
	P0Build.store_override = store
	var page: P0SettingsPage = auto_free(P0SettingsPage.settings("0.3.8 (2026111100)"))
	return page.body.find_child("TestOptions", true, false)

func test_settings_has_test_options_only_outside_the_store_build() -> void:
	assert_object(_test_options(false)).is_not_null()
	assert_object(_test_options(true)).is_null()

func test_the_card_room_is_on_the_map_only_outside_the_store_build() -> void:
	var view := {"homestead": {"level": 3}}   # past its gate (Homestead Lv2, the guide over)
	var room := P0Outposts.by_role("casino")
	assert_bool(room.is_empty()).is_false()
	P0Build.store_override = false
	assert_bool(P0Outposts.shown(room, view)).is_true()
	P0Build.store_override = true
	assert_bool(P0Outposts.shown(room, view)).is_false()
	for o in P0Outposts.all():   # the other places as ever
		if str(o.get("role", "")) != "casino": assert_bool(P0Outposts.shown(o, view)).override_failure_message(str(o.id)).is_true()

func test_no_resident_lives_in_the_card_room() -> void:
	assert_array(P0Outposts.by_role("casino").get("residents", [])).is_empty()

func test_the_voice_profile_is_androids_outside_the_store_build_only() -> void:
	assert_bool(P0ProfilePage.voice_profile_shown("Android", false)).is_true()
	assert_bool(P0ProfilePage.voice_profile_shown("Android", true)).is_false()
	assert_bool(P0ProfilePage.voice_profile_shown("iOS", false)).is_false()
	P0Build.store_override = true
	assert_bool(P0ProfilePage.voice_profile_shown("Android")).is_false()   # its default reads the build

func test_a_development_run_is_not_the_store_build() -> void:
	assert_bool(P0Build.store()).is_false()   # no `store` feature here: the OSS build's rows and places, as before

## Nothing lands on the card room the store build does not show: a Show on map for it opens no card (the pin is not
## there), though none points at it today — a later one would be a dead link (奕星 on 483).
func test_a_show_on_map_for_the_card_room_opens_nothing_in_the_store_build() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	var m := (load("res://scenes/p0/p0_map.tscn") as PackedScene).instantiate() as Node
	viewport.add_child(m)
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	m.rt.session.view = {"homestead": {"level": 3}}
	P0Build.store_override = false
	assert_dict(m.place_for("outpost:sf_card_room_1")).is_not_empty()
	P0Build.store_override = true
	assert_dict(m.place_for("outpost:sf_card_room_1")).is_empty()
	assert_dict(m.place_for("outpost:sh_tea_1")).is_not_empty()   # the other places as ever
