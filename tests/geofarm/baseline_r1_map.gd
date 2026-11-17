extends Control
## Flat Mercator camera shared by native Mapbox and public-data outlines. Never asks location or POI data.
signal selected(block_id: String)
signal camera_changed
const Geo := preload("res://demo/geofarm/geo_math.gd")
var bridge: MapBridge
var center := PackedFloat64Array([-122.4194,37.7749])
var zoom := 15.0
var density := 1.0
var features: Array = []
var claims := {}
var own_block := ""
var selected_id := ""
var _visible: Array = []
var _touches := {}
var _pressed := Vector2.ZERO
var _last := Vector2.ZERO
var _dragged := false
var _mouse_down := false
var _pinch := false
var _dirty := true
var _desktop := true
var input_enabled := true
var _last_touch_ms := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	resized.connect(_changed)
	get_viewport().size_changed.connect(_changed)

func scale_pixels() -> float:
	var window_h:=float(DisplayServer.window_get_size().y)
	var viewport_h:=get_viewport().get_visible_rect().size.y if is_inside_tree() else size.y
	if window_h>0 and not _desktop:return Geo.world_pixels(zoom,density,viewport_h,window_h)
	return 512.0*pow(2.0,zoom)

func screen_geo(p:Vector2) -> PackedFloat64Array:return Geo.unproject(p,center,size,scale_pixels())
func geo_screen(lon:float,lat:float) -> Vector2:return Geo.project(lon,lat,center,size,scale_pixels())
func visible_bbox() -> Array:
	var a:=screen_geo(Vector2.ZERO);var b:=screen_geo(size)
	return [a[0],b[1],b[0],a[1]]

func setup_map(map_bridge: MapBridge, token: String) -> void:
	bridge=map_bridge
	_desktop=bridge==null or not bridge.has_mapbox()
	if bridge:
		density=bridge.get_pixel_ratio()
		bridge.map_ready.connect(func():density=bridge.get_pixel_ratio();_changed())
		bridge.set_language("en")
		bridge.set_map_visible(true)
		bridge.create_map(token,center[1],center[0],zoom)
	get_viewport().transparent_bg=not _desktop
	_changed()

func set_features(rows:Array) -> void:
	features=rows;_rebuild();queue_redraw()
func set_claims(rows:Array,own:String) -> void:
	claims={}
	for row in rows:
		if row is Dictionary:claims[str(row.get("block_id",""))]=row
	own_block=own;queue_redraw()
func select_block(id:String) -> void:selected_id=id;queue_redraw()
func frame_center(lon:float,lat:float) -> void:
	center=PackedFloat64Array([lon,lat]);zoom=17.0;_changed()
func _changed() -> void:
	center[0]=clampf(center[0],-122.53,-122.34)
	center[1]=clampf(center[1],37.70,37.84)
	_dirty=true
	_rebuild();queue_redraw();camera_changed.emit()
func _process(_dt:float) -> void:
	if bridge:bridge.poll()
	if _dirty and bridge:
		_dirty=false
		bridge.set_camera(center[1],center[0],zoom,0.0,0.0)
func _rebuild() -> void:
	_visible=[]
	if size.x<=0 or size.y<=0:return
	var bounds:=visible_bbox()
	for feature in features:
		if not feature is Dictionary:continue
		var prop:Dictionary=feature.get("properties",{})
		if not Geo.bbox_intersects(prop.get("bbox",[]),bounds):continue
		var polygons:Array=[]
		for polygon in Geo.polygons(feature.get("geometry",{})):
			var rings:Array=[]
			for ring in polygon:
				var points:=PackedVector2Array()
				for xy in ring:points.append(geo_screen(float(xy[0]),float(xy[1])))
				if points.size()>=3:rings.append(points)
			if not rings.is_empty():polygons.append(rings)
		var ll:Array=prop.get("center",[0,0])
		_visible.append({"id":str(prop.get("block_id","")),"polygons":polygons,"label":geo_screen(float(ll[0]),float(ll[1]))})

func hit(point:Vector2) -> String:
	for entry in _visible:
		for rings in entry.polygons:
			if Geo.contains(point,rings):return entry.id
	return ""
