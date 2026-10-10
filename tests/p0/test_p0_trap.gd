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
	assert_str(P0Trap.event_toast({"action": "collected", "left": 1})).is_equal("1 left in the trap")
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
	pond._trap_hidden_until = Time.get_ticks_msec() - 1
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
	assert_str(P0Runtime.trap_line(names, got)).is_equal("Pond Crucian ×2 · Common Carp ×1")
	assert_array(P0Runtime.trap_fish(ev.slice(0, 4))).is_empty()   # a cast's catch: no trap event
	assert_array(P0Runtime.trap_fish([{"kind": "trap", "action": "set", "place": FERN, "fish": 0}])).is_empty()

## TRAP-COLLECT-2: while a trap's fish fly in, the creel badge counts without them, each landing counts its own in.
func test_the_creel_counts_each_fish_in_as_it_lands() -> void:
	var v := {"bag": {"free": 17, "slots": [{"id": "fish_crucian", "qty": 2}, {"id": "fish_carp", "qty": 1}, {"id": "bait_worm", "qty": 2}]}}
	assert_str(P0Logic.creel_line(v)).is_equal("Creel 3 · 17 free")
	var flying := [{"id": "fish_crucian", "count": 2}, {"id": "fish_carp", "count": 1}]
	assert_str(P0Logic.creel_line(v, flying)).is_equal("Creel 0 · 19 free")      # both stacks came with this catch
	assert_str(P0Logic.creel_line(v, flying.slice(1))).is_equal("Creel 2 · 18 free")   # the crucians landed (TRAP-COLLECT-2)
