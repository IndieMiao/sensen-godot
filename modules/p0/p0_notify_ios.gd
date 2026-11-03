class_name P0NotifyIOS
extends RefCounted
## P0Notify's phone on iOS (SGODOT-356): GodotNotify's methods over loopback UDP to tools/ios/LocalNotify.swift
## (127.0.0.1:46466; its header has the protocol). The state comes back on its own, so it is kept here: "" until it
## first does (P0Notify asks nothing before), then as the phone last said it — and again on every return to the front.

signal permission(granted: bool)

const PORT := 46466
## NOTIFY_STATE again this often until the first answer: the listener starts after Godot (G3Spike, 2 s in).
const STATE_RESEND_FRAMES := 30

var _udp: PacketPeerUDP
## What goes out: the UDP socket's put, or a test's.
var _send: Callable
var _state := ""
var _asking := false
var _frames := 0

func _init(send := Callable()) -> void:
	_send = send
	if not _send.is_valid():
		_udp = PacketPeerUDP.new()
		_udp.connect_to_host("127.0.0.1", PORT)
		_send = func(line: String): _udp.put_packet(line.to_utf8_buffer())
		var tree := Engine.get_main_loop() as SceneTree
		if tree: tree.process_frame.connect(_poll)
	_send.call("NOTIFY_STATE")

func state() -> String: return _state

func request_permission() -> void:
	_asking = true
	_send.call("NOTIFY_AUTH")

func open_settings() -> void: _send.call("NOTIFY_SETTINGS")

func schedule(at_ms: float, title: String, body: String, _channel: String) -> void:
	_send.call("NOTIFY_AT|%d|%s|%s" % [int(at_ms), title.replace("|", " "), body.replace("|", " ")])

func cancel_all() -> void: _send.call("NOTIFY_CANCEL_ALL")

## One packet from LocalNotify.swift. A new state answers the system's dialog (`permission`, as on Android) or tells the
## screen the phone's settings changed meanwhile (P0Runtime refreshes on it either way).
func receive(line: String) -> void:
	if not line.begins_with("NOTIFY_STATE|"): return
	var s = JSON.parse_string(line.substr("NOTIFY_STATE|".length()))
	if not s is Dictionary: return
	var was := _state
	_state = JSON.stringify(s)
	if _asking or was != _state:
		_asking = false
		permission.emit(bool(s.get("allowed", false)))

func _poll() -> void:
	_frames += 1
	if _state == "" and _frames % STATE_RESEND_FRAMES == 0: _send.call("NOTIFY_STATE")
	while _udp.get_available_packet_count() > 0:
		receive(_udp.get_packet().get_string_from_utf8())
