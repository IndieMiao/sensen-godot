class_name FieldGrowth
extends RefCounted

static func allows(state: Dictionary, source_id: String) -> bool:
	var progress: Dictionary = state.get("field_progress", {})
	if progress.is_empty(): return true
	var order: Array = progress.get("order", [])
	if not order.has(source_id): return int(state.get("beds_unlocked", 3)) == 4
	return order.find(source_id) < int(progress.get("plots", 4))

static func count(state: Dictionary) -> int:
	if int(state.get("beds_unlocked", 3)) == 4: return 12
	return int(state.get("field_progress", {}).get("plots", 9))

static func goal(state: Dictionary) -> String:
	var progress: Dictionary = state.get("field_progress", {})
	if progress.is_empty() or int(progress.get("plots", 4)) >= 9: return ""
	var rules: Dictionary = JourneyProgress.data().field_growth
	if int(progress.get("plots", 4)) < 6:
		return L10n.format_text("Sow %d/%d · unlock 6 plots", [mini(int(progress.get("planted", 0)), int(rules.plant_target)), int(rules.plant_target)])
	return L10n.format_text("Harvest %d/%d · unlock 9 plots", [mini(int(progress.get("harvested", 0)), int(rules.harvest_target)), int(rules.harvest_target)])
