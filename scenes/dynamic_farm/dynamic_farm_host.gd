extends Node3D
## Presentation-only wrapper: connects child signals before tree entry and owns routing/errors.
signal preview_ready(summary:Dictionary)
signal preview_error(message:String)
signal closed(return_context:Dictionary)
const VIEW_SCENE:="res://scenes/dynamic_farm/dynamic_farm.tscn"
const Contract:=preload("res://modules/dynamic_farm/map/geo_contract.gd")
var view_factory:=Callable() # isolated lifecycle fixture; production loads the fixed scene above
var _args:Dictionary={}
var _view:Node3D
var _epoch:=0
var _leaving:=false
var _state:="loading"
var _hud:CanvasLayer
var _panel:PanelContainer
var _message:Label
var _retry:Button

func setup(args:Dictionary) -> void:
	_args={}
	for key in ["farm","dataset","block_id","preview_only","own_parcel","farm_store"]:
		if args.has(key):_args[key]=args[key].duplicate(true) if args[key] is Dictionary or args[key] is Array else args[key]
	_args["return_context"]=args.return_context.duplicate(true) if args.get("return_context") is Dictionary else {}
func _ready() -> void:
	get_viewport().transparent_bg=false
	_build_hud()
	if await _surface_settled():_open_view()

## C-168: as this scene is pushed the map asks Android for an opaque Godot surface (dynamic_farm_map._suspend_map), and
## Android replaces the surface on its UI thread. The parcel is built in one long frame (seconds under an emulator's
## software renderer); replaced during it, the render thread presents to the old surface (EGL_BAD_SURFACE) and Godot
## draws nothing more until the app is backgrounded. So the first build waits until the map plugin reports the surface
## opaque (at most SURFACE_WAIT_MS), then SURFACE_SETTLE_FRAMES drawn frames: the render thread is on the new surface.
## Without the plugin (desktop, tests) it builds at once. False when Back left meanwhile.
const MAP_PLUGIN:="GodotMap"
const RGBX_8888:=2 # android.graphics.PixelFormat: the map plugin's opaque format
const SURFACE_WAIT_MS:=1500
const SURFACE_SETTLE_FRAMES:=2
## Frames waited for the surface on the last open (tests).
var surface_wait_frames:=0
func _surface_settled() -> bool:
	surface_wait_frames=0
	if not Engine.has_singleton(MAP_PLUGIN):return true
	var plugin:=Engine.get_singleton(MAP_PLUGIN)
	if not is_instance_valid(plugin) or not plugin.has_method("getMapVisibilityState"):return true
	var started:=Time.get_ticks_msec()
	# getMapVisibilityState returns the UI thread's last snapshot and asks for a new one: a stale one is not opaque yet.
	while Time.get_ticks_msec()-started<SURFACE_WAIT_MS and not surface_is_opaque(str(plugin.getMapVisibilityState())):
		if not await _drawn_frame():return false
	for frame in SURFACE_SETTLE_FRAMES:
		if not await _drawn_frame():return false
	return true

## One frame drawn (AppRouter._render_frame); false when Back left meanwhile.
func _drawn_frame() -> bool:
	await get_tree().process_frame
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
	surface_wait_frames+=1
	return not _leaving and is_inside_tree()

## The plugin's cached state (getMapVisibilityState): the opaque mode asked for, and the surface Android has made in it.
static func surface_is_opaque(state_json:String) -> bool:
	var state=JSON.parse_string(state_json)
	if not state is Dictionary or not state.has("godot_surface_mode"):return true # an older plugin: nothing to wait for
	return int(state.godot_surface_mode)&1==1 and int(state.get("godot_requested_format",0))==RGBX_8888 \
		and int(state.get("godot_observed_format",0))==RGBX_8888
func _build_hud() -> void:
	_hud=CanvasLayer.new();_hud.layer=30;add_child(_hud)
	var root:=Control.new();root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.mouse_filter=Control.MOUSE_FILTER_IGNORE;_hud.add_child(root)
	_panel=PanelContainer.new();_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);_panel.offset_left=16;_panel.offset_top=32;_panel.offset_right=-16;root.add_child(_panel)
	var style:=StyleBoxFlat.new();style.bg_color=Color("FBF8F1");style.set_corner_radius_all(12);style.set_content_margin_all(12);_panel.add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);_panel.add_child(column)
	_message=Label.new();_message.text="Loading dynamic farm…";_message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_message.add_theme_color_override("font_color",Color("263E31"));column.add_child(_message)
	var actions:=HBoxContainer.new();column.add_child(actions)
	_retry=Button.new();_retry.text="Retry";_retry.custom_minimum_size.y=44;_retry.pressed.connect(_open_view);actions.add_child(_retry)
	var back:=Button.new();back.text="Back to map";back.custom_minimum_size.y=44;back.size_flags_horizontal=Control.SIZE_EXPAND_FILL;back.pressed.connect(_leave);actions.add_child(back)

