extends GdUnitTestSuite
## P0Ui's world prompt entries (SGODOT-250): world_icon / name_bar / npc_tag, the way rooms and the farm put them up.

const STORE := "user://test_p0_world_prompts.json"
const HOME := preload("res://assets/p0/icons/home.svg")

var ui: P0Ui

func _view() -> Dictionary:
	return {"energy": {"value": 200, "max": 200, "next_in": null, "regen_ms": 240000}, "coins": 40, "skills": {},
		"bag": {"capacity": 25, "free": 24, "slots": [{"id": "seed_radish", "qty": 20}]}, "plots": [],
		"names": {"seed_radish": "Radish Seeds"}, "crops": [{"id": "crop_radish", "seed": "seed_radish", "energy": 2}],
		"rest": {"used": 0, "limit": 1, "resets_in": 3600000}}

func before_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	ui = P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	ui.layer = 128
	await await_idle_frame()
	ui.set_mode("farm")
	ui.set_surface("farm")
	ui.set_view(_view())
	await await_idle_frame()

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func _mid() -> Vector2:
	var a := ui._marker_area()
	return Vector2(a.position.x + a.size.x * 0.4, a.get_center().y)

func test_an_icon_button_tap_is_its_facilitys_tap() -> void:
	var at := _mid()
	ui.world_icon("stall", HOME, at, true, false, -1, at + Vector2(0, 30))
	var b: UiWorldIconButton = ui._icons.stall
	assert_bool(b.visible).is_true()
	var taps := []
	var cards := []
	ui.tapped.connect(func(p): taps.append(p); cards.append(ui.tapped_card))
	assert_bool(ui._tap_at(b.hit_rect().get_center() + Vector2(18, 0), false)).is_true()   # inside the 44 area, off the 28 disc
	assert_array(taps).is_equal([at + Vector2(0, 30)])
	assert_array(cards).is_equal(["stall"])

func test_the_open_name_bar_stands_in_for_its_button_and_folds_back() -> void:
	var at := _mid()
	ui.world_icon("home", HOME, at, true)
	ui.name_bar("home", HOME, "Farmhouse", "", at, true)
	var bar: UiWorldNameBar = ui._name_bars.home
	assert_bool(bar.visible).is_true()
	assert_bool(ui._icons.home.visible).is_false()
	await get_tree().create_timer(0.25).timeout
	assert_bool(bar.is_expanded()).is_true()
	var taps := []
	ui.tapped.connect(func(p): taps.append(ui.tapped_card))
	assert_bool(ui._tap_at(bar.hit_rect().get_center(), false)).is_true()
	assert_array(taps).is_equal(["home"])
	ui.world_icon("home", HOME, at, true)   # another facility is nearest now: this one folds back to its button
	assert_bool(ui._icons.home.visible).is_false()   # not until the strip has folded
	await get_tree().create_timer(0.3).timeout
	assert_bool(bar.visible).is_false()
	ui.world_icon("home", HOME, at, true)
	assert_bool(ui._icons.home.visible).is_true()

func test_the_name_bar_flips_at_the_screen_edge() -> void:
	var a := ui._marker_area()
	var right_edge := Vector2(a.end.x - 30, a.get_center().y)
	ui.name_bar("stall", HOME, "Homestead Stall", "", right_edge, true)
	assert_int(ui._name_bars.stall.side).is_equal(UiWorldNameBar.Dir.LEFT)
	var left_edge := Vector2(a.position.x + 30, a.get_center().y)
	ui.name_bar("plaque", HOME, "Upgrade Plaque", "", left_edge, true, UiWorldNameBar.Dir.LEFT)
	assert_int(ui._name_bars.plaque.side).is_equal(UiWorldNameBar.Dir.RIGHT)

func test_prompts_hide_under_a_drawer_and_outside_the_band() -> void:
	var at := _mid()
	ui.world_icon("stall", HOME, at, true)
	ui.npc_tag("ama", "Ama", at + Vector2(0, -40), true, true)
	assert_bool(ui._npc_tags.ama.visible).is_true()
	assert_bool(ui._npc_tags.ama.highlight).is_true()
	ui.open_inbox()
	ui.world_icon("stall", HOME, at, true)
	ui.npc_tag("ama", "Ama", at + Vector2(0, -40), true)
	assert_bool(ui._icons.stall.visible).is_false()
	assert_bool(ui._npc_tags.ama.visible).is_false()
	ui.close_modal()
	ui.world_icon("stall", HOME, Vector2(at.x, 4), true)   # up under the HUD
	assert_bool(ui._icons.stall.visible).is_false()

