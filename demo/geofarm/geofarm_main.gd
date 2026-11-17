extends Control
const Api := preload("res://demo/geofarm/geo_api.gd")
const Identity := preload("res://demo/geofarm/geo_identity.gd")
const Geo := preload("res://demo/geofarm/geo_math.gd")
const MapCanvas := preload("res://demo/geofarm/geo_map.gd")
const FARM_VIEW := "res://scenes/geo_farm_demo/farm_view.tscn"
const CONFIG := "res://demo/geofarm/config.json"
const VERSION := "sf-20261117-v1"
var api: Node
var identity := Identity.new()
var map_canvas: Control
var bridge: MapBridge
var index := {}
var by_id := {}
var claims := {}
var _selected := ""
var _busy := false
var _claims_busy := false
var _refresh_left := 10.0
var _farm_generation := 0
var _farm: Control
var _dialog: Control
var _preview: Label
var _message: Label
var _selection: Label
var _action: Button
var _refresh: Button
var _overlay: Control
var _identity_ok := false
var _map_ready := false
var _map_wait := 0.0
var _stage := "select"
var _dialog_panel: MarginContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().quit_on_go_back = false
	get_viewport().transparent_bg = true
	_identity_ok=identity.load_or_create()
	api=Api.new();add_child(api)
	var parser:=JSON.new()
	if FileAccess.file_exists(CONFIG) and parser.parse(FileAccess.get_file_as_string(CONFIG))==OK and parser.data is Dictionary:
		api.base_url=str(parser.data.get("base_url","")).trim_suffix("/")
	map_canvas=MapCanvas.new();add_child(map_canvas)
	map_canvas.selected.connect(_select)
	_build_ui()
	bridge=MapBridgeAndroid.new() if Engine.has_singleton("GodotMap") else null
	var token:=""
	if FileAccess.file_exists("res://mapbox_token.txt"):token=FileAccess.get_file_as_string("res://mapbox_token.txt").strip_edges()
	if bridge and token!="":
		_preview.hide()
		bridge.map_ready.connect(func():_map_ready=true)
		map_canvas.setup_map(bridge,token)
	else:
		bridge=null
		map_canvas.setup_map(null,"")
		_message.text="Map preview · native basemap unavailable"
	if not _identity_ok:
		_message.text="Demo identity could not be saved. Restart or clear this demo's data."
		_action.disabled=true
	elif not Api.valid_base(api.base_url):
		_message.text="Demo service is not configured. Please use the latest demo build."
	else: _load_index.call_deferred()

func _build_ui() -> void:
	_overlay=Control.new();_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_overlay)
	var top:=_panel(_overlay,Vector4(12,32,-12,0),false)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",6);top.add_child(column)
	column.add_child(_label("San Francisco · GeoFarm DEMO",19))
	_preview=_label("Outlines preview · native basemap unavailable",11);column.add_child(_preview)
	_message=_label("Loading census blocks…",13);column.add_child(_message)
	var row:=HBoxContainer.new();column.add_child(row)
	_refresh=_button("Refresh",func():
		if index.is_empty():_load_index()
		else:_load_claims())
	row.add_child(_refresh)
	row.add_child(_button("My farm",_my_farm))
	row.add_child(_button("SF",func():map_canvas.center=PackedFloat64Array([-122.4194,37.7749]);map_canvas.zoom=15;map_canvas._changed()))
	var zooms:=VBoxContainer.new();zooms.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT);zooms.position=Vector2(-60,-50);zooms.size=Vector2(48,104);_overlay.add_child(zooms)
	zooms.add_child(_button("+",func():map_canvas.change_zoom(.5)))
	zooms.add_child(_button("−",func():map_canvas.change_zoom(-.5)))
	var bottom:=_panel(_overlay,Vector4(12,0,-12,-32),true)
	var details:=VBoxContainer.new();details.add_theme_constant_override("separation",7);bottom.add_child(details)
	_selection=_label("Tap an outlined block to choose your farm.",15);details.add_child(_selection)
	_action=_button("Select a block",_action_pressed);_action.disabled=true;details.add_child(_action)
	var credits:=HBoxContainer.new();details.add_child(credits)
	for entry in [["© Mapbox","https://www.mapbox.com/about/maps/"],["© OpenStreetMap","https://www.openstreetmap.org/copyright"]]:
		var credit:=Button.new();credit.text=entry[0];credit.flat=true;credit.add_theme_color_override("font_color",Color("3B5D4B"));credit.add_theme_color_override("font_hover_color",Color("163F2B"));credit.add_theme_font_size_override("font_size",10);credit.pressed.connect(OS.shell_open.bind(entry[1]));credits.add_child(credit)
	var source:=_label("Blocks: US Census / DataSF · Land use: DataSF",10);details.add_child(source)

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

