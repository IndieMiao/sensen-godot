extends SceneTree
const Main:=preload("res://demo/geofarm/geofarm_main.tscn")
const Fixture:=preload("res://tests/geofarm/parcel_fixtures.gd")
const Contract:=preload("res://demo/geofarm/geo_contract.gd")
const Bridge:=preload("res://demo/geofarm/geo_parcel_bridge.gd")
class Native extends MapBridge:
	signal parcel_ready(generation:int,style:int,payload:Dictionary)
	signal parcel_query_result(request:int,generation:int,style:int,payload:Dictionary)
	signal parcel_error(generation:int,style:int,code:String)
	var sources:Array=[]
	var queries:Array=[]
	var states:Array=[]
	var labels:Array=[]
	var visible:=true
	func is_parcel_capable() -> bool:return true
	func configure(g:int,c:Dictionary) -> void:sources.append({"generation":g,"config":c})
	func query(r:int,g:int,p:Vector2) -> void:queries.append({"request":r,"generation":g,"point":p})
	func set_states(_g:int,rows:Array) -> void:states.append(rows.duplicate(true))
	func set_claims(_g:int,rows:Array) -> void:labels.append(rows.duplicate(true))
	func clear(_g:int) -> void:pass
	func set_map_visible(value:bool) -> void:visible=value
var page:Control
var native:Native
var checked:=0
var failed:=0
var calls:Array=[]
var reply:Dictionary={}
var server_claims:Array=[]
var hold_claim:=false
var hold_farm:=false
var hold_claims:=false
var claims_fail:=false
signal release_claim
signal release_farm
signal release_claims
func _initialize() -> void:_run.call_deferred()
func verify(ok:bool,label:String) -> void:
	checked+=1
	if not ok:failed+=1
	print("PASS " if ok else "FAIL ",label)
func transport(path:String,body:Dictionary) -> Dictionary:
	calls.append({"path":path,"body":body.duplicate(true)})
	if path=="/manifest.json":return Fixture.manifest()
	if path=="/claims":
		var snapshot:=server_claims.duplicate(true)
		if hold_claims:await release_claims
		return {"ok":false} if claims_fail else {"ok":true,"dataset_version":Contract.DATASET,"claims":snapshot}
	if path=="/claim":
		if hold_claim:await release_claim
		if reply.get("ok")==true or reply.get("code")=="already_claimed":
			if not server_claims.any(func(row:Dictionary):return row.block_id==reply.claim.block_id):server_claims.append(reply.claim.duplicate(true))
		return reply.duplicate(true)
	if path.begins_with("/farms/"):
		if hold_farm:await release_farm
		return Fixture.farm(path.get_file().get_basename())
	return {"ok":false,"code":"network"}
func select_reply(p:Array) -> void:
	page._map_tapped(Vector2(.5,.5))
	var q:Dictionary=native.queries[-1]
	native.parcel_query_result.emit(q.request,q.generation,page._style_generation,{"parcel_ids":p.map(func(x:Dictionary):return x.block_id),"properties":p,"error":""})
func reset_identity() -> void:
	page.identity.data={"dataset_version":Contract.DATASET,"device_id":"a".repeat(64),"nickname":"","own_block_id":"","pending":{}}
	page.identity.path="user://test-parcel-flow.json";page.identity.save()
	server_claims=[];page.session.claims={};reply={};calls=[];claims_fail=false
	if is_instance_valid(page._farm):page._back_to_map()
	page._select(Fixture.metadata())
