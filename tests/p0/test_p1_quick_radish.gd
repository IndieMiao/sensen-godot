extends GdUnitTestSuite
## q(217) (SGODOT-343): Quick Radish Seeds, the first session's teaching seed — the bar's first slot, `Quick Radish` on a
## quick slot, a countdown in m:ss on the key and in Today, `Ready in 45s` on its card, harvested as a Radish.

const QUICK := {"id": "crop_quick_radish", "seed": "seed_quick_radish", "energy": 2, "grow_s": 45, "harvest": "crop_radish"}

func _view(plots: Array = []) -> Dictionary:
	return {
		"energy": {"value": 196, "max": 200},
		"names": {"seed_quick_radish": "Quick Radish Seeds", "crop_quick_radish": "Quick Radish", "seed_radish": "Radish Seeds",
			"crop_radish": "Radish", "seed_lettuce": "Lettuce Seeds", "crop_lettuce": "Lettuce", "fert_compost": "Compost"},
		"items": {"seed_quick_radish": {"name": "Quick Radish Seeds", "kind": "seed", "sell": null},
			"seed_radish": {"name": "Radish Seeds", "kind": "seed", "sell": null}},
		"crops": [{"id": "crop_radish", "seed": "seed_radish", "energy": 2, "grow_h": 4, "level": 1},
			{"id": "crop_lettuce", "seed": "seed_lettuce", "energy": 2, "grow_h": 8, "level": 1}],
		"quick_seeds": [QUICK],
		"bag": {"capacity": 25, "slots": [{"id": "seed_quick_radish", "qty": 2}, {"id": "seed_radish", "qty": 20},
			{"id": "seed_lettuce", "qty": 10}]},
		"plots": plots,
		"skills": {"farming": {"level": 1, "xp": 0, "next": 50}},
		"firsts": [],
	}

func _growing(id: int, ms: float, crop := "crop_quick_radish") -> Dictionary:
	return {"id": id, "state": "growing", "crop": crop, "ready_in": ms, "xp_pct": 100, "fert": false}

## ② The start bag's three stacks on the bar: Quick Radish first (P0Ui picks the first stocked slot), then by count.
func test_the_teaching_seed_takes_the_bars_first_slot() -> void:
	assert_array(P0Logic.quick_bar(_view(), [])).is_equal(["seed_quick_radish", "seed_radish", "seed_lettuce"])
	# a slot the player put somewhere stays there
	assert_array(P0Logic.quick_bar(_view(), ["seed_radish"])).is_equal(["seed_radish", "seed_quick_radish", "seed_lettuce"])

## Its name, Energy and grow time come from view.quick_seeds; it is never one of view.crops' lists.
func test_it_is_looked_up_by_seed_and_by_plot_crop() -> void:
	var v := _view()
	assert_int(int(P0Logic.crop_for_seed(v, "seed_quick_radish").energy)).is_equal(2)
	assert_str(str(P0Logic.crop(v, "crop_quick_radish").harvest)).is_equal("crop_radish")
	assert_dict(P0Logic.crop(v, "seed_quick_radish")).is_empty()   # a seed is not a crop
	assert_str(P0Logic.harvest_of(v, "crop_quick_radish")).is_equal("crop_radish")
	assert_str(P0Logic.harvest_of(v, "crop_lettuce")).is_equal("crop_lettuce")
	assert_str(P0Logic.harvest_of(v, "")).is_equal("")   # a plot with nothing in it
	assert_dict(P0Logic.crop(v, "")).is_empty()
	assert_str(P0Logic.unlock_line(v, "farming", 1)).not_contains("Quick")

## ④ The key on a growing Quick Radish ticks in m:ss; other crops keep q(97) ②'s minutes.
func test_the_key_counts_down_in_minutes_and_seconds() -> void:
	var v := _view([_growing(0, 45000.0), _growing(1, 4 * 3600000.0 - 120000.0, "crop_radish")])
	var a := P0Logic.main_action(v, v.plots[0], "seed_quick_radish")
	assert_str(str(a.verb)).is_equal("Growing")
	assert_str(str(a.sub)).is_equal("Ready in 0:45")
	assert_str(str(P0Logic.main_action(v, _growing(0, 1500.0), "").sub)).is_equal("Ready in 0:02")
	assert_str(str(P0Logic.main_action(v, v.plots[1], "").sub)).is_equal("3h 58m")
	# the view ages it on the client clock: 30 s later
	assert_str(str(P0Logic.main_action(P0Logic.project(v, 30000.0), P0Logic.project(v, 30000.0).plots[0], "").sub)).is_equal("Ready in 0:15")

