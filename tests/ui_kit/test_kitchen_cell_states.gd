extends GdUnitTestSuite
## Compact/Kitchen/Cell 655:58506 states on UiItemCell's KITCHEN density (SGODOT-226, LOCK-20; WP1b B1-02,
## inPot / notForCooking from 223): what each state shows, and that DEFAULT keeps the plain cell.

const K := UiItemCell.KitchenState

func _cell(fields: Dictionary) -> UiItemCell:
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	var c := UiItemCell.new(UiItemCell.Density.KITCHEN)
	for k in fields: c.set(k, fields[k])
	host.add_child(c)
	return c

func _settle() -> void:
	for i in 2: await get_tree().process_frame

func _shows(c: Control, texture: Texture2D) -> bool:
	return c.find_children("*", "TextureRect", true, false).any(func(t): return t.is_visible_in_tree() and (t as TextureRect).texture == texture)

func _texts(c: Control) -> Array:
	return c.find_children("*", "Label", true, false).filter(func(l): return l.is_visible_in_tree()).map(func(l): return (l as Label).text)

func test_unknown_pages_show_the_silhouette_and_never_the_dish() -> void:
	var dish := load("res://assets/p0/icons/dish_grilled_fish.svg")
	for st in [K.HIDDEN, K.CLUED, K.LOCKED]:
		var c := _cell({icon = dish, kitchen_state = st})
		await _settle()
		assert_bool(_shows(c, UiItemCell.SILHOUETTE)).override_failure_message(str(st)).is_true()
		assert_bool(_shows(c, dish)).override_failure_message(str(st)).is_false()
	var clued := _cell({kitchen_state = K.CLUED})
	await _settle()
	assert_bool(_shows(clued, UiItemCell.FAMILY_DOTS_CLUED)).is_true()
	var locked := _cell({kitchen_state = K.LOCKED})
	await _settle()
	assert_array(_texts(locked)).contains(["Lv4"])
	assert_bool(_shows(locked, UiItemCell.LOCK_GLYPH)).is_true()

func test_tasted_mastered_in_pot_and_not_for_cooking() -> void:
	var fish := load("res://assets/p0/icons/fish_crucian.svg")
	var tasted := _cell({icon = fish, kitchen_state = K.TASTED})
	await _settle()
	assert_array(_texts(tasted)).contains(["Tasted"])
	assert_bool(_shows(tasted, UiItemCell.STAR_GLYPH)).is_false()
	var mastered := _cell({icon = fish, kitchen_state = K.MASTERED})
	await _settle()
	assert_bool(_shows(mastered, UiItemCell.STAR_GLYPH)).is_true()
	var in_pot := _cell({icon = fish, quantity = "×2", kitchen_state = K.IN_POT})
	await _settle()
	assert_array(_texts(in_pot)).contains(["×2"])   # some left: the count, no label (COOK-2b / P0-2)
	assert_array(_texts(in_pot)).not_contains(["In pot"])
	assert_bool(_shows(in_pot, UiItemCell.CHECK_GLYPH)).is_true()
	var nfc := _cell({icon = fish, quantity = "×1", kitchen_state = K.NOT_FOR_COOKING})
	await _settle()
	assert_array(_texts(nfc)).contains(["Not for\ncooking"])
	assert_array(_texts(nfc)).not_contains(["×1"])
	assert_bool(_shows(nfc, UiItemCell.CHECK_GLYPH)).is_false()

func test_default_keeps_the_plain_status_label_and_mark() -> void:
	var c := _cell({icon = load("res://assets/p0/icons/dish_fish_soup.svg"), status = "Shop", marked = true})
	await _settle()
	assert_array(_texts(c)).contains(["Shop"])
	assert_bool(_shows(c, UiItemCell.CHECK_GLYPH)).is_true()
	assert_bool(_shows(c, UiItemCell.SILHOUETTE)).is_false()
	c.kitchen_state = K.HIDDEN
	c.kitchen_state = K.DEFAULT
	await _settle()
	assert_array(_texts(c)).contains(["Shop"])
	assert_bool(_shows(c, UiItemCell.SILHOUETTE)).is_false()

func test_the_grid_passes_kitchen_state_to_its_cells() -> void:
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	var g := UiInventoryGrid.new()
	g.density = UiItemCell.Density.KITCHEN
	g.size = Vector2(336, 300)
	host.add_child(g)
	g.items = [{id = "fish_crucian", icon = load("res://assets/p0/icons/fish_crucian.svg"), qty = 2, kitchen_state = K.IN_POT},
		{id = "fish_koi", icon = load("res://assets/p0/icons/fish_koi.svg"), qty = 1, kitchen_state = K.NOT_FOR_COOKING}]
	await _settle()
	assert_int(g.cell_for("fish_crucian").kitchen_state).is_equal(K.IN_POT)
	assert_int(g.cell_for("fish_koi").kitchen_state).is_equal(K.NOT_FOR_COOKING)
	g.items = [{id = "fish_crucian", icon = load("res://assets/p0/icons/fish_crucian.svg"), qty = 2}]
	await _settle()
	assert_int(g.cell_for("fish_crucian").kitchen_state).is_equal(K.DEFAULT)

func test_in_pot_names_itself_only_once_none_is_left() -> void:
	var dish := load("res://assets/p0/icons/fish_crucian.svg")
	var some := _cell({icon = dish, kitchen_state = K.IN_POT, quantity = "×2"})
	await _settle()
	assert_bool(_texts(some).has("In pot")).override_failure_message(str(_texts(some))).is_false()
	assert_bool(_texts(some).has("×2")).is_true()
	var none := _cell({icon = dish, kitchen_state = K.IN_POT, quantity = ""})
	await _settle()
	assert_bool(_texts(none).has("In pot")).is_true()

func test_a_rack_seasoning_shows_the_rack_tag_and_no_rarity_dot() -> void:
	var salt := load("res://assets/p0/icons/fish_crucian.svg")
	var c := _cell({icon = salt, quantity = "×12", rarity = 1, rack = true})
	await _settle()
	assert_array(_texts(c)).contains(["Rack", "×12"])
	var dots := c.find_children("*", "Panel", true, false).filter(func(p): return p.is_visible_in_tree() and p.size == Vector2(UiTokens.SIZE_RARITY_DOT, UiTokens.SIZE_RARITY_DOT))
	assert_array(dots).is_empty()
	var plain := _cell({icon = salt, quantity = "×12", rarity = 1})
	await _settle()
	assert_array(_texts(plain)).not_contains(["Rack"])
	var in_pot := _cell({icon = salt, rarity = 1, rack = true, kitchen_state = UiItemCell.KitchenState.IN_POT})   # COOK-2b-RACK
	await _settle()
	assert_array(_texts(in_pot)).contains(["Rack", "In pot"])

