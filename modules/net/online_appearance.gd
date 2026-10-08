class_name OnlineAppearance
extends RefCounted

static func payload(config: AvatarConfig) -> Dictionary:
	var normalized := OnlineAppearance.config({"version": 1, "slots": config.slots})
	return {"version": 1, "slots": normalized.slots.duplicate()}

## Old clients and unavailable parts have a complete, safe fallback. Never load
## paths from the wire or persist another player's appearance to our wardrobe.
## allow_npc: an outpost NPC's own outfit data may use NPC-only parts (SGODOT-229); anything from the wire may not.
static func config(raw: Variant, allow_npc := false) -> AvatarConfig:
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
		if part != null and part.slot == slot and (allow_npc or not part.npc_only): result.slots[slot] = id
	return result
