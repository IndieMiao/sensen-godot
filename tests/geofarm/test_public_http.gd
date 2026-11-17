extends SceneTree
## Read-only public-demo smoke using the same HTTPRequest adapter as Android.
const Main:=preload("res://demo/geofarm/geofarm_main.tscn")
const Block:=preload("res://scenes/geo_farm_demo/farm_block.gd")
var failed:=false
func _initialize() -> void:_run.call_deferred()
func verify(value:bool,label:String) -> void:
	print("PASS " if value else "FAIL ",label)
	failed=failed or not value
func _run() -> void:
	var page=Main.instantiate();root.add_child(page);await process_frame
	page.set_process(false)
	page.api.base_url=OS.get_cmdline_user_args()[0]
	var start:=Time.get_ticks_msec()
	await page._load_index()
	verify(page.by_id.size()==5802,"real HTTPS index accepted: 5802 blocks")
	print("INDEX_AND_CLAIMS ms=",Time.get_ticks_msec()-start)
	if page.by_id.is_empty():page.queue_free();await process_frame;quit(1);return
	var result:Dictionary=await page.api.request("/claims")
	verify(result.get("ok")==true and result.get("_http_status")==200,"real HTTPS claims returned 200")
	verify(not JSON.stringify(result).contains("device_id"),"public claims omit private installation credential")
	var id:="60750201011000"
	var farm:Dictionary=await page.api.request("/farms/"+id+".json")
	verify(farm.get("_http_status")==200 and Block.decode(farm).get("ok")==true,"real HTTPS farm decoded by shared view model")
	await page._open_farm(id)
	verify(is_instance_valid(page._farm) and page._farm._grid._cells.size()==793,"real main-to-view HTTP path renders 793 generated cells")
	page._back_to_map()
	verify(page.map_canvas.visible and not is_instance_valid(page._farm),"return from live-data farm restores map")
	# Let the return-triggered HTTP request finish before releasing the node.
	while page._claims_busy:await process_frame
	page.queue_free();await process_frame
	print("PUBLIC_READ_ONLY_RESULT ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
