extends GdUnitTestSuite
## SGODOT-283 Fish Trap on the client (q(109) ⑦, 不知火舞's spec on 283): the Set Trap key, the card, the prompt, the
## pond card's fact, Today's row, the toasts and the refusals — all from view.fishing.trap.

const P0Trap := preload("res://modules/p0/p0_trap.gd")
const FERN := "pond_san_francisco_03"
const BLOSSOM := "pond_san_francisco_06"

func _view(traps: Array, slots := 1, next_level = 8) -> Dictionary:
	return {"fishing": {"place": FERN, "trap": {"traps": traps, "slots": slots, "next_level": next_level, "have": 1},
		"places": {FERN: {"name": "Fern Pond"}, BLOSSOM: {"name": "Blossom Pond"}}}}

func _trap(place: String, fish := 0, extra := {}) -> Dictionary:
	return {"place": place, "fish": fish, "keep": 3, "next_in": 18720000 if fish < 3 else null, "fits": fish, "all_fit": true, "back_fits": true}.merged(extra, true)

func test_the_key_sets_a_trap_or_says_why_not() -> void:
	var k := P0Trap.set_key(_view([]), FERN)
	assert_that([k.verb, k.sub, k.enabled, k.cmd]).is_equal(["Set Trap", "Free", true, {"type": "set_trap"}])
	assert_str(str(P0Trap.set_key(_view([_trap(FERN)]), FERN).sub)).is_equal("Trap already here")
	var full := P0Trap.set_key(_view([_trap(BLOSSOM)]), FERN)
	assert_that([full.sub, full.enabled]).is_equal(["Traps 1/1 · Fishing Lv8 adds 1", false])
	assert_str(str(P0Trap.set_key(_view([_trap(BLOSSOM), _trap("a"), _trap("b")], 3, null), FERN).sub)).is_equal("Traps 3/3")

func test_the_fishing_key_turns_into_set_trap_when_the_trap_is_picked() -> void:
	var v := _view([])
	v["energy"] = {"value": 100}
	v["bag"] = {"free": 5}
	assert_str(str(P0Logic.fish_action(v, "trap_fish").verb)).is_equal("Set Trap")
	assert_str(str(P0Logic.fish_action(v, "").verb)).is_equal("Cast")

func test_the_card_collects_what_fits_and_takes_back_when_all_fit() -> void:
	var c := P0Trap.card(_view([_trap(FERN, 2)]), FERN)
	assert_that([c.title, c.fact, c.main.label, c.main.enabled, c.second.label]).is_equal(["Fish Trap", "2/3", "Collect 2", true, "Take back"])   # q(122): no Free
	assert_str(str(P0Trap.card(_view([_trap(FERN, 0)]), FERN).main.label)).is_equal("Empty · next in 5h 12m")
	var some := P0Trap.card(_view([_trap(FERN, 3, {"fits": 1, "all_fit": false})]), FERN)
	assert_that([some.main.label, some.second.label, some.second.enabled]).is_equal(["Collect 1", "Take back · Collect first", false])
	assert_str(str(P0Trap.card(_view([_trap(FERN, 3, {"fits": 0, "all_fit": false})]), FERN).main.label)).is_equal("Collect · Creel full")
	assert_str(str(P0Trap.card(_view([_trap(FERN, 0, {"back_fits": false})]), FERN).second.label)).is_equal("Take back · Bag full")
	assert_dict(P0Trap.card(_view([]), FERN)).is_empty()

