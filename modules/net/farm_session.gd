class_name FarmSession
extends RefCounted
## 农场会话：登录 → 建/取农场 → 发命令 → version 对账。
##
## 客户端契约（方案 §3 D4）：**不算钱、不算 XP、不算 ready_at**。这里只负责把命令送出去、
## 把回包里的权威状态收回来。任何「本地先算个数给玩家看」的逻辑都不属于这一层。
##
## 断网时进只读态并**不排队离线命令**：排队会让玩家以为操作生效了，回来却发现全被拒——
## 那比当场说「现在离线」更糟。

signal state_changed(state: Dictionary, version: int)
signal offline_changed(offline: bool)
signal rejected(code: String, detail: String)

const OFFLINE_AFTER_FAILURES := 2
const PENDING_COMMANDS := [&"pending_resident_command", &"pending_kitchen_command", &"pending_economy_command", &"pending_decoration_command", &"pending_event_command", &"pending_stall_command"]

var client: ApiClient
var player_id := ""
var farm_id := ""
## 服务端农场用的蓝图。**这才是权威**：2026-09-04 真机上客户端按本地选的 sh_b 进场，服务端
## 农场却是 sh_c，发出去的格子全 CELL_NOT_CULTIVABLE，状态里的草画到了别的坐标上。
var layout_patch_id := ""
var blueprint_revision := 0
var region_id := ""
var location: Dictionary = {}
var version := -1
var state: Dictionary = {}
var derived: Dictionary = {}
var offline := false
## 服务端时间 − 本地时间（毫秒）。成熟判定必须用它换算：本地时钟不可信，
## 玩家改系统时间不应该让作物提前熟（PRD §9.1 L668）。
var clock_offset_ms := 0
var _server_time_ms := -1
var _server_sample_ticks_ms := 0

var last_error_code := ""
var _failures := 0
## 命令串行：上一条还没回包就发下一条，base_version 必然过期 → 409 → 重发一次 → 若第三条
## 又在路上就再 409 → 放弃。自动玩家跑批量清理时 9 格丢了 2 格，就是这么丢的。
var _next_ticket := 0
var _serving := 0
## Retain the exact envelope until the server has resolved a response that may have been lost.
var _unconfirmed_command: Dictionary = {}

func _init(p_client: ApiClient) -> void:
	client = p_client

func logged_in() -> bool:
	return client != null and not client.token.is_empty()

func has_unconfirmed_command() -> bool:
	return not _unconfirmed_command.is_empty()

func has_farm() -> bool:
	return not farm_id.is_empty()

## 服务端「现在」的毫秒时间戳。
func server_now() -> int:
	if _server_time_ms >= 0:
		return _server_time_ms + Time.get_ticks_msec() - _server_sample_ticks_ms
	return int(Time.get_unix_time_from_system() * 1000.0) + clock_offset_ms

func login() -> bool:
	var r: ApiClient.Response = await client.request("POST", "/auth/anonymous", {"install_key": ApiClient.install_key()})
	if not _track(r):
		last_error_code = "TRANSPORT"
		return false
	if not r.is_success():
		# 429 = 登录限流（每 IP 每小时 10 次）；记下来，否则「登录失败」和断网分不清。
		last_error_code = str(r.json.get("code", "HTTP_%d" % r.status))
		return false
	player_id = str(r.json.get("player_id", ""))
	client.token = str(r.json.get("token", ""))
	return not client.token.is_empty()

## 已有农场就取回来，没有就建一个。
func ensure_farm(region_id: String, layout_patch_id: String, revision: int, placement: Dictionary = {}) -> bool:
	last_error_code = ""
	var me: ApiClient.Response = await client.request("GET", "/farms/me")
	if not _track(me):
		last_error_code = "TRANSPORT"
		return false
	if me.is_success():
		_adopt(me.json)
		return true
	if me.status != 404:
		last_error_code = str(me.json.get("code", "HTTP_%d" % me.status))
		return false
	if not placement.is_empty():
		if not FarmPlacement.is_valid(placement):
			return _reject_placement("INVALID_LOCATION", "Choose a valid farm location")
		# An older server ignores unknown create fields, which would silently create at the template.
		var regions: ApiClient.Response = await client.request("GET", "/regions")
		if not _track(regions):
			last_error_code = "TRANSPORT"
			return false
		if not regions.is_success() or int(regions.json.get("farm_placement_version", 0)) < 1:
			return _reject_placement("LOCATION_UNSUPPORTED", "This server does not support choosing a farm location yet")
	var payload := {
		"idempotency_key": _new_key(),
		"region_id": region_id,
		"layout_patch_id": layout_patch_id,
		"blueprint_revision": revision,
	}
	if not placement.is_empty():
		payload["location"] = placement.duplicate()
	var r: ApiClient.Response = await client.request("POST", "/farms", payload)
	if not _track(r):
		last_error_code = "TRANSPORT"
		return false
	if not r.is_success():
		last_error_code = str(r.json.get("code", "UNKNOWN"))
		emit_signal("rejected", last_error_code, str(r.json.get("message", "")))
		return false
	_adopt(r.json)
	return true

func _reject_placement(code: String, detail: String) -> bool:
	last_error_code = code
	emit_signal("rejected", code, detail)
	return false

func refresh() -> bool:
	# 和命令走同一条串行队列：GET 与在途命令并发时，先回来的旧状态会盖掉后回来的新状态
	#（自动玩家：9 格都 applied，客户端却剩「Water 1 plot」）。
	var ticket := _next_ticket
	_next_ticket += 1
	while _serving != ticket:
		await Engine.get_main_loop().process_frame
	if not _unconfirmed_command.is_empty():
		var replay := await _request_command(_unconfirmed_command.duplicate(true), true)
		if not _track(replay):
			_serving += 1
			return false
		if _command_succeeded(replay) or str(replay.json.get("code", "")) == "VERSION_CONFLICT":
			_adopt(replay.json)
	var r: ApiClient.Response = await client.request("GET", "/farms/me")
	_serving += 1
	if not _track(r):
		return false
	if r.is_success():
		_adopt(r.json)
	return r.is_success()

