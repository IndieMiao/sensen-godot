class_name AvatarSlotTable
extends Resource

@export var slots: Array[AvatarSlotDef] = []

func slot(name: StringName) -> AvatarSlotDef:
	for s in slots:
		if s.slot_name == name:
			return s
	return null

func slot_names() -> Array[StringName]:
	var out: Array[StringName] = []
	for s in slots:
		out.append(s.slot_name)
	return out

func default_config() -> AvatarConfig:
	var cfg := AvatarConfig.new()
	for s in slots:
		cfg.slots[s.slot_name] = s.default_part
	return cfg
