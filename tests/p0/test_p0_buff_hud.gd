extends GdUnitTestSuite
## q(300) ⑨ (不知火舞's spec v1.1 §3–4): the priest's buffs on the HUD — an icon in a ring counting down, its time in a
## pill under it, fish left of farm, centres 40 apart, the left pill 5 after the Energy chip; a toast when one is taken
## or renewed and when one runs out on screen (none on launch, none for one gone while away); the catch card `×2`.

var ui: P0Ui

func before_test() -> void:
	ui = P0Ui.new()
	add_child(auto_free(ui))
	await await_idle_frame()

func _view(buffs: Array) -> Dictionary:
	return {"energy": {"have": 100, "max": 200}, "coins": 1234, "buffs": buffs, "fishing": {"dex": [
		{"id": "fish_crucian", "caught": 1}]}, "names": {"fish_crucian": "Pond Crucian"}}

func test_the_rings_say_the_time_left_fish_first() -> void:
	var rings := P0Logic.buff_rings({"buffs": [{"id": "farm", "left": 300000}, {"id": "fish", "left": 1100000}]})
	assert_array(rings.map(func(r): return r.id)).is_equal(["fish", "farm"])
	assert_str(str(rings[0].remaining)).is_equal("18:20")
	assert_float(float(rings[0].progress)).is_equal_approx(1100000.0 / 1200000.0, 0.0001)
	assert_str(str(rings[1].remaining)).is_equal("5:00")
	assert_array(P0Logic.buff_rings({"buffs": [{"id": "fish", "left": 0}]})).is_empty()
	assert_array(P0Logic.buff_rings({})).is_empty()

func test_two_rings_sit_after_the_energy_chip_40_apart() -> void:
	ui.set_view(_view([{"id": "fish", "left": 1100000}, {"id": "farm", "left": 600000}]))
	await await_idle_frame()
	var rings: Control = ui.hud._buff_rings
	assert_bool(rings.visible).is_true()
	var slots: Array = rings._slots
	var a: Control = slots[0][0]
	var b: Control = slots[1][0]
	assert_float(b.position.x - a.position.x).is_equal_approx(40.0, 0.01)   # centres 40 apart
	assert_vector(a.size).is_equal(Vector2(28, 28))
	var pill: Control = slots[0][2]
	assert_float(pill.size.y).is_equal(16.0)
	assert_float(pill.position.y - (a.position.y + 28.0)).is_equal(-4.0)   # its top over the circle's bottom 4
	var energy: Rect2 = ui.hud._energy_chip.get_global_rect()
	assert_float(pill.get_global_rect().position.x - energy.end.x).is_equal_approx(5.0, 0.5)
	assert_str((slots[0][3] as Label).text).is_equal("18:20")
	# 360 wide, 4-digit coins: the right ring and its pill keep ≥ 8 clear of the coins capsule (spec §3)
	var coins: Rect2 = (ui.hud._balances.get_child(0) as Control).get_global_rect()
	var right := maxf(b.get_global_rect().end.x, (slots[1][2] as Control).get_global_rect().end.x)
	print("P0_BUFF_GAP to coins ", coins.position.x - right)
	assert_float(coins.position.x - right).is_greater_equal(8.0)
	ui.set_view(_view([]))
	assert_bool(rings.visible).is_false()

func test_toasts_on_taking_renewing_and_running_out() -> void:
	ui.set_view(_view([{"id": "fish", "left": 600000}]))   # the first view after launch: nothing said
	assert_str(ui.toast_text()).is_empty()
	ui.set_view(_view([{"id": "fish", "left": 599000}, {"id": "farm", "left": 1200000}]))   # farm taken
	assert_str(_one_line(ui.toast_text())).is_equal("Swift Growth · 20 min · crops sown now grow 2× faster")
	ui.set_view(_view([{"id": "fish", "left": 1200000}, {"id": "farm", "left": 1199000}]))   # fish renewed (Pray drew it, v1.2 §4)
	assert_str(ui.toast_text()).is_equal("Twin Catch · back to 20 min")
	ui.set_view(_view([{"id": "fish", "left": 1199500}, {"id": "farm", "left": 1198600}]))   # a server answer: no toast
	assert_str(ui.toast_text()).is_equal("Twin Catch · back to 20 min")
	ui.set_view(_view([{"id": "fish", "left": 1199000}, {"id": "farm", "left": 800}]))
	ui.set_view(_view([{"id": "fish", "left": 1198000}]))   # farm ran out on screen
	assert_str(ui.toast_text()).is_equal("Swift Growth has worn off")
	ui.set_view(_view([]))   # fish gone at a jump (back from the background): nothing
	assert_str(ui.toast_text()).is_equal("Swift Growth has worn off")

## A toast broken after a ` · ` (break_at_dot) read back as the one line it was.
func _one_line(t: String) -> String: return t.replace("\n", " · ")

## q(305) (不知火舞 (ii)): the fish toast for a take in the demo week (view.buff_takes.limit null) says every fish lands
## ×2; from 11-15 (the limit set) that a Legendary lands one. The farm one is the same either way. Both break after a ` · `.
func test_the_fish_toast_says_the_legendary_rule_once_the_limit_is_on() -> void:
	assert_str(P0Ui.buff_line("fish", {"buff_takes": {"used": 0, "limit": null}})).is_equal("%s · %d min · every fish lands ×2")
	assert_str(P0Ui.buff_line("fish", {})).is_equal("%s · %d min · every fish lands ×2")   # a server before #865
	assert_str(P0Ui.buff_line("fish", {"buff_takes": {"used": 1, "limit": 2}})).is_equal("%s · %d min · fish ×2, Legendary ×1")
	assert_str(P0Ui.buff_line("farm", {"buff_takes": {"used": 1, "limit": 2}})).is_equal("%s · %d min · crops sown now grow 2× faster")
	var v := _view([])
	v["buff_takes"] = {"used": 0, "limit": 2, "resets_in": 3600000}
	ui.set_view(v)
	v = v.duplicate(); v["buffs"] = [{"id": "fish", "left": 1200000}]
	ui.set_view(v)
	assert_str(_one_line(ui.toast_text())).is_equal("Twin Catch · 20 min · fish ×2, Legendary ×1")

func test_a_twin_catch_card_says_x2() -> void:
	ui.set_view(_view([]))
	ui.show_catch("fish_crucian", 1, 15, {"qty": 2})
	await await_idle_frame()
	var m: UiRewardMoment = ui.find_children("*", "UiRewardMoment", true, false)[0]
	assert_str(m.item_name).is_equal("Pond Crucian ×2")
