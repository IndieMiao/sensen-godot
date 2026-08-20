class_name PartCatalog
extends RefCounted

const MANIFEST_VERSION := 1
const REQUIRED_FIELDS := ["id", "slot", "attach", "res"]

class AvatarPartMeta:
	extends RefCounted
	var id: String
	var slot: StringName
	var attach: String
	var tier: int = 0
	var pack: String = "builtin"
	var res_path: String
	var thumb_path: String = ""
	var offset_pos := Vector3.ZERO
	var offset_rot_deg := Vector3.ZERO
	var offset_scale := Vector3.ONE

var _by_id: Dictionary = {}
var _by_slot: Dictionary = {}

static func load_from_file(path: String) -> PartCatalog:
	if not FileAccess.file_exists(path):
		push_warning("PartCatalog: manifest 不存在 %s" % path)
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != MANIFEST_VERSION:
		push_warning("PartCatalog: manifest 版本/格式非法 %s" % path)
		return null
	if typeof(data.get("parts")) != TYPE_ARRAY:
		return null
	var cat := PartCatalog.new()
	for entry in data.parts:
		if typeof(entry) != TYPE_DICTIONARY:
			return null
		for field in REQUIRED_FIELDS:
			if not entry.has(field):
				push_warning("PartCatalog: 缺字段 %s: %s" % [field, str(entry)])
				return null
		var meta := AvatarPartMeta.new()
		meta.id = entry.id
		meta.slot = StringName(entry.slot)
		meta.attach = entry.attach
		meta.tier = int(entry.get("tier", 0))
		meta.pack = str(entry.get("pack", "builtin"))
		meta.res_path = entry.res
		meta.thumb_path = str(entry.get("thumb", ""))
		var off = entry.get("offset")
		if typeof(off) == TYPE_DICTIONARY:
			meta.offset_pos = _vec3(off.get("pos"), Vector3.ZERO)
			meta.offset_rot_deg = _vec3(off.get("rot"), Vector3.ZERO)
			meta.offset_scale = _vec3(off.get("scale"), Vector3.ONE)
		if meta.attach != "mesh" and meta.attach != "socket":
			return null
		if cat._by_id.has(meta.id):
			push_warning("PartCatalog: 重复 id %s" % meta.id)
			return null
		cat._by_id[meta.id] = meta
		if not cat._by_slot.has(meta.slot):
			cat._by_slot[meta.slot] = []
		cat._by_slot[meta.slot].append(meta)
	return cat

static func _vec3(v, fallback: Vector3) -> Vector3:
	if typeof(v) == TYPE_ARRAY and v.size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return fallback

func part(id: String) -> AvatarPartMeta:
	return _by_id.get(id)

func has_part(id: String) -> bool:
	return _by_id.has(id)

func parts_for_slot(slot: StringName) -> Array:
	return _by_slot.get(slot, [])

func size() -> int:
	return _by_id.size()

func all_ids() -> Array:
	return _by_id.keys()
