extends RefCounted
## The owner's parcel farm on the server: C-31 `POST /parcels/mine/enter` and
## `POST /parcels/mine/commands` (docs/plans/C-31.md) over an ApiClient whose base ends in /v1.
## Same results as the local stand-in, so the scene reads either:
##   {ok, granted?, farm, farm_version, server_time} or
##   {ok:false, code, index, detail?, farm?, farm_version?, server_time?}.
## The server answers for the player's own parcel; a reply about another parcel is refused,
## so the scene never shows one parcel's farm on another.
var client: ApiClient
var block_id: String
var dataset: String

func _init(p_client: ApiClient, parcel_block_id: String, dataset_version: String) -> void:
	client = p_client
	block_id = parcel_block_id
	dataset = dataset_version

## Sends the client's own dataset (C-136): the server moves a claim made on an older registered dataset of the
## same community onto it, so an r4 claim opens in this r6 package; cell progress restarts (Q-168).
func enter() -> Dictionary:
	return _result(await _call("/parcels/mine/enter", {"dataset_version": dataset}), true)

## The farm without entering it (C-31 `GET /parcels/mine`): no welcome gift. The market and the
## carpenter on the map read it this way (C-59).
func read() -> Dictionary:
	if client == null: return _result(ApiClient.Response.new(false, 0, {}, "offline"), false)
	return _result(await client.request("GET", "/parcels/mine"), false)

func send(base_version: int, commands: Array) -> Dictionary:
	return _result(await _call("/parcels/mine/commands", {"base_version": base_version, "commands": commands}), false)

func _call(path: String, body: Dictionary) -> ApiClient.Response:
	if client == null: return ApiClient.Response.new(false, 0, {}, "offline")
	return await client.request("POST", path, body)

func _result(r: ApiClient.Response, entering: bool) -> Dictionary:
	if not r.ok: return {"ok": false, "code": "NETWORK", "index": 0}
	var out := {"ok": r.is_success(), "code": str(r.json.get("code", "")), "index": int(r.json.get("index", 0))}
	if r.json.get("server_time") is float or r.json.get("server_time") is int: out.server_time = int(r.json.server_time)
	if r.json.get("detail") is Dictionary: out.detail = r.json.detail
	var parcel = r.json.get("parcel")
	if parcel is Dictionary:
		if parcel.get("parcel_id") != block_id or parcel.get("dataset_version") != dataset:
			return {"ok": false, "code": "OTHER_PARCEL", "index": 0}
		out.farm = parcel.get("farm")
		out.farm_version = int(parcel.get("farm_version", -1))
	elif out.ok:
		return {"ok": false, "code": "SCHEMA", "index": 0}
	if entering: out.granted = r.json.get("granted") == true
	return out
