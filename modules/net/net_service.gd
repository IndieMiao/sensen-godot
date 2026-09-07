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
## 一条 IM inbox 事件（type / seq / …，见 server/README.md「IM」）；WS 实时推的和补拉回来的都从这里出。
signal im_event(event: Dictionary)

const DEFAULT_BASE := "https://farm.sensenjoy.cn/v1"
## 放一行 URL 就能把客户端指到别的服务器（局域网调试用），不用改代码重打包。
const SERVER_OVERRIDE := "user://server.txt"
## IM 增量同步游标（用户级 seq）落盘：重启后从上次位置补拉，不漏事件。
const IM_SYNC_PATH := "user://im_sync.json"

var client: ApiClient
var auth: AuthSession
var firebase: FirebaseAuth
var account: AccountApi
var profile: ProfileApi
var feed: FeedApi
var safety: SafetyApi
var im: ImApi
## 最后一条已交付给上层的 IM 事件 seq；-1 = 还没同步过。
var im_last_seq := -1
var im_syncing := false
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
	safety = SafetyApi.new(client)
	im = ImApi.new(client)
	if not is_test_process():
		im_last_seq = load_im_seq()
	ws = WsClient.new()
	ws.name = "Ws"
	ws.token_provider = auth.access_token
	ws.connected.connect(_on_ws_connected)
	ws.message_received.connect(_on_ws_message)
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
	# 环境变量优先（桌面 QA 实例指到局域网服务），其次 user://server.txt（真机），最后默认。
	var env := OS.get_environment("SENSEN_SERVER_BASE").strip_edges()
	if env.begins_with("http"):
		return env.trim_suffix("/")
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
	safety = SafetyApi.new(client)
	im = ImApi.new(client)
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

# —— D3 IM 在线通道与增量同步 ——

## REST 基址 → WS 地址：https://host/v1 → wss://host/v1/im/ws。
static func ws_url_for(base: String) -> String:
	var b := base.trim_suffix("/")
	if b.begins_with("https://"):
		b = "wss://" + b.trim_prefix("https://")
	elif b.begins_with("http://"):
		b = "ws://" + b.trim_prefix("http://")
	return b + "/im/ws"

## 登录后调用。Dev 会话没有真 token 不连；重复调用只是重开。
func connect_im() -> void:
	if auth == null or not auth.is_signed_in() or auth.provider == "dev":
		return
	# 用 client 当前的基址而不是 base_url()：测试注入的假传输带自己的基址。
	ws.open(ws_url_for(client.base_url))

func disconnect_im() -> void:
	ws.close()

## 每次连上（首连与重连都算）先按落盘的 last_seq 补拉：WsClient 自己的 resync_needed 只在重连时发，
## 而应用重启后的首连同样可能漏了事件，所以统一挂在 connected 上，不用 resync_needed。
func _on_ws_connected() -> void:
	await resync()

func _on_ws_message(msg: Dictionary) -> void:
	var t := str(msg.get("type", ""))
	if t.is_empty() or t == "hello" or t == "pong":
		return
	_deliver(msg)

## 从 im_last_seq 起拉到 latest_seq 为止。返回交付给上层的事件数；同一时刻只跑一份。
func resync() -> int:
	if im_syncing or im == null:
		return 0
	im_syncing = true
	var total := 0
	var cursor := maxi(im_last_seq, 0)
	while true:
		var r: Dictionary = await im.sync(cursor)
		if not bool(r.get("ok", false)):
			break
		var events: Array = r.get("events", []) if r.get("events") is Array else []
		for e in events:
			_deliver(e)
			cursor = maxi(cursor, int(e.get("seq", 0)))
			total += 1
		if events.is_empty() or cursor >= int(r.get("latest_seq", 0)):
			break
	im_syncing = false
	return total

## 交付给上层并推进游标；乱序 / 重复的旧事件丢掉（WS 推送与补拉可能重叠）。
func _deliver(e: Dictionary) -> void:
	var seq := int(e.get("seq", 0))
	if seq > 0:
		if seq <= im_last_seq:
			return
		im_last_seq = seq
		ws.last_seq = maxi(ws.last_seq, seq)
		if not is_test_process():
			save_im_seq()
	im_event.emit(e)

func save_im_seq() -> void:
	var f := FileAccess.open(IM_SYNC_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"last_seq": im_last_seq, "user_id": auth.user_id if auth != null else ""}))

## 换了账号就不能沿用上一个人的游标。
func load_im_seq() -> int:
	if not FileAccess.file_exists(IM_SYNC_PATH):
		return -1
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(IM_SYNC_PATH))
	if not (parsed is Dictionary):
		return -1
	if auth != null and str(parsed.get("user_id", "")) != auth.user_id:
		return -1
	return int(parsed.get("last_seq", -1))
