extends GdUnitTestSuite
## LOOK-PICK (SGODOT-282; 不知火舞 49498df6 / e2d76a7c, q(112) / q(115)): Homestead looks a (timber) / b (stone) at
## Lv3 / 5 / 8 / 15 — HOME-1's Looks rows, the card, and the parts on the farm.

const Looks = preload("res://scenes/p0/p0_looks.gd")
const Fence = preload("res://scenes/p0/p0_fence.gd")
const FarmProps = preload("res://modules/farm/farm_props.gd")
const FarmArt = preload("res://modules/farm/farm_art.gd")

func _view(level: int, looks := {}) -> Dictionary:
	var rows: Array = []
	for l in P0Logic.look_stages():
		var reached := level >= int(l.level)
		rows.append({"id": l.id, "level": l.level, "name": l.name, "a": l.a, "b": l.b,
			"look": str(looks.get(str(l.id), "a")) if reached else null})
	return {"homestead": {"level": level, "looks": rows, "next": null, "unlocks": {"fence": level >= 3}},
		"energy": {"max": 240}, "bag": {"capacity": 30}}

func _ui(v: Dictionary) -> P0Ui:
	var ui: P0Ui = auto_free(P0Ui.new())
	add_child(ui)
	ui.set_view(v)
	return ui

# ---------------------------------------------------------------- HOME-1 Looks (e2d76a7c, Figma 2201:33545)
func test_looks_rows_name_the_look_on_reached_stages_and_grey_the_rest() -> void:
	var rows := P0Logic.look_rows(_view(4))
	assert_array(rows.map(func(r): return "%s … %s" % [r.name, r.value])).is_equal(
		["Fence & Mailbox … Timber Fence ›", "Porch … Homestead Lv5", "Kitchen Wing … Homestead Lv8", "Master Farmhouse … Homestead Lv15"])
	assert_array(rows.map(func(r): return [r.reached, r.open])).is_equal([[true, true], [false, false], [false, false], [false, false]])
	assert_array(rows.map(func(r): return str(r.icon))).is_equal(["mailbox", "door", "kitchen", "home"])
	assert_array(P0Logic.look_rows(_view(2))).is_empty()   # no stage yet: no Looks section
	var away := P0Logic.look_rows(_view(5, {"porch": "b"}), false)   # away from home: read only, no ›
	assert_str(str(away[1].value)).is_equal("Stone Porch")
	assert_bool(bool(away[1].open)).is_false()

func test_the_next_look_level_lists_its_stage_timber_or_stone() -> void:
	var v := _view(4)
	v.homestead.next = {"level": 5, "coins": {"need": 840, "have": 0}, "skills": [{"skill": "fishing", "need": 9, "have": 9}],
		"materials": [], "energy": 240, "meals": 240, "unlocks": ["notice_board", "trip_7", "porch", "standard_room"]}
	var p := P0Logic.home_panel(v)
	assert_str(str(p.look)).is_equal("Lv5 look · Porch")
	var row: Dictionary = p.changes.filter(func(c): return str(c.text).ends_with("Timber or Stone"))[0]
	assert_str("%s · %s" % [row.text, row.note]).is_equal("Porch · Timber or Stone · pick one")
	assert_str(str(row.icon)).is_equal("door")
	var board: Dictionary = p.changes.filter(func(c): return str(c.text) == "Notice Board")[0]
	assert_str(str(board.note)).is_equal("at the Homestead Stall")   # §9, Figma HOME-1-LV5 (不知火舞 on #250)

func test_a_reached_looks_row_opens_the_card_with_the_current_look() -> void:
	var ui := _ui(_view(5, {"porch": "b"}))
	ui.space = "home"
	load("res://scenes/p0/home/p0_home_panel.gd").open(ui, true)
	var row: Control = ui.find_children("Look_porch", "", true, false)[0]
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	row.gui_input.emit(up)
	var card: P0LookPick = ui.find_children("*", "P0LookPick", true, false)[0]
	assert_bool(card.first).is_false()
	assert_str(card.choice).is_equal("b")
	assert_str(card.use_button.label).is_equal("Use Stone Porch")
	card.dismiss()   # from HOME-1: no change, back to HOME-1
	assert_str(ui.modal_kind).is_equal("homestead")

