extends Control
const Api:=preload("res://demo/geofarm/geo_api.gd")
const Identity:=preload("res://demo/geofarm/geo_parcel_identity.gd")
const Contract:=preload("res://demo/geofarm/geo_contract.gd")
const Geo:=preload("res://demo/geofarm/geo_math.gd")
const Session:=preload("res://demo/geofarm/geo_parcel_session.gd")
const CameraInput:=preload("res://demo/geofarm/geo_native_camera.gd")
const ParcelBridge:=preload("res://demo/geofarm/geo_parcel_bridge.gd")
const FARM_VIEW:="res://scenes/geo_farm_demo/farm_view.tscn"
const CONFIG:="res://demo/geofarm/config.json"
var api:Node
var session:Node
var identity:=Identity.new()
var map_canvas:Control
var bridge:RefCounted
var config:Dictionary={}
var manifest:Dictionary={}
var by_id:Dictionary={} # Only selected/example metadata; never the geometry index.
var _examples:Array=[]
var _default_center:=PackedFloat64Array([-122.45190271843384,37.729419227])
var _default_zoom:=17.5
var _min_zoom:=17.0
var _selected:=""
var _busy:=false
var _manifest_busy:=false
var _claims_busy:=false
var _refresh_left:=10.0
var _identity_ok:=false
var _native_ready:=false
var _generation:=0
var _style_generation:=-1
var _camera_serial:=0
var _request_id:=0
var _pending_query:Dictionary={}
var _query_time:=0.0
var _sent_states:Dictionary={}
var _sent_claim_labels:Array=[]
var _has_sent_claim_labels:=false
var _map_warning:=""
var _needs_map_retry:=false
var _farm_generation:=0
var _farm:Control
var _dialog:Control
var _dialog_panel:MarginContainer
var _message:Label
var _selection:Label
var _action:Button
var _refresh:Button
var _overlay:Control
var _stage:="select"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().quit_on_go_back=false
	_identity_ok=identity.load_parcel()
	api=Api.new();add_child(api)
	session=Session.new();session.api=api;session.identity=identity;add_child(session)
	var parser:=JSON.new()
	if FileAccess.file_exists(CONFIG) and parser.parse(FileAccess.get_file_as_string(CONFIG))==OK and parser.data is Dictionary:
		config=parser.data
	if config.get("dataset_version")==Contract.DATASET:
		api.base_url=str(config.get("base_url","")).trim_suffix("/")
	for raw in config.get("examples",[]):
		var p:=_metadata(raw)
		if not p.is_empty():_examples.append(p);by_id[p.block_id]=p
	map_canvas=CameraInput.new();add_child(map_canvas)
	_build_ui()
	map_canvas.tapped.connect(_map_tapped);map_canvas.camera_changed.connect(_camera_changed)
	var token:=""
	if FileAccess.file_exists("res://mapbox_token.txt"):token=FileAccess.get_file_as_string("res://mapbox_token.txt").strip_edges()
	if Engine.has_singleton("GodotMap") and not token.is_empty():
		bridge=ParcelBridge.new()
		bridge.parcel_ready.connect(_native_loaded);bridge.parcel_query_result.connect(_query_result);bridge.parcel_error.connect(_native_error)
	map_canvas.setup_map(bridge,token)
	if not _identity_ok:_message.text="Demo identity could not be read or saved. Please restart."
	elif not Api.valid_base(api.base_url):_message.text="Demo service is not configured. Use the latest demo build."
	else:_bootstrap.call_deferred()

static func _metadata(raw:Variant) -> Dictionary:
	if not raw is Dictionary or not Contract.parcel_identity(raw) or not raw.get("name") is String:return {}
	raw=raw.duplicate(true)
	# Native queried-feature properties may serialize array-valued GeoJSON properties as JSON strings.
	for key in ["center","bbox"]:
		if raw.get(key) is String:
			var parser:=JSON.new()
			if parser.parse(raw[key])!=OK:return {}
			raw[key]=parser.data
	if raw.get("selection_unit",Contract.UNIT)!=Contract.UNIT:return {}
	if raw.get("farm_path")!=Contract.farm_path(raw.block_id).trim_prefix("/"):return {}
	if not Geo.valid_point(raw.get("center")) or not Geo.valid_bbox(raw.get("bbox")):return {}
	for key in ["cell_count","source_area_m2","inset_area_m2"]:
		if not (raw.get(key) is int or raw.get(key) is float) or not is_finite(float(raw[key])) or float(raw[key])<=0:return {}
	var result:Dictionary={}
	for key in ["block_id","parcel_id","name","address","address_count","center","bbox","cell_count","farm_path","source_area_m2","inset_area_m2","building_count"]:
		if raw.has(key):result[key]=raw[key]
	return result

