extends GdUnitTestSuite
## A pond wearing the Request ! says why (q(103), SGODOT-268; 不知火舞's spec on 268): an Info toast on arrival after the
## TipCard. How far along a request is comes from the server for every taken request (q(134)): `Pond Catch 1/2` over
## `Pond Crucian ×1` while it is short, and on the one that fills it a two-line Success toast, `Pond Catch · 2/2` /
## `Deliver at the Stall`, after the Caught! card and any TipCard.

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

## q(134): the server says which taken request grew; the runtime puts it in words — the count while it is short, the
## two-line Success toast on the one that fills it, each request's own `deliver`.
func _view() -> Dictionary:
	return {"names": {"fish_crucian": "Pond Crucian", "crop_carrot": "Carrot", "crop_radish": "Radish"},
		"boards": {"stall": {"slots": [{"id": "req_pond_catch", "title": "Pond Catch", "kind": "fish", "items": ["fish_crucian"],
			"qty": 2, "have": 1, "status": "accepted"}]},
			"market": {"slots": [{"id": "basket", "title": "Market Basket", "kind": "crop", "items": ["crop_carrot", "crop_radish"],
				"qty": 6, "have": 2, "status": "accepted"}]}}}

func test_progress_reads_the_count_then_the_two_line_toast() -> void:
	var v := _view()
	assert_dict(P0Runtime.progress_said(v, {"kind": "request_progress", "id": "req_pond_catch", "have": 1, "qty": 2})) \
		.is_equal({"float": "Pond Catch 1/2"})
	assert_dict(P0Runtime.progress_said(v, {"kind": "request_progress", "id": "req_pond_catch", "have": 2, "qty": 2, "done": true})) \
		.is_equal({"toast": "Pond Catch · 2/2\nDeliver at the Stall"})
	# a basket says the item that grew; full, where it is handed in
	assert_dict(P0Runtime.progress_said(v, {"kind": "request_progress", "id": "basket", "item": "crop_carrot", "have": 5, "qty": 6})) \
		.is_equal({"float": "Market Basket · Carrot 5/6"})
	assert_dict(P0Runtime.progress_said(v, {"kind": "request_progress", "id": "basket", "have": 6, "qty": 6, "done": true})) \
		.is_equal({"toast": "Market Basket · 6/6\nDeliver at Mission Market Square"})
	assert_dict(P0Runtime.progress_said(v, {"kind": "request_progress", "id": "gone", "have": 1, "qty": 2})).is_empty()   # handed in meanwhile

## A resident's sow request counts plots (`Five Little Plots · Plots 3/5`) and is handed in to them.
func test_a_residents_plots_and_their_name() -> void:
	var rid := ""
	var q := {}
	var residents: Dictionary = P0Logic.content().get("residents", {})
	for id in residents:
		for r in residents[id].get("requests", []):
			if str(r.get("need", {}).get("kind", "")) == "sow" and q.is_empty():
				rid = str(id)
				q = r
	assert_bool(q.is_empty()).is_false()
	var v := {"names": {}, "residents": {rid: {"request_state": "accepted",
		"request": {"id": str(q.id), "kind": "sow", "have": 3, "qty": int(q.qty)}}}}
	assert_dict(P0Runtime.progress_said(v, {"kind": "request_progress", "id": str(q.id), "have": 3, "qty": int(q.qty)})) \
		.is_equal({"float": "%s · Plots 3/%d" % [str(q.title), int(q.qty)]})
	assert_str(str(P0Runtime.progress_said(v, {"kind": "request_progress", "id": str(q.id), "have": int(q.qty), "qty": int(q.qty),
		"done": true}).toast)).ends_with("\nDeliver to %s" % P0Logic.PinReason.resident_name(rid))

## Two requests moved by one reply: a line each, over the items (q(134) ④), still within three lines.
func test_two_requests_take_a_line_each() -> void:
	var ui := _ui()
	await get_tree().process_frame
	ui.queue_floats([{kind = "item", key = "catch:fish_crucian", text = "Pond Crucian ×1", tone = UiFloatText.Tone.ITEM},
		{kind = "request", key = "request:a:", text = "Pond Catch 1/2", tone = UiFloatText.Tone.ITEM},
		{kind = "request", key = "request:b:", text = "Dusk Haul 2/4", tone = UiFloatText.Tone.ITEM}], Vector2(180, 400))
	await get_tree().process_frame
	assert_array(_floats(ui).map(func(f): return f.text)).is_equal(["Pond Crucian ×1", "Pond Catch 1/2", "Dusk Haul 2/4"])

## The filled request's toast waits for a TipCard on screen and comes when it closes (q(134) ⑤).
func test_the_filled_toast_waits_for_a_tip_on_screen() -> void:
	var ui := _ui()
	await get_tree().process_frame
	ui.tips = P0Guide.TipQueue.new({})
	ui.teach("map")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(ui._teach != null and ui._teach.visible).is_true()
	ui.toast_success_when_clear("Pond Catch · 2/2\nDeliver at the Stall", false, true)
	assert_str(ui.toast_text()).is_empty()
	ui._hide_tip()
	await get_tree().process_frame
	assert_str(ui.toast_text()).is_equal("Pond Catch · 2/2\nDeliver at the Stall")
	assert_int(ui._toasts.current_severity()).is_equal(ToastLayer.Severity.SUCCESS)

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

