extends SceneTree
const Main := preload("res://demo/geofarm/geofarm_main.tscn")
const Geo := preload("res://demo/geofarm/geo_math.gd")
const Identity := preload("res://demo/geofarm/geo_identity.gd")
const Api := preload("res://demo/geofarm/geo_api.gd")
const Fixture := preload("res://tests/geofarm/fixtures.gd")
var checks:=0
var failed:=0
var page:Control
var posted:Array=[]
var reply:Dictionary={}
var server_claims:Array=[]
var delay_claim:=false
var delay_farm:=false
var bad_claims:=false
signal claim_reply
signal farm_reply

func _initialize() -> void:_run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failed+=1;printerr("FAIL ",label)
	else:print("PASS ",label)
func _transport(path:String,body:Dictionary) -> Dictionary:
	if path=="/claim":
		posted.append(body.duplicate(true))
		if delay_claim:await claim_reply
		return reply.duplicate(true)
	if path=="/claims":
		return {"ok":false} if bad_claims else {"ok":true,"dataset_version":Fixture.VERSION,"claims":server_claims.duplicate(true)}
	if path=="/index.geojson":return Fixture.index_data()
	if path.begins_with("/farms/"):
		if delay_farm:await farm_reply
		return Fixture.farm(path.get_file().get_basename())
	return {"ok":false,"code":"network"}
func reset_identity() -> void:
	page.identity.data={"device_id":"a".repeat(64),"nickname":"","own_block_id":"","pending":{}}
	page.identity.path="user://test-flow.json"
	page.identity.save()
	page.claims={};server_claims=[];reply={};posted=[];bad_claims=false
	if is_instance_valid(page._farm):page._back_to_map()
	page._select("A")

