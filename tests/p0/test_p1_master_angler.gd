extends GdUnitTestSuite
## Master Angler (Fishing Lv10, §4.6.2 / §4.8.3; q(179)): the title is fishing.conveniences.title_master_angler 10 in
## content, its name in P0Logic.TITLE_NAMES (刘邦's #381). The Lv10 row ends `… Master Angler title`, and a RewardMoment
## Milestone follows the Lv10 banner: `Master Angler` · `Fishing Lv10` · `New title`, the rod.

var rt: P0Runtime

func before_test() -> void:
	rt = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	rt.session.transport = func(_m: int, _p: String, _b: Dictionary, _c: Dictionary): pass
	rt.session.view = {"seq": 5, "energy": {"value": 120, "max": 200}, "coins": 50, "bag": {"capacity": 25, "free": 25, "slots": []},
		"skills": {"farming": {"level": 4}, "fishing": {"level": 10, "xp": 4000}, "cooking": {"level": 3}}, "homestead": {"level": 6}}

func test_fishing_lv10_brings_master_angler_by_name() -> void:
	assert_array(P0Logic.level_titles("fishing", 10)).is_equal(["title_master_angler"])
	assert_array(P0Logic.level_titles("fishing", 9)).is_empty()
	var row := P0Logic.level_unlocks({}, "fishing", 10)
	assert_str(str(row.back())).is_equal("Master Angler title")   # last on its row, after what else Lv10 brings
	assert_bool(row.any(func(x): return str(x).begins_with("title_"))).is_false()   # never the key
	var card := P0Logic.title_card("fishing", 10, "title_master_angler")
	assert_that([card.event, card.item_name, card.strip]).is_equal(["Master Angler", "Fishing Lv10", "New title"])
	assert_object(card.icon).is_same(P0Logic.icon(str(P0Logic.GATE_SKILL_ICONS.get("fishing", "star"))))

func test_the_title_card_follows_the_lv10_banner() -> void:
	rt.session.state_changed.emit(rt.session.view, [{"kind": "level", "skill": "fishing", "level": 10, "unlocks": []}])
	for i in 3: await get_tree().process_frame
	assert_int(rt.ui.root.find_children("*", "UiMomentBanner", true, false).size()).is_equal(1)   # the banner first
	assert_int(rt.ui._card_queue.size()).is_equal(1)
	rt.ui.close_modal()
	for i in 2: await get_tree().process_frame
	var cards := rt.ui.root.find_children("*", "UiRewardMoment", true, false)
	assert_int(cards.size()).is_equal(1)
	var m := cards[0] as UiRewardMoment
	assert_that([m.tone, m.event, m.item_name, m.strip]).is_equal([UiRewardMoment.Tone.MILESTONE, "Master Angler", "Fishing Lv10", "New title"])
	rt.ui.close_modal()
	await get_tree().process_frame