# ---------------------------------------------------------------- LOOK-PICK (49498df6, Figma 2199:32862)
func test_the_card_after_the_upgrade_previews_writes_and_closes_to_a() -> void:
	var ui := _ui(_view(5))
	var previews: Array = []
	var sent: Array = []
	ui.look_previewed.connect(func(st, lk): previews.append([st, lk]))
	ui.command.connect(func(c): sent.append(c))
	var card := P0LookPick.open(ui, "porch", true)
	await get_tree().process_frame
	assert_str((card.find_child("Title", true, false) as Label).text).is_equal("Lv5 look · Porch")
	assert_str((card.find_child("Subtitle", true, false) as Label).text).is_equal("Pick one · free to change later")
	assert_str(card.choice).is_equal("a")   # default a
	assert_bool((card.options.a as UiLookOption).selected).is_true()
	assert_str(card.use_button.label).is_equal("Use Timber Porch")
	(card.options.b as UiLookOption).picked.emit()
	assert_str(card.use_button.label).is_equal("Use Stone Porch")
	assert_bool((card.options.b as UiLookOption).selected).is_true()
	assert_array(previews).is_equal([["porch", "b"]])   # the farmhouse shows it at once
	assert_array(sent).is_empty()                         # only Use writes it
	card.use()
	assert_array(sent).is_equal([{"type": "set_look", "stage": "porch", "look": "b"}])
	assert_bool(ui.has_modal()).is_false()
	# closing the next one after an upgrade = a: the preview ends, nothing is sent
	var again := P0LookPick.open(ui, "porch", true)
	again.pick("b")
	again.dismiss()
	assert_array(previews.back()).is_equal(["porch", ""])
	assert_int(sent.size()).is_equal(1)

func test_two_cards_are_as_tall_as_the_taller() -> void:
	var a := UiLookOption.new("Timber Porch")
	var b := UiLookOption.new("Stone Porch")
	a.theme = UiKit.theme()
	b.theme = UiKit.theme()
	add_child(auto_free(a))
	add_child(auto_free(b))
	UiLookOption.pair(a, b)
	assert_float(a.custom_minimum_size.y).is_equal(b.custom_minimum_size.y)
	assert_float(a.custom_minimum_size.x).is_equal(158.0)
	var wing_a := UiLookOption.new("Timber Kitchen Wing")
	var wing_b := UiLookOption.new("Stone Kitchen Wing")
	for o in [wing_a, wing_b]:
		o.theme = UiKit.theme()
		add_child(auto_free(o))
	await get_tree().process_frame
	UiLookOption.pair(wing_a, wing_b)
	assert_float(wing_a.custom_minimum_size.y).is_greater(a.custom_minimum_size.y)   # two lines: taller, same font size
	assert_float(wing_a.custom_minimum_size.y).is_equal(wing_b.custom_minimum_size.y)

# ---------------------------------------------------------------- the farm's parts (上官婉儿 e4d03424)
func test_stone_wall_follows_the_fence_run_three_rocks_a_segment() -> void:
	var bp := P0Garden.blueprint()
	var segs := P0Garden.fence_front(bp) + P0Garden.fence_ring(bp)
	var wall := P0Garden.stone_wall(segs)
	assert_int(wall.size()).is_equal(segs.size() * P0Garden.STONE_PER_SEG)
	for i in segs.size():   # each segment's rocks sit on it, within its length
		var seg: Dictionary = segs[i]
		for k in P0Garden.STONE_PER_SEG:
			var p: Vector3 = wall[i * P0Garden.STONE_PER_SEG + k].pos
			assert_float(p.distance_to(seg.pos)).is_less(P0Garden.FENCE_SEG * float(seg.stretch) * 0.5)