func _build_ui() -> void:
	_overlay=Control.new();_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_overlay)
	var top:=_panel(_overlay,Vector4(12,30,-12,0),false)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",5);top.add_child(column)
	column.add_child(_label("San Francisco · Parcel DEMO",18))
	_message=_label("Loading parcel map…",12);column.add_child(_message)
	var row:=HBoxContainer.new();column.add_child(row)
	_refresh=_button("Refresh",_refresh_pressed);row.add_child(_refresh)
	row.add_child(_button("My farm",_my_farm));row.add_child(_button("Demo area",_reset_area))
	if not _examples.is_empty():
		var jump:=OptionButton.new();jump.add_item("Find an example parcel…");jump.set_item_disabled(0,true);jump.custom_minimum_size.y=38
		for p in _examples:jump.add_item(str(p.name))
		jump.item_selected.connect(func(i:int):
			if i>0 and i<=_examples.size():_jump_to(_examples[i-1])
			jump.select(0))
		column.add_child(jump)
	var zooms:=VBoxContainer.new();zooms.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT);zooms.position=Vector2(-60,-50);zooms.size=Vector2(48,104);_overlay.add_child(zooms)
	zooms.add_child(_button("+",func():map_canvas.change_zoom(.5)))
	zooms.add_child(_button("−",func():map_canvas.change_zoom(-.5)))
	var bottom:=_panel(_overlay,Vector4(12,0,-12,-28),true)
	var details:=VBoxContainer.new();details.add_theme_constant_override("separation",6);bottom.add_child(details)
	_selection=_label("Tap inside a parcel to choose your farm.",14);details.add_child(_selection)
	_action=_button("Select a parcel",_action_pressed);_action.disabled=true;details.add_child(_action)
	var credits:=HBoxContainer.new();details.add_child(credits)
	for entry in [["© Mapbox","https://www.mapbox.com/about/maps/"],["© OpenStreetMap","https://www.openstreetmap.org/copyright"]]:
		var credit:=Button.new();credit.text=entry[0];credit.flat=true;credit.add_theme_color_override("font_color",Color("3B5D4B"));credit.add_theme_font_size_override("font_size",10);credit.pressed.connect(OS.shell_open.bind(entry[1]));credits.add_child(credit)
	details.add_child(_label("Parcels / buildings: DataSF · PDDL / CC0",10))

func _bootstrap() -> void:
	if _manifest_busy or _busy or not _identity_ok:return
	_manifest_busy=true;_refresh.disabled=true;_native_ready=false;_map_warning="";_needs_map_retry=false
	_message.text="Loading demo area…"
	var result:Dictionary=await api.request("/manifest.json",{},str(config.get("manifest_sha256","")))
	_manifest_busy=false;_refresh.disabled=false
	if not Contract.envelope(result) or not result.get("native_map") is Dictionary:
		_message.text="Could not load this demo area. Tap Refresh to retry.";return
	var native:Dictionary=result.native_map
	if native.get("type")!="geojson" or native.get("promote_id")!="block_id" or native.get("parcel_url_path")!="index.geojson" or native.get("buildings_url_path")!="buildings.geojson" or not Geo.valid_point(native.get("center")):
		_message.text="This map version is not supported. Use the latest demo.";return
	var first_load:=manifest.is_empty()
	manifest=result
	_default_center=PackedFloat64Array(native.center);_default_zoom=float(native.get("initial_zoom",17.5));_min_zoom=float(native.get("minzoom",17))
	if first_load:_reset_area()
	await _load_claims()
	if bridge==null or not bridge.is_parcel_capable():
		_message.text="Native parcel map requires the latest Android demo.";return
	_generation+=1;_style_generation=-1;_pending_query={};_sent_states={};_has_sent_claim_labels=false
	bridge.configure(_generation,{"parcel_url":api.base_url+"/index.geojson","buildings_url":api.base_url+"/buildings.geojson","min_zoom":_min_zoom,"address_min_zoom":float(native.get("address_minzoom",18)),"promote_id":"block_id"})
	_message.text="Loading parcel boundaries…"
	_restore_pending()
