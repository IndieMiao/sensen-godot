extends SceneTree
const Main:=preload("res://demo/geofarm/geofarm_main.gd")
const Fixture:=preload("res://tests/geofarm/parcel_fixtures.gd")
var checked:=0
var failed:=0
func verify(ok:bool,label:String) -> void:
	checked+=1
	if not ok:failed+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:
	var raw:=Fixture.metadata()
	var clean:=Main._metadata(raw)
	verify(clean.get("cell_count")==800 and clean.get("total_cell_count")==1344,"core count and total remain distinct")
	for key in ["core_cell_count","extension_cell_count","total_cell_count"]:
		var missing:=raw.duplicate(true);missing.erase(key)
		verify(Main._metadata(missing).is_empty(),"missing zone count rejected: "+key)
	var wrong:=raw.duplicate(true);wrong.cell_count=wrong.total_cell_count
	verify(Main._metadata(wrong).is_empty(),"cell_count cannot be total")
	wrong=raw.duplicate(true);wrong.total_cell_count=raw.core_cell_count
	verify(Main._metadata(wrong).is_empty(),"incorrect sum rejected")
	wrong=raw.duplicate(true);wrong.extension_cell_count=0;wrong.total_cell_count=800
	verify(Main._metadata(wrong).is_empty(),"missing walking extension rejected")
	wrong=raw.duplicate(true);wrong.extension_cell_count=8000;wrong.total_cell_count=8800
	verify(Main._metadata(wrong).is_empty(),"over-budget total rejected")
	wrong=raw.duplicate(true);wrong.core_cell_count=800.5;wrong.cell_count=800.5;wrong.total_cell_count=1344.5
	verify(Main._metadata(wrong).is_empty(),"fractional cells rejected")
	raw.erase("cell_count");raw.center=JSON.stringify(raw.center);raw.bbox=JSON.stringify(raw.bbox)
	verify(Main._metadata(raw).get("cell_count")==800,"canonical counts accept native encoded arrays and core alias")
	print("DYNAMIC METADATA ",checked-failed,"/",checked)
	quit(1 if failed else 0)