## #875's models (赵云 #858, 刘备 #854): each stage one model, its origin the house anchor, set there as it is; the
## Master Farmhouse the house's own mesh. Every one is in the farm's art and drawn with its vertex colours. The wing's
## (and the Master Farmhouse's, which has it built in) wait while P0Garden.WING_WAITS (不知火舞 448 b18d13c6): the old
## lean-to / stone room and house_barn / house_dome, and the standalone parts stay up beside them.
func test_each_look_is_its_model_at_the_house() -> void:
	var bp := P0Garden.blueprint()
	var house := bp.cell_to_world(P0Garden.ANCHORS.house)
	for look in ["a", "b"]:
		var porch := P0Garden.look_parts(bp, "porch", look)
		assert_array(porch.map(func(p): return p.asset)).is_equal(["porch_" + look])
		assert_object(porch[0].pos).is_equal(house)
		assert_float(float(porch[0].yaw)).is_equal(0.0)
		var wing := P0Garden.look_parts(bp, "kitchen_extension", look)
		if P0Garden.WING_WAITS:
			var old: Array = ["storage"] if look == "a" else ["path_tile", "rock", "rock"]
			assert_array(wing.map(func(p): return p.asset)).is_equal(old)
			for p in wing: assert_float((p.pos as Vector3).y).is_less(0.01)   # on the ground, nothing stacked (#250)
		else:
			assert_array(wing.map(func(p): return p.asset)).is_equal(["kitchen_wing_" + look])
	for asset in ["porch_a", "porch_b", "kitchen_wing_a", "kitchen_wing_b", "master_farmhouse_a", "master_farmhouse_b"]:
		assert_object(FarmArt.mesh_for(asset)).override_failure_message(asset).is_not_null()
	assert_array(P0Garden.look_parts(bp, "porch", "")).is_empty()
	var whole := not P0Garden.WING_WAITS
	assert_str(P0Garden.look_house("a")).is_equal("master_farmhouse_a" if whole else "house_barn")
	assert_str(P0Garden.look_house("b")).is_equal("master_farmhouse_b" if whole else "house_dome")
	assert_str(P0Garden.look_house("")).is_equal("house_cottage")
	assert_bool(P0Garden.whole_house("a")).is_equal(whole)
	assert_bool(P0Garden.whole_house("")).is_false()
	var m := FarmArt.instance("porch_a")   # the colour is in the vertex colours: the farm's one material (上官婉儿 on #875)
	assert_object(m.material_override).is_same(FarmArt.material())
	m.free()

func test_the_farm_shows_the_views_looks_and_the_cards_preview() -> void:
	var bp := P0Garden.blueprint()
	var house := FarmProps.build("house", bp.cell_to_world(P0Garden.ANCHORS.house), 1.0, "cottage")
	add_child(auto_free(house))
	var fence: Node3D = auto_free(Fence.new())
	add_child(fence)
	fence.build(bp)
	var looks: Node3D = auto_free(Looks.new())
	add_child(looks)
	looks.build(bp, house, "cottage", fence)
	var cottage := house.mesh
	var v := _view(5)
	looks.sync(v)
	fence.sync(v)
	assert_str(looks.shown("porch")).is_equal("a")
	assert_str(looks.shown("kitchen_extension")).is_equal("")   # Lv8 not reached: nothing there
	assert_object((looks.parts("porch")[0] as MeshInstance3D).mesh).is_same(FarmArt.mesh_for("porch_a"))
	assert_str(fence.look).is_equal("a")
	looks.preview("porch", "b")   # LOOK-PICK's preview
	looks.sync(v)
	assert_str(looks.shown("porch")).is_equal("b")
	assert_object((looks.parts("porch")[0] as MeshInstance3D).mesh).is_same(FarmArt.mesh_for("porch_b"))
	var used := _view(5, {"porch": "b"})   # Use landed: the preview lets go, the view keeps b
	looks.sync(used)
	assert_bool(looks.previews.has("porch")).is_false()
	assert_str(looks.shown("porch")).is_equal("b")
	fence.preview = "b"
	fence.sync(used)
	assert_str(fence.look).is_equal("b")   # Stone Wall
	var ring: MultiMeshInstance3D = fence.find_child("Ring", true, false)   # one batch, one draw (上官婉儿 on #250)
	assert_int(ring.multimesh.instance_count).is_equal(P0Garden.fence_ring(bp).size() * P0Garden.STONE_PER_SEG)
	var lv8 := _view(8, {"porch": "b"})
	looks.sync(lv8)
	var wing_a := P0Garden.look_parts(P0Garden.blueprint(), "kitchen_extension", "a")
	assert_int(looks.parts("kitchen_extension").size()).is_equal(wing_a.size())
	var lv15 := _view(15, {"porch": "b", "master_farmhouse": "b"})   # the Master Farmhouse at Lv15 since v4q(1) ⑧
	looks.sync(lv15)
	assert_object(house.mesh).is_not_same(cottage)
	assert_object(house.mesh).is_same(FarmArt.mesh_for(P0Garden.look_house("b")))
	# a whole house has its porch and wing in it: the standalone two stand down; the old house keeps them beside it
	for stage in ["porch", "kitchen_extension"]:
		assert_bool((looks.parts(stage)[0] as Node3D).get_parent().visible).override_failure_message(stage) \
			.is_equal(not P0Garden.whole_house("b"))