## The width the dot break measures against is the toast label's real one (哪吒 on #188): a change in ToastLayer's
## layout fails here instead of breaking the pond's toasts quietly.
func test_the_measured_width_is_the_toast_labels() -> void:
	var ui := _ui()
	await get_tree().process_frame
	ui.toast("Pond Catch · Pond Crucian 0/2", 0.0, true)
	await get_tree().process_frame
	await get_tree().process_frame
	var label: Label = ui._toasts._label
	assert_float(label.size.x).is_equal_approx(ui.toast_text_width(), 1.0)

# ---------------------------------------------------------------- the filled toast's turn (q(134) ⑤; 周瑜 on #302)
const DONE := {"kind": "request_progress", "id": "req_pond_catch", "have": 2, "qty": 2, "done": true}
const SAID := "Pond Catch · 2/2\nDeliver at the Stall"

class LandingWorld extends Node:   # a world that shows a landed fish itself (the pond's p0_event)
	func p0_event(_ev: Dictionary, _v: Dictionary) -> bool: return true

func _rt() -> P0Runtime:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	return rt

func _rt_view() -> Dictionary:
	return _view().merged({"energy": {"value": 140, "max": 200}, "coins": 52, "bag": {"capacity": 25, "free": 23,
		"slots": [{"id": "fish_crucian", "qty": 2}]}, "skills": {"fishing": {"level": 5}}, "items": {"fish_crucian": {"rarity": 1}},
		"fishing": {"dex": [{"id": "fish_crucian", "caught": 1}]}})

## Anything but a catch: the toast after REQUEST_TOAST_AFTER_S (a level-up's banner comes deferred), not at once.
func test_a_filled_request_toasts_after_the_reply() -> void:
	var rt := _rt()
	await get_tree().process_frame
	var v := _rt_view()
	rt.session.view = v
	rt.ui.set_view(v)
	rt._on_state(v, [{"kind": "item", "id": "fish_crucian", "delta": 1}, DONE])
	await get_tree().process_frame
	assert_str(rt.ui.toast_text()).is_empty()
	await get_tree().create_timer(P0Runtime.REQUEST_TOAST_AFTER_S + 0.1).timeout
	assert_str(rt.ui.toast_text()).is_equal(SAID)

## A landed fish the world shows: the toast is held with its floats for the pond's settle (after the Caught! card), and
## a world left before the fish reached the hand still says it.
func test_a_landed_fish_holds_its_toast_for_the_pond() -> void:
	var rt := _rt()
	await get_tree().process_frame
	var v := _rt_view()
	rt.session.view = v
	rt.ui.set_view(v)
	rt.world = auto_free(LandingWorld.new())
	rt._on_state(v, [{"kind": "item", "id": "fish_crucian", "delta": 1},
		{"kind": "catch", "fish": "fish_crucian", "rarity": 1, "result": "landed", "refund": 0}, DONE])
	await get_tree().create_timer(P0Runtime.REQUEST_TOAST_AFTER_S + 0.1).timeout
	assert_str(rt.ui.toast_text()).is_empty()   # not before the fish is in the hand
	assert_str(rt.catch_toast).is_equal(SAID)
	rt.attach(auto_free(Node.new()))   # left mid-arc
	assert_str(rt.catch_toast).is_empty()
	assert_str(rt.ui.toast_text()).is_equal(SAID)

## A trap that fills it: after its In your trap! card, not before.
func test_a_trap_toasts_after_its_card() -> void:
	var rt := _rt()
	await get_tree().process_frame
	var v := _rt_view()
	rt.session.view = v
	rt.ui.set_view(v)
	rt._on_state(v, [{"kind": "item", "id": "fish_crucian", "delta": 1}, {"kind": "xp", "skill": "fishing", "amount": 2, "percent": 100},
		{"kind": "first", "what": "catch:fish_crucian", "xp": 15}, {"kind": "xp", "skill": "fishing", "amount": 15, "percent": 100},
		{"kind": "trap", "action": "collected", "place": "pond_san_francisco_03", "fish": 1, "left": 0}, DONE])
	await get_tree().create_timer(P0Runtime.REQUEST_TOAST_AFTER_S + 0.1).timeout
	assert_str(rt.ui.toast_text()).is_empty()   # the card's timer has not run yet
	for i in 40:
		if rt.ui.has_modal(): break
		await get_tree().create_timer(0.05).timeout
	assert_bool(rt.ui.has_modal()).is_true()   # In your trap!
	assert_str(rt.ui.toast_text()).is_empty()
	rt.ui.close_modal()
	await get_tree().process_frame
	assert_str(rt.ui.toast_text()).is_equal(SAID)
