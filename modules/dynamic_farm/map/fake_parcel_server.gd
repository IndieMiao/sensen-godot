extends RefCounted
## In-memory stand-in for the C-31 parcel endpoints, used only while that server is unavailable
## (`sensen/dynamic_farm/fake_claims`). Same status codes and bodies; nothing is persisted. Fake data
## is never evidence of a claim or a save.
const Contract := preload("res://modules/dynamic_farm/map/geo_contract.gd")
## Every third parcel the map asks about is pretended to belong to this neighbour.
const NEIGHBOUR := "Maple"
var nicknames := {"fake-a": "Ash", "fake-b": "Birch"}
var reselect := true
var claims := {} # parcel_id -> {player, center}
var _seeded := {}

func client(token := "fake-a") -> ApiClient:
	var api := ApiClient.new("https://fake.invalid/v1", handle)
	api.token = token
	return api

func handle(method: String, url: String, headers: PackedStringArray, body: String) -> ApiClient.Response:
	var player := ""
	for header in headers:
		if header.begins_with("authorization: Bearer "): player = header.trim_prefix("authorization: Bearer ")
	if not nicknames.has(player): return _reply(401, {"code": "UNAUTHENTICATED"})
	var path := url.trim_prefix("https://fake.invalid/v1")
	var query := {}
	if "?" in path:
		for pair in path.get_slice("?", 1).split("&"):
			query[pair.get_slice("=", 0)] = pair.get_slice("=", 1).uri_decode()
		path = path.get_slice("?", 0)
	var data = JSON.parse_string(body) if not body.is_empty() else {}
	if not data is Dictionary: return _reply(400, {"code": "SCHEMA"})
	match [method, path]:
		["GET", "/parcels/mine"]: return _reply(200, {"parcel": _parcel(_mine(player))})
		["GET", "/parcels"]: return _owners(player, query)
		["POST", "/parcels/claim"]: return _claim(player, data)
		["POST", "/parcels/mine/abandon"]:
			if not reselect: return _reply(403, {"code": "RESELECT_DISABLED"})
			var id := _mine(player)
			if id.is_empty(): return _reply(404, {"code": "NO_PARCEL"})
			claims.erase(id)
			return _reply(200, {"abandoned": {"community_id": "sf", "layer": 0, "parcel_id": id}})
	return _reply(404, {"code": "NOT_FOUND"})

func _claim(player: String, data: Dictionary) -> ApiClient.Response:
	var id = data.get("parcel_id")
	if data.get("dataset_version") != Contract.DATASET or not Contract.valid_id(id) or not data.get("center") is Array:
		return _reply(400, {"code": "SCHEMA"})
	_seed(id)
	var mine := _mine(player)
	if mine == id: return _reply(200, {"parcel": _parcel(id)})
	if not mine.is_empty(): return _reply(409, {"code": "ALREADY_CLAIMED", "parcel": _parcel(mine)})
	if claims.has(id): return _reply(409, {"code": "PARCEL_TAKEN"})
	claims[id] = {"player": player, "center": data.center}
	return _reply(201, {"parcel": _parcel(id)})

func _owners(player: String, query: Dictionary) -> ApiClient.Response:
	if query.get("dataset_version") != Contract.DATASET: return _reply(422, {"code": "UNKNOWN_DATASET"})
	var rows: Array = []
	if query.has("ids"):
		for id in str(query.ids).split(","):
			_seed(id)
			rows.append(_owner(player, id))
	else:
		for id in claims: rows.append(_owner(player, id))
	return _reply(200, {"parcels": rows})

func _owner(player: String, id: String) -> Dictionary:
	if not claims.has(id): return {"parcel_id": id, "owner": "none", "nickname": null}
	var owner: String = claims[id].player
	return {"parcel_id": id, "owner": "mine" if owner == player else "other", "nickname": nicknames.get(owner, NEIGHBOUR)}

func _seed(id: String) -> void:
	if _seeded.has(id): return
	_seeded[id] = true
	if not claims.has(id) and id.hash() % 3 == 0: claims[id] = {"player": "neighbour", "center": []}

func _mine(player: String) -> String:
	for id in claims:
		if claims[id].player == player: return id
	return ""

func _parcel(id: String) -> Variant:
	if id.is_empty(): return null
	return {"community_id": "sf", "layer": 0, "parcel_id": id, "dataset_version": Contract.DATASET,
		"center": claims[id].center, "claimed_at": 0, "farm_version": 0, "farm": {"v": 1}}

static func _reply(status: int, json: Dictionary) -> ApiClient.Response:
	json["server_time"] = Time.get_ticks_msec()
	return ApiClient.Response.new(true, status, json)
