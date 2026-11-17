extends Control
## Input/camera only: parcel geometry and picking belong to the native Mapbox source/layers.
signal tapped(point:Vector2)
signal camera_changed
const Geo:=preload("res://demo/geofarm/geo_math.gd")
var bridge:MapBridge
var center:=PackedFloat64Array([-122.45190271843384,37.729419227])
var zoom:=17.5
var density:=1.0
var input_enabled:=true
var _desktop:=true
var _dirty:=true
var _touches:Dictionary={}
var _pressed:=Vector2.ZERO
var _last:=Vector2.ZERO
var _dragged:=false
var _mouse_down:=false
var _pinch:=false
var _last_touch_ms:=0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	resized.connect(_changed);get_viewport().size_changed.connect(_changed)
func scale_pixels() -> float:
	var height:=float(DisplayServer.window_get_size().y)
	var viewport_h:=get_viewport().get_visible_rect().size.y if is_inside_tree() else size.y
	if height>0 and not _desktop:return Geo.world_pixels(zoom,density,viewport_h,height)
	return 512.0*pow(2.0,zoom)
func screen_geo(point:Vector2) -> PackedFloat64Array:
	return Geo.unproject(point,center,size,scale_pixels())
func setup_map(map_bridge:MapBridge,token:String) -> void:
	bridge=map_bridge;_desktop=bridge==null or not bridge.has_mapbox()
	if bridge:
		density=bridge.get_pixel_ratio()
		bridge.map_ready.connect(func():density=bridge.get_pixel_ratio();_changed())
		bridge.set_language("en");bridge.set_map_visible(true);bridge.create_map(token,center[1],center[0],zoom)
	get_viewport().transparent_bg=not _desktop
	_changed();queue_redraw()
func frame_center(lon:float,lat:float,level:=19.5) -> void:
	center=PackedFloat64Array([lon,lat]);zoom=level;_changed()
func _changed() -> void:
	center[0]=clampf(center[0],-122.53,-122.34);center[1]=clampf(center[1],37.70,37.84)
	_dirty=true;camera_changed.emit()
func _process(_dt:float) -> void:
	if bridge:bridge.poll()
	if _dirty:
		_dirty=false
		if bridge:bridge.set_camera(center[1],center[0],zoom,0.0,0.0)
func _draw() -> void:
	if _desktop:draw_rect(Rect2(Vector2.ZERO,size),Color("E8EEE6"))
func change_zoom(delta:float,anchor:=Vector2(-1,-1)) -> void:
	var at:=size*.5 if anchor.x<0 else anchor;var before:=screen_geo(at)
	zoom=clampf(zoom+delta,13.0,21.0)
	var after:=screen_geo(at);center[0]+=before[0]-after[0];center[1]+=before[1]-after[1];_changed()
func _pan(delta:Vector2) -> void:
	center=screen_geo(size*.5-delta);_changed()
func _gui_input(event:InputEvent) -> void:
	if not input_enabled:return
	if event is InputEventScreenTouch:
		_last_touch_ms=Time.get_ticks_msec()
		if event.pressed:
			_touches[event.index]=event.position
			if _touches.size()==1:_pressed=event.position;_last=event.position;_dragged=false;_pinch=false
			else:_pinch=true;_dragged=true
		else:
			if _touches.has(event.index) and _touches.size()==1 and not _dragged and not _pinch:tapped.emit(event.position/size)
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
					if _mouse_down and not _dragged:tapped.emit(event.position/size)
					_mouse_down=false
			accept_event()
		elif event is InputEventMouseMotion and _mouse_down:
			if event.position.distance_to(_pressed)>8:_dragged=true
			if _dragged:_pan(event.position-_last)
			_last=event.position
			accept_event()
