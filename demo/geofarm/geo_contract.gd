extends RefCounted
## Wire identity is block_id for compatibility; parcel_id is the public canonical parcel number.
const SCHEMA := 2
const DATASET := "sf-parcel-20261117-v2"
const UNIT := "parcel"

static func valid_id(value:Variant) -> bool:
	if not value is String or not value.begins_with("p-") or value.length()<3 or value.length()>100:
		return false
	return value.uri_encode()==value and not "/" in value and not "." in value

static func envelope(value:Dictionary) -> bool:
	return value.get("schema")==SCHEMA and value.get("dataset_version")==DATASET and value.get("selection_unit")==UNIT

static func parcel_identity(value:Dictionary) -> bool:
	var id=value.get("block_id")
	var canonical=value.get("parcel_id")
	return valid_id(id) and canonical is String and not canonical.is_empty() and id=="p-"+canonical

static func farm_path(id:String) -> String:
	return "/farms/"+id+".json" if valid_id(id) else ""

static func farm_matches(value:Dictionary,id:String) -> bool:
	return envelope(value) and parcel_identity(value) and value.block_id==id