func _load_index() -> void:
	if _busy or not _identity_ok:return
	_busy=true;_refresh.disabled=true;_message.text="Loading census blocks…"
	var result:Dictionary=await api.request("/index.geojson")
	_busy=false;_refresh.disabled=false
	if not _take_index(result):
		_message.text="Could not load blocks. Check your connection and tap Refresh."
		return
	_message.text="%d blocks · drag to explore, pinch to zoom" % by_id.size()
	await _load_claims()
	var pending:Dictionary=identity.data.get("pending",{})
	if not pending.is_empty() and by_id.has(str(pending.get("block_id",""))):
		_select(str(pending.block_id));_message.text="A previous claim needs checking. Retry the same block."

func _take_index(result:Dictionary) -> bool:
	if result.get("schema")!=1 or result.get("dataset_version")!=VERSION or result.get("type")!="FeatureCollection" or not result.get("features") is Array:return false
	var found:={}
	for feature in result.features:
		if not feature is Dictionary or not feature.get("properties") is Dictionary or not feature.get("geometry") is Dictionary:return false
		var p:Dictionary=feature.properties;var id:=str(p.get("block_id",""))
		if id=="" or found.has(id) or not p.get("bbox") is Array or p.bbox.size()!=4 or not p.get("center") is Array or p.center.size()!=2:return false
		if str(p.get("farm_path",""))!="farms/"+id+".json" or id.uri_encode()!=id or "/" in id or ".." in id:return false
		if not p.get("name") is String or not (p.get("cell_count") is float or p.get("cell_count") is int) or not (p.get("inset_area_m2") is float or p.get("inset_area_m2") is int):return false
		if not Geo.valid_geometry(feature.geometry) or not Geo.valid_bbox(p.bbox) or not Geo.valid_point(p.center):return false
		found[id]=feature
	if found.is_empty():return false
	index=result;by_id=found;map_canvas.set_features(result.features)
	return true

func _load_claims() -> void:
	if _claims_busy or index.is_empty():return
	_claims_busy=true
	var result:Dictionary=await api.request("/claims")
	_claims_busy=false;_refresh_left=10.0
	if result.get("ok")!=true or result.get("dataset_version")!=VERSION or not result.get("claims") is Array:
		_message.text="Claims may be out of date. Tap Refresh to try again."
		return
	var found:={}
	for row in result.claims:
		if row is Dictionary and by_id.has(str(row.get("block_id",""))) and row.get("nickname") is String:found[str(row.block_id)]=row
	claims=found
	map_canvas.set_claims(claims.values(),str(identity.data.get("own_block_id","")))
	_update_selection()

func _select(id:String) -> void:
	if _busy or is_instance_valid(_dialog):return
	_selected=id if by_id.has(id) else ""
	map_canvas.select_block(_selected)
	_update_selection()
func _update_selection() -> void:
	if not by_id.has(_selected):
		_selection.text="Tap an outlined block to choose your farm.";_action.text="Select a block";_action.disabled=true;return
	var p:Dictionary=by_id[_selected].properties
	var name:=str(p.get("name","SF Block"))
	_selection.text="%s · %d cells · %.0f m²" % [name,int(p.get("cell_count",0)),float(p.get("inset_area_m2",0))]
	var pending:Dictionary=identity.data.get("pending",{})
	if str(pending.get("block_id",""))==_selected:
		_action.text="Retry previous claim"
	elif claims.has(_selected):
		_selection.text+="\nClaimed by "+str(claims[_selected].nickname)
		_action.text="View farm"
	elif str(identity.data.get("own_block_id",""))==_selected:_action.text="View my farm"
	else:_action.text="Choose this block"
	_action.disabled=_busy
