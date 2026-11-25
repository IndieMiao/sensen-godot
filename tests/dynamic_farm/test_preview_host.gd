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
## The Android map plugin's visibility state as the host reads it (GodotMapPlugin.getMapVisibilityState): transparent
## (the UI thread's snapshot from before the map asked for opaque) for `stale` calls, then opaque.
class SurfacePlugin extends Object:
	var stale:=0
	var calls:=0
	func getMapVisibilityState() -> String:
		calls+=1
		if calls<=stale:return JSON.stringify({"godot_surface_mode":2,"godot_requested_format":-3,"godot_observed_format":-3})
		return JSON.stringify({"godot_surface_mode":5,"godot_requested_format":2,"godot_observed_format":2})
## An Android singleton: a JavaObject wrapper whose has_method does not see the Java methods (MapBridgeAndroid._supports).
class JavaWrapper extends Object:
	func has_java_method(method:String) -> bool:return method=="getMapVisibilityStateJava"
	func getMapVisibilityState() -> String:return "{}"
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
## C-168: the parcel is built only once Android has made the opaque surface the map asked for, and its loading limit
## counts drawn frames only.
func _surface_checks(router:Node) -> void:
	var Host_:=preload("res://scenes/dynamic_farm/dynamic_farm_host.gd")
	verify(Host_.surface_is_opaque("{}"),"C-168: an older plugin without surface state is not waited for")
	verify(not Host_.surface_is_opaque(JSON.stringify({"godot_surface_mode":2,"godot_requested_format":-3,"godot_observed_format":-3})),
		"C-168: a snapshot from before the opaque request is not ready")
	verify(not Host_.surface_is_opaque(JSON.stringify({"godot_surface_mode":5,"godot_requested_format":2,"godot_observed_format":-2147483648})),
		"C-168: opaque asked for but no surface made in it yet is not ready")
	verify(Host_.surface_is_opaque(JSON.stringify({"godot_surface_mode":5,"godot_requested_format":2,"godot_observed_format":2})),
		"C-168: the opaque surface made is ready")
	var java:=JavaWrapper.new()
	verify(not Host_._plugin_has(java,"getMapVisibilityState") and Host_._plugin_has(java,"getMapVisibilityStateJava"),
		"C-168: an Android singleton's methods are asked through has_java_method, not the wrapper's has_method")
	java.free()
	var plugin:=SurfacePlugin.new();plugin.stale=2
	Engine.register_singleton("GodotMap",plugin)
	var host=Host.instantiate();host.view_factory=_factory;host.setup(args());router.top=host;root.add_child(host)
	verify(host._state=="loading" and not is_instance_valid(host._view),"C-168: no parcel is built while Android still has the old surface")
	for frame in 8:
		if host._state!="loading":break
		await process_frame
	verify(host._state=="ready" and plugin.calls==3,"C-168: the parcel is built after the opaque surface is reported")
	verify(host.surface_wait_frames==2+host.SURFACE_SETTLE_FRAMES,"C-168: then two more frames on the new surface first")
	host.queue_free();await process_frame
	plugin.calls=0
	var left=Host.instantiate();left.view_factory=_factory;left.setup(args());router.top=left;root.add_child(left)
	left._leave();await process_frame;await process_frame;await process_frame;await process_frame
	verify(not is_instance_valid(left._view),"C-168: Back while waiting for the surface builds no parcel")
	if is_instance_valid(left):left.queue_free()
	await process_frame
	Engine.unregister_singleton("GodotMap");plugin.free()
	var farm:Node3D=load("res://scenes/dynamic_farm/dynamic_farm.gd").new()
	verify(not farm.loading_timed_out(19.0),"C-168: one long stalled frame (the build, a lost surface) is not a timeout")
	var spent:=false
	for frame in 59:spent=farm.loading_timed_out(1.0) or spent
	verify(not spent,"C-168: 60 drawn frames, capped at 0.25 s each, stay under the 15 s limit")
	verify(farm.loading_timed_out(1.0),"C-168: past 15 s of drawn frames the scene still gives up")
	farm.free()

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
	await _surface_checks(router)
	RouterFixture.restore(root,router,real_router)
	print("PREVIEW HOST ",checked-failed,"/",checked)
	quit(1 if failed else 0)
