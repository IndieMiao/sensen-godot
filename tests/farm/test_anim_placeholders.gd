extends GdUnitTestSuite
## 守卫：数据引用的每个劳作动作，要么有真实 clip，要么在登记表里（方案 D9）。
## 占位不是问题，**悄悄占位**才是——新增动作忘了登记，这里立刻炸。

const RIG := "res://assets/avatar/base/base_rig.tscn"
const WEATHER := "res://assets/farm/data/weather_script.json"

func test_every_tool_action_is_registered() -> void:
	for action in FarmToolActions.ALL + FarmToolActions.EMOTES:
		assert_bool(AnimPlaceholders.is_registered(action)).override_failure_message(
			"动作 %s 既没有真实 clip 也没在 anim_placeholders.json 登记" % action).is_true()

func test_every_weather_care_action_is_registered() -> void:
	var w: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WEATHER))
	for cond in (w.care_action as Dictionary):
		var action := str(w.care_action[cond])
		assert_bool(AnimPlaceholders.is_registered(action)).override_failure_message(
			"田况 %s 的照料动作 %s 未登记" % [cond, action]).is_true()
		assert_str(str(AnimPlaceholders.CARE_ACTION.get(cond, ""))).override_failure_message(
			"CARE_ACTION 与 weather_script.json 的 care_action 不同源").is_equal(action)

func test_real_clips_list_matches_the_rig() -> void:
	# 登记表声称的真实 clip 必须真的在 rig 里；否则守卫会放过一个播不出来的动作。
	var rig := (load(RIG) as PackedScene).instantiate()
	add_child(auto_free(rig))
	var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	assert_object(ap).is_not_null()
	for clip in AnimPlaceholders.real_clips():
		assert_bool(ap.has_animation(str(clip))).override_failure_message(
			"登记表说 %s 是真实 clip，但 rig 里没有" % clip).is_true()

func test_placeholder_actions_fall_back_to_idle() -> void:
	# 播不出来也不能崩：玩家看到站着不动，而不是黑屏。
	# 已由 Mixamo 管线转正的条目（clip_id 进了 real_clips）则必须播它自己的真 clip。
	for action in AnimPlaceholders.placeholders():
		var clip_id := str(AnimPlaceholders.placeholders()[action].get("clip_id", ""))
		if AnimPlaceholders.real_clips().has(clip_id):
			assert_bool(AnimPlaceholders.is_placeholder(str(action))).is_false()
			assert_str(AnimPlaceholders.clip_for(str(action))).is_equal(clip_id)
		else:
			assert_bool(AnimPlaceholders.is_placeholder(str(action))).is_true()
			assert_str(AnimPlaceholders.clip_for(str(action))).is_equal("idle")

func test_placeholder_is_promoted_when_its_clip_becomes_real() -> void:
	# 登记表注入：labour_till 已是真 clip，till 就不再占位；labour_sow 没有，sow 仍回退 idle。
	var saved := AnimPlaceholders._table
	AnimPlaceholders._table = {"real_clips": ["idle", "labour_till"],
		"placeholders": {"till": {"clip_id": "labour_till"}, "sow": {"clip_id": "labour_sow"}}}
	assert_bool(AnimPlaceholders.is_registered("till")).is_true()
	assert_bool(AnimPlaceholders.is_placeholder("till")).is_false()
	assert_str(AnimPlaceholders.clip_for("till")).is_equal("labour_till")
	assert_bool(AnimPlaceholders.is_placeholder("sow")).is_true()
	assert_str(AnimPlaceholders.clip_for("sow")).is_equal("idle")
	AnimPlaceholders._table = saved

func test_real_clip_is_played_as_itself() -> void:
	assert_str(AnimPlaceholders.clip_for("walk")).is_equal("walk")
	assert_str(AnimPlaceholders.clip_for("idle")).is_equal("idle")

func test_unregistered_action_is_rejected_by_the_guard() -> void:
	# 守卫本身的判别力：没登记的动作必须返回 false。
	assert_bool(AnimPlaceholders.is_registered("labour_dance")).is_false()

func test_fallback_bow_returns_to_rest() -> void:
	var n := Node3D.new()
	add_child(auto_free(n))
	var tw := AnimPlaceholders.play_fallback(n, 0.04)
	await await_signal_on(tw, "finished", [], 2000)
	assert_vector(n.rotation).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.01)
