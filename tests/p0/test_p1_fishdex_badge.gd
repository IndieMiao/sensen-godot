extends GdUnitTestSuite
## The Fish-dex badge (283: 安其拉's mark badge_fishdex, 不知火舞's frames DEX-COMPLETE / FISH-6-COMPLETE / PROFILE-1-DEX):
## the whole dex shows it on the profile's Fish tile, the ring's top-right, and the MomentBanner can carry art in its
## disc's place.

func _view(kinds: int) -> Dictionary:
	var dex := []
	for i in 20: dex.append({"id": "fish_k%d" % i, "caught": 1 if i < kinds else 0})
	return {"profile": {"name": "Lin"}, "skills": {}, "fishing": {"dex": dex}}

func _page(v: Dictionary) -> P0ProfilePage:
	var page := P0ProfilePage.new(v)
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	host.add_child(page)
	return page

func test_the_fish_tile_wears_the_badge_once_all_are_caught() -> void:
	assert_bool(bool(P0ProfilePage.profile_data(_view(19)).collections[0].badge)).is_false()
	assert_bool(bool(P0ProfilePage.profile_data(_view(20)).collections[0].badge)).is_true()
	assert_bool(P0ProfilePage.profile_data(_view(20)).collections.slice(1).any(func(c): return bool(c.get("badge", false)))).is_false()
	var page := _page(_view(20))
	await get_tree().process_frame
	var corners := page.find_children("Corner", "TextureRect", true, false)
	assert_int(corners.size()).is_equal(1)
	var c := corners[0] as TextureRect
	assert_vector(c.size).is_equal(Vector2(22, 22))
	assert_object(c.texture).is_same(P0FishDex.badge_icon())
	assert_vector(c.position).is_equal(Vector2(36, -2))   # from the ring's top-left (Figma 9c93e46e: (51, −2) of the tile)
	var none := _page(_view(19))
	await get_tree().process_frame
	assert_int(none.find_children("Corner", "TextureRect", true, false).size()).is_equal(0)

func test_a_banner_with_art_drops_its_disc_and_mark() -> void:
	var b := UiMomentBanner.new()
	add_child(auto_free(b))
	b.kind = UiMomentBanner.Kind.COMPLETE
	b.icon = P0FishDex.badge_icon()
	await get_tree().process_frame
	var art: Array = b.find_children("*", "TextureRect", true, false).filter(func(t): return (t as TextureRect).texture == P0FishDex.badge_icon())
	assert_int(art.size()).is_equal(1)
	assert_bool((art[0] as TextureRect).visible).is_true()
	assert_vector((art[0] as TextureRect).size).is_equal(Vector2(52, 52))   # 52 at (15, 20) of the banner (9c93e46e)
	assert_vector((art[0] as TextureRect).position).is_equal(Vector2(-1, 0))
	b.icon = null   # back to the check
	assert_bool((art[0] as TextureRect).visible).is_false()
