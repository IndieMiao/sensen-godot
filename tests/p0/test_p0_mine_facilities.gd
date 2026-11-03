extends GdUnitTestSuite
## SGODOT-266 (user on SGODOT-263 ③; 不知火舞's spec 2e580bed, copy 李白 q(102)) on the 355 b1 mine: the ladders and
## elevator are facilities. A tap walks the player up (the stick on the way cancels), then a free move goes at once and a
## new floor's fee waits on the EntryCard's button; the main key stays Mining's. The stairs open on the monsters
## (contract-efg §5 ②), the elevator stands on Floor 1 and the stops.

const STORE := "user://test_p0_mine_facilities.json"
const P0_MINE := "res://scenes/p0/p0_mine.tscn"
const Fx := preload("res://tests/p0/fixtures/mine_b1_view.gd")
const Layout := preload("res://modules/mining/mine_layout.gd")
const DAY := "2026-11-02"
const CLEAR := {"mobs": []}   # this floor's monsters down: the stairs are open

var rt: P0Runtime
var mine: Node3D
var sent: Array = []

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
	mine.setup({"mine": Fx.MINE, "floor": n})
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
	await _open(Fx.view(1, CLEAR))
	for p in [Layout.DOWN, Layout.ELEVATOR, Layout.UP]:
		mine.actor.teleport(p + Vector3(0.6, 0, 0.6))
		mine.actor.face(p)
		await get_tree().process_frame
		await get_tree().process_frame
		assert_str(str(rt.ui.fab_state().verb)).is_equal("Mine")

## A new floor's fee is confirmed on the card at the ladder, never by the tap: walk up, the card, its button, the floor.
func test_the_ladder_down_walks_up_then_asks_for_the_fee() -> void:
	await _open(Fx.view(1, CLEAR))
	mine.p0_dev(PackedStringArray(["tapfac", "mine_down"]))
	assert_bool(mine._walk.is_empty()).is_false()   # walking there, nothing used yet
	assert_bool(await _until(func(): return mine.card_shown())).is_true()
	assert_float(P0FarmMaterials.flat(mine.actor.position, Layout.DOWN)).is_less_equal(mine.REACH)
	assert_array(_sent("mine_floor")).is_empty()   # the tap spent nothing
	assert_str(mine.card_entry().main_text()).is_equal("Floor 2 · 2 Energy")
	assert_bool(mine.card_entry()._title_row.visible).is_false()   # a ladder's card has no title
	# Kept off the player (不知火舞 on #190): clear of their box on screen by 4, unless already as high as it may go.
	await get_tree().process_frame
	var body: Rect2 = mine.actor.screen_box(mine.cam)
	var card := Rect2(mine.card_entry().position, mine.card_entry().size)
	assert_bool(not card.intersects(body.grow(3.9)) or is_equal_approx(card.position.y, rt.ui.card_top())).is_true()
	mine.p0_dev(PackedStringArray(["cardtap"]))
	assert_array(_sent("mine_floor")).is_equal([{"type": "mine_floor", "to": 2, "via": "ladder", "day": DAY}])   # with the day it was drawn for
	assert_bool(mine.card_shown()).is_false()

func test_pushing_the_stick_on_the_way_cancels() -> void:
	await _open(Fx.view(1, CLEAR))
	mine.p0_dev(PackedStringArray(["tapfac", "mine_down"]))
	await get_tree().process_frame
	mine.p0_joystick(Vector2(-1, 0))
	assert_bool(mine._walk.is_empty()).is_true()
	await get_tree().create_timer(0.2).timeout
	mine.p0_joystick(Vector2.ZERO)
	await get_tree().create_timer(1.5).timeout
	assert_bool(mine.card_shown()).is_false()
	assert_array(_sent("mine_floor")).is_empty()

## Grey with the reason (LOCK-10): while a monster stands the card's button says so and its press toasts it.
func test_a_standing_monster_greys_the_fee_button() -> void:
	await _open(Fx.view(1))
	mine.p0_dev(PackedStringArray(["tapfac", "mine_down"]))
	assert_bool(await _until(func(): return mine.card_shown())).is_true()
	assert_str(mine.card_entry().main_text()).is_equal("Floor 2 · Clear Floor 1 first")
	mine.p0_dev(PackedStringArray(["cardtap"]))
	assert_str(rt.ui.toast_text()).is_equal("Floor 2 · Clear Floor 1 first")
	assert_array(_sent("mine_floor")).is_empty()

## Short of Energy: amber with the whole line; its press opens the Energy card for this floor's fee.
func test_short_of_energy_the_card_opens_the_energy_card() -> void:
	await _open(Fx.view(1, CLEAR.merged({"energy": 1})))
	mine.p0_dev(PackedStringArray(["tapfac", "mine_down"]))
	assert_bool(await _until(func(): return mine.card_shown())).is_true()
	assert_str(mine.card_entry().main_text()).is_equal("Floor 2 · Need 2 Energy")
	assert_bool(mine.card_entry().is_amber()).is_true()
	mine.p0_dev(PackedStringArray(["cardtap"]))
	assert_str(rt.ui.modal_kind).is_equal("energy")
	assert_array(_sent("mine_floor")).is_empty()

