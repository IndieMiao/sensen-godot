extends GdUnitTestSuite
## Compact/Kitchen/Cell 655:58506 states on UiItemCell's KITCHEN density (SGODOT-226, LOCK-20; WP1b B1-02,
## inPot / notForCooking from 223): what each state shows, and that DEFAULT keeps the plain cell.

const K := UiItemCell.KitchenState
## The retired can-cook / selected / in-pot check (SGODOT-256 ⑨): no kitchen cell draws it any more.
const CHECK := preload("res://assets/ui/kit_icons/check.svg")

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
	var clued := _cell({kitchen_state = K.CLUED, families = ["F"], clues = [UiItemCell.family_icon("F")]})
	await _settle()
	assert_bool(_shows(clued, UiItemCell.family_icon("F"))).is_true()
	var locked := _cell({kitchen_state = K.LOCKED})
	await _settle()
	assert_array(_texts(locked)).contains(["Lv4"])
	assert_bool(_shows(locked, UiItemCell.LOCK_GLYPH)).is_true()

func test_tasted_mastered_in_pot_and_not_for_cooking() -> void:
	var fish := load("res://assets/p0/icons/fish_crucian.svg")
	var tasted := _cell({icon = fish, kitchen_state = K.TASTED})
	await _settle()
	assert_array(_texts(tasted)).contains(["Try it"])   # 256 ⑨ A: known, not cooked yet; the word Tasted is gone
	assert_array(_texts(tasted)).not_contains(["Tasted"])
	assert_bool(_shows(tasted, UiItemCell.STAR_GLYPH)).is_false()
	var mastered := _cell({icon = fish, quantity = "×3", kitchen_state = K.MASTERED})
	await _settle()
	assert_bool(_shows(mastered, UiItemCell.STAR_GLYPH)).is_true()
	# C28 (1228:105954): the star sits at the bottom right; no quantity, no check.
	var star: Panel = mastered.get("_star")
	assert_float(star.position.x).is_greater(26.0)
	assert_float(star.position.y).is_greater(26.0)
	assert_vector(star.size).is_equal(Vector2(12, 12))
	assert_object((star.get_theme_stylebox(&"panel") as UiStyleBox).bg_color).is_equal(UiTokens.COLOR_GOLD_DEEP)   # color/goldDeep
	assert_bool(_shows(mastered, CHECK)).is_false()
	assert_array(_texts(mastered)).not_contains(["×3"])
	var in_pot := _cell({icon = fish, quantity = "×2", kitchen_state = K.IN_POT})
	await _settle()
	assert_array(_texts(in_pot)).contains(["×2"])   # some left: the count, no label (COOK-2b / P0-2)
	assert_array(_texts(in_pot)).not_contains(["In pot"])
	assert_bool(_shows(in_pot, CHECK)).is_false()   # inPot 1405:92963: the primary stroke, no check
	var nfc := _cell({icon = fish, quantity = "×1", kitchen_state = K.NOT_FOR_COOKING})
	await _settle()
	assert_array(_texts(nfc)).contains(["Not for\ncooking"])
	assert_array(_texts(nfc)).not_contains(["×1"])
	assert_bool(_shows(nfc, CHECK)).is_false()

func test_default_keeps_the_plain_status_label() -> void:
	var c := _cell({icon = load("res://assets/p0/icons/dish_fish_soup.svg"), status = "Shop"})
	await _settle()
	assert_array(_texts(c)).contains(["Shop"])
	c.state = UiItemCell.State.SELECTED   # the selected outline only: the check is retired (256 ⑨)
	await _settle()
	assert_bool(_shows(c, CHECK)).is_false()
	c.state = UiItemCell.State.DEFAULT
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
	assert_array(_rarity_dots(c)).is_empty()
	var plain := _cell({icon = salt, quantity = "×12", rarity = 1})
	await _settle()
	assert_array(_texts(plain)).not_contains(["Rack"])
	assert_array(_rarity_dots(plain)).has_size(1)   # the same lookup does find the dot on a plain cell (PR #54 review)
	var in_pot := _cell({icon = salt, rarity = 1, rack = true, kitchen_state = UiItemCell.KitchenState.IN_POT})   # COOK-2b-RACK
	await _settle()
	assert_array(_texts(in_pot)).contains(["Rack", "In pot"])

