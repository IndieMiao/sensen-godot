extends GdUnitTestSuite
## Master Gardener (Farming Lv10, §4.6.1 / §4.8.3; SGODOT-275): a skill's title is a `title_*` key among its conveniences
## in content, at its level (farming.conveniences.title_master_gardener 10); its name lives in one table,
## P0Logic.TITLE_NAMES. The Lv10 banner lists it last as `… title` (`2nd Greenhouse, Seed Saver, Master Gardener title`), and a
## RewardMoment Milestone follows the banner: `Master Gardener` · `Farming Lv10` · `New title`, the hoe.

var rt: P0Runtime

func before_test() -> void:
	rt = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	rt.session.transport = func(_m: int, _p: String, _b: Dictionary, _c: Dictionary): pass
	rt.session.view = {"seq": 5, "energy": {"value": 120, "max": 200}, "coins": 50, "bag": {"capacity": 25, "free": 25, "slots": []},
		"skills": {"farming": {"level": 10, "xp": 2800}, "fishing": {"level": 4}, "cooking": {"level": 3}}, "homestead": {"level": 6}}

func test_the_levels_bring_their_titles_by_name() -> void:
	assert_array(P0Logic.level_titles("farming", 10)).is_equal(["title_master_gardener"])
	assert_array(P0Logic.level_titles("farming", 9)).is_empty()
	assert_array(P0Logic.level_titles("cooking", 10)).is_equal(["title_chef"])
	# the level's line names it from TITLE_NAMES, never the key
	assert_array(P0Logic.level_unlocks({}, "farming", 10)).is_equal(["2nd Greenhouse", "Seed Saver", "Master Gardener title"])
	assert_array(P0Logic.level_unlocks({}, "cooking", 10)).is_equal(["Lucky Double", "Chef title"])
	var card := P0Logic.title_card("farming", 10, "title_master_gardener")
	assert_that([card.event, card.item_name, card.strip]).is_equal(["Master Gardener", "Farming Lv10", "New title"])
	assert_object(card.icon).is_same(P0Logic.icon("hoe"))

func test_the_title_card_follows_the_lv10_banner() -> void:
	rt.session.state_changed.emit(rt.session.view, [{"kind": "level", "skill": "farming", "level": 10, "unlocks": []}])
	for i in 3: await get_tree().process_frame
	assert_int(rt.ui.root.find_children("*", "UiMomentBanner", true, false).size()).is_equal(1)   # the banner first
	assert_int(rt.ui._card_queue.size()).is_equal(1)
	rt.ui.close_modal()
	for i in 2: await get_tree().process_frame
	var cards := rt.ui.root.find_children("*", "UiRewardMoment", true, false)
	assert_int(cards.size()).is_equal(1)
	var m := cards[0] as UiRewardMoment
	assert_that([m.tone, m.event, m.item_name, m.strip]).is_equal([UiRewardMoment.Tone.MILESTONE, "Master Gardener", "Farming Lv10", "New title"])
	assert_object(m.icon).is_same(P0Logic.icon("hoe"))
	rt.ui.close_modal()
	await get_tree().process_frame

## Lv9 brings no title: the banner alone.
func test_a_level_without_a_title_queues_no_card() -> void:
	rt.session.state_changed.emit(rt.session.view, [{"kind": "level", "skill": "farming", "level": 9, "unlocks": []}])
	for i in 3: await get_tree().process_frame
	assert_int(rt.ui._card_queue.size()).is_equal(0)
	rt.ui.close_modal()
	await get_tree().process_frame
