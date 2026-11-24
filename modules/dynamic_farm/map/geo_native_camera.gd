extends Control
## Input/camera only: parcel geometry and picking belong to the native Mapbox source/layers.
## C-112 (C-103#16): the farm-dev map's camera feel, taken from map_poc.gd (read only, same values): a drag or
## pinch keeps going after the fingers lift and slows down, a double tap zooms in one level, two fingers moved
## up or down tilt the map, and the map's own moves fly (MapFlight). Tilted, a drag keeps the ground point under
## the finger and screen_geo follows Mapbox's tilted camera; taps are still picked by the native map itself.
signal tapped(point:Vector2)
signal camera_changed
## The player dragged, pinched, tilted or scrolled the map (not frame_center or fly_to from code).
signal user_moved
const Geo:=preload("res://modules/dynamic_farm/map/geo_math.gd")
const Flight:=preload("res://scenes/map_poc/map_flight.gd")
## Inertia: velocity decays by exp(-FLING_DECAY*dt) and stops under its minimum; FLING_EMA smooths frame jitter.
const FLING_DECAY:=4.0
const FLING_MIN_SPEED:=2.0 # ground pixels per second (farm-dev: 0.5 m/s, about a pixel a second at z17)
const FLING_EMA:=0.35
const ZOOM_FLING_MIN:=0.05 # zoom levels per second
## Double tap: two taps within 0.3 s and 32 px zoom in one level around the centre in 0.25 s, as on farm-dev.
const DOUBLE_TAP_S:=0.3
const DOUBLE_TAP_MAX_PX:=32.0
const DOUBLE_TAP_ZOOM_S:=0.25
const TAP_SLOP_PX:=8.0
## Tilt: each finger of a two-finger gesture moved up tilts by 0.1° a pixel, between flat and 70°.
const PITCH_PER_PX:=0.1
const MAX_PITCH:=70.0
const MIN_ZOOM:=13.0
const MAX_ZOOM:=21.0
## Mapbox's camera sits 1.5 view heights from the centre (fov 36.87°, farm-dev's MAP_FOV_DEG).
const EYE_HEIGHTS:=1.5
## Rays this close to the horizon are held there, so a far edge of a tilted view stays on the ground.
const HORIZON_CLIP:=0.95
## The map's own moves (My home, the locate key) fly no longer than farm-dev's home key (FLIGHT_MAX_S).
const FLIGHT_MAX_S:=1.2
const MOUSE:=-1 # Touch index used for the mouse.
var bridge:MapBridge
var center:=PackedFloat64Array([-122.45190271843384,37.729419227])
var zoom:=17.5
var pitch:=0.0
var density:=1.0
var input_enabled:=true
var _desktop:=true
var _dirty:=true
var _touches:Dictionary={}
var _pressed:=Vector2.ZERO
var _dragged:=false
var _pinch:=false
var _last_touch_ms:=0
var _fling:=Vector2.ZERO # Ground pixels per second.
var _zoom_vel:=0.0
var _zoom_anchor:=Vector2(-1,-1)
var _last_tap_ms:=0
var _last_tap_pos:=Vector2.ZERO
var _motion:Tween # Double-tap zoom or a flight.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	resized.connect(_changed);get_viewport().size_changed.connect(_changed)
func scale_pixels() -> float:
	var height:=float(DisplayServer.window_get_size().y)
	var viewport_h:=get_viewport().get_visible_rect().size.y if is_inside_tree() else size.y
	if height>0 and not _desktop:return Geo.world_pixels(zoom,density,viewport_h,height)
	return 512.0*pow(2.0,zoom)
## The ground point under a screen point, in ground pixels from the centre (flat: the screen offset itself).
func ground_offset(offset:Vector2) -> Vector2:
	if pitch<=0.01 or size.y<=0:return offset
	var phi:=deg_to_rad(pitch);var eye:=EYE_HEIGHTS*size.y
	var dy:=maxf(offset.y,-eye*cos(phi)/sin(phi)*HORIZON_CLIP)
	var t:=eye*cos(phi)/(eye*cos(phi)+dy*sin(phi))
	return Vector2(t*offset.x,eye*sin(phi)+t*(dy*cos(phi)-eye*sin(phi)))
func screen_geo(point:Vector2) -> PackedFloat64Array:
	return Geo.unproject(size*.5+ground_offset(point-size*.5),center,size,scale_pixels())