## 亚瑟 on #896: a model one walks into is a picture — the cells a shown porch, wing or whole house stands on are solid,
## off the house's own footprint and the door path, and the bench is still reached from the yard. While WING_WAITS the
## old wing and house block nothing new (as before); the porch's model blocks its cells.
func test_a_shown_model_stands_on_its_cells() -> void:
	var bp := P0Garden.blueprint()
	for asset in ["porch_a", "porch_b", "kitchen_wing_a", "kitchen_wing_b", "master_farmhouse_a", "master_farmhouse_b"]:
		var cells := P0Garden.look_cells(bp, asset)
		print("LOOK cells ", asset, " ", cells)
		for c in cells:
			assert_bool(P0Garden.FOOTPRINTS.house.has_point(c) or P0Garden.DOOR_PATH.has_point(c)).is_false()
	# the wing's walls and the room they close, on the house's left and back (亚瑟 counted (5..7, 17..18), (7, 16),
	# (8, 18) from its box; (5, 18) its set-back corner does not reach); the porch's left post; the whole house both
	var wing: Array[Vector2i] = [Vector2i(5, 17), Vector2i(6, 17), Vector2i(6, 18), Vector2i(7, 16), Vector2i(7, 17),
		Vector2i(7, 18), Vector2i(8, 18)]
	for look in ["a", "b"]:
		assert_array(P0Garden.look_cells(bp, "kitchen_wing_" + look)).contains_exactly_in_any_order(wing)
		assert_array(P0Garden.look_cells(bp, "porch_" + look)).contains_exactly([Vector2i(7, 15)])
		assert_array(P0Garden.look_cells(bp, "master_farmhouse_" + look)) \
			.contains_exactly_in_any_order(wing + [Vector2i(7, 15)])
	# with the whole house standing, the bench (5, 16) is still sat on from the yard in front of it
	var grid := BlueprintGrid.new(bp)
	for c in P0Garden.look_cells(bp, "master_farmhouse_a"): grid.set_solid(c, true)
	assert_array(grid.path(Vector2i(5, 12), Vector2i(5, 15))).is_not_empty()
	# on the farm: what the shown looks hold, and back when they go
	var house := FarmProps.build("house", bp.cell_to_world(P0Garden.ANCHORS.house), 1.0, "cottage")
	add_child(auto_free(house))
	var fence: Node3D = auto_free(Fence.new())
	add_child(fence)
	fence.build(bp)
	var looks: Node3D = auto_free(Looks.new())
	add_child(looks)
	looks.build(bp, house, "cottage", fence)
	looks.grid = BlueprintGrid.new(bp)
	looks.sync(_view(8))
	var held: Array = P0Garden.look_cells(bp, "porch_a")
	if not P0Garden.WING_WAITS: held += P0Garden.look_cells(bp, "kitchen_wing_a")
	assert_int(looks.solid_cells().size()).is_equal(held.size())
	for c in looks.solid_cells(): assert_bool(looks.grid._blocked(c)).is_true()
	looks.sync(_view(2))   # no looks: every cell walkable again
	assert_array(looks.solid_cells()).is_empty()
	for c in held: assert_bool(looks.grid._blocked(c)).override_failure_message(str(c)).is_false()
