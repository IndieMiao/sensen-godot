extends GdUnitTestSuite
## UiBlueprintCard (BlueprintCard 1434:93844, SGODOT-231 B2-06): one workbench recipe; the button carries the gap
## or the done state and still takes the tap (LOCK-10); an owned tool has no materials row.

func _host(c: Control) -> Control:
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 640)
	add_child(auto_free(host))
	host.add_child(c)
	return c

func _data(button: Dictionary, materials := true) -> Dictionary:
	var d := {"name": "Torch", "effect": "See what rocks hold", "yield": "You get 2", "have": "You have 6", "button": button}
	if materials:
		d.materials = [{"name": "Timber", "have": 17, "need": 1}, {"name": "Reeds", "have": 0, "need": 1}]
	return d

func test_lays_out_the_recipe() -> void:
	var c := _host(UiBlueprintCard.new(_data({"label": "Craft", "kind": UiBlueprintCard.Kind.PRIMARY}))) as UiBlueprintCard
	assert_str(c._name.text).is_equal("Torch")
	assert_str(c._yield.text).is_equal("You get 2")
	assert_str(c._have.text).is_equal("You have 6")
	assert_int(c.tiles().size()).is_equal(2)
	assert_str(c.tiles()[1].item_name).is_equal("Reeds")
	assert_int(c.button.kind).is_equal(UiCommandButton.Kind.PRIMARY)
	assert_str(c.button.reason).is_empty()

func test_craft_and_equip_press_the_card() -> void:
	var c := _host(UiBlueprintCard.new(_data({"label": "Craft", "kind": UiBlueprintCard.Kind.PRIMARY}))) as UiBlueprintCard
	var pressed := [0]
	c.pressed.connect(func(): pressed[0] += 1)
	c.button.activated.emit()
	assert_int(pressed[0]).is_equal(1)
	c.set_data(_data({"label": "Equip", "kind": UiBlueprintCard.Kind.SECONDARY}, false))
	assert_int(c.button.kind).is_equal(UiCommandButton.Kind.SECONDARY)
	assert_bool(c._materials.visible).is_false()

func test_a_reason_or_done_state_stays_tappable() -> void:
	var c := _host(UiBlueprintCard.new(_data({"label": "No room · free a slot first", "kind": UiBlueprintCard.Kind.UNAVAILABLE}))) as UiBlueprintCard
	assert_str(c.button.reason).is_equal("No room · free a slot first")
	var said: Array = []
	c.unavailable_pressed.connect(func(r): said.append(r))
	c.button.unavailable_pressed.emit(c.button.reason)
	assert_that(said).is_equal(["No room · free a slot first"])
	# Back to craftable: the reason clears.
	c.set_data(_data({"label": "Craft", "kind": UiBlueprintCard.Kind.PRIMARY}))
	assert_str(c.button.reason).is_empty()

func test_a_tile_reports_its_index() -> void:
	var c := _host(UiBlueprintCard.new(_data({"label": "Craft", "kind": UiBlueprintCard.Kind.PRIMARY}))) as UiBlueprintCard
	var got: Array = []
	c.material_pressed.connect(func(i, tile): got.append([i, tile]))
	c.tiles()[1].pressed.emit()
	assert_int(got[0][0]).is_equal(1)
	assert_object(got[0][1]).is_same(c.tiles()[1])

func test_supplies_lines_hide_on_tools() -> void:
	var d := _data({"label": "Craft", "kind": UiBlueprintCard.Kind.PRIMARY})
	d.erase("yield")
	d.erase("have")
	var c := _host(UiBlueprintCard.new(d)) as UiBlueprintCard
	assert_bool(c._yield.visible).is_false()
	assert_str(c._have.text).is_empty()

func test_the_icon_tile_asks_for_the_items_info() -> void:
	var c := _host(UiBlueprintCard.new(_data({"label": "Craft", "kind": UiBlueprintCard.Kind.PRIMARY}))) as UiBlueprintCard
	var asked := [0]
	c.icon_pressed.connect(func(): asked[0] += 1)
	var hit: Button = c.find_children("*", "Button", true, false).filter(func(b): return b.flat)[0]
	hit.pressed.emit()
	assert_int(asked[0]).is_equal(1)

## FAC-GH 482:380 (不知火舞 on 241, 4e7d1119): at most three NEED-TILEs a row — the greenhouse's fourth, Coins, wraps to
## a second row, left-aligned, the row gap the tile gap; the card stays within the drawer's width, its tiles their size.
func test_a_fourth_material_wraps_to_a_second_row() -> void:
	var d := {"name": "Greenhouse", "effect": "16 plots · −25%", "button": {"label": "Build", "kind": UiBlueprintCard.Kind.PRIMARY},
		"materials": [{"name": "Timber", "have": 60, "need": 20}, {"name": "Stone", "have": 40, "need": 12},
			{"name": "Copper Ore", "have": 20, "need": 8}, {"name": "Coins", "have": 600, "need": 300}]}
	var c := _host(UiBlueprintCard.new(d)) as UiBlueprintCard
	c.size.x = 332.0
	await await_idle_frame()
	var rows := c._materials.get_children()
	assert_int(rows.size()).is_equal(2)
	assert_int(rows[0].get_child_count()).is_equal(3)
	assert_str((rows[1].get_child(0) as UiNeedTile).item_name).is_equal("Coins")
	var t := c.tiles()
	assert_float(t[3].global_position.x).is_equal_approx(t[0].global_position.x, 0.5)   # left-aligned under Timber
	assert_float(t[3].global_position.y - t[0].get_global_rect().end.y).is_equal_approx(8.0, 0.5)   # the tile gap
	assert_float(c.get_combined_minimum_size().x).is_less_equal(332.0)   # no wider than the drawer's card
	c.set_data(d)   # set again: the rows are rebuilt, not added to
	await await_idle_frame()
	assert_int(c._materials.get_child_count()).is_equal(2)