func _refresh_pressed() -> void:
	if _busy:return
	if manifest.is_empty() or not _native_ready or _needs_map_retry:_bootstrap()
	else:_load_claims()
func _native_loaded(generation:int,style_generation:int,payload:Dictionary) -> void:
	if generation!=_generation or style_generation<_style_generation:return
	var reinitialize:=style_generation!=_style_generation or not _native_ready
	_style_generation=style_generation
	_native_ready=payload.get("source_ready")==true and str(payload.get("error",""))==""
	if _native_ready:
		if reinitialize:_sent_states={};_has_sent_claim_labels=false;_push_states()
		_map_hint()
	else:_message.text="Loading parcel boundaries…"
	_update_selection()
func _native_error(generation:int,style_generation:int,code:String) -> void:
	if generation!=_generation or style_generation<_style_generation:return
	_needs_map_retry=true
	if code=="buildings_source_load_failed":
		_map_warning="Building outlines could not load. Tap Refresh."
	elif code in ["claims_update_failed","claims_source_load_failed","feature_state_failed"]:
		_map_warning="Claim markers may be out of date. Tap Refresh."
	else:
		_native_ready=false;_pending_query={};_update_selection()
		_map_warning="Parcel map could not load. Tap Refresh to retry."
	_message.text=_map_warning
func _camera_changed() -> void:
	_camera_serial+=1;_pending_query={}
	if _native_ready:_map_hint()
func _map_hint() -> void:
	if not _map_warning.is_empty():_message.text=_map_warning;return
	_message.text="Zoom in to choose a parcel." if map_canvas.zoom<_min_zoom else "%d parcels · tap inside a boundary"%int(manifest.get("parcel_count",0))
func _map_tapped(point:Vector2) -> void:
	if not _native_ready or map_canvas.zoom<_min_zoom or _busy or is_instance_valid(_dialog) or is_instance_valid(_farm):return
	_request_id+=1;_pending_query={"request_id":_request_id,"camera":_camera_serial,"style":_style_generation};_query_time=0
	_selected="";_update_selection();_push_states();_message.text="Finding parcel…"
	bridge.query(_request_id,_generation,point)
func _query_result(request_id:int,generation:int,style_generation:int,payload:Dictionary) -> void:
	if generation!=_generation or style_generation!=_style_generation or request_id!=int(_pending_query.get("request_id",-1)) or int(_pending_query.get("camera",-1))!=_camera_serial:return
	_pending_query={}
	if is_instance_valid(_farm) or is_instance_valid(_dialog) or _busy:return
	if str(payload.get("error",""))!="" or not payload.get("parcel_ids") is Array or not payload.get("properties") is Array:
		_message.text="Could not check this parcel. Tap again.";return
	var candidates:Array=[];var seen:={}
	for raw in payload.properties:
		var p:=_metadata(raw)
		if p.is_empty() or not payload.parcel_ids.has(p.block_id) or seen.has(p.block_id):continue
		seen[p.block_id]=true;candidates.append(p)
	if candidates.is_empty():_message.text="No parcel here. Zoom in and tap inside a boundary.";return
	if candidates.size()==1:_select(candidates[0]);return
	var col:=_dialog_shell("Choose a parcel")
	col.add_child(_label("Several parcels meet here. Choose an address or zoom in.",14))
	for p in candidates.slice(0,6):col.add_child(_button(str(p.name),func():_close_dialog();_select(p)))
	col.add_child(_button("Cancel",_close_dialog))
func _select(p:Dictionary) -> void:
	if _busy:return
	if not Contract.parcel_identity(p):return
	_selected=str(p.block_id);by_id[_selected]=p
	_update_selection();_push_states()
