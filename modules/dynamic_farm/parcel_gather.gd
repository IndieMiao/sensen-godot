extends RefCounted
## Outer gathering on the owner's own parcel (C-60; owner rules C-30#29 question 4, C-30#36):
## the trees, flowers and rocks C-20 placed in the extension are picked by hand, no tool,
## one item each, and grow back after the server's respawn time. Kinds, items, amounts, the
## respawn time and the per-kind cap are `economy.gather` of assets/farm/data/dynamic_farm.json,
## the file the server validates (C-58 rules.ts); this client copy only reads them.
##
## Object ids are C-58's contract (docs/plans/C-58.md, server farm.ts parseObjectId):
##   <block id>:<outer recipe version>:<model>:<x>,<y>:<ordinal>
## x,y is the parcel grid cell holding the instance origin (FarmWalk.cell_at, the tilling grid),
## the ordinal counts the same model in the same cell in drawn layout order. The outer layout
## follows the parcel data and the recipe only, so a parcel reopens with the same ids; a recipe
## whose outer_groves.version differs from `recipe_version` gets no ids (the server would refuse
## them as STALE_RECIPE).
const RULES_PATH := "res://assets/farm/data/dynamic_farm.json"
## Server limits (C-58 farm.ts): records kept per farm, longest object id, highest cell / ordinal.
const MAX_GATHERED := 4096
const MAX_OBJECT_LENGTH := 256
const MAX_COORD := 1024
const MAX_ORDINAL := 99
const ID_PATTERN := "^[a-z0-9_-]{1,64}$"
const OBJECT_PATTERN := "^(p-[A-Za-z0-9_*-]{1,98}):([a-z0-9_-]{1,64}):([a-z0-9_-]{1,64}):((?:0|[1-9]\\d{0,3}),(?:0|[1-9]\\d{0,3})):(0|[1-9]\\d?)$"

static var _rules := {}
static var _object_re: RegEx
static var _id_re: RegEx

## Parsed `economy.gather`, or {} when it is missing or out of the server's bounds.
static func rules() -> Dictionary:
	if _rules.is_empty():
		var raw = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
		_rules = parse(raw.get("economy", {}).get("gather") if raw is Dictionary and raw.get("economy") is Dictionary else null)
	return _rules

