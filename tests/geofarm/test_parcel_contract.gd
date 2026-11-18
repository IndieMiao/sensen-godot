extends SceneTree
const Contract:=preload("res://demo/geofarm/geo_contract.gd")
const Identity:=preload("res://demo/geofarm/geo_parcel_identity.gd")
var failed:=0
var checked:=0
func verify(ok:bool,label:String) -> void:
	checked+=1
	if not ok:failed+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	verify(Contract.valid_id("p-2354001H") and Contract.valid_id("p-0039101"),"canonical parcel letters and leading zeroes preserved")
	verify(not Contract.valid_id("60750201011000") and not Contract.valid_id("p-../x"),"census IDs and traversal rejected")
	var farm:={"schema":4,"dataset_version":Contract.DATASET,"selection_unit":"parcel","block_id":"p-0039101","parcel_id":"0039101"}
	verify(Contract.farm_matches(farm,"p-0039101"),"wire block_id differs from canonical parcel_id by explicit prefix")
	verify(not Contract.farm_matches(farm,"p-0039102"),"wrong requested parcel rejected")
	farm.schema=2
	verify(not Contract.farm_matches(farm,"p-0039101"),"r1 response rejected")
	var legacy_path:="user://parcel-contract-legacy.json"
	var new_path:="user://parcel-contract-v2.json"
	for path in [legacy_path,new_path]:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	var legacy:={"device_id":"a".repeat(64),"nickname":"Old farm","own_block_id":"60750201011000","pending":{"block_id":"60750201011001","nickname":"Old pending"}}
	var f:=FileAccess.open(legacy_path,FileAccess.WRITE);f.store_string(JSON.stringify(legacy));f.close()
	var old_hash:=FileAccess.get_sha256(legacy_path)
	var identity=Identity.new()
	verify(identity.load_parcel(new_path,legacy_path),"v2 identity initializes from valid installation credential")
	verify(identity.data.device_id==legacy.device_id,"installation credential retained on update")
	verify(identity.data.own_block_id=="" and identity.data.pending.is_empty(),"r1 farm and pending claim are not migrated")
	verify(FileAccess.get_sha256(legacy_path)==old_hash,"r1 identity remains byte identical")
	verify(not identity.remember_pending("60750201011000","Tester"),"old census claim cannot be submitted from v2")
	verify(identity.remember_pending("p-0039101","Tester"),"parcel pending action persists")
	var reloaded=Identity.new()
	verify(reloaded.load_parcel(new_path,legacy_path) and reloaded.data.pending.block_id=="p-0039101","v2 pending resumes under same dataset")
	verify(identity.remember_claim({"block_id":"p-0039101","nickname":"Tester"}),"parcel claim records own farm")
	identity.data.dataset_version="sf-20261117-v1";identity.save()
	verify(not reloaded.load_parcel(new_path,legacy_path),"unexpected dataset in v2 identity fails closed")
	var old_path:="user://contract-prior-r3.json"
	var current_path:="user://contract-current-r4.json"
	for old_version in ["sf-parcel-20261117-v3","sf-parcel-small-20261117-v3"]:
		if FileAccess.file_exists(current_path):DirAccess.remove_absolute(current_path)
		var old:={"dataset_version":old_version,"device_id":"b".repeat(64),"own_block_id":"p-0039101","pending":{"block_id":"p-0039102","nickname":"Previous"}}
		f=FileAccess.open(old_path,FileAccess.WRITE);f.store_string(JSON.stringify(old));f.close()
		var before:=FileAccess.get_sha256(old_path)
		var current=Identity.new()
		verify(current.load_parcel(current_path,old_path,Contract.DATASET),"r4 initializes with prior installation credential")
		verify(current.data.device_id==old.device_id and current.data.own_block_id=="" and current.data.pending.is_empty(),"r3 ownership/pending never migrates into r4")
		verify(FileAccess.get_sha256(old_path)==before,"old r3 file remains byte-identical")
		verify(not current.load_parcel(current_path,old_path,old_version),"old dataset cannot be used as current r4")
	for path in [old_path,current_path]:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	for path in [legacy_path,new_path]:DirAccess.remove_absolute(path)
	print("PARCEL CONTRACT ",checked-failed,"/",checked)
	quit(1 if failed else 0)