func _update_selection() -> void:
	if not by_id.has(_selected):
		_selection.text="Tap inside a parcel to choose your farm.";_action.text="Select a parcel";_action.disabled=true;return
	var p:Dictionary=by_id[_selected]
	_selection.text=str(p.get("name","Your previous parcel"))
	if p.has("cell_count"):_selection.text+=" · %d cells"%int(p.cell_count)
	if p.has("inset_area_m2"):_selection.text+=" · %.0f m²"%float(p.inset_area_m2)
	if int(p.get("address_count",1))>1:_selection.text+="\n%d listed addresses"%int(p.address_count)
	var pending:Dictionary=identity.data.get("pending",{})
	if str(pending.get("block_id",""))==_selected:_action.text="Retry previous claim"
	elif session.claims.has(_selected):
		_selection.text+="\nClaimed by "+str(session.claims[_selected].nickname);_action.text="View farm"
	elif identity.data.get("own_block_id","")==_selected:_action.text="View my farm"
	else:_action.text="Choose this parcel"
	_action.disabled=_busy or not _native_ready
func _push_states() -> void:
	if not _native_ready or bridge==null:return
	var next:={};var own:=str(identity.data.get("own_block_id",""))
	for id in session.claims:next[id]={"block_id":id,"selected":id==_selected,"claimed":true,"own":id==own}
	for id in [_selected,own]:
		if Contract.valid_id(id) and not next.has(id):next[id]={"block_id":id,"selected":id==_selected,"claimed":id==own,"own":id==own}
	var changed:Array=[]
	for id in next:
		if _sent_states.get(id)!=next[id]:changed.append(next[id])
	for id in _sent_states:
		if not next.has(id):changed.append({"block_id":id,"selected":false,"claimed":false,"own":false})
	_sent_states=next
	if not changed.is_empty():bridge.set_states(_generation,changed)
	var labels:Array=[]
	for id in session.claims:
		var row:Dictionary=session.claims[id];var center_point=row.get("center",by_id.get(id,{}).get("center"))
		if Geo.valid_point(center_point):labels.append({"block_id":id,"nickname":row.nickname,"center":center_point})
	if not _has_sent_claim_labels or labels!=_sent_claim_labels:
		_sent_claim_labels=labels.duplicate(true);_has_sent_claim_labels=true;bridge.set_claims(_generation,labels)
func _load_claims() -> void:
	if _claims_busy or manifest.is_empty():return
	_claims_busy=true
	var result:Dictionary=await session.refresh_claims()
	_claims_busy=false;_refresh_left=10.0
	if result.get("ok")!=true:
		if result.get("code")=="superseded":_load_claims.call_deferred()
		else:_message.text="Claims may be out of date. Tap Refresh to retry."
		return
	_update_selection();_push_states()
func _action_pressed() -> void:
	if _busy or not _native_ready or not by_id.has(_selected):return
	var pending:Dictionary=identity.data.get("pending",{})
	if pending.get("block_id")==_selected:_claim(_selected,str(pending.nickname));return
	if session.claims.has(_selected) or identity.data.get("own_block_id")==_selected:_open_farm(_selected);return
	if not str(identity.data.get("own_block_id","")).is_empty():_message.text="This installation already has a farm. Use My farm or view another.";return
	if not pending.is_empty():_restore_pending();_message.text="Check your previous claim before choosing another parcel.";return
	_confirm()
func _restore_pending() -> void:
	var pending:Dictionary=identity.data.get("pending",{})
	var id:=str(pending.get("block_id",""))
	if not Contract.valid_id(id):return
	if not by_id.has(id):by_id[id]={"block_id":id,"parcel_id":id.trim_prefix("p-"),"name":"Your previous parcel"}
	_select(by_id[id])
func _reset_area() -> void:
	if _busy:return
	map_canvas.frame_center(_default_center[0],_default_center[1],_default_zoom)
func _jump_to(p:Dictionary) -> void:
	if _busy or is_instance_valid(_dialog):return
	map_canvas.frame_center(float(p.center[0]),float(p.center[1]),19.5)
	_select(p)
func _my_farm() -> void:
	if _busy:return
	var id:=str(identity.data.get("own_block_id",""))
	if Contract.valid_id(id):_open_farm(id)
	elif not identity.data.get("pending",{}).is_empty():_restore_pending()
	else:_message.text="Choose a parcel and claim your demo farm first."