func _draw() -> void:
	if _desktop:
		draw_rect(Rect2(Vector2.ZERO,size),Color("E8EEE6"))
		for x in range(0,int(size.x),48):draw_line(Vector2(x,0),Vector2(x,size.y),Color("D7DFD4"))
		for y in range(0,int(size.y),48):draw_line(Vector2(0,y),Vector2(size.x,y),Color("D7DFD4"))
	var labels:Array[Rect2]=[]
	var captions:Array=[]
	var font:=ThemeDB.fallback_font
	for entry in _visible:
		var id:String=entry.id
		var color:=Color("3B7757")
		if claims.has(id):color=Color("496CAD")
		if id==own_block:color=Color("B66324")
		if id==selected_id:color=Color("ED9F18")
		for rings in entry.polygons:
			for ring:PackedVector2Array in rings:
				var line:=ring.duplicate()
				if line[0]!=line[-1]:line.append(line[0])
				draw_polyline(line,color,3.5 if id==selected_id else 1.8,true)
		if not claims.has(id):continue
		var text:=str(claims[id].get("nickname",""))
		var w:=minf(font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x,155.0)+14
		var rect:=Rect2(entry.label-Vector2(w*0.5,11),Vector2(w,23))
		if rect.position.y<110 or rect.end.y>size.y-150:continue
		if labels.any(func(other:Rect2):return other.intersects(rect)):continue
		labels.append(rect)
		captions.append({"rect":rect,"text":text})
	# Draw all labels last so neighboring outlines cannot cross their text.
	for caption in captions:
		var rect:Rect2=caption.rect
		draw_rect(rect,Color(1,1,1,.97))
		draw_string(font,rect.position+Vector2(7,16),caption.text,HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-14,13,Color("243B30"))

func change_zoom(delta:float,anchor:=Vector2(-1,-1)) -> void:
	var at:=size*0.5 if anchor.x<0 else anchor
	var before:=screen_geo(at)
	zoom=clampf(zoom+delta,13.0,19.0)
	var after:=screen_geo(at)
	center[0]+=before[0]-after[0];center[1]+=before[1]-after[1];_changed()
func _pan(delta:Vector2) -> void:
	center=screen_geo(size*0.5-delta);_changed()
func _gui_input(event:InputEvent) -> void:
	if not input_enabled:return
	if event is InputEventScreenTouch:
		_last_touch_ms=Time.get_ticks_msec()
		if event.pressed:
			_touches[event.index]=event.position
			if _touches.size()==1:_pressed=event.position;_last=event.position;_dragged=false;_pinch=false
			else:_pinch=true;_dragged=true
		else:
			if _touches.has(event.index) and _touches.size()==1 and not _dragged and not _pinch:selected.emit(hit(event.position))
			_touches.erase(event.index)
		accept_event()
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_last_touch_ms=Time.get_ticks_msec()
		if _touches.size()==1:
			if event.position.distance_to(_pressed)>8:_dragged=true
			if _dragged:_pan(event.position-_touches[event.index])
			_touches[event.index]=event.position
		else:
			var old:Array=_touches.values();var distance:float=old[0].distance_to(old[1])
			_touches[event.index]=event.position
			var now:Array=_touches.values();var next:float=now[0].distance_to(now[1])
			if distance>5 and next>5:change_zoom(log(next/distance)/log(2.0),(now[0]+now[1])*0.5)
		accept_event()
	elif Time.get_ticks_msec()-_last_touch_ms>500:
		if event is InputEventMouseButton:
			if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed:change_zoom(.3,event.position)
			elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed:change_zoom(-.3,event.position)
			elif event.button_index==MOUSE_BUTTON_LEFT:
				if event.pressed:_mouse_down=true;_pressed=event.position;_last=event.position;_dragged=false
				else:
					if _mouse_down and not _dragged:selected.emit(hit(event.position))
					_mouse_down=false
			accept_event()
		elif event is InputEventMouseMotion and _mouse_down:
			if event.position.distance_to(_pressed)>8:_dragged=true
			if _dragged:_pan(event.position-_last)
			_last=event.position
			accept_event()
