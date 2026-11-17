extends "res://demo/geofarm/geo_identity.gd"
const Contract := preload("res://demo/geofarm/geo_contract.gd")
const PARCEL_PATH := "user://geo_farm_identity_sf-parcel-20261117-v3.json"
const V2_PATH := "user://geo_farm_identity_sf-parcel-20261117-v2.json"
func load_parcel(at:="",legacy_at:=PATH,version:=Contract.DATASET) -> bool:
	if not Contract.valid_dataset(version):return false
	path=Contract.identity_path(version) if at.is_empty() else at
	if FileAccess.file_exists(path):
		var json:=JSON.new()
		if json.parse(FileAccess.get_file_as_string(path))!=OK or not json.data is Dictionary:return false
		data=json.data
		if data.get("dataset_version")!=version:return false
		if not valid_device(str(data.get("device_id",""))):return false # never silently lose a claimed install
		if not data.get("pending",{}) is Dictionary or not data.get("own_block_id","") is String:return false
		var own:String=data.get("own_block_id","")
		if not own.is_empty() and not Contract.valid_id(own):return false
		var pending:Dictionary=data.get("pending",{})
		if not pending.is_empty() and (not Contract.valid_id(pending.get("block_id")) or not pending.get("nickname") is String or not valid_nickname(pending.nickname)):return false
	else:
		var device:=""
		# The installation credential can survive an app update. Census ownership cannot.
		# Read only the old credential; never rewrite/migrate r1 claims or its pending action.
		var previous:Array=[legacy_at]
		if legacy_at==PATH:
			previous=[Contract.identity_path(Contract.DATASET),Contract.identity_path(Contract.SMALL_DATASET),V2_PATH,PATH]
		for candidate in previous:
			if candidate==path or str(candidate).is_empty() or not FileAccess.file_exists(candidate):continue
			var legacy:=JSON.new()
			if legacy.parse(FileAccess.get_file_as_string(candidate))!=OK or not legacy.data is Dictionary:return false
			device=str(legacy.data.get("device_id",""))
			if not valid_device(device):return false
			break
		if device.is_empty():device=Crypto.new().generate_random_bytes(32).hex_encode()
		data={"dataset_version":version,"device_id":device,"nickname":"","own_block_id":"","pending":{}}
	return save()
func remember_pending(block_id:String,nickname:String) -> bool:
	if not Contract.valid_id(block_id) or not valid_nickname(nickname):return false
	return super.remember_pending(block_id,nickname)
func remember_claim(claim:Dictionary) -> bool:
	if not Contract.valid_id(claim.get("block_id")) or not claim.get("nickname") is String or not valid_nickname(claim.nickname):return false
	return super.remember_claim(claim)