## Free moves go at once on arrival, no card: a floor entered today, and the elevator's stop panel.
func test_free_moves_go_on_arrival() -> void:
	await _open(Fx.view(1, CLEAR.merged({"next": {"floor": 2, "paid": true, "fee": 0, "open": true, "locked": null}})))
	mine.p0_dev(PackedStringArray(["tapfac", "mine_down"]))
	assert_bool(await _until(func(): return not _sent("mine_floor").is_empty())).is_true()
	assert_array(_sent("mine_floor")).is_equal([{"type": "mine_floor", "to": 2, "via": "ladder", "day": DAY}])
	assert_bool(mine.card_shown()).is_false()
	mine.p0_dev(PackedStringArray(["tapfac", "mine_elevator"]))
	assert_bool(await _until(func(): return rt.ui.modal_kind == "elevator")).is_true()

## Floor 1's way up is the Entrance: out of the mine, nothing sent (the map's read takes the player out, §5 ⑪).
func test_the_entrance_walks_up_then_leaves() -> void:
	await _open(Fx.view(1))
	mine.p0_dev(PackedStringArray(["tapfac", "mine_up"]))
	assert_bool(await _until(func(): return mine._leaving)).is_true()
	assert_array(_sent("mine_floor")).is_empty()

## Only Floor 1 and the stops have the elevator; a quarry's last floor has no way down (contract-efg §4 ⑤, §7.1).
func test_which_floors_have_which_facilities() -> void:
	await _open(Fx.view(7, CLEAR))
	assert_array(mine._facilities.keys()).contains_exactly_in_any_order(["mine_up", "mine_down"])
	assert_str(str(mine._facilities.mine_up.kind)).is_equal("up")
	mine.queue_free()
	await get_tree().process_frame
	await _open(Fx.view(10, {"mobs": [], "rocks": 0, "station": true}), 10)
	assert_array(mine._facilities.keys()).contains_exactly_in_any_order(["mine_up", "mine_down", "mine_elevator"])
	mine.queue_free()
	await get_tree().process_frame
	await _open(Fx.view(25, CLEAR.merged({"next": null, "type": "quarry", "name": "Redstone Quarry"})), 25)
	assert_bool(mine._facilities.has("mine_down")).is_false()

## Their prompts: an icon button each within 8 m, the nearest one's strip (the copy is P0WorldPrompts.mine_facility's,
## tested in test_p0_material_logic; how they look is on the shots).
func test_the_facilities_wear_world_prompts() -> void:
	await _open(Fx.view(1, CLEAR))
	mine.actor.teleport(Layout.DOWN + Vector3(-0.8, 0, 0.8))
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
	await _open(Fx.view(1))
	var r: Rect2 = mine.actor.screen_box(mine.cam)
	var feet: Vector2 = mine.cam.unproject_position(mine.actor.position)
	var px_per_m: float = mine.get_viewport().get_visible_rect().size.x / mine.cam.size
	assert_float(r.end.y).is_equal_approx(feet.y, 0.5)
	assert_float(r.get_center().x).is_equal_approx(feet.x, 0.5)
	assert_float(r.size.x).is_equal_approx(2.0 * P0Actor.HALF_WIDTH_M * px_per_m, 1.0)
	var head: Vector2 = mine.cam.unproject_position(mine.actor.position + Vector3.UP * P0Actor.HEAD_M)
	assert_float(r.position.y).is_equal_approx(head.y, 8.0)   # the outfit's own top once drawn, else HEAD_M
	assert_float(r.size.y / px_per_m).is_between(0.8, 1.8)     # the figure's own height on screen, in metres across

## Joey 296 #16: a monster's hit that lands while another command is still on the wire (a swing, a rock, the 30 s read)
## was dropped — no hit sent, no HP gone. It queues now and goes behind that one; still one hit at a time.
func test_a_hit_while_a_command_is_on_the_wire_still_goes() -> void:
	await _open(Fx.view(3), 3)
	rt.session.send({"type": "mine_rock", "floor": 3, "rock": 0, "day": DAY})   # on the wire: this runtime never answers
	assert_bool(rt.session.busy).is_true()
	mine._on_contact(preload("res://modules/mining/p0_mine_combat.gd").mob_id(0))
	assert_array(_sent("mine_attack")).is_equal([{"type": "mine_attack", "floor": 3, "hurt_by": 0, "day": DAY}])   # queued behind it
	mine._on_contact(preload("res://modules/mining/p0_mine_combat.gd").mob_id(1))
	assert_int(_sent("mine_attack").size()).is_equal(1)   # one hit at a time: the next waits for its settle