func test_prompt_fact_and_today() -> void:
	var p := P0Trap.prompt(_view([_trap(FERN, 2)]), FERN)
	assert_that([p.text, p.fact, p.ready]).is_equal(["Fish Trap", "2/3", true])
	assert_array(P0Trap.pond_fact(_view([_trap(FERN, 2)]), FERN)).is_equal(["Your trap", "2/3"])
	assert_array(P0Trap.pond_fact(_view([]), FERN)).is_empty()
	assert_dict(P0Trap.today_row(_view([_trap(FERN, 2)]))).is_empty()
	var one := P0Trap.today_row(_view([_trap(FERN, 3)]))
	assert_that([one.line, one.go]).is_equal(["Collect 3 fish · Fern Pond", "pond:" + FERN])
	var two := P0Trap.today_row(_view([_trap(FERN, 3), _trap(BLOSSOM, 3)], 2))
	assert_str(str(two.line)).is_equal("Collect 6 fish · 2 traps")
	assert_str(str(two.dot)).is_equal("trap:%s,%s" % [FERN, BLOSSOM])

func test_toasts_and_refusals() -> void:
	assert_str(P0Trap.event_toast({"action": "set"})).is_equal("Fish Trap set · 1 fish every 8h")
	assert_str(P0Trap.event_toast({"action": "collected", "left": 1})).is_equal("")   # a float now (q(124) ①)
	assert_str(P0Trap.left_line({"action": "collected", "left": 1})).is_equal("1 left in the trap")
	assert_str(P0Trap.left_line({"action": "collected", "left": 0})).is_equal("")
	assert_str(P0Trap.left_line({"action": "taken_back", "left": 0})).is_equal("")
	assert_str(P0Trap.event_toast({"action": "collected", "left": 0})).is_equal("")
	assert_str(P0Trap.event_toast({"action": "taken_back"})).is_equal("Fish Trap back in your bag")
	assert_str(str(P0Trap.refusal_text({"type": "set_trap"}, "trap_slots", {"used": 1, "slots": 1, "next_level": 8}))).is_equal("Traps 1/1 · Fishing Lv8 adds 1")
	assert_str(str(P0Trap.refusal_text({"type": "collect_trap"}, "collect_first", {}))).is_equal("Take back · Collect first")
	assert_that(P0Trap.refusal_text({"type": "cast"}, "creel_full", {})).is_null()

func test_the_trap_sits_on_the_fishing_bar_and_the_tackle_tab() -> void:
	assert_str(P0Logic.bar_action_of("trap_fish")).is_equal("fish")
	var v := {"bag": {"slots": [{"id": "bait_worm", "qty": 3}, {"id": "trap_fish", "qty": 1}]}}
	assert_array(P0Logic.quick_bar(v, [], "fish")).contains(["trap_fish", "bait_worm"])
	assert_str(str(P0ItemInfo.tab_of({}, "trap_fish"))).is_equal("tackle")
	assert_bool(P0ItemInfo.rules().has("trap/bag")).is_true()

## Collect (不知火舞 on 289 b3a79614): the card goes at once and the trap's strip and button hide while the collect plays
## (COLLECT_HIDE_MS), then come back (`Fish Trap · 0/3`). Take back keeps its own way (the trap leaves the water).
func test_collect_closes_the_card_and_hides_the_strip_for_the_collect() -> void:
	var stub := GDScript.new()
	stub.source_code = "extends \"res://scenes/p0/p0_pond.gd\"\nvar sent := []\nfunc _ready() -> void: pass\nfunc p0_action(cmd: Dictionary) -> void: sent.append(cmd)\n"
	stub.reload()
	var pond: Node3D = auto_free(Node3D.new())
	pond.set_script(stub)
	pond._trap_open = true
	pond._press_trap({"label": "Collect 3", "enabled": true, "cmd": {"type": "collect_trap"}})
	assert_bool(pond._trap_open).is_false()           # the card went at once
	assert_bool(pond.collecting_trap()).is_true()     # the strip and button hide while it plays
	assert_array(pond.sent).is_equal([{"type": "collect_trap"}])
	pond._trap_hidden_s = 0.0   # the window run out (p0_frame counts it down in game time)
	assert_bool(pond.collecting_trap()).is_false()    # … then back, as Fish Trap · 0/3
	pond._trap_open = true
	pond._press_trap({"label": "Take back", "enabled": true, "cmd": {"type": "collect_trap", "take_back": true}})
	assert_bool(pond.collecting_trap()).is_false()    # Take back: no collect to play
	pond._press_trap({"label": "Collect · Creel full", "enabled": false, "cmd": {}, "toast": ""})
	assert_bool(pond.collecting_trap()).is_false()    # a grey Collect sends nothing and hides nothing
	var src := FileAccess.get_file_as_string("res://scenes/p0/p0_pond.gd")
	assert_str(src).contains("not _trap_open and not collecting_trap()")   # the strip / button's show