## {recipe_version, respawn_ms, sources: {kind: {item, amount, max_objects, models}}, kind_of: {model: kind}}
## with the server's bounds: respawn 1 s–30 days, 1–99 per gather, cap 1–1000, a model in one kind only.
static func parse(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not _is_id(raw.get("recipe_version")) or not _whole_in(raw.get("respawn_seconds"), 1, 30 * 24 * 3600) \
			or not raw.get("sources") is Dictionary or raw.sources.is_empty():
		return {}
	var out := {"recipe_version": raw.recipe_version, "respawn_ms": int(raw.respawn_seconds) * 1000, "sources": {}, "kind_of": {}}
	for kind in raw.sources:
		var src = raw.sources[kind]
		if not _is_id(kind) or not src is Dictionary or not _is_id(src.get("item")) or not _whole_in(src.get("amount"), 1, 99) \
				or not _whole_in(src.get("max_objects"), 1, 1000) or not src.get("models") is Array or src.models.is_empty():
			return {}
		for model in src.models:
			if not _is_id(model) or out.kind_of.has(model): return {}
			out.kind_of[model] = kind
		out.sources[kind] = {"item": src.item, "amount": int(src.amount), "max_objects": int(src.max_objects), "models": src.models.duplicate()}
	return out

## The gatherable instances of a drawn outer layout: [{id, index, kind, item, amount, asset, cell, origin, box}],
## `index` into `layout`. [] when the layout's recipe version is not the one the rules lock.
static func objects(layout: Array, walk: RefCounted, block_id: String, gather: Dictionary, outer_version: String) -> Array:
	var out := []
	if gather.is_empty() or outer_version != gather.recipe_version: return out
	var seen := {}
	for index in layout.size():
		var item: Dictionary = layout[index]
		var kind = gather.kind_of.get(item.asset)
		if kind == null: continue
		var origin: Vector3 = item.transform.origin
		var cell: Vector2i = walk.cell_at(origin)
		if cell.x < 0 or cell.y < 0 or cell.x >= MAX_COORD or cell.y >= MAX_COORD: continue
		var base := "%s:%s:%s:%d,%d" % [block_id, gather.recipe_version, item.asset, cell.x, cell.y]
		var ordinal := int(seen.get(base, 0))
		seen[base] = ordinal + 1
		if ordinal > MAX_ORDINAL: continue
		var src: Dictionary = gather.sources[kind]
		out.append({"id": "%s:%d" % [base, ordinal], "index": index, "kind": kind, "item": src.item, "amount": src.amount,
			"asset": item.asset, "cell": cell, "origin": origin, "box": item.box})
	return out

## {parcel_id, recipe_version, model, cell ("x,y"), ordinal} or null, like the server's parseObjectId.
static func parse_id(value: Variant) -> Variant:
	if not value is String: return null
	if _object_re == null: _object_re = RegEx.create_from_string(OBJECT_PATTERN)
	var found := _object_re.search(value)
	if found == null: return null
	var xy := found.get_string(4).split(",")
	if int(xy[0]) >= MAX_COORD or int(xy[1]) >= MAX_COORD: return null
	return {"parcel_id": found.get_string(1), "recipe_version": found.get_string(2), "model": found.get_string(3),
		"cell": found.get_string(4), "ordinal": int(found.get_string(5))}

## Server time (ms) at which `id` can be gathered again, or 0 when it is ready now.
static func ready_at(gather: Dictionary, state: Dictionary, id: String, now: int) -> int:
	var at = state.get("gathered", {}).get(id)
	if at == null or gather.is_empty(): return 0
	var ready := int(at) + int(gather.respawn_ms)
	return ready if now < ready else 0

## The server's `gather` command on `state` (changed in place on success): {code, detail}, code "" when
## gathered. `parcel_id` is the owner's parcel (the server reads it from the locked row); `in_core` says
## the cell is under the house, tilled, sown or a cleared obstacle (the core cells the server knows).
## `short`: the player has not the Energy for it (C-148); after every other check, as the server, it is NO_ENERGY.
static func take(gather: Dictionary, state: Dictionary, object: String, parcel_id: String, in_core: bool, now: int,
		short := false) -> Dictionary:
	var o = parse_id(object)
	if o == null or gather.is_empty(): return {"code": "UNKNOWN_OBJECT", "detail": {}}
	if parcel_id.is_empty() or o.parcel_id != parcel_id: return {"code": "NOT_YOUR_PARCEL", "detail": {}}
	if o.recipe_version != gather.recipe_version: return {"code": "STALE_RECIPE", "detail": {"recipe_version": gather.recipe_version}}
	var kind = gather.kind_of.get(o.model)
	if kind == null: return {"code": "UNKNOWN_OBJECT", "detail": {}}
	if in_core: return {"code": "NOT_OUTER", "detail": {}}
	var id := "%s:%s:%s:%s:%d" % [o.parcel_id, o.recipe_version, o.model, o.cell, o.ordinal]
	var respawn := int(gather.respawn_ms)
	var gathered: Dictionary = state.gathered
	if gathered.has(id) and now < int(gathered[id]) + respawn:
		return {"code": "NOT_RESPAWNED", "detail": {"ready_at": int(gathered[id]) + respawn}}
	for key: String in gathered.keys():
		if now >= int(gathered[key]) + respawn: gathered.erase(key)
	if gathered.size() >= MAX_GATHERED: return {"code": "TOO_MANY_OBJECTS", "detail": {"max": MAX_GATHERED}}
	var src: Dictionary = gather.sources[kind]
	var live := 0
	for key: String in gathered:
		var other = parse_id(key)
		if other != null and other.model in src.models: live += 1
	if live >= int(src.max_objects): return {"code": "TOO_MANY_OBJECTS", "detail": {"max": src.max_objects}}
	if short: return {"code": "NO_ENERGY", "detail": {}}
	gathered[id] = now
	state.bag[src.item] = int(state.bag.get(src.item, 0)) + int(src.amount)
	return {"code": "", "detail": {}}

static func _is_id(value: Variant) -> bool:
	if not value is String: return false
	if _id_re == null: _id_re = RegEx.create_from_string(ID_PATTERN)
	return _id_re.search(value) != null

static func _whole_in(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) \
		and float(value) >= low and float(value) <= high
