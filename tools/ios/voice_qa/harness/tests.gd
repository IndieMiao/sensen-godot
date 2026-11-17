extends SceneTree
const Session = preload("res://session.gd")
const IOS = preload("res://modules/net/voice_backend_ios.gd")
var checks := 0
var failures := 0
class FakeNative extends RefCounted:
	signal voice_event(raw: String)
	var calls: Array = []
	func capabilities() -> String: return '{"protocol":1,"supported":true}'
	func request_permission(s): calls.append(["permission",s])
	func connect_voice(s,u,t): calls.append(["connect",s])
	func renew_lease(s,m): calls.append(["lease",s,m])
	func disconnect_voice(s): calls.append(["disconnect",s])
	func set_microphone(s,on): calls.append(["mic",s,on])
	func set_listening(s,on): calls.append(["listen",s,on])
	func set_participant_volume(s,id,v): calls.append(["volume",id,v])
	func set_participant_subscribed(s,id,on): calls.append(["subscribe",id,on])
	func set_publish_allowed(s,id,on): calls.append(["publish",id,on])
	func open_settings(): calls.append(["settings"])
class FakeBroker extends Node:
	var calls: Array = []
	var hold_join := false
	var hold_heartbeat := false
	var released := false
	var wrong_origin := false
	func request(action,body,code) -> Dictionary:
		calls.append([action,body.duplicate()])
		if (action == "join" and hold_join) or (action == "heartbeat" and hold_heartbeat):
			while not released: await get_tree().process_frame
		if action == "join": return {"ok":true,"json":{"ok":true,"url":"wss://other.test" if wrong_origin else "wss://qa.test","token":"fixture-not-real","lease_id":"lease-fixture","lease_ms":20000,"room":"p0-ios-voice-qa-1118-0123456789ab-1","capacity":2,"self":"qa-ios-a","blocked":[]}}
		if action == "heartbeat": return {"ok":true,"json":{"ok":true,"room":"p0-ios-voice-qa-1118-0123456789ab-1","lease_ms":20000}}
		return {"ok":true,"json":{"ok":true}}
func _initialize() -> void: call_deferred("_run")
func verify(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+title)
func setup(validation := false) -> Array:
	var native := FakeNative.new(); var broker := FakeBroker.new(); root.add_child(broker)
	var session = Session.new(); session.configure({"validation_only":validation,"media_origin":"wss://qa.test","client":"ios-a"},native,broker,true);root.add_child(session)
	return [session,native,broker]
func grant(session,native) -> void:
	session.join("fixture-code")
	native.voice_event.emit(JSON.stringify({"event":"permission","session":session._sid,"granted":true}))
func done(items: Array) -> void:
	items[0].leave(); items[0].queue_free(); items[2].queue_free()
