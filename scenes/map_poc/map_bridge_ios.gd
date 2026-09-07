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
## 已请求定位但还没收到第一手数据：与 CREATE 同节奏重发 LOC|1（监听器晚启动会丢首发）。
var _want_location := false
var _got_location := false

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

func get_pixel_ratio() -> float:
	return _ratio

func start_location() -> void:
	_want_location = true
	_got_location = false
	_send("LOC|1")

func stop_location() -> void:
	_want_location = false
	_send("LOC|0")

## "LOC|lat|lng|acc" → [lat, lng, acc]；格式不对返回空数组。
static func parse_location(s: String) -> Array:
	if not s.begins_with("LOC|"):
		return []
	var parts := s.split("|")
	if parts.size() < 4 or not parts[1].is_valid_float() or not parts[2].is_valid_float():
		return []
	var acc := float(parts[3]) if parts[3].is_valid_float() else -1.0
	return [float(parts[1]), float(parts[2]), acc]

func poll() -> void:
	_frames += 1
	if _frames % CREATE_RESEND_FRAMES == 0:
		if not _got_ready and not _pending_create.is_empty():
			_send(_pending_create)
		if _want_location and not _got_location:
			_send("LOC|1")
	while _udp.get_available_packet_count() > 0:
		var s := _udp.get_packet().get_string_from_utf8()
		if s.begins_with("READY|"):
			_ratio = maxf(float(s.get_slice("|", 1)), 1.0)
			_got_ready = true
			map_ready.emit()
		elif s.begins_with("LOC|"):
			var loc := parse_location(s)
			if not loc.is_empty():
				_got_location = true
				location_update.emit(loc[0], loc[1], loc[2])

func _send(s: String) -> void:
	_udp.put_packet(s.to_utf8_buffer())