func _panel(parent:Control,offsets:Vector4,bottom:bool) -> PanelContainer:
	var panel:=PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
	panel.offset_left=offsets.x;panel.offset_right=offsets.z
	if bottom:panel.offset_bottom=offsets.w;panel.grow_vertical=Control.GROW_DIRECTION_BEGIN
	else:panel.offset_top=offsets.y;panel.grow_vertical=Control.GROW_DIRECTION_END
	var style:=StyleBoxFlat.new();style.bg_color=Color("FBF8F1");style.set_corner_radius_all(16);style.content_margin_left=14;style.content_margin_right=14;style.content_margin_top=12;style.content_margin_bottom=12
	panel.add_theme_stylebox_override("panel",style);parent.add_child(panel)
	return panel
func _label(text:String,font_size:int) -> Label:
	var label:=Label.new();label.text=text;label.add_theme_font_size_override("font_size",font_size);label.add_theme_color_override("font_color",Color("263E31"));label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.auto_translate_mode=Node.AUTO_TRANSLATE_MODE_DISABLED;return label
func _button(text:String,action:Callable) -> Button:
	var b:=Button.new();b.text=text;b.custom_minimum_size.y=44;b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;b.add_theme_font_size_override("font_size",15);b.pressed.connect(action)
	for state in ["normal","hover","pressed","disabled"]:
		var style:=StyleBoxFlat.new();style.set_corner_radius_all(10);style.set_content_margin_all(8)
		style.bg_color={"normal":Color("DAE7D2"),"hover":Color("CDDFC2"),"pressed":Color("BBCFB0"),"disabled":Color("E5E5DF")}[state]
		b.add_theme_stylebox_override(state,style)
	for state in ["font_color","font_hover_color","font_pressed_color"]:b.add_theme_color_override(state,Color("263E31"))
	b.add_theme_color_override("font_disabled_color",Color("858D83"))
	return b

func _dialog_shell(title:String) -> VBoxContainer:
	_close_dialog()
	_dialog=Control.new();_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(_dialog)
	var veil:=ColorRect.new();veil.color=Color(0,0,0,.48);veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_dialog.add_child(veil)
	var margin:=MarginContainer.new();_dialog_panel=margin; margin.set_anchors_and_offsets_preset(Control.PRESET_CENTER);margin.grow_horizontal=Control.GROW_DIRECTION_BOTH;margin.grow_vertical=Control.GROW_DIRECTION_BOTH;margin.custom_minimum_size=Vector2(minf(size.x-32,328),0);margin.size=margin.custom_minimum_size;margin.position.x=-margin.size.x*.5;_dialog.add_child(margin)
	var panel:=PanelContainer.new();var s:=StyleBoxFlat.new();s.bg_color=Color("FBF8F1");s.set_corner_radius_all(20);s.set_content_margin_all(20);panel.add_theme_stylebox_override("panel",s);margin.add_child(panel)
	var col:=VBoxContainer.new();col.add_theme_constant_override("separation",12);panel.add_child(col);col.add_child(_label(title,20))
	map_canvas.input_enabled=false
	return col
func _confirm() -> void:
	_stage="confirm"
	var p:Dictionary=by_id[_selected]
	var col:=_dialog_shell("Choose this parcel?")
	col.add_child(_label("%s\n%d generated cells · %.0f m² parcel area\nOne farm per installation." % [str(p.name),int(p.cell_count),float(p.inset_area_m2)],14))
	col.add_child(_button("Continue",_nickname))
	col.add_child(_button("Cancel",_close_dialog))
func _nickname() -> void:
	_stage="nickname"
	var col:=_dialog_shell("Name your demo farm")
	col.add_child(_label("Use a nickname, not your real name.\nOther players can see it.",14))
	var edit:=LineEdit.new();edit.name="Nickname";edit.max_length=16;edit.placeholder_text="Nickname (1–16 characters)";edit.custom_minimum_size.y=48
	var pending:Dictionary=identity.data.get("pending",{})
	edit.text=str(pending.get("nickname",identity.data.get("nickname","")))
	var input_style:=StyleBoxFlat.new();input_style.bg_color=Color("FFFFFF");input_style.border_color=Color("8BA184");input_style.set_border_width_all(1);input_style.set_corner_radius_all(8);input_style.set_content_margin_all(10)
	edit.add_theme_stylebox_override("normal",input_style);edit.add_theme_color_override("font_color",Color("263E31"));edit.add_theme_color_override("font_placeholder_color",Color("71816E"));edit.add_theme_color_override("caret_color",Color("263E31"))
	col.add_child(edit)
	var submit:=_button("Claim farm",func():_claim(_selected,edit.text.strip_edges()))
	submit.disabled=not Identity.valid_nickname(edit.text);edit.text_changed.connect(func(value:String):submit.disabled=not Identity.valid_nickname(value));col.add_child(submit)
	col.add_child(_button("Cancel",_close_dialog))