func _run() -> void:
	var t := setup(true); t[0].join("fixture-code")
	verify(t[1].calls.is_empty() and t[2].calls.is_empty(),"validation build cannot request permission or grant");done(t)
	t=setup();t[0].join("fixture-code")
	verify(t[1].calls.size()==1 and t[2].calls.is_empty(),"permission precedes any broker request")
	t[1].voice_event.emit(JSON.stringify({"event":"permission","session":t[0]._sid,"granted":false}))
	verify(t[0].state=="idle" and t[2].calls.is_empty(),"denial never requests grant")
	verify(t[0].evidence[0].get("granted")==false and not t[0].evidence[0].has("code"),"permission evidence records denial without a synthetic error code");done(t)
	t=setup();grant(t[0],t[1])
	verify(t[0].state=="connecting" and t[1].calls.any(func(c):return c[0]=="connect"),"valid grant reaches real backend interface")
	verify(t[1].calls.any(func(c):return c[0]=="lease" and c[2]>19000 and c[2]<=19500),"normal native lease below 20s server lease")
	t[1].voice_event.emit(JSON.stringify({"event":"connected","session":t[0]._sid,"participants":[],"microphone":false,"listening":true}))
	verify(t[0].evidence.any(func(row):return row.get("event")=="connected" and not row.has("code") and not row.has("reason")),"successful native events do not acquire false failure fields")
	t[1].voice_event.emit(JSON.stringify({"event":"microphone","session":t[0]._sid,"microphone":false,"qa_native_uptime_ms":1234.5,"qa_native_wall_seconds":1794936000.25}))
	verify(t[0].evidence[-1].get("qa_native_uptime_ms")==1234.5 and t[0].evidence[-1].get("qa_native_wall_seconds")==1794936000.25,"harness preserves both numeric native clocks from wire events")
	t[0].set_blocked("qa-android-b",true)
	verify(t[1].calls.any(func(c):return c[0]=="subscribe" and c[2]==false) and t[1].calls.any(func(c):return c[0]=="publish" and c[2]==false),"Block affects both native directions")
	t[0].set_blocked("qa-android-b",false)
	verify(t[1].calls[-2][2]==true and t[1].calls[-1][2]==true,"unblock explicitly restores both directions")
	t[0].test_native_expiry()
	verify(not t[0].renew_enabled and t[1].calls[-1][0]=="lease" and t[1].calls[-1][2]==5000,"native expiry test renews server then shortens only native lease")
	verify(t[0].evidence.any(func(row):return row.get("kind")=="native_expiry_test_start" and row.get("server_lease_ms")==20000),"native/server lease difference is recorded")
	t[0].foreground(false)
	verify(t[0].state=="idle" and t[0]._sid=="","background leaves without automatic fresh grant")
	t[0].foreground(true);verify(t[0].state=="idle","foreground stays idle until user joins");done(t)
	t=setup();grant(t[0],t[1]);t[2].hold_heartbeat=true;t[0]._heartbeat()
	var wait_until := Time.get_ticks_msec()+60
	while Time.get_ticks_msec()<wait_until: await process_frame
	t[2].released=true;await process_frame;await process_frame
	verify(t[1].calls[-1][0]=="lease" and t[1].calls[-1][2]<19460,"slow heartbeat response reduces native lease budget")
	verify(t[0].lease_budget(Time.get_ticks_msec()-21000)==0,"expired response has no renewable budget");done(t)
	t=setup();t[2].hold_join=true;grant(t[0],t[1]);t[0].leave();t[2].released=true
	await process_frame;await process_frame
	verify(not t[1].calls.any(func(c):return c[0]=="connect") and t[2].calls.any(func(c):return c[0]=="leave"),"late grant after Leave is released without native connect");done(t)
	t=setup();t[2].wrong_origin=true;grant(t[0],t[1])
	verify(not t[1].calls.any(func(c):return c[0]=="connect") and t[2].calls.any(func(c):return c[0]=="leave"),"wrong-origin grant is refused and lease released");done(t)
	t=setup();grant(t[0],t[1]);t[2].hold_heartbeat=true;t[0]._heartbeat();t[0].renew_enabled=false
	var before: int=t[1].calls.size();t[2].released=true;await process_frame;await process_frame
	verify(t[1].calls.size()==before,"inflight heartbeat cannot renew after pause")
	t[1].voice_event.emit(JSON.stringify({"event":"SENSITIVE_FIXTURE","session":t[0]._sid,"code":"SENSITIVE_FIXTURE","qa_native_wall_seconds":"SENSITIVE_FIXTURE"}))
	verify(not JSON.stringify(t[0].evidence).contains("SENSITIVE_FIXTURE"),"event evidence never retains arbitrary body strings")
	verify(not JSON.stringify(t[0].evidence).contains("fixture-code") and not JSON.stringify(t[0].evidence).contains("fixture-not-real"),"evidence excludes code and JWT")
	done(t);await process_frame
	var wire_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wire-fixture="): wire_path = arg.trim_prefix("--wire-fixture=")
	verify(not wire_path.is_empty() and FileAccess.file_exists(wire_path),"actual emitter/outbox wire fixture supplied")
	if not wire_path.is_empty() and FileAccess.file_exists(wire_path):
		var parser := JSON.new(); parser.parse(FileAccess.get_file_as_string(wire_path))
		var fixture: Dictionary = parser.data
		var sent: Array[String] = []; var emitted: Array[String] = []
		var real_backend = IOS.new(func(line: String):sent.append(line),func():return "0".repeat(64))
		var transport := FakeBroker.new();root.add_child(transport)
		var client = Session.new();client.configure({"validation_only":false,"client":"ios-a","media_origin":"wss://qa.test"},real_backend,transport,true);root.add_child(client)
		client._sid="qa-fixture";client.state="connected"
		real_backend.voice_event.connect(func(raw: String):emitted.append(raw))
		real_backend.receive(str(fixture.initial));real_backend.receive(str(fixture.retry))
		var expected_parser:=JSON.new();expected_parser.parse(str(fixture.initial).split("|",true,2)[2])
		var expected: Dictionary=expected_parser.data
		verify(client.evidence.size()==1 and client.evidence[0].get("qa_native_uptime_ms")==expected.get("qa_native_uptime_ms") and client.evidence[0].get("qa_native_wall_seconds")==expected.get("qa_native_wall_seconds"),"real backend preserves clocks from actual native emit and outbox bytes")
		verify(emitted.size()==1 and sent.filter(func(line):return line.begins_with("VOICE_ACK|")).size()==2,"real backend ACKs retry twice but emits event once")
		client.leave();client.queue_free();transport.queue_free();await process_frame
	print("QA_HARNESS ",checks," checks, ",failures," failures; fake transport only")
	quit(1 if failures else 0)