## 发一条命令。返回是否被服务端接受（applied 或 replayed）。
##
## 重试协议（spec §7.3）：
##   传输层失败 → 同 key 原样重发一次（服务端幂等，重复不会双花）
##   409 VERSION_CONFLICT → 用回包里的新 version **换新 key** 重发一次
## 两次都不成就放弃，让上层回滚预测。
func send(type: String, payload: Dictionary, pending_owner: StringName = &"") -> bool:
	var ticket := _next_ticket
	_next_ticket += 1
	while _serving != ticket:
		await Engine.get_main_loop().process_frame
	if not _unconfirmed_command.is_empty():
		_serving += 1
		last_error_code = "PENDING_ACTION"
		rejected.emit(last_error_code, "Check the previous command before sending another")
		return false
	for key in PENDING_COMMANDS:
		if key != pending_owner and has_meta(key):
			_serving += 1
			last_error_code = "PENDING_ACTION"
			rejected.emit(last_error_code, str(key))
			return false
	var result: bool = await _send_serialized(type, payload)
	_serving += 1
	return result

func _send_serialized(type: String, payload: Dictionary) -> bool:
	if offline:
		last_error_code = "OFFLINE"
		emit_signal("rejected", "OFFLINE", "离线中，命令未发送")
		return false
	var r := await _request_command(_command_envelope(type, payload))
	if not _track(r):
		return false
	if r.status == 409 and str(r.json.get("code", "")) == "VERSION_CONFLICT":
		# 回包带着最新状态，先对账再用**新 key** 重发（同 key 换 base_version 会被判
		# IDEMPOTENCY_MISMATCH）。
		_adopt(r.json)
		r = await _request_command(_command_envelope(type, payload))
		if not _track(r):
			return false
	if _command_succeeded(r):
		last_error_code = ""
		_adopt(r.json)
		return true
	last_error_code = str(r.json.get("code", "UNKNOWN"))
	emit_signal("rejected", last_error_code, str(r.json.get("detail", "")))
	return false

func _command_envelope(type: String, payload: Dictionary) -> Dictionary:
	return {"idempotency_key": _new_key(), "base_version": version, "type": type, "payload": payload.duplicate(true)}

func _request_command(envelope: Dictionary, recovering := false) -> ApiClient.Response:
	var uncertain := recovering
	var r := await _post_command(str(envelope.idempotency_key), int(envelope.base_version), str(envelope.type), envelope.payload)
	if not r.ok:
		uncertain = true
		r = await _post_command(str(envelope.idempotency_key), int(envelope.base_version), str(envelope.type), envelope.payload)
	var final_response := r.is_success() or r.status == 422 \
		or (r.status == 409 and str(r.json.get("code", "")) == "VERSION_CONFLICT") \
		or (r.status == 503 and str(r.json.get("code", "")) == "VERSION_MISMATCH")
	# A proxy timeout or an auth error on replay cannot prove that the original command did not commit.
	if not r.ok or (r.status >= 500 and not final_response) or (uncertain and not final_response):
		_unconfirmed_command = envelope.duplicate(true)
		return ApiClient.Response.new(false, r.status, r.json, r.error)
	_unconfirmed_command.clear()
	return r

static func _command_succeeded(response: ApiClient.Response) -> bool:
	return response.is_success() and str(response.json.get("replayed_outcome", "")) != "rejected"

func _post_command(key: String, base: int, type: String, payload: Dictionary) -> ApiClient.Response:
	return await client.request("POST", "/farms/me/commands", {
		"idempotency_key": key, "base_version": base, "type": type, "payload": payload,
	})

## 记录传输层成败并维护离线态。返回 false 表示这次连响应都没拿到。
func _track(r: ApiClient.Response) -> bool:
	if r.ok:
		_failures = 0
		if offline:
			offline = false
			emit_signal("offline_changed", false)
		return true
	_failures += 1
	last_error_code = "TRANSPORT"
	if not offline and _failures >= OFFLINE_AFTER_FAILURES:
		offline = true
		emit_signal("offline_changed", true)
	return false

## 用回包整体覆盖本地状态。**不做 diff 合并**：漂移一律以服务端为准（方案 §3 D4）。
func _adopt(body: Dictionary) -> void:
	# 版本只增不减：比手上还旧的回包（并发 GET、迟到的重试）一律丢弃，否则状态倒退。
	if body.has("version") and int(body.version) < version:
		return
	if body.has("server_time"):
		_server_time_ms = int(body.server_time)
		_server_sample_ticks_ms = Time.get_ticks_msec()
		clock_offset_ms = _server_time_ms - int(Time.get_unix_time_from_system() * 1000.0)
	if body.has("farm_id"):
		farm_id = str(body.farm_id)
		location = body.get("location", {}).duplicate() if FarmPlacement.is_valid(body.get("location")) else {}
	if body.has("layout_patch_id"):
		layout_patch_id = str(body.layout_patch_id)
	if body.has("blueprint_revision"):
		blueprint_revision = int(body.blueprint_revision)
	if body.has("region_id"):
		region_id = str(body.region_id)
	if body.has("version"):
		version = int(body.version)
	if body.has("state"):
		state = body.state
		derived = body.derived if body.get("derived") is Dictionary else {}
		emit_signal("state_changed", state, version)

func _new_key() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()