## ④ The one-line farm status (P0Logic.today_line, the profile's farm line): the Quick Radishes' countdown in m:ss. Today
## has no crop rows any more (A 包 spec ①).
func test_the_farm_line_says_quick_radishes_ready_in_m_ss() -> void:
	assert_str(P0Logic.today_line(_view([_growing(0, 45000.0)]))).is_equal("Quick Radishes ready in 0:45")
	var two := _view([_growing(0, 45000.0), _growing(1, 43000.0)])
	assert_bool(P0Logic.today_rows(two).any(func(r): return str(r.line).begins_with("Quick"))).is_false()

## ① No Compost on it: with Compost selected the key goes by the plot's state (Water, Growing), nothing about Compost.
func test_compost_does_not_take_a_quick_radish() -> void:
	var v := _view()
	var sown := {"id": 0, "state": "sown", "crop": "crop_quick_radish", "fert": false}
	assert_str(str(P0Logic.main_action(v, sown, "fert_compost").verb)).is_equal("Water")
	assert_str(str(P0Logic.main_action(v, _growing(0, 30000.0), "fert_compost").verb)).is_equal("Growing")
	assert_str(str(P0Logic.main_action(v, _growing(0, 3600000.0, "crop_radish"), "fert_compost").verb)).is_equal("Fertilize")

## Sowing it costs its 2 Energy.
func test_sowing_it_is_2_energy() -> void:
	var a := P0Logic.main_action(_view(), {"id": 3, "state": "tilled"}, "seed_quick_radish")
	assert_str(str(a.verb)).is_equal("Sow ×1")
	assert_str(str(a.sub)).is_equal("2 Energy")
	assert_dict(a.cmd).is_equal({"type": "sow", "plot": 3, "seed": "seed_quick_radish"})

## ④ The card's fact is a static `Ready in 45s`, not m:ss.
func test_the_card_says_ready_in_45s() -> void:
	var v := _view()
	v["storage"] = {}
	v["residents"] = []
	for slot in v.bag.slots: slot["locked"] = false
	assert_array(P0ItemInfo.spec(v, "seed_quick_radish", &"bag", {place = "home"}).facts).is_equal(["2 Energy per plot · Ready in 45s"])
	assert_str(P0ItemInfo.grow_time({"grow_h": 4})).is_equal("4h")

## Short name (不知火舞 340 c4a3b888): only on a quick slot, only when the name breaks into more than two lines, only the
## last `Seeds` / `Seed`; every seed name of the content stays as it is.
func test_a_quick_slot_drops_seeds_only_past_two_lines() -> void:
	assert_int(UiItemCell.quick_lines("Quick Radish Seeds")).is_greater(2)
	assert_str(UiItemCell.quick_name("Quick Radish Seeds")).is_equal("Quick Radish")
	assert_int(UiItemCell.quick_lines("Quick Radish")).is_less_equal(2)
	assert_str(UiItemCell.quick_name("Radish Seeds")).is_equal("Radish Seeds")
	# of the content's seeds only Sweet Potato Seeds also takes three lines (its third was cut before): `Sweet Potato`
	for c in P0Logic.content().get("crops", []):
		var name := str(c.get("seed_name", ""))
		var shown := "Sweet Potato" if name == "Sweet Potato Seeds" else name
		assert_str(UiItemCell.quick_name(name)).override_failure_message(name).is_equal(shown)

## A Quick Radish's harvest flies as the Radish the reply put in the bag (the row's crop_of is what each plot gives).
func test_the_harvest_flight_is_a_radish() -> void:
	var farm: GDScript = load("res://scenes/p0/p0_farm.gd")
	var v := _view()
	var crop_of := {0: P0Logic.harvest_of(v, "crop_quick_radish"), 1: P0Logic.harvest_of(v, "crop_quick_radish")}
	assert_array(farm.row_flights([0, 1], crop_of, [{"kind": "item", "id": "crop_radish", "delta": 2}])).is_equal([["crop_radish", 2, 0]])
	assert_str(str(P0Garden.CROP_CODES.get("crop_quick_radish", ""))).is_equal("R")

## The growth stages run over 45 s, not the default 4 h.
func test_the_field_grows_it_over_45_seconds() -> void:
	var cells := P0Garden.cells(_view([_growing(0, 15000.0)]), 1000000)
	var slot: Dictionary = cells[P0Garden.cell_id(P0Garden.cell_of(0))]
	assert_int(int(slot.ready_at) - int(slot.watered_at)).is_equal(45000)
