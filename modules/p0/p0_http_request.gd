class_name P0HttpRequest extends HTTPRequest
## SGODOT-370: every P0 request to the server. Godot's HTTPRequest steps its connection on the main thread, a step a
## frame, and its timeout is a Timer that counts every frame's time: while a world loads (an outpost took 5–7 s on a
## slow emulator) the request does not move at all, and the first frame after it adds the whole stall to the timer —
## the reply that came 17 ms after the request reached the server was too late for an 8 s that began before the load
## (蒙恬 X6 / X15, 10-30: "Couldn't get there", Retry fine). So the wait is counted here in live time: a frame counts at
## most FRAME_CAP_S, and a stall of the whole app is not the server being slow; after it the request goes on stepping.
## Not use_threads: a threaded request blocks on a server that says nothing, and its cancel (the timeout's) then waits
## on that thread with the main thread — the app froze in the test of exactly that. Start one with send().

const FRAME_CAP_S := 0.25
var wait_s := 8.0      # live seconds before a request with no answer is given up (RESULT_TIMEOUT)
var _waited := -1.0    # live seconds the request on the wire has waited; < 0: none

func _init(wait := 8.0) -> void:
	wait_s = wait
	timeout = 0.0   # the engine's own timer counts stalls: ours does not (_process)
	request_completed.connect(func(_r, _c, _h, _b): _waited = -1.0)

## HTTPRequest.request, with the live-time wait started.
func send(url: String, headers: PackedStringArray = PackedStringArray(), method := HTTPClient.METHOD_GET, body := "") -> Error:
	var err := request(url, headers, method, body)
	_waited = 0.0 if err == OK else -1.0
	return err

func _process(dt: float) -> void:
	if _waited < 0.0: return
	_waited += live_dt(dt)
	if _waited < wait_s: return
	_waited = -1.0
	cancel_request()
	request_completed.emit(RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())

## A frame's time as the wait counts it: a stall (a scene loading, the app paused) counts as one slow frame.
static func live_dt(dt: float) -> float:
	return minf(dt, FRAME_CAP_S)
