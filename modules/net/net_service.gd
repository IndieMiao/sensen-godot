extends Node
## 全局网络服务（autoload `Net`）：一个 ApiClient + 一个 FarmSession，App 启动时登录。
##
## 为什么是 Node 而不是 RefCounted：真实 HTTPRequest 需要挂在场景树里，autoload 正好是
## 一直在树里的节点。
##
## **测试与工具进程绝不自动联网**：headless 或带 gdUnit 参数时跳过 boot()。否则 396 条单测
## 每次启动都会去打线上服务器——慢、抖，还会在生产库里留下一堆匿名账号。

signal booted(logged_in: bool)

const DEFAULT_BASE := "https://farm.sensenjoy.cn/v1"
const MOBILE_BASE := "https://farm.sensenjoy.cn/preview/journey/v1"
## 放一行 URL 就能把客户端指到别的服务器（局域网调试用），不用改代码重打包。
const SERVER_OVERRIDE := "user://server.txt"

var client: ApiClient
var session: FarmSession
var booting := false
var booted_once := false
var online_available := false

func _ready() -> void:
	client = ApiClient.new(base_url(), ApiClient.make_http_transport(self))
	session = FarmSession.new(client)
	if not is_test_process():
		call_deferred("boot")

static func is_test_process() -> bool:
	if bool(ProjectSettings.get_setting("sensen/network/online_qa", false)): return true
	if OS.is_debug_build() and (OS.has_feature("g3_device_qa") or OS.has_feature("journey_device_qa")):
		return true
	if DisplayServer.get_name() == "headless":
		return true
	for a in OS.get_cmdline_args():
		if str(a).to_lower().contains("gdunit"):
			return true
	return false

static func base_url() -> String:
	if FileAccess.file_exists(SERVER_OVERRIDE):
		var s := FileAccess.get_file_as_string(SERVER_OVERRIDE).strip_edges()
		if s.begins_with("http"):
			return s.trim_suffix("/")
	# 手机包连 Journey 公开服务（domain 27）；根路径 /v1 是早期旧服，不支持当前农场生成。
	if OS.has_feature("mobile"):
		return str(ProjectSettings.get_setting("sensen/network/mobile_base_url", MOBILE_BASE)).trim_suffix("/")
	return str(ProjectSettings.get_setting("sensen/network/base_url", DEFAULT_BASE)).trim_suffix("/")

## 测试注入假传输；同时重建会话，丢掉上一次的 token 与状态。
func use_transport(t: Callable, p_base := "https://example.test/v1") -> void:
	online_available = false
	client = ApiClient.new(p_base, t)
	session = FarmSession.new(client)
	booted_once = false

## 登录 + 取回已有农场（404 是正常的：新玩家还没建场）。返回是否登录成功。
func boot() -> bool:
	if booting:
		return false
	booting = true
	var ok := await session.login()
	if ok:
		# 已有农场就带回来；没有（404）也算 boot 成功，建场交给选地流程。
		await session.refresh()
		var capabilities := await client.request("GET", "/online/status")
		online_available = capabilities.is_success() and int(capabilities.json.get("protocol", 0)) == 1
	booting = false
	booted_once = true
	if OS.is_debug_build():
		print("Farm connection: logged_in=", ok, " has_farm=", session.has_farm(), " result=", session.last_error_code)
	emit_signal("booted", ok)
	return ok

func logged_in() -> bool:
	return session != null and session.logged_in()

## 同城可访问的农场列表。返回 {ok, count, entries, error}。
func nearby(region_id: String) -> Dictionary:
	var r: ApiClient.Response = await client.request("GET", "/nearby?region_id=%s" % region_id.uri_encode())
	if not r.is_success():
		return {"ok": false, "count": 0, "entries": [], "error": r.error if not r.ok else str(r.json.get("code", r.status))}
	return {"ok": true, "count": int(r.json.get("count", 0)), "entries": r.json.get("entries", []), "error": ""}

## 某座农场的访客快照。返回 {ok, snapshot, status, error}。
func snapshot(farm_id: String) -> Dictionary:
	var r: ApiClient.Response = await client.request("GET", "/farms/%s/snapshot" % farm_id.uri_encode())
	if not r.is_success():
		return {"ok": false, "snapshot": {}, "status": r.status, "error": r.error if not r.ok else str(r.json.get("code", r.status))}
	return {"ok": true, "snapshot": r.json, "status": r.status, "error": ""}
