class_name AvatarConfig
extends RefCounted

const FORMAT_VERSION := 1

## StringName(槽位) -> String(部件id)，"" 表示该槽位为空
var slots: Dictionary = {}

func duplicate_config() -> AvatarConfig:
	var c := AvatarConfig.new()
	c.slots = slots.duplicate()
	return c

func changed_slots(other: AvatarConfig) -> Array[StringName]:
	var out: Array[StringName] = []
	var keys := {}
	for k in slots: keys[k] = true
	for k in other.slots: keys[k] = true
	for k in keys:
		if String(slots.get(k, "")) != String(other.slots.get(k, "")):
			out.append(k)
	return out

func to_json_text() -> String:
	var slot_dict := {}
	for k in slots:
		slot_dict[String(k)] = slots[k]
	return JSON.stringify({"version": FORMAT_VERSION, "slots": slot_dict}, "\t")

static func from_json_text(text: String) -> AvatarConfig:
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return null
	if int(data.get("version", 0)) != FORMAT_VERSION:
		return null
	var raw = data.get("slots")
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var cfg := AvatarConfig.new()
	for k in raw:
		if typeof(raw[k]) != TYPE_STRING:
			return null
		cfg.slots[StringName(k)] = raw[k]
	return cfg
