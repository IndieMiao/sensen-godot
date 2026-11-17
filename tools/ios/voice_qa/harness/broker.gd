extends Node
## GENSEN_VOICE_MEDIA_QA_V1. Fixed HTTPS broker; no redirects, persistence or body logging.
var origin := ""
var validation_only := true

func request(action: String, body: Dictionary, capability: String) -> Dictionary:
	if validation_only or action not in ["join", "heartbeat", "leave"] or capability.is_empty():
		return {"ok": false, "json": {"code": "QA_NOT_READY"}}
	if capability.contains("\r") or capability.contains("\n"):
		return {"ok": false, "json": {"code": "QA_CODE_INVALID"}}
	var http := HTTPRequest.new()
	http.max_redirects = 0
	http.timeout = 8.0
	http.body_size_limit = 16384
	add_child(http)
	var err := http.request(origin + "/qa/voice/" + action,
		PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + capability]),
		HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return {"ok": false, "json": {"code": "NETWORK"}}
	var response: Array = await http.request_completed
	http.queue_free()
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "json": {"code": "NETWORK"}}
	var parser := JSON.new()
	if parser.parse((response[3] as PackedByteArray).get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return {"ok": false, "json": {"code": "BAD_RESPONSE"}}
	var data: Dictionary = parser.data
	return {"ok": int(response[1]) >= 200 and int(response[1]) < 300 and data.get("ok", false) == true, "json": data}
