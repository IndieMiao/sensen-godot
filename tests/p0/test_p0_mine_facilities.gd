extends GdUnitTestSuite
## SGODOT-266 (user on SGODOT-263 ③; 不知火舞's spec 2e580bed, copy 李白 q(102)): the mine's ladders and elevator are
## facilities. A tap walks the player up (the stick on the way cancels), then a free move goes at once and a new
## floor's fee waits on the EntryCard's button; the main key stays Mining's.

const STORE := "user://test_p0_mine_facilities.json"
const P0_MINE := "res://scenes/p0/p0_mine.tscn"
const CLEARED := [true, true, true, true, true, true]
const ROCKS := [false, false, false, false, false, false]

var rt: P0Runtime
var mine: Node3D
var sent: Array = []

func _floor(n: int, paid := true, broken := ROCKS) -> Dictionary:
	var left := broken.filter(func(b): return not b).size()
	return {"floor": n, "paid": paid, "cleared": left == 0, "left": left, "broken": broken, "lit": false, "preview": null, "bag_ok": true}

func _view(floors: Array, energy := 200) -> Dictionary:
	return {"energy": {"value": energy, "max": 200, "next_in": null, "regen_ms": 240000}, "coins": 40, "skills": {}, "plots": [],
		"bag": {"capacity": 25, "free": 25, "slots": []}, "names": {"torch": "Torch"}, "inbox": {"parcels": [], "letters": []},
		"rest": {"used": 0, "limit": 1, "resets_in": 1},
		"mine": {"runs": {"used": 1, "limit": 2, "resets_in": 33120000}, "ended": null, "floor_energy": 2, "rock_energy": 2,
			"rocks": 6, "run": {"id": 1, "deepest": 1, "can_new_run": false, "new_run_block": "clear_floor_2", "floors": floors}}}

func before_test() -> void:
	UiCommandButton.offline = false
	sent = []

func after_test() -> void:
	if is_instance_valid(mine): mine.queue_free()
	P0Runtime.free_instance_for_tests()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	await get_tree().process_frame

## The real mine scene on a runtime with no server: the view is set by hand, sent commands are recorded.
func _open(v: Dictionary, n := 1) -> void:
	P0Runtime.free_instance_for_tests()
	rt = P0Runtime.ensure()
	rt.ui.quick_store = STORE
	rt.session.transport = func(_m, _p, _b, _c): pass
	rt.session.sent.connect(func(cmd): sent.append(cmd))
	await get_tree().process_frame   # ensure() adds it deferred
	rt.session.view = v
	mine = load(P0_MINE).instantiate()
	mine.setup({"floor": n})
	add_child(mine)
	await get_tree().process_frame
	await get_tree().process_frame

