extends RefCounted
## C-31 parcel claim endpoints (`docs/plans/C-31.md`) over an ApiClient whose base already ends in /v1.
## Results are flat dictionaries: {ok, status, code, ...}. HTTP/transport details never leave this file.
const Contract := preload("res://modules/dynamic_farm/map/geo_contract.gd")
const Geo := preload("res://modules/dynamic_farm/map/geo_math.gd")
const MAX_IDS := 200
const MAX_BBOX_SPAN := 0.25
var client: ApiClient
var dataset := Contract.DATASET

func _init(p_client: ApiClient = null, p_dataset := Contract.DATASET) -> void:
	client = p_client; dataset = p_dataset

func mine() -> Dictionary:
	var r := await _call("GET", "/parcels/mine")
	if not r.ok: return r
	var parcel = r.json.get("parcel")
	return {"ok": true, "status": r.status, "code": "", "parcel": parcel if parcel is Dictionary else {}}

## ids → {parcel_id: {owner: "mine"|"other"|"none", nickname}}; ids outside the contract are dropped.
func owners(ids: Array) -> Dictionary:
	var wanted: Array = []
	for id in ids:
		if Contract.valid_id(id) and not wanted.has(id): wanted.append(id)
	if wanted.is_empty() or wanted.size() > MAX_IDS: return {"ok": false, "status": 0, "code": "SCHEMA"}
	return _owners(await _call("GET", "/parcels?dataset_version=%s&ids=%s" % [dataset.uri_encode(), ",".join(wanted)]), false)

## Claimed parcels inside [west, south, east, north]; unlisted parcels there are unclaimed unless truncated.
func owners_in(bbox: Array) -> Dictionary:
	if bbox.size() != 4 or float(bbox[2]) - float(bbox[0]) > MAX_BBOX_SPAN or float(bbox[3]) - float(bbox[1]) > MAX_BBOX_SPAN:
		return {"ok": false, "status": 0, "code": "SCHEMA"}
	var box := ",".join(bbox.map(func(v): return "%.6f" % float(v)))
	return _owners(await _call("GET", "/parcels?dataset_version=%s&bbox=%s" % [dataset.uri_encode(), box]), true)

func claim(parcel_id: String, center: Array) -> Dictionary:
	var r := await _call("POST", "/parcels/claim", {"dataset_version": dataset, "parcel_id": parcel_id, "center": center})
	if r.status in [200, 201] or r.code == "ALREADY_CLAIMED":
		var parcel = r.json.get("parcel")
		r["parcel"] = parcel if parcel is Dictionary else {}
		r["ok"] = r.status in [200, 201] and not r.parcel.is_empty()
	return r

## C-130 starter zone of this dataset's community (public, no account needed). `zone` is {} when the server has it
## switched off; otherwise {id, name, boundary, center, zoom, parcel_ids: {id: true}}. A malformed answer is SCHEMA.
func starter_zone() -> Dictionary:
	var r := await _call("GET", "/parcels/starter-zone?dataset_version=%s" % dataset.uri_encode())
	if not r.ok: return r
	var raw = r.json.get("zone")
	if r.json.get("enabled") != true or raw == null:
		return {"ok": true, "status": r.status, "code": "", "zone": {}}
	var zone := parse_zone(raw)
	if zone.is_empty(): return {"ok": false, "status": r.status, "code": "SCHEMA"}
	return {"ok": true, "status": r.status, "code": "", "zone": zone}

## The server's zone with every field checked; {} if anything is off (the map then keeps its old behaviour and the
## server still decides every claim).
static func parse_zone(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return {}
	var ring = raw.get("boundary")
	var ids = raw.get("parcel_ids")
	var zoom = raw.get("zoom")
	if not ring is Array or ring.size() < 4 or ring.size() > 512 or not Geo.valid_point(raw.get("center")): return {}
	if not (zoom is float or zoom is int) or float(zoom) < 13 or float(zoom) > 21: return {}
	if not ids is Array or ids.is_empty() or ids.size() > 5000: return {}
	for point in ring:
		if not Geo.valid_point(point): return {}
	var set := {}
	for id in ids:
		if not Contract.valid_id(id): return {}
		set[id] = true
	return {"id": str(raw.get("id", "")), "name": str(raw.get("name", "")), "boundary": ring, "center": raw.center,
		"zoom": float(zoom), "parcel_ids": set}

## Internal test builds only; the release server answers 403 RESELECT_DISABLED.
func abandon() -> Dictionary:
	return await _call("POST", "/parcels/mine/abandon", {})

func _owners(r: Dictionary, area: bool) -> Dictionary:
	if not r.ok: return r
	var rows: Dictionary = {}
	var list = r.json.get("parcels")
	if not list is Array: return {"ok": false, "status": r.status, "code": "SCHEMA"}
	for row in list:
		if not row is Dictionary or not Contract.valid_id(row.get("parcel_id")) or not row.get("owner") in ["mine", "other", "none"]: continue
		var nickname = row.get("nickname")
		rows[row.parcel_id] = {"owner": row.owner, "nickname": nickname if nickname is String else ""}
	return {"ok": true, "status": r.status, "code": "", "owners": rows, "truncated": area and r.json.get("truncated") == true}

func _call(method: String, path: String, body: Variant = null) -> Dictionary:
	if client == null: return {"ok": false, "status": 0, "code": "OFFLINE", "json": {}}
	var r: ApiClient.Response = await client.request(method, path, body)
	if not r.ok: return {"ok": false, "status": 0, "code": "NETWORK", "json": {}}
	return {"ok": r.is_success(), "status": r.status, "code": str(r.json.get("code", "")), "json": r.json}
