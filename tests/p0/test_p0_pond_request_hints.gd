extends GdUnitTestSuite
## A pond wearing the Request ! says why and how far along it is (q(103), SGODOT-268; 不知火舞's spec on 268): an Info
## toast on arrival after the TipCard, `Pond Catch 1/2` under `Pond Crucian ×1` while the catch is short, and on the
## catch that completes it only a Success toast `Pond Catch · 2/2 · Deliver at the Stall`, after the Caught! card.

const P0Pond := preload("res://scenes/p0/p0_pond.gd")
const STORE := "user://test_p0_pond_request_hints.json"

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func _ui() -> P0Ui:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	return ui

func _floats(ui: P0Ui) -> Array:
	return ui.root.get_children().filter(func(c): return c is UiFloatText and not c.is_queued_for_deletion())

const STALL := {"id": "req_pond_catch", "title": "Pond Catch", "qty": 2, "deliver": "Deliver at the Stall"}

func test_the_catch_floats_its_progress_then_completes_with_a_toast() -> void:
	assert_dict(P0Pond.request_progress(STALL.merged({"have": 1}), 0)).is_equal({"float": "Pond Catch 1/2"})
	assert_dict(P0Pond.request_progress(STALL.merged({"have": 2}), 1)).is_equal({"toast": "Pond Catch · 2/2 · Deliver at the Stall"})
	# A resident's and a market request say where they are handed in.
	var kai := {"title": "Old Kai's Catch", "qty": 3, "have": 3, "deliver": "Deliver to Old Kai"}
	assert_dict(P0Pond.request_progress(kai, 2)).is_equal({"toast": "Old Kai's Catch · 3/3 · Deliver to Old Kai"})

func test_nothing_for_a_fish_it_does_not_take_or_past_the_count() -> void:
	assert_dict(P0Pond.request_progress(STALL.merged({"have": 1}), 1)).is_empty()   # a carp: the count did not move
	assert_dict(P0Pond.request_progress(STALL.merged({"have": 3}), 2)).is_empty()   # already complete before
	assert_dict(P0Pond.request_progress({}, 0)).is_empty()                         # handed in or dropped meanwhile

## 不知火舞: the progress line sits right under the fish line, ink (ITEM) with no icon; three lines at most still holds.
func test_the_progress_line_sits_under_the_fish_line() -> void:
	var ui := _ui()
	await get_tree().process_frame
	ui.queue_floats([{kind = "request", key = "request:req_pond_catch", text = "Pond Catch 1/2", tone = UiFloatText.Tone.ITEM}],
		Vector2(180, 400))
	ui.queue_floats([{kind = "xp", key = "%s XP", amount = 5, fmt = "%s XP", tone = UiFloatText.Tone.XP},
		{kind = "item", key = "catch:fish_crucian", text = "Pond Crucian ×1", tone = UiFloatText.Tone.ITEM,
			icon = P0Logic.icon("fish_crucian")}], Vector2(180, 400))
	await get_tree().process_frame
	var fl := _floats(ui)
	assert_array(fl.map(func(f): return f.text)).is_equal(["+5 XP", "Pond Crucian ×1", "Pond Catch 1/2"])
	assert_int(fl[2].tone).is_equal(UiFloatText.Tone.ITEM)
	assert_object(fl[2].icon).is_null()

## The arrival toast waits for a TipCard on screen or in line (q(49)).
func test_tip_pending_while_a_tip_is_up_or_waits() -> void:
	var ui := _ui()
	await get_tree().process_frame
	ui.tips = P0Guide.TipQueue.new({})   # nothing taught before (the real store may remember this machine's runs)
	assert_bool(ui.tip_pending()).is_false()
	ui.teach("map")
	assert_bool(ui.tip_pending()).is_true()   # waiting its turn, then on screen
	await get_tree().process_frame
	assert_bool(ui.tip_pending()).is_true()
	ui._hide_tip()
	assert_bool(ui.tip_pending()).is_false()

## The completion toast waits for the Caught! card of the same catch, then shows as a Success toast.
func test_the_completion_toast_waits_for_the_card_and_is_a_success() -> void:
	var ui := _ui()
	await get_tree().process_frame
	var card := Control.new()
	card.custom_minimum_size = Vector2(200, 80)
	ui.show_moment(card, false)
	ui.toast_success_when_clear("Pond Catch · 2/2 · Deliver at the Stall")
	assert_str(ui.toast_text()).is_empty()
	ui.close_modal()
	assert_str(ui.toast_text()).is_equal("Pond Catch · 2/2 · Deliver at the Stall")
	assert_int(ui._toasts.current_severity()).is_equal(ToastLayer.Severity.SUCCESS)
	ui.toast_when_clear("Worm Bait · all used")   # the plain held toast stays an Info one
	assert_int(ui._toasts.current_severity()).is_equal(ToastLayer.Severity.INFO)

## 不知火舞 on #188: two lines break at a " · " (the dot dropped), a text that fits stays one line, and only callers
## that ask for it (the pond's two toasts) do this; the toast still wraps by words otherwise.
func test_two_lines_break_at_a_dot() -> void:
	var ui := _ui()
	await get_tree().process_frame
	ui.toast("Pond Catch · Pond Crucian 0/2", 0.0, true)
	assert_str(ui.toast_text()).is_equal("Pond Catch\nPond Crucian 0/2")
	ui.toast_success("Pond Catch · 2/2 · Deliver at the Stall", true)
	assert_str(ui.toast_text()).is_equal("Pond Catch · 2/2\nDeliver at the Stall")
	ui.toast("Line in · Energy back", 0.0, true)
	assert_str(ui.toast_text()).is_equal("Line in · Energy back")
	ui.toast("Pond Catch · Pond Crucian 1/2")
	assert_str(ui.toast_text()).is_equal("Pond Catch · Pond Crucian 1/2")
	var card := Control.new()
	ui.show_moment(card, false)
	ui.toast_success_when_clear("Pond Catch · 2/2 · Deliver at the Stall", true)
	ui.close_modal()
	assert_str(ui.toast_text()).is_equal("Pond Catch · 2/2\nDeliver at the Stall")