func _until(cond: Callable, seconds := 8.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call(): return true
		await get_tree().process_frame
	return cond.call()

func _sent(type: String) -> Array:
	return sent.filter(func(c): return str(c.get("type", "")) == type)

func test_the_key_stays_minings_by_every_facility() -> void:
	await _open(_view([_floor(1, true, CLEARED), _floor(2, false)]))
	for p in [preload("res://modules/mining/mine_layout.gd").DOWN, preload("res://modules/mining/mine_layout.gd").ELEVATOR,
			preload("res://modules/mining/mine_layout.gd").UP]:
		mine.actor.teleport(p + Vector3(0.6, 0, 0.6))
		mine.actor.face(p)
		await get_tree().process_frame
		await get_tree().process_frame
		assert_str(str(rt.ui.fab_state().verb)).is_equal("Mine")

## A new floor's fee is confirmed on the card at the ladder, never by the tap: walk up, the card, its button, the floor.
func test_the_ladder_down_walks_up_then_asks_for_the_fee() -> void:
	await _open(_view([_floor(1, true, CLEARED), _floor(2, false)]))
	mine.p0_dev(PackedStringArray(["tapfac", "mine_down"]))
	assert_bool(mine._walk.is_empty()).is_false()   # walking there, nothing used yet
	assert_bool(await _until(func(): return mine.card_shown())).is_true()
	assert_float(P0FarmMaterials.flat(mine.actor.position, preload("res://modules/mining/mine_layout.gd").DOWN)).is_less_equal(mine.REACH)
	assert_array(_sent("mine_floor")).is_empty()   # the tap spent nothing
	assert_str(mine.card_entry().main_text()).is_equal("Floor 2 · 2 Energy")
	assert_bool(mine.card_entry()._title_row.visible).is_false()   # a ladder's card has no title
	# Kept off the player (不知火舞 on #190): clear of their box on screen by 4, unless already as high as it may go.
	await get_tree().process_frame
	var body: Rect2 = mine.actor.screen_box(mine.cam)
	var card := Rect2(mine.card_entry().position, mine.card_entry().size)
	assert_bool(not card.intersects(body.grow(3.9)) or is_equal_approx(card.position.y, rt.ui.card_top())).is_true()
	mine.p0_dev(PackedStringArray(["cardtap"]))
	assert_array(_sent("mine_floor")).is_equal([{"type": "mine_floor", "floor": 2}])
	assert_bool(mine.card_shown()).is_false()

func test_pushing_the_stick_on_the_way_cancels() -> void:
	await _open(_view([_floor(1, true, CLEARED), _floor(2, false)]))
	mine.p0_dev(PackedStringArray(["tapfac", "mine_down"]))
	await get_tree().process_frame
	mine.p0_joystick(Vector2(-1, 0))
	assert_bool(mine._walk.is_empty()).is_true()
	await get_tree().create_timer(0.2).timeout
	mine.p0_joystick(Vector2.ZERO)
	await get_tree().create_timer(1.5).timeout
	assert_bool(mine.card_shown()).is_false()
	assert_array(_sent("mine_floor")).is_empty()

## Grey with the reason (LOCK-10): the card's button says why and its press toasts it.
func test_an_uncleared_floor_greys_the_fee_button() -> void:
	await _open(_view([_floor(1), _floor(2, false)]))
	mine.p0_dev(PackedStringArray(["tapfac", "mine_down"]))
	assert_bool(await _until(func(): return mine.card_shown())).is_true()
	assert_str(mine.card_entry().main_text()).is_equal("Floor 2 · Clear Floor 1 first")
	mine.p0_dev(PackedStringArray(["cardtap"]))
	assert_str(rt.ui.toast_text()).is_equal("Floor 2 · Clear Floor 1 first")
	assert_array(_sent("mine_floor")).is_empty()

## Short of Energy: amber with the whole line; its press opens the Energy card for this floor's fee.
func test_short_of_energy_the_card_opens_the_energy_card() -> void:
	await _open(_view([_floor(1, true, CLEARED), _floor(2, false)], 1))
	mine.p0_dev(PackedStringArray(["tapfac", "mine_down"]))
	assert_bool(await _until(func(): return mine.card_shown())).is_true()
	assert_str(mine.card_entry().main_text()).is_equal("Floor 2 · Need 2 Energy")
	assert_bool(mine.card_entry().is_amber()).is_true()
	mine.p0_dev(PackedStringArray(["cardtap"]))
	assert_str(rt.ui.modal_kind).is_equal("energy")
	assert_array(_sent("mine_floor")).is_empty()

## Free moves go at once on arrival, no card: a floor paid this run, and the elevator's stop panel.
func test_free_moves_go_on_arrival() -> void:
	await _open(_view([_floor(1, true, CLEARED), _floor(2)]))
	mine.p0_dev(PackedStringArray(["tapfac", "mine_down"]))
	assert_bool(await _until(func(): return not _sent("mine_floor").is_empty())).is_true()
	assert_array(_sent("mine_floor")).is_equal([{"type": "mine_floor", "floor": 2}])
	assert_bool(mine.card_shown()).is_false()
	mine.p0_dev(PackedStringArray(["tapfac", "mine_elevator"]))
	assert_bool(await _until(func(): return rt.ui.modal_kind == "elevator")).is_true()

func test_the_way_out_walks_up_then_leaves() -> void:
	await _open(_view([_floor(1), _floor(2, false)]))
	mine.p0_dev(PackedStringArray(["tapfac", "mine_up"]))
	assert_bool(await _until(func(): return mine._leaving)).is_true()

## Their prompts: an icon button each within 8 m, the nearest one's strip (the copy is P0WorldPrompts.mine_facility's,
## tested in test_p0_material_logic; how they look is on the SGODOT-266 shots).
func test_the_facilities_wear_world_prompts() -> void:
	await _open(_view([_floor(1, true, CLEARED), _floor(2, false)]))
	mine.actor.teleport(preload("res://modules/mining/mine_layout.gd").DOWN + Vector3(-0.8, 0, 0.8))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_str(mine._strip_open).is_equal("mine_down")
	assert_bool(rt.ui._name_bars.has("mine_down")).is_true()
	assert_bool(rt.ui._icons.has("mine_up") and rt.ui._icons.has("mine_elevator")).is_true()
	for id in mine._facilities: assert_bool((mine._facilities[id].box as AABB).has_volume()).is_true()   # found once a floor
	mine.p0_dev(PackedStringArray(["tapfac", "mine_down"]))   # right there: the card at once, in the strip's place
	assert_bool(await _until(func(): return mine.card_shown())).is_true()
	assert_bool(rt.ui._name_bars.get("mine_down").visible and not rt.ui._name_bars.get("mine_down").get_meta("folding", false)).is_false()

## The box a card keeps off (不知火舞 on #190): the figure on screen, feet to the top of the head and the body's width —
## not the map avatar's 70 × 130 tap target.
func test_the_player_box_is_the_figure_on_screen() -> void:
	await _open(_view([_floor(1), _floor(2, false)]))
	var r: Rect2 = mine.actor.screen_box(mine.cam)
	var feet: Vector2 = mine.cam.unproject_position(mine.actor.position)
	var px_per_m: float = mine.get_viewport().get_visible_rect().size.x / mine.cam.size
	assert_float(r.end.y).is_equal_approx(feet.y, 0.5)
	assert_float(r.get_center().x).is_equal_approx(feet.x, 0.5)
	assert_float(r.size.x).is_equal_approx(2.0 * P0Actor.HALF_WIDTH_M * px_per_m, 1.0)
	var head: Vector2 = mine.cam.unproject_position(mine.actor.position + Vector3.UP * P0Actor.HEAD_M)
	assert_float(r.position.y).is_equal_approx(head.y, 8.0)   # the outfit's own top once drawn, else HEAD_M
	assert_float(r.size.y / px_per_m).is_between(0.8, 1.8)     # the figure's own height on screen, in metres across

## Joey 296 #16: a slime's leap that lands while another command is still on the wire (a swing, a rock, the 30 s read)
## was dropped — no hit sent, no HP gone. It queues now and goes behind that one; still one hit at a time.
func test_a_hit_while_a_command_is_on_the_wire_still_goes() -> void:
	await _open(_view([_floor(1, true, CLEARED), _floor(2, true, CLEARED), _floor(3)]), 3)
	rt.session.send({"type": "mine_rock", "floor": 3, "rock": 0})   # on the wire: this runtime never answers
	assert_bool(rt.session.busy).is_true()
	mine._on_contact(preload("res://modules/mining/p0_mine_combat.gd").mob_id(0))
	assert_array(_sent("mine_attack")).is_equal([{"type": "mine_attack", "floor": 3, "hurt_by": 0}])   # queued behind it
	mine._on_contact(preload("res://modules/mining/p0_mine_combat.gd").mob_id(1))
	assert_int(_sent("mine_attack").size()).is_equal(1)   # one hit at a time: the next waits for its settle