func _run() -> void:
	root.size=Vector2i(360,800)
	root.content_scale_size=Vector2i(360,800)
	var center:=Vector2(-122.4194,37.7749)
	var size:=Vector2(360,800)
	var scale:=512.0*pow(2.0,15)
	var screen:=Geo.project(center.x,center.y,center,size,scale)
	check(screen.distance_to(size*.5)<.001,"camera center projects to viewport center")
	var north:=Geo.project(center.x,center.y+.001,center,size,scale)
	check(north.y<screen.y,"north projects upward")
	var east:=Geo.project(center.x+.001,center.y,center,size,scale)
	check(absf(east.x-screen.x-scale*.001/360.0)<.001,"longitude uses Mercator world pixels")
	var back:=Geo.unproject(east,center,size,scale)
	check(absf(back[0]-(center.x+.001))<.00000001 and absf(back[1]-center.y)<.00000001,"project/unproject round trip")
	check(is_equal_approx(Geo.world_pixels(15,3,800,2400),scale),"physical density and viewport stretch cancel correctly")
	check(is_equal_approx(Geo.world_pixels(15,2,800,2400),scale*2.0/3.0),"nonmatching density gets correct projection scale")
	var outer:=PackedVector2Array([Vector2(0,0),Vector2(10,0),Vector2(10,10),Vector2(0,10)])
	var hole:=PackedVector2Array([Vector2(4,4),Vector2(6,4),Vector2(6,6),Vector2(4,6)])
	check(Geo.contains(Vector2(2,2),[outer,hole]),"outer polygon selectable")
	check(not Geo.contains(Vector2(5,5),[outer,hole]),"hole is not selectable")
	check(not Geo.contains(Vector2(15,5),[outer,hole]),"outside is not selectable")
	check(Geo.valid_geometry(Fixture.feature("A",-122.42,37.77).geometry),"valid geographic ring accepted")
	check(not Geo.valid_geometry({"type":"Polygon","coordinates":[[[0,0],null,[1,1],[0,0]]]}),"malformed coordinate rejected without drawing")
	check(not Geo.valid_bbox([1,1,0,0]),"reversed bounds rejected")
	check(Api.valid_base("https://demo.example/geo") and not Api.valid_base("http://demo.example"),"HTTPS endpoint with prefix only")
	check(not Api.valid_base("https://user@host") and not Api.valid_base("https://host?x=y"),"credential/query base rejected")
	var identity=Identity.new()
	var file:="user://test-identity.json"
	if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	check(identity.load_or_create(file),"create independent demo identity")
	var device:String=identity.data.device_id
	check(Identity.valid_device(device),"device is exactly 64 lowercase hex")
	var again=Identity.new()
	check(again.load_or_create(file) and again.data.device_id==device,"identity persists across restart")
	check(identity.remember_pending("A","Tester A"),"pending claim persisted before POST")
	again.load_or_create(file)
	check(again.data.pending.block_id=="A","pending claim survives process restart")
	check(Identity.valid_nickname("玩家 A") and not Identity.valid_nickname(""),"Unicode nickname and empty validation")
	check(not Identity.valid_nickname("A\nB") and not Identity.valid_nickname("A".repeat(17)),"control characters and overlong nickname rejected")
	check(not Identity.valid_nickname("A\u200bB"),"invisible formatting character rejected like server")
	var f:=FileAccess.open(file,FileAccess.WRITE);f.store_string("broken");f.close()
	check(not again.load_or_create(file),"corrupt identity fails closed instead of issuing new device")
	page=Main.instantiate();root.add_child(page)
	await process_frame
	page.api.transport=_transport
	page.set_process(false)
	reset_identity()
	check(page._take_index(Fixture.index_data()),"full index accepted")
	check(page.map_canvas._visible.size()==2,"only viewport blocks projected")
	check(page.map_canvas.hit(size*.5)=="A","map hit finds centered block")
	page.map_canvas.zoom=19;page.map_canvas._changed()
	var before:PackedFloat64Array=page.map_canvas.center.duplicate()
	page.map_canvas._pan(Vector2(1,0))
	check(page.map_canvas.center[0]!=before[0] and page.map_canvas.center[0]>before[0]-.00001,"street zoom retains sub-Vector2 precision when panning one pixel")
	page.map_canvas.center=before;page.map_canvas.zoom=15;page.map_canvas._changed()
	var malformed:=Fixture.index_data();malformed.features[0].geometry.coordinates[0][1]=null
	check(not page._take_index(malformed) and page.by_id.size()==3,"bad index retains last valid index")
	page._select("A");page._action_pressed()
	check(is_instance_valid(page._dialog) and page._stage=="confirm","select opens confirm before nickname")
	check(page.is_back_navigation_locked() and not is_instance_valid(page._dialog),"Back closes confirm without leaving map")
	page._confirm();page._nickname()
	check(page._stage=="nickname","confirm advances to nickname")
	page._close_dialog()
	delay_claim=true;reply={"ok":true,"claim":Fixture.claim("A","Tester A")}
	page._claim("A","Tester A")
	page._claim("A","Tester A")
	check(posted.size()==1 and page._busy,"in-flight duplicate POST suppressed")
	check(page.is_back_navigation_locked() and page._busy,"Back swallowed during claim")
	delay_claim=false;claim_reply.emit()
	await process_frame
	check(page.identity.data.own_block_id=="A" and page.identity.data.pending.is_empty(),"success records ownership and clears pending")
	check(is_instance_valid(page._farm),"successful claim opens shared farm view")
	check(page.is_back_navigation_locked() and not is_instance_valid(page._farm) and page.map_canvas.visible,"Back returns farm to map")
	reset_identity();reply={"ok":false,"code":"block_taken"}
	await page._claim("A","Tester A")
	check(page.identity.data.own_block_id=="" and page.identity.data.pending.is_empty(),"block_taken does not grant ownership and allows another block")
	reset_identity();reply={"ok":false,"code":"already_claimed","claim":Fixture.claim("B","Tester A")}
	await page._claim("A","Tester A")
	check(page.identity.data.own_block_id=="B" and is_instance_valid(page._farm),"already_claimed restores server-owned block")
	reset_identity();reply={"ok":false,"code":"network"}
	await page._claim("A","Tester A")
	check(page.identity.data.pending.block_id=="A" and page.identity.data.own_block_id=="","lost response keeps pending without claiming success")
	server_claims=[Fixture.claim("A","Tester A")];await page._load_claims()
	page._select("A")
	check(page._action.text=="Retry previous claim","public claim does not hide pending ownership recovery")
	reply={"ok":true,"claim":Fixture.claim("A","Tester A")}
	page._action_pressed();await process_frame
	check(posted.size()==2 and page.identity.data.own_block_id=="A","retry is same-device idempotent POST then own farm")
	check(posted[0]==posted[1],"recovery reuses original identity/block/nickname")
	reset_identity();reply={"ok":true,"claim":Fixture.claim("B","Wrong")}
	await page._claim("A","Tester A")
	check(page.identity.data.own_block_id=="" and not page.identity.data.pending.is_empty(),"wrong-block success rejected")
	reset_identity();server_claims=[Fixture.claim("A","Visible A")]
	await page._load_claims();page._select("A");page._action_pressed();await process_frame
	check(is_instance_valid(page._farm) and posted.is_empty() and page._selection.text.contains("Visible A"),"B can view A nickname/farm without claiming")
	page._back_to_map();bad_claims=true;await page._load_claims()
	check(page.claims.has("A") and page._message.text.contains("out of date"),"refresh failure retains last good claims with warning")
	bad_claims=false;delay_farm=true
	page._open_farm("B");page._back_to_map();farm_reply.emit();await process_frame
	check(not is_instance_valid(page._farm) and page.map_canvas.visible,"stale farm response cannot reopen after Back")
	delay_farm=false
	page.api.transport=Callable()
	page.queue_free();await process_frame
	for path in [file,"user://test-flow.json"]:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	print("RESULT ",checks-failed,"/",checks," checks passed; failures=",failed)
	quit(1 if failed else 0)
