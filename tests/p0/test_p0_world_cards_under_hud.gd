extends GdUnitTestSuite
## World cards a tap opens stay under the HUD (李元芳, 0.2.1 smoke d83191bb): with a run open the mine mouth's EntryCard
## is four rows tall, and on a short screen it rose over the location chip; the card is passive, so `Continue run · Free`
## went to the chip and opened the map. The mine mouth's, a floor's and a trap's cards are placed by P0Ui.place_card inside
## card_area(): under the HUD, above the quick bar. Headless runs at the project's 360 × 640.

const STORE := "user://test_p0_world_cards_under_hud.json"
const GATE := Vector2(120, 232)   # the mouth's gate in the reported shot, 360 × 640

var rt: P0Runtime

func before_test() -> void:
	UiCommandButton.offline = false
	P0Runtime.free_instance_for_tests()
	rt = P0Runtime.ensure()
	rt.ui.quick_store = STORE
	rt.session.transport = func(_m, _p, _b, _c): pass
	await get_tree().process_frame   # ensure() adds it deferred
	await get_tree().process_frame   # the HUD lays out

func after_test() -> void:
	P0Runtime.free_instance_for_tests()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	await get_tree().process_frame

## A tall card: four rows, as the farm's old mine mouth card had with a run open.
func _mouth_card() -> UiEntryCard:
	var e := UiEntryCard.new()
	e.theme = UiKit.theme()
	e.passive = true
	rt.ui.root.add_child(e)
	e.title = "The mine"
	e.title_fact = "Runs today 1/2"
	e.action = "Continue run · Free"
	e.second = "New run · 2 Energy"
	e.third = "Floor 5 · Express · Free"
	e.note = "Current run will end · Runs today 1/2"
	return e

func _hud() -> Rect2:
	return Rect2(0, 0, rt.ui.root.size.x, UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + rt.ui.safe_top())

func _old_place(card: UiEntryCard, point: Vector2) -> Rect2:   # before: anywhere on the screen
	return WorldAnchor.place(card.get_combined_minimum_size(), point - Vector2(0, UiTokens.SPACE_WITHIN),
		Rect2(Vector2.ZERO, rt.ui.root.size), UiTokens.SPACE_WITHIN, true)

func test_a_tall_card_over_a_high_gate_stays_under_the_hud() -> void:
	var card := _mouth_card()
	assert_bool(_old_place(card, GATE).intersects(_hud())).is_true()   # the case: over the HUD's rows
	rt.ui.place_card(card, GATE, Rect2(), P0FarmMaterials.BODY_GAP)
	var r := Rect2(card.position, card.size)
	assert_float(r.position.y).is_equal_approx(rt.ui.card_top(), 0.01)   # 8 under the HUD, as when lifted off the player
	assert_bool(r.intersects(_hud())).is_false()
	assert_bool(rt.ui.open_marker_area().encloses(r)).is_true()
	# so its button takes the tap: under it there is no HUD chip, and the card resolves it
	assert_bool(_hud().has_point(card.main_rect().get_center() - rt.ui.root.global_position)).is_false()
	assert_str(card.tap_at(card.main_rect().get_center())).is_equal("main")

## Low on the screen it keeps off the quick bar the same way (a passive card over a slot lost its taps to the slot).
func test_a_card_over_a_low_anchor_stays_above_the_quick_bar() -> void:
	var card := _mouth_card()
	var low := Vector2(180, 620)
	rt.ui.place_card(card, low, Rect2(), P0FarmMaterials.BODY_GAP)
	var r := Rect2(card.position, card.size)
	assert_float(r.end.y).is_less_equal(rt.ui.open_marker_area().end.y - UiTokens.SPACE_WITHIN + 0.01)
	assert_bool(rt.ui.open_marker_area().encloses(r)).is_true()

## Where it fits, it sits exactly where it did: the pointer's tip SPACE_WITHIN over the gate.
func test_a_card_that_fits_is_placed_as_before() -> void:
	var card := _mouth_card()
	var mid := Vector2(180, 420)
	var before := _old_place(card, mid)
	rt.ui.place_card(card, mid, Rect2(), P0FarmMaterials.BODY_GAP)
	assert_vector(card.position).is_equal_approx(before.position, Vector2.ONE * 0.01)
	assert_vector(card.size).is_equal(card.get_combined_minimum_size())

## Lifted off the player (不知火舞 on #190) it still never goes above card_top.
func test_lifted_off_the_player_it_stops_under_the_hud() -> void:
	var card := _mouth_card()
	var body := Rect2(150, 200, 40, 120)   # the player just under the gate
	rt.ui.place_card(card, Vector2(170, 330), body, P0FarmMaterials.BODY_GAP)
	assert_float(card.position.y).is_greater_equal(rt.ui.card_top() - 0.01)
	assert_bool(Rect2(card.position, card.size).intersects(_hud())).is_false()
