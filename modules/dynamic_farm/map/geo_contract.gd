extends RefCounted
## Wire identity is block_id for compatibility; parcel_id is the public canonical parcel number.
const SCHEMA := 4
const FARM_SCHEMA := 4
const DATASET := "sf-dynamic-farm-20261118-r4" # Reviewed r4 (fixtures). config.json dataset_version + manifest_sha256 select the active release.
const UNIT := "parcel"
const DATASET_PATTERN := "^sf-dynamic-farm-[0-9]{8}-r[0-9]{1,3}$"

static func valid_id(value:Variant) -> bool:
	if not value is String or not value.begins_with("p-") or value.length()<3 or value.length()>100:
		return false
	for c in value:
		if not c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-*":return false
	return true

static func valid_dataset(value:Variant) -> bool:
	return value is String and RegEx.create_from_string(DATASET_PATTERN).search(value)!=null

static func identity_path(version:String) -> String:
	return "user://geo_farm_identity_"+version+".json" if valid_dataset(version) else ""

static func envelope(value:Dictionary,version:String) -> bool:
	return valid_dataset(version) and value.get("schema")==SCHEMA and value.get("dataset_version")==version and value.get("selection_unit")==UNIT

static func parcel_identity(value:Dictionary) -> bool:
	var id=value.get("block_id")
	var canonical=value.get("parcel_id")
	return valid_id(id) and canonical is String and not canonical.is_empty() and id=="p-"+canonical

static func farm_path(id:String) -> String:
	return "/farms/"+id+".json" if valid_id(id) else ""

static func farm_matches(value:Dictionary,id:String,version:String) -> bool:
	return valid_dataset(version) and value.get("schema")==FARM_SCHEMA and value.get("dataset_version")==version and value.get("selection_unit")==UNIT and parcel_identity(value) and value.block_id==id