func setup_map(map_bridge:MapBridge,token:String) -> void:
	bridge=map_bridge;_desktop=bridge==null or not bridge.has_mapbox()
	if bridge:
		density=bridge.get_pixel_ratio()
		bridge.map_ready.connect(func():density=bridge.get_pixel_ratio();_changed())
		bridge.set_language("en");bridge.set_map_visible(true);bridge.create_map(token,center[1],center[0],zoom)
	get_viewport().transparent_bg=not _desktop
	_changed();queue_redraw()
## Jumps there (the first framing); the tilt is kept.
func frame_center(lon:float,lat:float,level:=19.5) -> void:
	stop();center=PackedFloat64Array([lon,lat]);zoom=level;_changed()
## Flies there like farm-dev's home and recenter keys: out, across and in, cubic in-out, at most FLIGHT_MAX_S.
func fly_to(lon:float,lat:float,level:float) -> void:
	stop()
	var scale:=scale_pixels()
	var view_w:=size.x*512.0*pow(2.0,zoom)/scale if scale>0 else size.x
	var flight:=Flight.plan(center[1],center[0],zoom,lat,lon,level,maxf(view_w,1.0))
	_motion=create_tween()
	_motion.tween_method(_fly_step.bind(flight,lon,lat,level),0.0,1.0,flight.duration(FLIGHT_MAX_S)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
func _fly_step(t:float,flight:RefCounted,lon:float,lat:float,level:float) -> void:
	var p:Vector3=flight.sample(t)
	center=PackedFloat64Array([lon,lat] if t>=1.0 else [p.y,p.x]);zoom=level if t>=1.0 else p.z;_changed()
func flying() -> bool:
	return _motion!=null and _motion.is_running()
## Ends a gesture, its inertia and any zoom or flight in progress (a new touch, leaving the map).
func stop() -> void:
	_fling=Vector2.ZERO;_zoom_vel=0.0
	if _motion:_motion.kill();_motion=null
func _changed() -> void:
	center[0]=clampf(center[0],-122.53,-122.34);center[1]=clampf(center[1],37.70,37.84)
	_dirty=true;camera_changed.emit()
func _process(dt:float) -> void:
	_step_fling(dt)
	if bridge:bridge.poll()
	if _dirty:
		_dirty=false
		if bridge:bridge.set_camera(center[1],center[0],zoom,0.0,pitch)
func _draw() -> void:
	if _desktop:draw_rect(Rect2(Vector2.ZERO,size),Color("E8EEE6"))
func change_zoom(delta:float,anchor:=Vector2(-1,-1)) -> void:
	var at:=size*.5 if anchor.x<0 else anchor;var before:=screen_geo(at)
	zoom=clampf(zoom+delta,MIN_ZOOM,MAX_ZOOM)
	var after:=screen_geo(at);center[0]+=before[0]-after[0];center[1]+=before[1]-after[1];_changed()
## Moves the ground by `delta` ground pixels (a drag's or the inertia's step).
func _shift(delta:Vector2) -> void:
	center=Geo.unproject(size*.5+delta,center,size,scale_pixels());_changed()
func set_pitch(value:float) -> void:
	var next:=clampf(value,0.0,MAX_PITCH)
	if next!=pitch:pitch=next;_changed()
## Lifted fingers keep the map moving; fingers on the map hold the velocity until they lift.
func _step_fling(dt:float) -> void:
	if not _touches.is_empty():return
	if not input_enabled:_fling=Vector2.ZERO;_zoom_vel=0.0;return
	if _fling.length()<FLING_MIN_SPEED:_fling=Vector2.ZERO
	if absf(_zoom_vel)<ZOOM_FLING_MIN:_zoom_vel=0.0
	if _fling!=Vector2.ZERO:
		_shift((_fling*dt).limit_length(EYE_HEIGHTS*size.y));_fling*=exp(-FLING_DECAY*dt)
	if _zoom_vel!=0.0:
		change_zoom(_zoom_vel*dt,_zoom_anchor);_zoom_vel*=exp(-FLING_DECAY*dt)
		if zoom<=MIN_ZOOM or zoom>=MAX_ZOOM:_zoom_vel=0.0
func _is_double_tap(now_ms:int,pos:Vector2) -> bool:
	return _last_tap_ms>0 and now_ms-_last_tap_ms<=int(DOUBLE_TAP_S*1000.0) and pos.distance_to(_last_tap_pos)<=DOUBLE_TAP_MAX_PX
func _zoom_in() -> void:
	stop()
	_motion=create_tween()
	_motion.tween_method(_zoom_step,zoom,clampf(zoom+1.0,MIN_ZOOM,MAX_ZOOM),DOUBLE_TAP_ZOOM_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	user_moved.emit()
func _zoom_step(level:float) -> void:
	zoom=level;_changed()
func _press(index:int,pos:Vector2) -> void:
	if _touches.has(index):return
	stop() # A touch stops the inertia, a double-tap zoom and a flight where they are.
	_touches[index]=pos
	if _touches.size()==1:_pressed=pos;_dragged=false;_pinch=false
	else:_pinch=true;_dragged=true;_last_tap_ms=0
func _release(index:int,pos:Vector2,canceled:=false) -> void:
	if not _touches.has(index):return
	var single:=_touches.size()==1
	_touches.erase(index)
	if canceled:_fling=Vector2.ZERO;_zoom_vel=0.0;_last_tap_ms=0
	if not single or canceled:return
	if _pinch:_fling=Vector2.ZERO # A pinch lifts one finger at a time: the last one does not throw the map.
	elif not _dragged:
		_fling=Vector2.ZERO
		var now:=Time.get_ticks_msec()
		if _is_double_tap(now,pos):_last_tap_ms=0;_zoom_in()
		else:_last_tap_ms=now;_last_tap_pos=pos;tapped.emit(pos/size)
	_pinch=false
func _move(index:int,pos:Vector2) -> void:
	if not _touches.has(index):return
	var previous:Vector2=_touches[index]
	if _touches.size()==1:
		if pos.distance_to(_pressed)>TAP_SLOP_PX:_dragged=true;_last_tap_ms=0
		_touches[index]=pos
		if not _dragged or _pinch:return
		# Grab the ground: the point pressed stays under the finger, tilted too. One step moves at most an eye distance.
		var delta:=(ground_offset(previous-size*.5)-ground_offset(pos-size*.5)).limit_length(EYE_HEIGHTS*size.y)
		_shift(delta);_fling=_fling.lerp(delta/maxf(get_process_delta_time(),0.001),FLING_EMA);user_moved.emit()
		return
	var other:Vector2=_touches.values()[1] if _touches.keys()[0]==index else _touches.values()[0]
	var distance:=previous.distance_to(other)
	_touches[index]=pos
	var next:=pos.distance_to(other)
	if distance>5 and next>5:
		var dz:=log(next/distance)/log(2.0);_zoom_anchor=(pos+other)*0.5
		change_zoom(dz,_zoom_anchor);_zoom_vel=lerpf(_zoom_vel,dz/maxf(get_process_delta_time(),0.001),FLING_EMA)
	set_pitch(pitch-(pos.y-previous.y)*PITCH_PER_PX)
	user_moved.emit()
func _gui_input(event:InputEvent) -> void:
	if not input_enabled:return
	if event is InputEventScreenTouch:
		_last_touch_ms=Time.get_ticks_msec()
		if event.pressed:_press(event.index,event.position)
		else:_release(event.index,event.position,event.canceled)
		accept_event()
	elif event is InputEventScreenDrag:
		_last_touch_ms=Time.get_ticks_msec()
		_move(event.index,event.position);accept_event()
	elif Time.get_ticks_msec()-_last_touch_ms>500:
		if event is InputEventMouseButton:
			if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed:stop();change_zoom(.3,event.position);user_moved.emit()
			elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed:stop();change_zoom(-.3,event.position);user_moved.emit()
			elif event.button_index==MOUSE_BUTTON_LEFT:
				if event.pressed:_press(MOUSE,event.position)
				else:_release(MOUSE,event.position)
			accept_event()
		elif event is InputEventMouseMotion and _touches.has(MOUSE):
			_move(MOUSE,event.position);accept_event()
		elif event is InputEventPanGesture:
			set_pitch(pitch-event.delta.y*0.2);user_moved.emit();accept_event() # farm-dev's trackpad tilt
func _notification(what:int) -> void:
	# A finger still down when the app loses focus never reports its release.
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:_touches.clear();_pinch=false;_last_tap_ms=0;stop()
