class_name OnlineAppearance
extends RefCounted

static func payload(config: AvatarConfig) -> Dictionary:
	var normalized := OnlineAppearance.config({"version": 1, "slots": config.slots})
	return {"version": 1, "slots": normalized.slots.duplicate()}

## Old clients and unavailable parts have a complete, safe fallback. Never load
## paths from the wire or persist another player's appearance to our wardrobe.
static func config(raw: Variant) -> AvatarConfig:
	var result := Avatar.slot_table.default_config()
	if not raw is Dictionary or raw.get("version") != 1 or not raw.get("slots") is Dictionary: return result
	for definition in Avatar.slot_table.slots:
		var slot: StringName = definition.slot_name
		var id = raw.slots.get(String(slot), raw.slots.get(slot, ""))
		if not id is String: continue
		if id.is_empty():
			if not definition.required: result.slots[slot] = ""
			continue
		var part = Avatar.catalog.part(id)
		if part != null and part.slot == slot: result.slots[slot] = id
	return result
