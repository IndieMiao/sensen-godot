extends SceneTree
const Main:=preload("res://demo/geofarm/geofarm_main.tscn")
const Fixture:=preload("res://tests/geofarm/fixtures.gd")
var page:Control
var output:String
var data_root:String
func _initialize() -> void:_run.call_deferred()
func shot(name:String) -> void:
	for frame in 5:await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	print("CAPTURE ",name," result=",image.save_png(output.path_join(name+".png"))," size=",image.get_size())
func _transport(path:String,_body:Dictionary) -> Dictionary:
	if path=="/claims":return {"ok":true,"dataset_version":Fixture.VERSION,"claims":[]}
	if path.begins_with("/farms/"):
		return JSON.parse_string(FileAccess.get_file_as_string(data_root.path_join(path.trim_prefix("/"))))
	return {"ok":false}
func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	output=args[0];data_root=args[1]
	root.size=Vector2i(720,1600);root.content_scale_size=Vector2i(360,800)
	page=Main.instantiate();root.add_child(page);await process_frame
	page.api.transport=_transport;page.set_process(false)
	page.identity.data={"device_id":"a".repeat(64),"nickname":"","own_block_id":"","pending":{}}
	var index:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(data_root.path_join("index.geojson")))
	if not page._take_index(index):printerr("REAL INDEX REJECTED");quit(1);return
	page._message.text="5802 blocks · drag to explore, pinch to zoom"
	var id:String=page.map_canvas.hit(Vector2(180,400))
	if id.is_empty():id=str(page.map_canvas._visible[0].id)
	page._select(id)
	print("REAL selected ",id," visible ",page.map_canvas._visible.size())
	await shot("map-real-data")
	page._confirm();await shot("confirm")
	page._nickname();await shot("nickname")
	page._close_dialog()
	page.claims={id:Fixture.claim(id,"Demo neighbor")};page.map_canvas.set_claims(page.claims.values(),"");page._select(id)
	await shot("neighbor")
	await page._open_farm(id);await shot("farm-through-map")
	page._back_to_map()
	root.size=Vector2i(320,568);root.content_scale_size=Vector2i(320,568)
	await shot("map-small")
	page._confirm();await shot("confirm-small")
	page.api.transport=Callable();page.queue_free();await process_frame
	quit(0)
