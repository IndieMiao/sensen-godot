extends GdUnitTestSuite
## VoiceBackendIOS (SGODOT-387; 亚瑟's protocol v1.1): the lines it sends (each with this launch's key, `|` in a field a
## space), VOICE_CAPS again till answered, capabilities before and after, one-off events answered every packet but
## emitted once, snapshots never answered, and PartyVoiceSession reading it as a backend.

var sent: Array = []
var key := "k3y"

func _backend() -> VoiceBackendIOS:
	sent.clear()
	key = "k3y"
	return VoiceBackendIOS.new(func(line: String): sent.append(line), func(): return key)

func test_every_line_ends_with_the_launch_key_and_a_bar_in_a_field_is_a_space() -> void:
	var b := _backend()
	b.request_permission("s1")
	b.connect_voice("s1", "wss://lk.example|x", "tok|en")
	b.renew_lease("s1", 20000)
	b.set_microphone("s1", true)
	b.set_listening("s1", false)
	b.set_participant_volume("s1", "peer|7", 0.0)
	b.set_participant_subscribed("s1", "peer7", false)
	b.set_publish_allowed("s1", "peer7", true)
	b.disconnect_voice("s1")
	b.open_settings()
	assert_array(sent).is_equal([
		"VOICE_CAPS|key=k3y",
		"VOICE_PERMISSION|s1|key=k3y",
		"VOICE_CONNECT|s1|wss://lk.example x|tok en|key=k3y",
		"VOICE_LEASE|s1|20000|key=k3y",
		"VOICE_MIC|s1|1|key=k3y",
		"VOICE_LISTEN|s1|0|key=k3y",
		"VOICE_VOLUME|s1|peer 7|0.0|key=k3y",   # str(float): 0.0 / 1.0, read as a Double
		"VOICE_SUBSCRIBE|s1|peer7|0|key=k3y",
		"VOICE_PUBLISH|s1|peer7|1|key=k3y",
		"VOICE_DISCONNECT|s1|key=k3y",
		"VOICE_SETTINGS|key=k3y"])
	key = "n3w"   # read again for each line: a key written after Godot started still goes out
	b.set_microphone("s1", false)
	assert_str(sent.back()).is_equal("VOICE_MIC|s1|0|key=n3w")
	key = ""   # not written yet: sent anyway (the bridge drops it; CAPS comes again till it answers)
	b.set_microphone("s1", false)
	assert_str(sent.back()).is_equal("VOICE_MIC|s1|0|key=")

func test_capabilities_say_unsupported_till_the_bridge_answers_and_caps_go_again_meanwhile() -> void:
	var b := _backend()
	assert_str(b.capabilities()).is_equal("{\"protocol\":1,\"supported\":false}")
	for i in 59: b.poll_events()
	assert_int(sent.count("VOICE_CAPS|key=k3y")).is_equal(2)   # at start and at frame 30
	b.poll_events()
	assert_int(sent.count("VOICE_CAPS|key=k3y")).is_equal(3)
	var caps := {"protocol": 1, "supported": true, "platform": "ios", "per_participant": true, "publish_permissions": true}
	b.receive("VOICE_CAPS|" + JSON.stringify(caps))
	assert_str(b.capabilities()).is_equal(JSON.stringify(caps))   # kept as the bridge said it
	for i in 60: b.poll_events()
	assert_int(sent.count("VOICE_CAPS|key=k3y")).is_equal(3)   # answered: no more
	b.receive("VOICE_CAPS|not json")   # a broken answer keeps the last good one
	assert_str(b.capabilities()).is_equal(JSON.stringify(caps))

func test_a_one_off_is_answered_every_packet_but_emitted_once_and_a_snapshot_never_answered() -> void:
	var b := _backend()
	var got: Array = []
	b.voice_event.connect(func(raw: String): got.append(raw))
	var connected := "{\"event\":\"connected\",\"session\":\"s1\"}"
	b.receive("VOICE_EVENT|3|" + connected)
	b.receive("VOICE_EVENT|3|" + connected)
	assert_array(got).is_equal([connected])
	assert_int(sent.count("VOICE_ACK|3|key=k3y")).is_equal(2)
	var people := "{\"event\":\"participants\",\"session\":\"s1\",\"participants\":[{\"name\":\"A|B\"}]}"
	b.receive("VOICE_EVENT|0|" + people)
	b.receive("VOICE_EVENT|0|" + people)
	assert_array(got).is_equal([connected, people, people])   # a `|` inside the JSON kept; snapshots each time
	assert_bool(sent.any(func(l: String): return l.begins_with("VOICE_ACK|0"))).is_false()
	b.receive("VOICE_EVENT|x|{}")
	b.receive("VOICE_EVENT|4")
	b.receive("SOMETHING_ELSE|1|{}")
	assert_int(got.size()).is_equal(3)

func test_only_the_last_64_one_offs_are_remembered() -> void:
	var b := _backend()
	var got: Array = []
	b.voice_event.connect(func(raw: String): got.append(raw))
	for n in range(1, 66): b.receive("VOICE_EVENT|%d|{\"event\":\"error\"}" % n)
	assert_int(got.size()).is_equal(65)
	b.receive("VOICE_EVENT|65|{\"event\":\"error\"}")   # remembered
	assert_int(got.size()).is_equal(65)
	b.receive("VOICE_EVENT|1|{\"event\":\"error\"}")   # long forgotten: taken as new
	assert_int(got.size()).is_equal(66)

func test_the_voice_session_reads_it_as_a_native_backend() -> void:
	var b := _backend()
	var voice := PartyVoiceSession.new()
	add_child(auto_free(voice))
	voice.set_process(false)
	voice.set_backend(b)
	assert_bool(voice.supported()).is_false()   # no CAPS yet: no mic key
	b.receive("VOICE_CAPS|{\"protocol\":1,\"supported\":true,\"platform\":\"ios\",\"per_participant\":true,\"publish_permissions\":true}")
	assert_bool(voice.supported()).is_true()
	assert_bool(voice.per_participant()).is_true()
	voice._process(0.016)   # the session polls the bridge each frame
	assert_int(b._frames).is_equal(1)
