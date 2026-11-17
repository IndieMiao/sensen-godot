extends MapBridgeAndroid
## Native owns parcel geometry, rendering, labels and hit testing. No geometry crosses this bridge.
signal parcel_ready(generation:int,style_generation:int,payload:Dictionary)
signal parcel_query_result(request_id:int,generation:int,style_generation:int,payload:Dictionary)
signal parcel_error(generation:int,style_generation:int,code:String)

func _init() -> void:
	super()
	if not is_instance_valid(_plugin):return
	if _plugin.has_signal("parcel_ready"):
		_plugin.connect("parcel_ready",func(g:int,s:int,json:String):parcel_ready.emit(g,s,_decode(json)),CONNECT_DEFERRED)
	if _plugin.has_signal("parcel_query_result"):
		_plugin.connect("parcel_query_result",func(r:int,g:int,s:int,json:String):parcel_query_result.emit(r,g,s,_decode(json)),CONNECT_DEFERRED)
	if _plugin.has_signal("parcel_error"):
		_plugin.connect("parcel_error",func(g:int,s:int,code:String):parcel_error.emit(g,s,code),CONNECT_DEFERRED)

static func _decode(raw:String) -> Dictionary:
	var parser:=JSON.new()
	if parser.parse(raw)!=OK or not parser.data is Dictionary:return {"error":"invalid_native_response"}
	return parser.data
func is_parcel_capable() -> bool:
	for method in ["setParcelSources","queryParcelAt","setParcelStates","setParcelClaims","clearParcelLayers"]:
		if not _supports(method):return false
	return true
func configure(generation:int,config:Dictionary) -> void:
	if is_parcel_capable():_plugin.setParcelSources(generation,JSON.stringify(config))
func query(request_id:int,generation:int,point:Vector2) -> void:
	if is_parcel_capable():_plugin.queryParcelAt(request_id,generation,clampf(point.x,0,1),clampf(point.y,0,1))
func set_states(generation:int,rows:Array) -> void:
	if is_parcel_capable():_plugin.setParcelStates(generation,JSON.stringify(rows))
func set_claims(generation:int,rows:Array) -> void:
	if is_parcel_capable():_plugin.setParcelClaims(generation,JSON.stringify(rows))
func clear(generation:int) -> void:
	if is_parcel_capable():_plugin.clearParcelLayers(generation)