## TRAP-COLLECT-2 / -3 (289): a collect's fish by kind in the order they came, one line `Pond Crucian ×2 · Common Carp ×1`;
## nothing for a reply with no trap catch.
func test_a_trap_catch_reads_as_one_line_by_kind() -> void:
	var ev := [{"kind": "item", "id": "fish_crucian", "delta": 1}, {"kind": "xp", "skill": "fishing", "amount": 2},
		{"kind": "item", "id": "fish_carp", "delta": 1}, {"kind": "item", "id": "fish_crucian", "delta": 1},
		{"kind": "trap", "action": "collected", "place": FERN, "fish": 3, "left": 0}]
	var got := P0Runtime.trap_fish(ev)
	assert_array(got).is_equal([{"id": "fish_crucian", "count": 2}, {"id": "fish_carp", "count": 1}])
	var names := {"names": {"fish_crucian": "Pond Crucian", "fish_carp": "Common Carp"}}   # the view names its items
	assert_array(P0Runtime.trap_parts(names, got).map(func(p): return [p.kind, p.text])).is_equal([["item", "Pond Crucian ×2"], ["item", "Common Carp ×1"]])
	assert_array(P0Runtime.trap_fish(ev.slice(0, 4))).is_empty()   # a cast's catch: no trap event
	assert_array(P0Runtime.trap_fish([{"kind": "trap", "action": "set", "place": FERN, "fish": 0}])).is_empty()

## TRAP-COLLECT-2: while a trap's fish fly in, the creel badge counts without them, each landing counts its own in.
func test_the_creel_counts_each_fish_in_as_it_lands() -> void:
	var v := {"bag": {"free": 17, "slots": [{"id": "fish_crucian", "qty": 2}, {"id": "fish_carp", "qty": 1}, {"id": "bait_worm", "qty": 2}]}}
	assert_str(P0Logic.creel_line(v)).is_equal("Creel 3 · 17 free")
	var flying := [{"id": "fish_crucian", "count": 2}, {"id": "fish_carp", "count": 1}]
	assert_str(P0Logic.creel_line(v, flying)).is_equal("Creel 0 · 19 free")      # both stacks came with this catch
	assert_str(P0Logic.creel_line(v, flying.slice(1))).is_equal("Creel 2 · 18 free")   # the crucians landed (TRAP-COLLECT-2)

## q(124) ①: a kind first got from a trap gets the landed fish's first card, titled `In your trap!` — one a new kind in
## the server's order; the reply's New city! XP on the first card, a first Fine's Energy on the first Fine's.
const FIRST_EVENTS := [
	{"kind": "item", "id": "fish_crucian", "delta": 1}, {"kind": "xp", "skill": "fishing", "amount": 2, "percent": 100},
	{"kind": "first", "what": "catch:fish_crucian", "xp": 15}, {"kind": "xp", "skill": "fishing", "amount": 15, "percent": 100},
	{"kind": "first", "what": "fishing_city:gn-5391959", "xp": 10, "name": "San Francisco"}, {"kind": "xp", "skill": "fishing", "amount": 10, "percent": 100},
	{"kind": "item", "id": "fish_perch", "delta": 1}, {"kind": "xp", "skill": "fishing", "amount": 3, "percent": 100},
	{"kind": "first", "what": "catch:fish_perch", "xp": 30}, {"kind": "xp", "skill": "fishing", "amount": 30, "percent": 100},
	{"kind": "energy", "delta": 20, "reason": "reward"}, {"kind": "reward", "id": "first_fish_2", "energy": 20},
	{"kind": "trap", "action": "collected", "place": FERN, "fish": 2, "left": 0}]