func _valid_context() -> bool:
	var farm=_args.get("farm")
	# own_parcel: the owner's claimed parcel, farmed through ParcelFarming (C-34); otherwise a read-only preview.
	return (_args.get("preview_only")==true or _args.get("own_parcel")==true) and Contract.valid_dataset(_args.get("dataset")) and farm is Dictionary and farm.get("schema")==4 and farm.get("dataset_version")==_args.dataset and farm.get("selection_unit")=="parcel" and _args.get("block_id") is String and _args.block_id.begins_with("p-") and _args.block_id.length()>2 and _args.block_id==farm.get("block_id")
func _open_view() -> void:
	if _leaving:return
	_epoch+=1;var epoch:=_epoch
	_drop_view()
	_state="loading";_panel.show();_retry.hide();_message.text="Loading dynamic farm…"
	if not _valid_context():_failed("This dynamic farm preview is not available.",epoch);return
	var candidate:Node
	if view_factory.is_valid():candidate=view_factory.call()
	elif ResourceLoader.exists(VIEW_SCENE):
		var packed=load(VIEW_SCENE)
		if packed is PackedScene:candidate=packed.instantiate()
	if not candidate is Node3D or not candidate.has_method("setup"):
		if is_instance_valid(candidate):candidate.free()
		_failed("This build is missing the dynamic farm scene.",epoch);return
	for signal_name in ["preview_ready","preview_error","back_requested"]:
		if not candidate.has_signal(signal_name):
			candidate.free();_failed("This dynamic farm scene is not supported.",epoch);return
	_view=candidate
	# Connecting before add_child is essential: a valid child may report ready/error inside _ready.
	_view.preview_ready.connect(_ready_result.bind(epoch))
	_view.preview_error.connect(_failed.bind(epoch))
	_view.back_requested.connect(_child_back.bind(epoch))
	_view.setup(_args.duplicate(true))
	if _leaving or _state=="error":_drop_view();return
	add_child(_view)
func _ready_result(summary:Dictionary,epoch:int) -> void:
	if epoch!=_epoch or _leaving or _state!="loading":return
	if summary.get("dataset")!=_args.dataset or summary.get("block_id")!=_args.block_id:
		_failed("This preview does not match the selected parcel.",epoch);return
	_state="ready";_panel.hide();preview_ready.emit(summary.duplicate(true))
func _failed(message:String,epoch:int) -> void:
	if epoch!=_epoch or _leaving:return
	_state="error"
	if is_instance_valid(_view):
		_view.process_mode=Node.PROCESS_MODE_DISABLED
		if _view.is_inside_tree() and _view.has_method("suspend"):_view.suspend()
	_panel.show();_retry.show();_message.text=message if not message.is_empty() else "Could not open this farm. Please try again."
	preview_error.emit(_message.text)
func _child_back(epoch:int) -> void:
	if epoch==_epoch:_leave()
func _leave() -> void:
	if _leaving:return
	_leaving=true;_epoch+=1
	_finish_leave.call_deferred()
func _finish_leave() -> void:
	if not is_inside_tree():return
	var router:=get_node_or_null("/root/AppRouter")
	if router and router.has_method("top_instance") and router.top_instance()==self:
		router.pop_instance()
	else:closed.emit(_args.get("return_context",{}).duplicate(true))
func is_back_navigation_locked() -> bool:
	# Android Back closes the farm's open drawer (the bag, C-74) before it leaves the farm.
	if is_instance_valid(_view) and _view.has_method("close_modal") and _view.close_modal():return true
	_leave();return true
func suspend() -> void:
	process_mode=Node.PROCESS_MODE_DISABLED
	if is_instance_valid(_hud):_hud.hide()
	if is_instance_valid(_view) and _view.has_method("suspend"):_view.suspend()
func resume() -> void:
	process_mode=Node.PROCESS_MODE_INHERIT
	get_viewport().transparent_bg=false
	if is_instance_valid(_hud):_hud.show()
	if is_instance_valid(_view) and _state=="ready" and _view.has_method("resume"):_view.resume()
func _drop_view() -> void:
	if not is_instance_valid(_view):return
	if _view.is_inside_tree() and _view.has_method("suspend"):_view.suspend()
	if _view.get_parent()==self:remove_child(_view)
	_view.queue_free();_view=null
func presentation_state() -> Dictionary:
	var result:={"state":_state,"viewport_transparent":get_viewport().transparent_bg}
	if is_instance_valid(_view):
		for child in _view.get_children():
			if child is WorldEnvironment and child.environment != null:
				result["environment_mode"]=child.environment.background_mode
				result["background_rgba"]=child.environment.background_color.to_html(true)
	return result
func _exit_tree() -> void:
	_leaving=true;_epoch+=1
