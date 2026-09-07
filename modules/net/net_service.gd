extends Node
## 全局网络服务（autoload `Net`）：一个 ApiClient + 登录会话 AuthSession + WebSocket 客户端，
## 外加农场分支遗留的 FarmSession（本分支不承接农场，但 --qa-scene=city/farm 仍可跑）。
##
## 为什么是 Node 而不是 RefCounted：真实 HTTPRequest 需要挂在场景树里，autoload 正好是
## 一直在树里的节点。
##
## **测试与工具进程绝不自动联网**：headless 或带 gdUnit 参数时跳过 boot()，也不读磁盘上的
## 会话文件——否则开发机上一次「Dev 登录」留下的会话会漏进几百条单测里。

signal booted(logged_in: bool)

const DEFAULT_BASE := "https://farm.sensenjoy.cn/v1"
## 放一行 URL 就能把客户端指到别的服务器（局域网调试用），不用改代码重打包。
const SERVER_OVERRIDE := "user://server.txt"

var client: ApiClient
var auth: AuthSession
var firebase: FirebaseAuth
var account: AccountApi
var profile: ProfileApi
var feed: FeedApi
var ws: WsClient
var session: FarmSession
var booting := false
var booted_once := false

func _ready() -> void:
	auth = AuthSession.new()
	if not is_test_process():
		auth.restore()
	firebase = FirebaseAuth.new(FirebaseConfig.api_key(), ApiClient.make_http_transport(self))
	auth.refresher = firebase.refresh
	client = ApiClient.new(base_url(), ApiClient.make_http_transport(self))
	bind_auth(client)
	session = FarmSession.new(client)
	account = AccountApi.new(client)
	profile = ProfileApi.new(client)
	feed = FeedApi.new(client)
	ws = WsClient.new()
	ws.name = "Ws"
	ws.token_provider = auth.access_token
	add_child(ws)
	if not is_test_process() and farm_boot_requested(OS.get_cmdline_user_args()):
		call_deferred("boot")

## 让 client 每次请求现取会话 token；401 时给会话一次刷新机会。
func bind_auth(c: ApiClient) -> void:
	c.token_provider = auth.access_token
	c.on_unauthorized = auth.refresh

static func is_test_process() -> bool:
	if OS.is_debug_build() and OS.has_feature("g3_device_qa"):
		return true
	if DisplayServer.get_name() == "headless":
		return true
	for a in OS.get_cmdline_args():
		if str(a).to_lower().contains("gdunit"):
			return true
	return false

## 农场匿名登录只服务农场场景：社交主线的启动由 boot.tscn 按 AuthSession 决定去向。
static func farm_boot_requested(args: PackedStringArray) -> bool:
	for arg in args:
		if not arg.begins_with("--qa-scene="):
			continue
		return arg.trim_prefix("--qa-scene=").to_lower() in ["city", "farm", "map", "week"]
	return false

static func base_url() -> String:
	if FileAccess.file_exists(SERVER_OVERRIDE):
		var s := FileAccess.get_file_as_string(SERVER_OVERRIDE).strip_edges()
		if s.begins_with("http"):
			return s.trim_suffix("/")
	return DEFAULT_BASE

## 测试注入假传输；同时重建会话，丢掉上一次的 token 与状态。
func use_transport(t: Callable, p_base := "https://example.test/v1") -> void:
	client = ApiClient.new(p_base, t)
	bind_auth(client)
	session = FarmSession.new(client)
	account = AccountApi.new(client)
	profile = ProfileApi.new(client)
	feed = FeedApi.new(client)
	booted_once = false

## 农场分支：登录 + 取回已有农场（404 是正常的：新玩家还没建场）。返回是否登录成功。
func boot() -> bool:
	if booting:
		return false
	booting = true
	var ok := await session.login()
	if ok:
		# 已有农场就带回来；没有（404）也算 boot 成功，建场交给选地流程。
		await session.refresh()
	booting = false
	booted_once = true
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
