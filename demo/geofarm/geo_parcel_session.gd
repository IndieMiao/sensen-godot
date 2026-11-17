extends Node
## Dataset-scoped service operations, independent of map rendering and tile format.
const Contract := preload("res://demo/geofarm/geo_contract.gd")
const Geo := preload("res://demo/geofarm/geo_math.gd")
const Identity := preload("res://demo/geofarm/geo_identity.gd")
var api: Node
var identity: RefCounted
var busy := false
var claims: Dictionary = {}
var _claim_revision := 0

func _public_claim(row:Variant) -> Dictionary:
	if not row is Dictionary or not Contract.valid_id(row.get("block_id")):
		return {}
	if not row.get("nickname") is String or not Identity.valid_nickname(row.nickname):
		return {}
	var result:={"block_id":str(row.block_id),"nickname":str(row.nickname),"claimed_at":str(row.get("claimed_at",""))}
	if row.get("address") is String:result["address"]=row.address
	if Geo.valid_point(row.get("center")):
		result["center"]=row.center.duplicate()
	return result

func refresh_claims() -> Dictionary:
	var revision:=_claim_revision
	var result:Dictionary=await api.request("/claims")
	if revision!=_claim_revision:return {"ok":false,"code":"superseded"}
	if result.get("ok")!=true or result.get("dataset_version")!=Contract.DATASET or not result.get("claims") is Array:
		return {"ok":false,"code":"claims_unavailable"}
	var next:={}
	for raw in result.claims:
		var row:=_public_claim(raw)
		if row.is_empty() or next.has(row.block_id):return {"ok":false,"code":"invalid_response"}
		next[row.block_id]=row
	claims=next
	return {"ok":true,"claims":claims.values()}

func claim(id:String,nickname:String) -> Dictionary:
	if busy:return {"ok":false,"code":"busy"}
	if identity==null or identity.data.get("dataset_version")!=Contract.DATASET:
		return {"ok":false,"code":"identity"}
	if not Contract.valid_id(id) or not Identity.valid_nickname(nickname):
		return {"ok":false,"code":"schema"}
	var pending:Dictionary=identity.data.get("pending",{})
	if not pending.is_empty():
		if str(pending.get("block_id",""))!=id:return {"ok":false,"code":"pending_claim"}
		# A lost response must retry the original request, including its nickname.
		nickname=str(pending.get("nickname",""))
	if not identity.remember_pending(id,nickname):return {"ok":false,"code":"persistence"}
	busy=true
	var result:Dictionary=await api.request("/claim",{"device_id":str(identity.data.device_id),"nickname":nickname,"block_id":id})
	busy=false
	var code:=str(result.get("code",""))
	if result.get("ok")==true or code=="already_claimed":
		var row:=_public_claim(result.get("claim"))
		if row.is_empty() or (result.get("ok")==true and row.block_id!=id):
			return {"ok":false,"code":"invalid_response"}
		var saved:bool=identity.remember_claim(row)
		_claim_revision+=1
		claims[row.block_id]=row
		return {"ok":true,"claim":row,"already_claimed":code=="already_claimed","local_saved":saved}
	if code in ["block_taken","unknown_block","schema"]:
		identity.data["pending"]={}
		identity.save()
	return {"ok":false,"code":code if not code.is_empty() else "network"}

func fetch_farm(id:String) -> Dictionary:
	var path:=Contract.farm_path(id)
	if path.is_empty():return {"ok":false,"code":"schema"}
	var result:Dictionary=await api.request(path)
	if not Contract.farm_matches(result,id):return {"ok":false,"code":"invalid_farm"}
	return {"ok":true,"farm":result}