func _action_pressed() -> void:
	if _busy or not by_id.has(_selected):return
	var retry:Dictionary=identity.data.get("pending",{})
	if str(retry.get("block_id",""))==_selected:
		_claim(_selected,str(retry.get("nickname","")));return
	if claims.has(_selected) or str(identity.data.get("own_block_id",""))==_selected:_open_farm(_selected);return
	var own:=str(identity.data.get("own_block_id",""))
	if own!="":_message.text="This installation already has a farm. Use My farm or view another.";return
	var pending:Dictionary=identity.data.get("pending",{})
	if not pending.is_empty() and str(pending.get("block_id",""))!=_selected:
		_message.text="Check your previous claim before choosing another block."
		_select(str(pending.get("block_id","")));return
	_confirm()

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
	var p:Dictionary=by_id[_selected].properties
	var col:=_dialog_shell("Choose this block?")
	col.add_child(_label("%s\n%d generated cells · %.0f m² inset area\nOne farm per installation." % [str(p.name),int(p.cell_count),float(p.inset_area_m2)],14))
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
	if _busy or not by_id.has(id) or not Identity.valid_nickname(nickname):return
	if not identity.remember_pending(id,nickname):_message.text="Could not save claim recovery. Please restart this demo.";return
	_close_dialog();_busy=true;map_canvas.input_enabled=false;_action.disabled=true
	_message.text="Claiming this block…"
	var result:Dictionary=await api.request("/claim",{"device_id":str(identity.data.device_id),"nickname":nickname,"block_id":id})
	_busy=false;map_canvas.input_enabled=true
	var code:=str(result.get("code",""))
	if result.get("ok")==true or code=="already_claimed":
		var row=result.get("claim")
		if not row is Dictionary or not by_id.has(str(row.get("block_id",""))) or not row.get("nickname") is String or (result.get("ok")==true and str(row.get("block_id",""))!=id):
			_message.text="Claim response could not be checked. Retry the same block.";_update_selection();return
		var saved:=identity.remember_claim(row)
		claims[str(row.block_id)]=row
		_select(str(row.block_id));map_canvas.set_claims(claims.values(),str(identity.data.own_block_id))
		_message.text="Farm claimed." if saved else "Farm claimed, but local save failed. Keep this demo open."
		_load_claims()
		_open_farm(str(row.block_id))
	else:
		if code in ["block_taken","unknown_block","schema"]:
			identity.data["pending"]={};identity.save()
		_message.text={"block_taken":"Someone else claimed this block. Pick another.","already_claimed":"This installation already has a farm.","unknown_block":"This block is no longer available.","schema":"Check your nickname and try again.","rate_limited":"Too many requests. Please wait and retry."}.get(code,"Could not confirm the claim. Retry this same block.")
		_update_selection()
		if code=="block_taken":_load_claims()

func _open_farm(id:String) -> void:
	if not by_id.has(id) or _busy:return
	_farm_generation+=1
	var generation:=_farm_generation
	_close_dialog()
	if not ResourceLoader.exists(FARM_VIEW):_message.text="Farm viewer is not included in this build.";return
	if is_instance_valid(_farm):_farm.queue_free()
	_farm=load(FARM_VIEW).instantiate();add_child(_farm);_farm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_farm.back_requested.connect(_back_to_map)
	_overlay.hide();map_canvas.hide();map_canvas.input_enabled=false
	if bridge:bridge.set_map_visible(false)
	get_viewport().transparent_bg=false
	_farm.show_loading(str(by_id[id].properties.name))
	var result:Dictionary=await api.request("/"+str(by_id[id].properties.farm_path))
	if generation!=_farm_generation or not is_instance_valid(_farm):return
	if result.get("schema")!=1 or result.get("dataset_version")!=VERSION or str(result.get("block_id",""))!=id:
		_farm.show_error("Could not load this farm. Return to the map and try again.")
	else:_farm.show_block(result)
func _back_to_map() -> void:
	_farm_generation+=1
	if is_instance_valid(_farm):_farm.queue_free()
	_farm=null;_overlay.show();map_canvas.show();map_canvas.input_enabled=true
	if bridge:bridge.set_map_visible(true)
	get_viewport().transparent_bg=bridge!=null
	_load_claims()
func _my_farm() -> void:
	var own:=str(identity.data.get("own_block_id",""))
	if by_id.has(own):
		var point:Array=by_id[own].properties.center;map_canvas.frame_center(float(point[0]),float(point[1]));_select(own);_open_farm(own)
	else:_message.text="Choose a block and claim your demo farm first."
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
	# Standalone export removes the game autoloads. If AppRouter is retained, it remains the sole Back owner.
	if what==NOTIFICATION_WM_GO_BACK_REQUEST and not has_node("/root/AppRouter"):
		if not is_back_navigation_locked():get_tree().quit()

func _process(dt:float) -> void:
	if is_instance_valid(_dialog_panel) and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		var window_h:=maxf(float(DisplayServer.window_get_size().y),1.0)
		var keyboard:=float(DisplayServer.virtual_keyboard_get_height())*size.y/window_h
		_dialog_panel.position.y=maxf(16.0,(size.y-keyboard-_dialog_panel.size.y)*.5)
	_refresh_left-=dt
	if _refresh_left<=0 and not index.is_empty() and not _busy and not is_instance_valid(_farm):_load_claims()
	if bridge and not _map_ready:
		_map_wait+=dt
		if _map_wait>20:_message.text="Basemap is still loading. Public block outlines remain selectable.";_map_wait=-1000
func _exit_tree() -> void:
	if bridge:bridge.set_map_visible(false)
	get_viewport().transparent_bg=false
