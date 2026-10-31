extends GdUnitTestSuite
## q(49) (SGODOT-376): one card at a time at the pond. The fishing panel (canvas layer 30) draws over the P0 UI's
## TipCard (layer 10); the first cast's `Casting uses 5 Energy` came up with `Watch the float…` over it, half hidden.
## While a TipCard is on screen the status card waits, and comes back with its latest line once the tip closes.

class Recorder extends P0Session:
	var cmds: Array = []
	func send(cmd: Dictionary, _key := "") -> bool:
		cmds.append(cmd)
		return true

const TIPS_FILE := "user://test_p0_tip_over_fishing_notice.json"

func after_test() -> void:
	DirAccess.remove_absolute(TIPS_FILE)

func _setup() -> P0FishingPanel:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	var rec: Recorder = auto_free(Recorder.new())
	rec.view = {"fishing": {"cast": {"rarity": 1, "hook_ms": 2200, "breaks": null, "sure": true}}}
	rt.session = rec
	rt.ui.tips_path = TIPS_FILE
	var panel: P0FishingPanel = auto_free(P0FishingPanel.new())
	panel.rt = rt
	add_child(panel)
	await get_tree().process_frame
	panel.set_process(false)   # frames are stepped by hand below
	panel.show()
	return panel

func _tip_up(panel: P0FishingPanel) -> void:
	var ui := panel.rt.ui
	if ui.tips == null: ui.tips = P0Guide.TipQueue.new()
	ui.tips.request("cast")
	ui._show_tip(P0Guide.tip_text(ui.tips.next()), "cast")

func test_the_status_card_waits_while_a_tip_is_up() -> void:
	var panel := await _setup()
	panel.on_cast({"bite_in": 5000, "rarity": 1, "breaks": null})
	panel._process(0.016)
	assert_bool(panel._message_card.visible).is_true()          # no tip: the card is up as before
	_tip_up(panel)                                               # the first cast's `Casting uses 5 Energy`
	assert_bool(panel.rt.ui.tip_on_screen()).is_true()
	panel._process(0.016)
	assert_bool(panel._message_card.visible).is_false()         # not under the tip
	panel._refresh_button()                                      # a refresh shows it again in the base panel
	assert_bool(panel._message_card.visible).is_false()

func test_it_comes_back_with_its_latest_line_when_the_tip_closes() -> void:
	var panel := await _setup()
	panel.on_cast({"bite_in": 5000, "rarity": 1, "breaks": null})
	_tip_up(panel)
	panel._process(0.016)
	assert_bool(panel._message_card.visible).is_false()
	panel._bite_at = float(Time.get_ticks_msec()) - 10.0       # the bite comes while the tip is still up
	panel._process(0.016)
	assert_str(panel.phase).is_equal("hook")
	assert_bool(panel._message_card.visible).is_false()
	panel.rt.ui._hide_tip()                                      # its time ran out (or a tap)
	panel._process(0.016)
	assert_bool(panel._message_card.visible).is_true()
	assert_str(panel._status.text).is_equal("A bite! Tap to hook the fish!")

func test_a_closed_panel_stays_hidden_after_the_tip() -> void:
	var panel := await _setup()
	panel.on_cast({"bite_in": 5000, "rarity": 1, "breaks": null})
	_tip_up(panel)
	panel._process(0.016)
	panel.on_catch({"result": "landed", "fish": "fish_crucian", "rarity": 1})   # the result hides the card
	panel.rt.ui._hide_tip()
	panel._process(0.016)
	assert_bool(panel._message_card.visible).is_false()