func test_the_open_name_bar_draws_over_badges_and_icon_buttons() -> void:
	# 哪吒 in the farmhouse: the stove's badge sat on the warming cabinet's card. The open strip goes on top.
	var at := _mid()
	ui.name_bar("cabinet", HOME, "Warming Cabinet", "", at, true)
	ui.badge("stove", UiStatusBadge.State.READY, at + Vector2(10, 0), true)
	ui.world_icon("stall", HOME, at + Vector2(-20, 0), true)
	ui.name_bar("cabinet", HOME, "Warming Cabinet", "", at, true)   # the next frame
	var bar: Control = ui._name_bars.cabinet
	assert_int(bar.get_index()).is_greater(ui._badges.stove.get_index())
	assert_int(bar.get_index()).is_greater(ui._icons.stall.get_index())
	assert_object(ui._bar.get_parent()).is_same(bar.get_parent())
	assert_int(bar.get_index()).is_less(ui._bar.get_index())   # still under the quick bar and the rest of the UI


## #57 (不知火舞): an open strip over an NPC's name tag opens the other way when that side is clear.
func test_a_strip_over_a_name_tag_opens_the_other_way() -> void:
	var at := _mid()
	ui.npc_tag("ama", "Ama", at + Vector2(70, 10), true)
	ui.name_bar("stall", HOME, "Homestead Stall", "", at, true, UiWorldNameBar.Dir.RIGHT)
	assert_int(ui._name_bars.stall.side).is_equal(UiWorldNameBar.Dir.LEFT)
	ui.name_bar("cabinet", HOME, "Warming Cabinet", "", at + Vector2(0, 120), true, UiWorldNameBar.Dir.RIGHT)
	assert_int(ui._name_bars.cabinet.side).is_equal(UiWorldNameBar.Dir.RIGHT)   # nothing in the way

## #57: covered on both sides, the tag under the strip fades while it is open and comes back once it folds.
func test_a_name_tag_the_strip_covers_fades_until_it_folds() -> void:
	var at := _mid()
	var tags := func():
		ui.npc_tag("ama", "Ama", at + Vector2(60, 10), true)
		ui.npc_tag("pip", "Pip", at + Vector2(-60, 10), true)
	tags.call()
	ui.name_bar("stall", HOME, "Homestead Stall", "", at, true, UiWorldNameBar.Dir.RIGHT)
	assert_int(ui._name_bars.stall.side).is_equal(UiWorldNameBar.Dir.RIGHT)   # both sides covered: keeps its side
	tags.call()
	await get_tree().create_timer(0.2).timeout
	assert_float(ui._npc_tags.ama.modulate.a).is_equal_approx(0.0, 0.01)
	assert_float(ui._npc_tags.pip.modulate.a).is_equal_approx(1.0, 0.01)
	ui.world_icon("stall", HOME, at, true)   # another facility is nearest: the strip folds
	await get_tree().create_timer(0.3).timeout
	tags.call()
	await get_tree().create_timer(0.2).timeout
	assert_float(ui._npc_tags.ama.modulate.a).is_equal_approx(1.0, 0.01)

## #57 / NPC-G1: in the greeting card or the dialogue bar the speaker's tag stays, highlighted, over the veil; other
## tags and icon buttons hide; under any other card or drawer every tag hides.
func test_the_speakers_tag_stays_over_the_conversation() -> void:
	var at := _mid()
	var frame := func(talking: bool):
		ui.npc_tag("ama", "Ama", at, true, false, talking)
		ui.npc_tag("pip", "Pip", at + Vector2(90, 0), true)
		ui.world_icon("seat", HOME, at + Vector2(0, 80), true, true)
	frame.call(false)
	ui._open_modal(Control.new())   # the keeper greeting card (2A, #56) as P0Ui opens it
	ui.modal_kind = "greeting"
	frame.call(true)
	var ama: UiNpcNameTag = ui._npc_tags.ama
	assert_bool(ama.visible).is_true()
	assert_bool(ama.highlight).is_true()
	assert_object(ama.get_parent()).is_same(ui.root)
	assert_int(ama.get_index()).is_greater(ui._modal.get_index())   # over the card's veil
	assert_bool(ui._npc_tags.pip.visible).is_false()
	assert_bool(ui._icons.seat.visible).is_false()
	ui.close_modal()
	ui.open_inbox()
	frame.call(true)
	assert_bool(ama.visible).is_false()
	ui.close_modal()
	frame.call(false)
	assert_bool(ama.visible).is_true()
	assert_bool(ama.highlight).is_false()
	assert_object(ama.get_parent()).is_same(ui._kit)
