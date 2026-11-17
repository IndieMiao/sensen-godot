extends RefCounted
const PATH := "user://geo_farm_identity.json"
var data := {}
var path := PATH
var writable := false
static func valid_device(value: String) -> bool:
	if value.length()!=64: return false
	for c in value:
		if not c in "0123456789abcdef": return false
	return true
static func valid_nickname(value: String) -> bool:
	var s:=value.strip_edges()
	if s.length()<1 or s.length()>16: return false
	var forbidden:=RegEx.new()
	forbidden.compile("[\\p{Cc}\\p{Cf}]")
	if forbidden.search(value)!=null:return false
	return true
func load_or_create(at:=PATH) -> bool:
	path=at
	if FileAccess.file_exists(path):
		var json:=JSON.new()
		if json.parse(FileAccess.get_file_as_string(path))!=OK or not json.data is Dictionary:return false
		data=json.data
		if not valid_device(str(data.get("device_id",""))):return false # never silently lose a claimed install
		if not data.get("pending",{}) is Dictionary or not data.get("own_block_id","") is String:return false
		var pending:Dictionary=data.get("pending",{})
		if not pending.is_empty() and (not pending.get("block_id") is String or not pending.get("nickname") is String or not valid_nickname(pending.nickname)):return false
	else:
		data={"device_id":Crypto.new().generate_random_bytes(32).hex_encode(),"nickname":"","own_block_id":"","pending":{}}
	return save()
func save() -> bool:
	var temporary:=path+".tmp"
	var f:=FileAccess.open(temporary,FileAccess.WRITE)
	if f==null:writable=false;return false
	f.store_string(JSON.stringify(data));f.flush()
	var ok:=f.get_error()==OK;f.close()
	if not ok:writable=false;return false
	writable=DirAccess.rename_absolute(temporary,path)==OK
	return writable
func remember_pending(block_id:String,nickname:String) -> bool:
	data["pending"]={"block_id":block_id,"nickname":nickname}
	return save()
func remember_claim(claim:Dictionary) -> bool:
	data["own_block_id"]=str(claim.get("block_id",""))
	data["nickname"]=str(claim.get("nickname",""))
	data["pending"]={}
	return save()
