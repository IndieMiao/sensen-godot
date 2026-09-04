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

var client: ApiClient
var player_id := ""
var farm_id := ""
var version := -1
var state: Dictionary = {}
var offline := false
## 服务端时间 − 本地时间（毫秒）。成熟判定必须用它换算：本地时钟不可信，
## 玩家改系统时间不应该让作物提前熟（PRD §9.1 L668）。
var clock_offset_ms := 0

var last_error_code := ""
var _failures := 0

func _init(p_client: ApiClient) -> void:
	client = p_client

func logged_in() -> bool:
	return client != null and not client.token.is_empty()

func has_farm() -> bool:
	return not farm_id.is_empty()

## 服务端「现在」的毫秒时间戳。
func server_now() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) + clock_offset_ms

func login() -> bool:
	var r: ApiClient.Response = await client.request("POST", "/auth/anonymous", {"install_key": ApiClient.install_key()})
	if not _track(r):
		return false
	if not r.is_success():
		return false
	player_id = str(r.json.get("player_id", ""))
	client.token = str(r.json.get("token", ""))
	return not client.token.is_empty()

## 已有农场就取回来，没有就建一个。
func ensure_farm(region_id: String, layout_patch_id: String, revision: int) -> bool:
	var me: ApiClient.Response = await client.request("GET", "/farms/me")
	if not _track(me):
		return false
	if me.is_success():
		_adopt(me.json)
		return true
	if me.status != 404:
		return false
	var r: ApiClient.Response = await client.request("POST", "/farms", {
		"idempotency_key": _new_key(),
		"region_id": region_id,
		"layout_patch_id": layout_patch_id,
		"blueprint_revision": revision,
	})
	if not _track(r):
		return false
	if not r.is_success():
		emit_signal("rejected", str(r.json.get("code", "UNKNOWN")), str(r.json.get("message", "")))
		return false
	_adopt(r.json)
	return true

func refresh() -> bool:
	var r: ApiClient.Response = await client.request("GET", "/farms/me")
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
func send(type: String, payload: Dictionary) -> bool:
	if offline:
		last_error_code = "OFFLINE"
		emit_signal("rejected", "OFFLINE", "离线中，命令未发送")
		return false
	var key := _new_key()
	var r: ApiClient.Response = await _post_command(key, version, type, payload)
	if not r.ok:
		# 传输层失败：同 key 原样重发，服务端幂等保证不会应用两次。
		r = await _post_command(key, version, type, payload)
	if not _track(r):
		return false
	if r.status == 409 and str(r.json.get("code", "")) == "VERSION_CONFLICT":
		# 回包带着最新状态，先对账再用**新 key** 重发（同 key 换 base_version 会被判
		# IDEMPOTENCY_MISMATCH）。
		_adopt(r.json)
		r = await _post_command(_new_key(), version, type, payload)
		if not _track(r):
			return false
	if r.is_success():
		last_error_code = ""
		_adopt(r.json)
		return true
	last_error_code = str(r.json.get("code", "UNKNOWN"))
	emit_signal("rejected", last_error_code, str(r.json.get("detail", "")))
	return false

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
	if not offline and _failures >= OFFLINE_AFTER_FAILURES:
		offline = true
		emit_signal("offline_changed", true)
	return false

## 用回包整体覆盖本地状态。**不做 diff 合并**：漂移一律以服务端为准（方案 §3 D4）。
func _adopt(body: Dictionary) -> void:
	if body.has("server_time"):
		clock_offset_ms = int(body.server_time) - int(Time.get_unix_time_from_system() * 1000.0)
	if body.has("farm_id"):
		farm_id = str(body.farm_id)
	if body.has("version"):
		version = int(body.version)
	if body.has("state"):
		state = body.state
		emit_signal("state_changed", state, version)

func _new_key() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()