func _claim(id:String,nickname:String) -> void:
	if _busy:return
	_close_dialog();_busy=true;map_canvas.input_enabled=false;_action.disabled=true;_message.text="Claiming this parcel…"
	var result:Dictionary=await session.claim(id,nickname)
	_busy=false;map_canvas.input_enabled=true
	if result.get("ok")==true:
		_message.text="Farm claimed." if result.get("local_saved")==true else "Farm claimed, but local save failed. Keep this demo open."
		_selected=str(result.claim.block_id);_update_selection();_push_states();_load_claims();_open_farm(_selected)
	else:
		_message.text={"block_taken":"Someone else claimed this parcel. Pick another.","unknown_block":"This parcel is not available.","schema":"Check your nickname and try again.","rate_limited":"Too many requests. Please wait and retry.","persistence":"Could not save claim recovery. Please restart.","pending_claim":"Retry your previous claim first."}.get(str(result.get("code","")),"Could not confirm the claim. Retry this same parcel.")
		_update_selection()
		if result.get("code")=="block_taken":_load_claims()
func _open_farm(id:String) -> void:
	if _busy or not Contract.valid_id(id):return
	_farm_generation+=1;var generation:=_farm_generation
	_pending_query={};_close_dialog()
	if not ResourceLoader.exists(FARM_VIEW):_message.text="Farm viewer is not included in this build.";return
	if is_instance_valid(_farm):_farm.queue_free()
	_farm=load(FARM_VIEW).instantiate();add_child(_farm);_farm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_farm.back_requested.connect(_back_to_map)
	_overlay.hide();map_canvas.hide();map_canvas.input_enabled=false
	if bridge:bridge.set_map_visible(false)
	get_viewport().transparent_bg=false
	_farm.show_loading(str(by_id.get(id,{}).get("name","Parcel farm")))
	var result:Dictionary=await session.fetch_farm(id)
	if generation!=_farm_generation or not is_instance_valid(_farm):return
	if result.get("ok")==true:_farm.show_block(result.farm)
	else:_farm.show_error("Could not load this farm. Return to the map and try again.")
func _back_to_map() -> void:
	_farm_generation+=1
	if is_instance_valid(_farm):_farm.queue_free()
	_farm=null;_overlay.show();map_canvas.show();map_canvas.input_enabled=true
	if bridge:bridge.set_map_visible(true)
	get_viewport().transparent_bg=bridge!=null
	_load_claims()
func _close_dialog() -> void:
	if _busy:return
	if is_instance_valid(_dialog):_dialog.queue_free()
	_dialog=null;_dialog_panel=null
	if is_instance_valid(map_canvas):map_canvas.input_enabled=true
func is_back_navigation_locked() -> bool:
	if _busy:return true
	if is_instance_valid(_farm):_back_to_map();return true
	if is_instance_valid(_dialog):_close_dialog();return true
	return false
func _notification(what:int) -> void:
	if what==NOTIFICATION_WM_GO_BACK_REQUEST and not has_node("/root/AppRouter"):
		if not is_back_navigation_locked():get_tree().quit()
func _process(dt:float) -> void:
	if is_instance_valid(_dialog_panel) and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		var height:=maxf(float(DisplayServer.window_get_size().y),1.0)
		var keyboard:=float(DisplayServer.virtual_keyboard_get_height())*size.y/height
		_dialog_panel.position.y=maxf(16,(size.y-keyboard-_dialog_panel.size.y)*.5)
	if not _pending_query.is_empty():
		_query_time+=dt
		if _query_time>5:_pending_query={};_message.text="Parcel lookup took too long. Tap again."
	_refresh_left-=dt
	if _refresh_left<=0 and not manifest.is_empty() and not _busy and not is_instance_valid(_farm):_load_claims()
func _exit_tree() -> void:
	if bridge:bridge.clear(_generation);bridge.set_map_visible(false)
	get_viewport().transparent_bg=false