## Visible rarity dots on a cell (SIZE_RARITY_DOT squares).
func _rarity_dots(c: Control) -> Array:
	var dot := Vector2(UiTokens.SIZE_RARITY_DOT, UiTokens.SIZE_RARITY_DOT)
	return c.find_children("*", "Panel", true, false).filter(func(p): return p.is_visible_in_tree() and p.size.is_equal_approx(dot))

func _dots(c: UiItemCell) -> Array:
	var row: HBoxContainer = c.get("_family")
	return row.get_children().filter(func(n): return n is Panel).map(func(n): return ((n as Panel).get_theme_stylebox(&"panel") as UiStyleBox).bg_color)

func test_the_family_row_has_one_dot_per_slot_in_its_family_colour() -> void:
	# int6 C29: the row used to be one fixed picture (blue, green, tan) on every unknown page, and every clued page
	# lit a fish. Now: one 5 px dot per slot, coloured by its family; a clue lights its slot as a 10 px icon.
	var F := UiItemCell.FAMILY_COLORS
	var one := _cell({kitchen_state = K.HIDDEN, families = ["F"]})
	var three := _cell({kitchen_state = K.HIDDEN, families = ["W", "O", "S"]})
	await _settle()
	assert_array(_dots(one)).is_equal([F.F])
	assert_array(_dots(three)).is_equal([F.W, F.O, F.S])
	assert_bool(_shows(one, UiItemCell.family_icon("W"))).is_false()
	# A clue on slot 0: that slot is its icon (a named ingredient's own), the rest stay dots; the row stays centred.
	var radish := load("res://assets/p0/icons/crop_radish.svg")
	var clued := _cell({kitchen_state = K.CLUED, families = ["F", "S"], clues = [radish, null]})
	await _settle()
	assert_bool(_shows(clued, radish)).is_true()
	assert_array(_dots(clued)).is_equal([F.S])
	var row: HBoxContainer = clued.get("_family")
	var mid := row.get_global_rect().get_center().x - clued.get_global_rect().position.x
	assert_float(mid).is_equal_approx(UiTokens.SIZE_KITCHEN_CELL_W * 0.5, 0.6)
	# Known pages draw no row.
	clued.kitchen_state = K.TASTED
	await _settle()
	assert_bool(row.is_visible_in_tree()).is_false()

func test_might_have_rings_the_cell_in_color_new() -> void:
	# State=mightHave 1726:32864: the hidden look with a still ring outside the cell (blur 4, spread 2, new at 50 %).
	var c := _cell({kitchen_state = K.HIDDEN, families = ["W"], might_have = true})
	await _settle()
	var glow: Panel = c.get("_glow")
	assert_bool(glow.is_visible_in_tree()).is_true()
	assert_vector(glow.size).is_equal(Vector2.ONE * (UiTokens.SIZE_KITCHEN_CELL_W + 4))
	var ring := glow.get_theme_stylebox(&"panel") as UiStyleBox
	assert_object(ring.shadow_color).is_equal(UiKit.alpha(UiTokens.COLOR_NEW, 0.5))
	assert_float(ring.shadow_size).is_equal(4.0)
	assert_int(glow.get_index()).is_less(c.get("_surface").get_index())   # under the cell: only the ring shows
	c.might_have = false
	await _settle()
	assert_bool(glow.is_visible_in_tree()).is_false()

## SGODOT-256 ⑨ A (1919:32860): `Try it` in primary, 10 Bold, on a surface-raised tag with a border, centred across the
## cell at y 35.4; the icon stays half colour.
func test_try_it_tag_sits_centred_in_primary_on_a_half_colour_icon() -> void:
	var fish := load("res://assets/p0/icons/dish_fish_soup.svg")
	var c := _cell({icon = fish, kitchen_state = K.TASTED})
	await _settle()
	var label: Label = c.get("_chip_label")
	assert_str(label.text).is_equal("Try it")
	assert_object(label.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_PRIMARY_INK)
	var tag := label.get_parent() as Control
	var cell := c.get_global_rect()
	assert_float(absf(tag.get_global_rect().get_center().x - cell.get_center().x)).is_less_equal(0.6)
	assert_float(tag.get_global_rect().position.y - cell.position.y).is_between(35.0, 38.0)
	var icon: TextureRect = c.get("_icon")
	assert_float(icon.modulate.a).is_equal(0.5)
	c.kitchen_state = K.DEFAULT   # cooked once: full colour, no tag
	await _settle()
	assert_bool(label.is_visible_in_tree()).is_false()
	assert_float(icon.modulate.a).is_equal(1.0)
