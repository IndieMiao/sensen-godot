class_name MapUsage
extends RefCounted
## Settings › Licenses › Mapbox › Map data (q(133) v3): Mapbox's telemetry switch (`Share anonymous map usage`) and the
## `Improve this map` address. The switch is the map SDK's own state, through public interfaces that need no map view:
## Android the map plugin (Mapbox Common TelemetryUtils), iOS MapUnderlay's TELEM (UserDefaults MGLMapboxMetricsEnabled).
## The SDKs keep the choice; the game keeps a copy for where it cannot ask (iOS, the desktop). On by default.

const PREFS := "user://map_usage.cfg"
const IOS_PORT := 46464   # MapUnderlay.swift's loopback listener (MapBridgeIOS)
const FEEDBACK := "https://apps.mapbox.com/feedback/#/%.5f/%.5f/%.2f"
const MAPBOX_CREDIT := "https://www.mapbox.com/about/maps/"
const OSM_CREDIT := "https://www.openstreetmap.org/copyright"

## The map's last centre and zoom (lat, lng, zoom), for Improve this map; zero before the map has opened.
static var last_view := Vector3.ZERO

static func enabled() -> bool:
	var plugin = _android()
	if plugin != null: return bool(plugin.isTelemetryEnabled())
	return saved()

## The game's own copy of the choice (on by default).
static func saved() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(PREFS) != OK: return true
	return bool(cfg.get_value("mapbox", "telemetry", true))

## iOS: the TELEM line for MapUnderlay, from the saved choice. MapBridgeIOS sends it again once the map is up and with
## its LANG repeats (UDP to a listener not yet up is lost).
static func telem_packet() -> String:
	return "TELEM|%d" % (1 if saved() else 0)

static func set_enabled(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PREFS)
	cfg.set_value("mapbox", "telemetry", on)
	cfg.save(PREFS)
	var plugin = _android()
	if plugin != null:
		plugin.setTelemetryEnabled(on)
	elif OS.has_feature("ios"):
		var udp := PacketPeerUDP.new()
		udp.connect_to_host("127.0.0.1", IOS_PORT)
		udp.put_packet(telem_packet().to_utf8_buffer())
		udp.close()

## Mapbox's feedback page at the map's last centre and zoom, else at `fallback` (lat, lng, zoom: the home city's).
static func feedback_url(fallback: Vector3) -> String:
	var v := last_view if last_view != Vector3.ZERO else fallback
	return FEEDBACK % [v.y, v.x, v.z]

static func _android() -> Object:
	return Engine.get_singleton("GodotMap") if OS.has_feature("android") and Engine.has_singleton("GodotMap") else null
