extends SceneTree
## Real HTTPS reads only. No claim POST and no claim of native Mapbox rendering coverage.
const Main:=preload("res://demo/geofarm/geofarm_main.tscn")
const Contract:=preload("res://demo/geofarm/geo_contract.gd")
var failed:=0
var checked:=0
func _initialize() -> void:_run.call_deferred()
func verify(ok:bool,label:String) -> void:
	checked+=1
	if not ok:failed+=1
	print("PASS " if ok else "FAIL ",label)
func _run() -> void:
	var page=Main.instantiate();root.add_child(page);page.set_process(false)
	page.api.base_url=OS.get_cmdline_user_args()[0]
	page.config={"manifest_sha256":"318d4e27405ae879226d1672c0253b3930e119cf878115bd71d559fc932e40db"}
	await page._bootstrap()
	verify(page.manifest.get("parcel_count")==1322,"pinned real HTTPS manifest validates 1322 parcel dataset")
	verify(page.manifest.get("dataset_version")==Contract.DATASET,"r2 service version isolated from r1")
	verify(absf(page.map_canvas.center[0]+122.45190271843384)<.00000001 and page.map_canvas.zoom==17.5,"manifest sets exact screenshot-region default camera")
	var claims:Dictionary=await page.session.refresh_claims()
	verify(claims.get("ok")==true,"real r2 public claims endpoint read")
	for id in ["p-3139019","p-3139010"]:
		await page._open_farm(id)
		verify(is_instance_valid(page._farm) and page._farm._grid._cells.size()==(795 if id=="p-3139019" else 809),"real "+id+" farm reaches shared view with exact cell count")
		verify(page._farm._stats.text.contains("House"),"real "+id+" house layer is counted")
		page._back_to_map()
		while page._claims_busy:await process_frame
	page.queue_free();await process_frame
	print("PARCEL PUBLIC READS ",checked-failed,"/",checked)
	quit(1 if failed else 0)
