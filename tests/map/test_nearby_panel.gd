extends GdUnitTestSuite
## Nearby Farmers 面板：条目渲染、单选互斥、预览摘要、360×800 不与顶栏/侧栏重叠、英文。

func _panel(entries: Array, count := -1, offline := false) -> NearbyPanel:
	var p := NearbyPanel.new()
	add_child(auto_free(p))
	p.set_entries(entries, entries.size() if count < 0 else count, offline)
	return p

func _entries(n: int) -> Array:
	var out := []
	for i in n:
		out.append({"farm_id": "f%d" % i, "avatar_ref": "seed:%08x" % (i * 2654435761), "nursery_stage": "derelict"})
	return out

func test_renders_one_card_per_entry_and_shows_count() -> void:
	var p := _panel(_entries(3), 7)
	assert_int(p.card_count()).is_equal(3)
	assert_str(p._title.text).is_equal("Nearby Farmers · 7")
	assert_bool(p._subtitle.visible).is_false()

func test_offline_subtitle_names_sample_farms() -> void:
	var p := _panel(_entries(2), 2, true)
	assert_bool(p._subtitle.visible).is_true()
	assert_str(p._subtitle.text).is_equal("Offline · sample farms")

func test_empty_list_says_so_instead_of_blank() -> void:
	var p := _panel([], 0)
	assert_bool(p._subtitle.visible).is_true()
	assert_str(p._subtitle.text).contains("No open farms")

func test_only_one_card_focused_at_a_time() -> void:
	var p := _panel(_entries(3))
	var seen := []
	p.farm_focused.connect(func(id): seen.append(id))
	p.cards()[0].pressed.emit()
	p.cards()[2].pressed.emit()
	assert_str(p.focused_id).is_equal("f2")
	assert_int(p.cards().filter(func(c): return c.button_pressed).size()).is_equal(1)
	assert_array(seen).is_equal(["f0", "f2"])

func test_preview_summary_counts_growing_and_ripe() -> void:
	var snap := {"farm_id": "f0", "cells": [
		{"state": "growing", "ripe": false}, {"state": "growing", "ripe": true},
		{"state": "sown", "ripe": false}, {"state": "tilled", "ripe": false}, {"state": "wild", "ripe": false},
	], "weather_snapshot": "rain"}
	assert_str(NearbyPanel.summary(snap)).is_equal("2 growing · 1 ripe · Rain")

func test_preview_only_applies_to_the_focused_farm() -> void:
	# 等快照期间用户换了卡：迟到的回包不能盖掉新选中的预览。
	var p := _panel(_entries(2))
	p.focus("f1")
	p.set_preview({"farm_id": "f0", "layout_patch_id": "sh_b", "blueprint_revision": 2, "cells": []})
	assert_str(p._preview_text.text).is_equal("Finding farm...")
	assert_bool(p.visit_button.disabled).is_true()
	p.set_preview({"farm_id": "f1", "layout_patch_id": "sh_b", "blueprint_revision": 2, "cells": [], "weather_snapshot": "sunny"})
	assert_bool(p._preview.visible).is_true()
	assert_object(p._preview_img.texture).is_not_null()
	assert_bool(p.visit_button.disabled).is_false()

func test_unavailable_preview_disables_visit() -> void:
	var p := _panel(_entries(1))
	p.focus("f0")
	p.set_preview_unavailable()
	assert_bool(p.visit_button.disabled).is_true()
	assert_str(p._preview_text.text).contains("unavailable")

func test_visit_emits_focused_farm() -> void:
	var p := _panel(_entries(2))
	var seen := []
	p.visit_requested.connect(func(id): seen.append(id))
	p.visit_button.pressed.emit()        # 未选中：不发
	p.focus("f1")
	p.visit_button.pressed.emit()
	assert_array(seen).is_equal(["f1"])

func test_fits_phone_width_without_touching_top_or_side_bars() -> void:
	# 顶栏 ≤220×64 在左上，侧栏在右侧中部；面板必须整个在底部。
	var root := Control.new()
	root.size = Vector2(360, 800)
	add_child(auto_free(root))
	var p := NearbyPanel.new()
	root.add_child(p)
	p.set_entries(_entries(6), 6)
	p.focus("f0")
	p.set_preview({"farm_id": "f0", "layout_patch_id": "sh_b", "blueprint_revision": 2,
		"cells": [{"state": "growing", "ripe": true}], "weather_snapshot": "sunny"})
	await get_tree().process_frame
	await get_tree().process_frame
	var r := p.get_global_rect()
	assert_bool(r.position.y >= 400.0).override_failure_message("面板顶到 y=%.0f，侵入地图/侧栏区域" % r.position.y).is_true()
	assert_bool(r.end.y <= 800.5).is_true()
	for c in p.cards():
		assert_bool((c as Control).get_global_rect().size.y >= 44.0).is_true()
	assert_bool(p.visit_button.get_global_rect().size.y >= 44.0).is_true()

func test_all_text_is_english() -> void:
	var p := _panel([{"farm_id": "x", "avatar_ref": "preset_a", "nursery_stage": "cleared"}], 1, true)
	p.focus("x")
	p.set_preview({"farm_id": "x", "layout_patch_id": "sh_b", "blueprint_revision": 2, "cells": [], "weather_snapshot": "wind"})
	var stack: Array = [p]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var text := ""
		if n is Button:
			text = (n as Button).text
		elif n is Label:
			text = (n as Label).text
		for ch in text:
			assert_bool(ch.unicode_at(0) < 0x2E80).override_failure_message("含非英文: %s" % text).is_true()
	assert_str(SeededOutfit.short_name("preset_a")).is_equal("Sample A")
	assert_str(SeededOutfit.short_name("seed:abcd1234")).is_equal("Farmer 1234")
