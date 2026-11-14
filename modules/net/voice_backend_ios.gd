class_name VoiceBackendIOS
extends RefCounted
## PartyVoiceSession's backend on iOS (SGODOT-387; 亚瑟's protocol v1.1, store-readiness/ios-voice-udp-protocol.md): the
## Android plugin's methods (GodotVoicePlugin) as lines over loopback UDP to the native VoiceBridge (127.0.0.1:46467),
## as P0NotifyIOS talks to LocalNotify. One line a packet, fields split by `|` (a `|` inside one becomes a space), and
## every line Godot sends ends `|key=<this launch's key>` (AppleSignIn.bridge_key(), read again for each line; the
## bridge drops a line without it — another app could write to the port, and VOICE_CONNECT carries the LiveKit token).
## Back come VOICE_CAPS|<json>, kept as it is (capabilities() answers it; {"protocol":1,"supported":false} till then, so
## the mic key stays away — VOICE_CAPS goes again every 30 frames till the first answer: the bridge listens 2 s after
## Godot starts), and VOICE_EVENT|<n>|<json>, the plugin's own event JSON, emitted as voice_event for
## PartyVoiceSession._on_native_event. n = 0 is a snapshot (participants, microphone, listening): no answer. A one-off
## (permission, connected, …) counts up from 1 and the bridge sends it again every 250 ms till VOICE_ACK|<n>: every
## packet of it is answered, its event emitted once (the last 64 n remembered).

signal voice_event(raw: String)

const PORT := 46467
const CAPS_RESEND_FRAMES := 30
const SEEN_MAX := 64
const NO_CAPS := "{\"protocol\":1,\"supported\":false}"

var _udp: PacketPeerUDP
## What goes out: the UDP socket's put, or a test's.
var _send: Callable
## The launch's key: AppleSignIn.bridge_key, or a test's.
var _key: Callable
var _caps := ""
var _frames := 0
var _seen: Array[int] = []

func _init(send := Callable(), key := Callable()) -> void:
	_send = send
	_key = key if key.is_valid() else AppleSignIn.bridge_key
	if not _send.is_valid():
		_udp = PacketPeerUDP.new()
		_udp.connect_to_host("127.0.0.1", PORT)
		_send = func(line: String): _udp.put_packet(line.to_utf8_buffer())
	_out(["VOICE_CAPS"])

## The bridge's answer as it gave it, or not supported till there is one (PartyVoiceSession.supported reads it).
func capabilities() -> String:
	return _caps if _caps != "" else NO_CAPS

func request_permission(session: String) -> void: _out(["VOICE_PERMISSION", session])
func connect_voice(session: String, url: String, token: String) -> void: _out(["VOICE_CONNECT", session, url, token])
func renew_lease(session: String, milliseconds: int) -> void: _out(["VOICE_LEASE", session, str(milliseconds)])
func set_microphone(session: String, on: bool) -> void: _out(["VOICE_MIC", session, _bit(on)])
func set_listening(session: String, on: bool) -> void: _out(["VOICE_LISTEN", session, _bit(on)])
func set_participant_volume(session: String, identity: String, volume: float) -> void:
	_out(["VOICE_VOLUME", session, identity, str(clampf(volume, 0.0, 1.0))])
func set_participant_subscribed(session: String, identity: String, on: bool) -> void:
	_out(["VOICE_SUBSCRIBE", session, identity, _bit(on)])
func set_publish_allowed(session: String, identity: String, on: bool) -> void:
	_out(["VOICE_PUBLISH", session, identity, _bit(on)])
func disconnect_voice(session: String) -> void: _out(["VOICE_DISCONNECT", session])
## This app's page in the system settings (after the microphone was refused; whether a key shows it is 不知火舞's).
func open_settings() -> void: _out(["VOICE_SETTINGS"])

## Each frame (PartyVoiceSession._process): VOICE_CAPS again till answered, then what the bridge sent.
func poll_events() -> void:
	_frames += 1
	if _caps == "" and _frames % CAPS_RESEND_FRAMES == 0: _out(["VOICE_CAPS"])
	if _udp == null: return
	while _udp.get_available_packet_count() > 0:
		receive(_udp.get_packet().get_string_from_utf8())

## One packet from the bridge.
func receive(line: String) -> void:
	if line.begins_with("VOICE_CAPS|"):
		var raw := line.substr("VOICE_CAPS|".length())
		if JSON.parse_string(raw) is Dictionary: _caps = raw   # as the bridge said it (a re-stringify makes 1 into 1.0)
		return
	if not line.begins_with("VOICE_EVENT|"): return
	var parts := line.split("|", true, 2)   # the event's JSON may hold `|` in a name: only the first two split
	if parts.size() < 3 or not parts[1].is_valid_int(): return
	var n := int(parts[1])
	if n > 0:
		_out(["VOICE_ACK", str(n)])   # every packet of a one-off, a repeat too: the bridge stops on the first it hears
		if n in _seen: return
		_seen.append(n)
		if _seen.size() > SEEN_MAX: _seen.pop_front()
	voice_event.emit(parts[2])

## A line out: its fields with `|` as spaces, then this launch's key.
func _out(fields: Array) -> void:
	var clean := PackedStringArray()
	for f in fields: clean.append(str(f).replace("|", " "))
	_send.call("|".join(clean) + "|key=" + str(_key.call()))

static func _bit(on: bool) -> String: return "1" if on else "0"
