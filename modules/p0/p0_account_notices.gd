extends Node
## Private, versioned notices (contract v1.6.10). Network ownership is checked before account refusal side effects.
## A notice epoch is independent of Session's world queue and of the login flow's request counter.
const PATH := "/p0/account/notices"
const MAX_VERSION := 9007199254740991
var session: P0Session
var _epoch := 0

static func version(value) -> int:
	if not (value is int or value is float): return -1
	if not is_finite(float(value)) or float(value) < 1.0 or float(value) > MAX_VERSION: return -1
	if float(value) != floorf(float(value)): return -1
	return int(value)

## -1 is unknown/malformed, 0 is explicitly no unread notice. Never infer null from a missing field.
static func unread(reply: Dictionary) -> int:
	if not reply.get("ok") is bool or reply.ok != true or not reply.has("name_reset"): return -1
	if reply.name_reset == null: return 0
	if not reply.name_reset is Dictionary: return -1
	return version(reply.name_reset.get("version"))

func invalidate() -> void: _epoch += 1

func read(done: Callable) -> void:
	_request(HTTPClient.METHOD_GET, PATH, {}, done)

func acknowledge(seen_version: int, done: Callable) -> void:
	_request(HTTPClient.METHOD_POST, PATH + "/ack", {"kind": "name_reset", "version": seen_version}, done)

func _request(method: int, path: String, body: Dictionary, done: Callable) -> void:
	_epoch += 1
	var ticket := _epoch
	if not is_instance_valid(session) or not session.accounts or not session.identity_ready or session.auth_token() == "":
		done.call({"ok": false, "code": "not_ready"})
		return
	var context := session.request_context()
	var http := P0HttpRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers, raw: PackedByteArray):
		http.queue_free()
		if ticket != _epoch or not is_instance_valid(session) or not session.request_is_current(context): return
		# Invalidation must precede the global 401/403 effect, not merely the card callback.
		if session.take_account_refusal(result, code, raw, context): return
		var data = JSON.parse_string(raw.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS else null
		if not data is Dictionary:
			done.call({"ok": false, "code": "network"})
		elif code == 200 and data.get("ok") is bool and data.ok == true:
			done.call(data)
		else:
			done.call({"ok": false, "code": str(data.get("code", "network"))}))
	if http.send(session.base_url + path, session._headers(), method,
			"" if method == HTTPClient.METHOD_GET else JSON.stringify(body)) != OK:
		http.queue_free()
		if ticket == _epoch and session.request_is_current(context): done.call({"ok": false, "code": "network"})
