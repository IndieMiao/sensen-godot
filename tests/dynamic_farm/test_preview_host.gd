extends SceneTree
const Host:=preload("res://scenes/dynamic_farm/dynamic_farm_host.tscn")
const RouterFixture:=preload("res://tests/dynamic_farm/app_router_fixture.gd")
class View extends Node3D:
	signal preview_ready(summary:Dictionary)
	signal preview_error(message:String)
	signal back_requested
	var args:Dictionary={}
	var fail:=false
	var paused:=false
	func setup(value:Dictionary) -> void:args=value
	func _ready() -> void:
		if fail:preview_error.emit("Preview fixture failure.")
		else:preview_ready.emit({"dataset":args.dataset,"block_id":args.block_id})
	func suspend() -> void:paused=true
	func resume() -> void:paused=false
class Router extends Node:
	var top:Node
	var pops:=0
	func top_instance() -> Node:return top
	func pop_instance() -> void:
		pops+=1
		if is_instance_valid(top):top.suspend()
		top=null
var checked:=0
var failed:=0
var _fixture_fail:=false
func _initialize() -> void:_run.call_deferred()
func verify(value:bool,label:String) -> void:
	checked+=1
	if not value:failed+=1
	print("PASS " if value else "FAIL ",label)
func _factory() -> Node3D:
	var v:=View.new();v.fail=_fixture_fail;return v
func args() -> Dictionary:
	return {"dataset":"sf-dynamic-farm-20261118-r4","block_id":"p-A","preview_only":true,"farm":{"schema":4,"dataset_version":"sf-dynamic-farm-20261118-r4","selection_unit":"parcel","block_id":"p-A"},"return_context":{"zoom":18.5}}
func _run() -> void:
	var router:=Router.new();var real_router:=RouterFixture.install(root,router)
	verify(root.get_node_or_null("AppRouter")==router,"fixture router is the one the host resolves")
	var host=Host.instantiate();host.view_factory=_factory;host.setup(args());router.top=host;root.add_child(host)
	verify(host._state=="ready","synchronous child ready is observed before returning from add_child")
	verify(host._view.args.preview_only==true,"child is explicitly presentation-only")
	var epoch:int=host._epoch
	host.suspend();verify(host._view.paused,"suspend reaches the 3D child")
	host.resume();verify(not host._view.paused,"resume restores this preview")
	_fixture_fail=true;host._open_view()
	verify(host._state=="error" and host._retry.visible,"synchronous error keeps a retry and return UI")
	host._ready_result({"dataset":args().dataset,"block_id":"p-A"},epoch)
	verify(host._state=="error","late ready from replaced scene is ignored")
	_fixture_fail=false;host._open_view();verify(host._state=="ready","retry builds a fresh preview")
	host._child_back(epoch);verify(not host._leaving,"late Back from replaced scene cannot close current preview")
	verify(host.is_back_navigation_locked(),"wrapper consumes system Back")
	host.is_back_navigation_locked();host._leave();await process_frame
	verify(router.pops==1,"button/system/child Back can pop only once")
	host.queue_free();await process_frame
	var bad=Host.instantiate();bad.view_factory=_factory
	var bad_args:=args();bad_args.preview_only=false;bad.setup(bad_args);root.add_child(bad)
	verify(bad._state=="error" and not is_instance_valid(bad._view),"gameplay mode is rejected before scene construction")
	bad_args=args();bad_args.block_id="p-B";bad.setup(bad_args);bad._open_view()
	verify(bad._state=="error" and not is_instance_valid(bad._view),"mismatched parcel context never constructs a scene")
	bad_args=args();bad_args.farm.dataset_version="sf-dynamic-farm-20261124-r5";bad.setup(bad_args);bad._open_view()
	verify(bad._state=="error" and not is_instance_valid(bad._view),"farm from another dataset release never constructs a scene")
	bad_args=args();bad_args.dataset="latest";bad_args.farm.dataset_version="latest";bad.setup(bad_args);bad._open_view()
	verify(bad._state=="error" and not is_instance_valid(bad._view),"malformed dataset version never constructs a scene")
	bad.queue_free()
	var next=Host.instantiate();next.view_factory=_factory
	var next_args:=args();next_args.dataset="sf-dynamic-farm-20261124-r5";next_args.farm.dataset_version="sf-dynamic-farm-20261124-r5"
	next.setup(next_args);root.add_child(next)
	verify(next._state=="ready","C-43: configured next dataset release opens the preview")
	next.queue_free();await process_frame
	RouterFixture.restore(root,router,real_router)
	print("PREVIEW HOST ",checked-failed,"/",checked)
	quit(1 if failed else 0)