func _first_view() -> Dictionary:
	return {"energy": {"value": 140, "max": 200}, "coins": 52, "bag": {"capacity": 25, "free": 23, "slots": [
		{"id": "fish_crucian", "qty": 1}, {"id": "fish_perch", "qty": 1}]}, "skills": {"fishing": {"level": 5}},
		"items": {"fish_crucian": {"rarity": 1}, "fish_perch": {"rarity": 2}},
		"names": {"fish_crucian": "Pond Crucian", "fish_perch": "River Perch"},
		"fishing": {"dex": range(20).map(func(n): return {"id": "f%d" % n, "caught": 1 if n < 2 else 0})}}

func test_a_trap_s_first_kind_gets_its_in_your_trap_card() -> void:
	assert_array(P0Runtime.trap_cards(_first_view(), FIRST_EVENTS)).is_equal([
		{"fish": "fish_crucian", "rarity": 1, "xp": 15, "extras": {"city_xp": 10, "dex_back": 1}},
		{"fish": "fish_perch", "rarity": 2, "xp": 30, "extras": {"energy": 20}}])
	var plain := FIRST_EVENTS.filter(func(e): return str(e.kind) not in ["first", "reward"])
	assert_array(P0Runtime.trap_cards(_first_view(), plain)).is_empty()   # kinds it had: no card
	assert_array(P0Runtime.trap_cards(_first_view(), FIRST_EVENTS.slice(0, 10))).is_empty()   # no trap event: a rod's

## The collect's own XP float stays the trap's (§6.8: `+5 XP` here), the firsts' XP is on the cards, which come one at a
## time once the fish are in the creel.
func test_the_trap_cards_come_after_the_flights_and_keep_their_xp_off_the_float() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	var v := _first_view()
	rt.session.view = v
	rt.ui.set_view(v)
	rt._on_state(v, FIRST_EVENTS)
	await get_tree().process_frame
	await get_tree().process_frame
	var texts: Array = rt.ui.root.get_children().filter(func(c): return c is UiFloatText).map(func(f): return f.text)
	assert_array(texts).contains(["+5 XP", "Pond Crucian ×1 · River Perch ×1"])
	assert_array(texts).not_contains(["+20 Energy"])   # the first Fine's Energy is on its card
	assert_array(texts.filter(func(t): return str(t).contains("15") or str(t).contains("30") or str(t).contains("+10 XP"))).is_empty()
	assert_array(rt.ui.find_children("*", "UiRewardMoment", true, false)).is_empty()   # not while the fish fly
	await get_tree().create_timer(UiItemFly.FLIGHT_S + UiItemFly.DELAY_STEP_S + P0Runtime.TRAP_CARD_AFTER_S + 0.1).timeout
	var cards := rt.ui.find_children("*", "UiRewardMoment", true, false)
	assert_int(cards.size()).is_equal(1)   # one at a time
	var first: UiRewardMoment = cards[0]
	assert_array([first.event, first.item_name, first.strip, first.note]).is_equal(["In your trap!", "Pond Crucian", "First catch! +15 XP · New city! +10 XP", "Fish-dex 1/20"])
	rt.ui.close_modal()
	await get_tree().process_frame
	await get_tree().process_frame
	var second: UiRewardMoment = rt.ui.find_children("*", "UiRewardMoment", true, false).filter(func(m): return not m.is_queued_for_deletion()).front()
	assert_array([second.event, second.item_name, second.strip, second.note]).is_equal(["In your trap!", "River Perch", "First catch! +30 XP", "Fish-dex 2/20"])
	assert_int(second.rewards.size()).is_equal(1)   # the first Fine's +20 Energy
