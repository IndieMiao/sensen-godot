class_name MapBridgeIOS
extends MapBridge
## iOS 实现：本机 UDP 回环 → MapUnderlay.swift（监听 127.0.0.1:46464）。
## PoC 形态：Mapbox v11 是纯 Swift API，正式化时迁 GDExtension/插件；
## 协议见 tools/ios/MapUnderlay.swift 头注释。
## 可靠性：UDP 丢包无害——CAM 每帧幂等重发；CREATE 在收到 READY 前周期重发
## （Swift 侧监听器启动晚于 Godot _ready，首发必然落空）。

const PORT := 46464
const CREATE_RESEND_FRAMES := 30

var _udp := PacketPeerUDP.new()
var _ratio := 1.0
var _pending_create := ""
var _got_ready := false
var _frames := 0
var _locale := "zh_CN"
## POIS 回包按 request_id 收集分包：{id: {"parts": n, "chunks": {index: features}}}。
var _poi_parts: Dictionary = {}

func _init() -> void:
	_udp.connect_to_host("127.0.0.1", PORT)
	_ratio = maxf(DisplayServer.screen_get_scale(), 1.0) # READY 前的合理默认

static func format_cam(lat: float, lng: float, zoom: float, bearing: float, pitch: float) -> String:
	return "CAM|%.7f|%.7f|%.3f|%.2f|%.2f" % [lat, lng, zoom, bearing, pitch]

func create_map(token: String, lat: float, lng: float, zoom: float) -> void:
	_pending_create = "CREATE|%s|%.7f|%.7f|%.3f" % [token, lat, lng, zoom]
	_got_ready = false
	_send(_pending_create)

func set_camera(lat: float, lng: float, zoom: float, bearing: float, pitch: float) -> void:
	_send(format_cam(lat, lng, zoom, bearing, pitch))

func set_map_visible(visible: bool) -> void:
	_send("VIS|%d" % (1 if visible else 0))

func set_language(locale: String) -> void:
	_locale = locale
	_send("LANG|" + _locale)

func get_pixel_ratio() -> float:
	return _ratio

func has_mapbox() -> bool:
	return _got_ready   # the map is up (周瑜 on #309)

func poll() -> void:
	_frames += 1
	if _frames % CREATE_RESEND_FRAMES == 0:
		_send("LANG|" + _locale)
		_send(MapUsage.telem_packet())   # Map data's switch, again: a TELEM sent before the listener was up is lost (周瑜 on #309)
	if not _got_ready and not _pending_create.is_empty() \
			and _frames % CREATE_RESEND_FRAMES == 0:
		_send(_pending_create)
	while _udp.get_available_packet_count() > 0:
		var s := _udp.get_packet().get_string_from_utf8()
		if s.begins_with("POIS|"):
			_on_pois_packet(s)
		elif s.begins_with("READY|"):
			_ratio = maxf(float(s.get_slice("|", 1)), 1.0)
			_got_ready = true
			_send(MapUsage.telem_packet())
			map_ready.emit()

func request_pois(request_id: int) -> void:
	_send("POIS|%d" % request_id)

## 原生侧把一次查询拆成 POIS|id|part|parts|{json}；收齐后合并成一次 pois_received。
func _on_pois_packet(s: String) -> void:
	var head := s.split("|", true, 4)
	if head.size() < 5: return
	var id := int(head[1])
	var index := int(head[2])
	var parts := maxi(1, int(head[3]))
	var body = JSON.parse_string(head[4])
	if not body is Dictionary: return
	# A newer request supersedes older partial answers.
	for old in _poi_parts.keys():
		if int(old) < id: _poi_parts.erase(old)
	var entry: Dictionary = _poi_parts.get(id, {"parts": parts, "chunks": {}, "error": ""})
	entry.chunks[index] = body.get("features", [])
	if body.has("error"): entry.error = str(body.error)
	_poi_parts[id] = entry
	if entry.chunks.size() < int(entry.parts): return
	_poi_parts.erase(id)
	var features := []
	for i in int(entry.parts): features.append_array(entry.chunks.get(i, []))
	var result := {"features": features}
	if not str(entry.error).is_empty(): result.error = entry.error
	pois_received.emit(id, JSON.stringify(result))

func _send(s: String) -> void:
	_udp.put_packet(s.to_utf8_buffer())