func _run() -> void:
	root.size=Vector2i(360,800);root.content_scale_size=Vector2i(360,800)
	page=Main.instantiate();root.add_child(page)
	page.set_process(false);page.api.transport=transport;page.api.base_url="https://demo.invalid"
	native=Native.new();page.bridge=native
	native.parcel_ready.connect(page._native_loaded);native.parcel_query_result.connect(page._query_result);native.parcel_error.connect(page._native_error)
	reset_identity()
	await page._bootstrap()
	verify(native.sources.size()==1 and native.sources[0].config.parcel_url=="https://demo.invalid/index.geojson","native receives URL instead of Godot geometry")
	verify(native.sources[0].config.promote_id=="block_id","native promoteId matches prefixed wire identity")
	verify(not calls.any(func(c:Dictionary):return c.path in ["/index.geojson","/buildings.geojson","/parcel-catalog.json"]),"Godot bootstrap never downloads geometry or full catalog")
	verify(not page._native_ready,"parcel selection waits for source readiness")
	native.parcel_ready.emit(page._generation,1,{"source_ready":true,"parcel_source_ready":true,"buildings_source_ready":false})
	verify(page._native_ready,"hidden building source does not block z17.5 parcel selection")
	var labels_before:=native.labels.size()
	native.parcel_ready.emit(page._generation,1,{"source_ready":true,"buildings_source_ready":true})
	verify(native.labels.size()==labels_before,"same-style ready updates do not repeatedly resend claim source")
	page._map_tapped(Vector2(.25,.75))
	verify(native.queries[-1].point==Vector2(.25,.75),"tap is normalized once with no density multiplier")
	var old_query:Dictionary=native.queries[-1]
	page.map_canvas._pan(Vector2(2,0))
	native.parcel_query_result.emit(old_query.request,old_query.generation,1,{"parcel_ids":["p-A"],"properties":[Fixture.metadata()],"error":""})
	verify(page._selected=="","camera move invalidates pending parcel pick")
	select_reply([Fixture.metadata()])
	verify(page._selected=="p-A" and page.by_id["p-A"].parcel_id=="A","query metadata selects prefixed ID and retains canonical identity")
	verify(not page.by_id["p-A"].has("geometry"),"selection metadata cache contains no geometry")
	var encoded:=Fixture.metadata();encoded.center=JSON.stringify(encoded.center);encoded.bbox=JSON.stringify(encoded.bbox)
	verify(not page._metadata(encoded).is_empty(),"native string-encoded array properties normalize safely")
	page._map_tapped(Vector2(.5,.5));var current:Dictionary=native.queries[-1]
	native.parcel_query_result.emit(current.request,current.generation-1,1,{"parcel_ids":["p-A"],"properties":[Fixture.metadata()],"error":""})
	verify(page._selected=="","old scene/data generation callback ignored")
	native.parcel_query_result.emit(current.request,current.generation,0,{"parcel_ids":["p-A"],"properties":[Fixture.metadata()],"error":""})
	verify(page._selected=="","old native style generation callback ignored")
	select_reply([Fixture.metadata(),Fixture.metadata("p-B")])
	verify(is_instance_valid(page._dialog) and page._selected=="","multiple candidates require explicit choice")
	page._close_dialog();select_reply([Fixture.metadata()])
	page._action_pressed()
	verify(is_instance_valid(page._dialog) and page._stage=="confirm","parcel tap still requires confirmation")
	verify(page.is_back_navigation_locked() and not is_instance_valid(page._dialog),"Back closes confirmation without leaving map")
	page._confirm();page._nickname()
	verify(page._stage=="nickname","confirmation advances to nickname")
	page._close_dialog()
	hold_claim=true;reply={"ok":true,"claim":Fixture.claim()}
	page._claim("p-A","Tester A");page._claim("p-A","Tester A")
	verify(calls.filter(func(c:Dictionary):return c.path=="/claim").size()==1,"in-flight claim emits only one POST")
	verify(page.is_back_navigation_locked(),"Back remains blocked during authoritative claim")
	hold_claim=false;release_claim.emit();await process_frame
	verify(page.identity.data.own_block_id=="p-A" and page.identity.data.pending.is_empty(),"server success persists v2 parcel ownership")
	verify(is_instance_valid(page._farm) and page._farm._grid._cells.size()==4 and not native.visible,"claim loads shared Building8 farm and pauses native map")
	verify(page.is_back_navigation_locked() and not is_instance_valid(page._farm) and native.visible,"Back resumes native map from farm")
	reset_identity();reply={"ok":false,"code":"block_taken"};await page._claim("p-A","Tester A")
	verify(page.identity.data.own_block_id=="" and page.identity.data.pending.is_empty(),"competing claim does not grant ownership")
	reset_identity();reply={"ok":false,"code":"already_claimed","claim":Fixture.claim("p-B")};await page._claim("p-A","Tester A")
	verify(page.identity.data.own_block_id=="p-B" and is_instance_valid(page._farm),"already_claimed opens server-owned parcel without global index")
	reset_identity();reply={"ok":false,"code":"network"};await page._claim("p-A","Tester A")
	verify(page.identity.data.pending.block_id=="p-A" and page.identity.data.own_block_id=="","unknown response leaves recoverable pending claim")
	server_claims=[Fixture.claim()];await page._load_claims()
	verify(page._action.text=="Retry previous claim","public visibility never masks unresolved own claim")
	reply={"ok":true,"claim":Fixture.claim()};page._action_pressed();await process_frame
	verify(page.identity.data.own_block_id=="p-A","idempotent recovery succeeds for original parcel")
	var posts:Array=calls.filter(func(c:Dictionary):return c.path=="/claim")
	verify(posts.size()==2 and posts[0].body==posts[1].body,"retry retains exact credential/parcel/nickname")
	reset_identity();reply={"ok":true,"claim":Fixture.claim("p-B")};await page._claim("p-A","Tester A")
	verify(page.identity.data.own_block_id=="" and not page.identity.data.pending.is_empty(),"mismatched successful claim rejected")
	reset_identity();server_claims=[Fixture.claim("p-A","Neighbor")];await page._load_claims();page._action_pressed();await process_frame
	verify(is_instance_valid(page._farm) and not calls.any(func(c:Dictionary):return c.path=="/claim"),"visitor views neighbor farm without POST")
	page._back_to_map();claims_fail=true;await page._load_claims()
	verify(page.session.claims.has("p-A"),"refresh failure preserves known claim markers")
	claims_fail=false;hold_farm=true;page._open_farm("p-B");page._back_to_map();hold_farm=false;release_farm.emit();await process_frame
	verify(not is_instance_valid(page._farm) and native.visible,"late farm response cannot reopen after returning")
	reset_identity();hold_claims=true;page._load_claims();reply={"ok":true,"claim":Fixture.claim()};await page._claim("p-A","Tester A")
	hold_claims=false;release_claims.emit();await process_frame
	verify(page.identity.data.own_block_id=="p-A" and page.session.claims.has("p-A"),"old claims snapshot cannot erase the newly committed claim")
	page._back_to_map()
	page._native_error(page._generation,1,"buildings_source_load_failed")
	verify(page._native_ready and page._needs_map_retry,"building-only failure retains parcel picking with retry warning")
	page._native_error(page._generation,1,"parcels_source_load_failed")
	verify(not page._native_ready,"parcel-source failure disables picking")
	verify(Bridge._decode("broken").get("error")=="invalid_native_response","bad native JSON is rejected quietly")
	page.api.transport=Callable();page.queue_free();await process_frame
	DirAccess.remove_absolute("user://test-parcel-flow.json")
	print("PARCEL FLOW ",checked-failed,"/",checked)
	quit(1 if failed else 0)
