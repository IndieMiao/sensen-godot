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
	var args:=OS.get_cmdline_user_args()
	if args.size()<3:printerr("Expected r3 base URL, dataset, client manifest SHA");quit(1);return
	page.api.base_url=args[0];page._dataset=args[1];page.session.dataset_version=args[1]
	page._identity_ok=page.identity.load_parcel("","user://geo_farm_identity.json",args[1])
	page.config={"manifest_path":"client-manifest.json","manifest_sha256":args[2]}
	await page._bootstrap()
	verify(int(page.manifest.get("parcel_count",0))>0,"pinned real HTTPS client manifest validates parcel dataset")
	verify(page.manifest.get("dataset_version")==args[1],"requested r3 service version matches exactly")
	verify(absf(page.map_canvas.center[0]+122.45190271843384)<.00000001 and page.map_canvas.zoom==17.5,"manifest sets exact screenshot-region default camera")
	var claims:Dictionary=await page.session.refresh_claims()
	verify(claims.get("ok")==true,"real r3 public claims endpoint read")
	var ids:Array=["p-3139019","p-3139010"]
	if args[1]==Contract.DATASET:ids.append("p-4591A011*")
	for id in ids:
		await page._open_farm(id)
		verify(is_instance_valid(page._farm) and (page._farm._grid._cells.size()==795 if id=="p-3139019" else page._farm._grid._cells.size()==809 if id=="p-3139010" else page._farm._grid._cells.size()>0),"real "+id+" farm reaches shared view with exact cell count")
		verify(page._farm._stats.text.contains("House"),"real "+id+" house layer is counted")
		page._back_to_map()
		while page._claims_busy:await process_frame
	page.queue_free();await process_frame
	print("PARCEL PUBLIC READS ",checked-failed,"/",checked)
	quit(1 if failed else 0)
