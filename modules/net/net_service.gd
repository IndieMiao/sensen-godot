extends Node
## 全局网络服务（autoload `Net`）：一个 ApiClient + 一个 FarmSession，App 启动时登录。
##
## 为什么是 Node 而不是 RefCounted：真实 HTTPRequest 需要挂在场景树里，autoload 正好是
## 一直在树里的节点。
##
## **测试与工具进程绝不自动联网**：headless 或带 gdUnit 参数时跳过 boot()。否则 396 条单测
## 每次启动都会去打线上服务器——慢、抖，还会在生产库里留下一堆匿名账号。

signal booted(logged_in: bool)
## 账号登录 / 登出后发出（SGODOT-135）。signed_in=false 表示回到游客只读身份。
signal account_changed(signed_in: bool)

const DEFAULT_BASE := "https://farm.sensenjoy.cn/v1"
const MOBILE_BASE := "https://farm.sensenjoy.cn/preview/journey/v1"
## 放一行 URL 就能把客户端指到别的服务器（局域网调试用），不用改代码重打包。
const SERVER_OVERRIDE := "user://server.txt"
## 动态农场正式包（C-98）才打开；它只连包里写死的正式地址，忽略 SERVER_OVERRIDE（C-116）。
const INVITE_ONLY_SETTING := "sensen/account/invite_only"

var client: ApiClient
var session: FarmSession
var account := AccountSession.new()
## 测试注入的账号文件路径；真机用 AccountSession.PATH。
var account_path := AccountSession.PATH
var booting := false
var booted_once := false
var online_available := false
## 上次恢复账号时没能向服务器核实、按原样保留了本机账号的原因（C-110）："TRANSPORT"、"RATE_LIMITED"、
## "HTTP_503" 这类；核实通过、没有已存账号或账号被清掉时为空。
var restore_error := ""

func _ready() -> void:
	client = ApiClient.new(base_url(), ApiClient.make_http_transport(self))
	session = FarmSession.new(client)
	# The P0 demo build (feature p0, SGODOT-232 D2) is a separate game on the P0 server: never sign in to Journey.
	if not is_test_process() and not OS.has_feature("p0"):
		call_deferred("boot")

static func is_test_process() -> bool:
	if bool(ProjectSettings.get_setting("sensen/network/online_qa", false)): return true
	# Desktop previews and screenshot tools render real UI without touching any server.
	if OS.get_environment("SENSEN_OFFLINE") == "1": return true
	if OS.is_debug_build() and (OS.has_feature("g3_device_qa") or OS.has_feature("journey_device_qa")):
		return true
	if DisplayServer.get_name() == "headless":
		return true
	for a in OS.get_cmdline_args():
		if str(a).to_lower().contains("gdunit"):
			return true
	return false

static func base_url() -> String:
	var invite_only := bool(ProjectSettings.get_setting(INVITE_ONLY_SETTING, false))
	if not invite_only and FileAccess.file_exists(SERVER_OVERRIDE):
		var s := FileAccess.get_file_as_string(SERVER_OVERRIDE).strip_edges()
		if s.begins_with("http"):
			return s.trim_suffix("/")
	# 手机包连 Journey 公开服务（domain 27）；根路径 /v1 是早期旧服，不支持当前农场生成。
	if OS.has_feature("mobile"):
		return str(ProjectSettings.get_setting("sensen/network/mobile_base_url", MOBILE_BASE)).trim_suffix("/")
	return str(ProjectSettings.get_setting("sensen/network/base_url", DEFAULT_BASE)).trim_suffix("/")

## 测试注入假传输；同时重建会话，丢掉上一次的 token 与状态。
func use_transport(t: Callable, p_base := "https://example.test/v1", p_account_path := "user://test_account.json") -> void:
	online_available = false
	client = ApiClient.new(p_base, t)
	session = FarmSession.new(client)
	account = AccountSession.new()
	account_path = p_account_path
	booted_once = false
	restore_error = ""

## 登录 + 取回已有农场（404 是正常的：新玩家还没建场）。返回是否登录成功。
func boot() -> bool:
	if booting:
		return false
	booting = true
	var ok := false
	ApiClient.debug_log("boot base=%s" % client.base_url)
	if account.load_saved(account_path):
		ok = await _resume_account()
	if not ok:
		ok = await session.login()
	if ok:
		# 已有农场就带回来；没有（404）也算 boot 成功，建场交给选地流程。
		await session.refresh()
		if session.has_farm(): await ensure_city(session.region_id)
		await _probe_online()
	booting = false
	booted_once = true
	if OS.is_debug_build():
		print("Farm connection: logged_in=", ok, " has_farm=", session.has_farm(), " result=", session.last_error_code)
	emit_signal("booted", ok)
	return ok

func logged_in() -> bool:
	return session != null and session.logged_in()

## 游客：只能浏览，建农场或任何写操作前要登录（决定 2）。
func is_guest() -> bool:
	return not account.signed_in()

## 启动时恢复已保存的账号会话。只有服务器明确回 401（token 失效）才清掉回游客；断网、限流、服务器
## 出错都保留本机账号先按账号进入，原因记在 restore_error 供界面提示（C-110）。
func _resume_account() -> bool:
	await session.adopt_account(account.token, account.player_id, account.user_id)
	var me := await AccountSession.me(client)
	if me.ok:
		restore_error = ""
		account.adopt(me.body, account_path)
		return true
	if int(me.status) != 401:
		restore_error = str(me.code) if not str(me.code).is_empty() else "HTTP_%d" % int(me.status)
		return true
	restore_error = ""
	account.clear(account_path)
	await session.forget_identity()
	return false

## 只读回本机已保存的账号 token（C-32）：给跳过 boot() 的隔离测试包用，不做匿名登录、不取农场、
## 不探测联机。调用方自己判断是否允许（动态农场内部测试包的 `sensen/dynamic_farm/account_restore`）。
func restore_saved_account() -> bool:
	if account.signed_in() and not client.token.is_empty():
		if restore_error.is_empty(): return true
		return await _resume_account() # The last check could not reach the server: ask again.
	restore_error = ""
	if not account.load_saved(account_path): return false
	return await _resume_account()

## 动态农场地图进场（C-32 / C-100）：restore 时先读回本机保存的账号 token；没有可用账号、且包带
## `sensen/dynamic_farm/guest_play`（装上即建号）时，用本机安装密钥匿名登录（已登录过就沿用）。
## 返回是否有可用的身份。游客能不能认领和存档由服务端决定（PARCEL_GUEST_WRITES）。
func dynamic_farm_sign_in(restore: bool, guest_play: bool) -> bool:
	if restore and await restore_saved_account(): return true
	if not guest_play: return false
	if not client.token.is_empty(): return true
	return await session.login()

## 联机只对账号开放：游客探测得到 401，online_available 保持 false。
func _probe_online() -> void:
	var capabilities := await client.request("GET", "/online/status")
	online_available = capabilities.is_success() and int(capabilities.json.get("protocol", 0)) == 1

## 城市数据不在本地（全球城市）就向服务端取一次并缓存（SGODOT-136）。返回 region 字典。
func ensure_city(city_id: String) -> Dictionary:
	if city_id.is_empty(): return {}
	var regions := FarmRegions.load_default()
	var known: Dictionary = regions.region(city_id) if regions else {}
	if not known.is_empty(): return known
	var r: ApiClient.Response = await client.request("GET", "/cities/%s" % city_id.uri_encode())
	if not r.is_success() or not r.json.get("city") is Dictionary: return {}
	return FarmRegions.remember_city(r.json.city)

## 注册 / 登录 / 重置成功后调用：换成账号身份并取回该账号的农场。
func sign_in_with(body: Dictionary) -> bool:
	if str(body.get("token", "")).is_empty() or str(body.get("user_id", "")).is_empty(): return false
	account.adopt(body, account_path)
	restore_error = ""
	await session.adopt_account(account.token, account.player_id, account.user_id)
	await session.refresh()
	if session.has_farm(): await ensure_city(session.region_id)
	await _probe_online()
	account_changed.emit(true)
	return true

## 登出：撤销本设备 token，回到游客身份。guest_login=false 时不做匿名登录（动态农场包不用游客身份）。
func sign_out(guest_login := true) -> void:
	if account.signed_in():
		await client.request("DELETE", "/auth/token")
	account.clear(account_path)
	restore_error = ""
	await session.forget_identity()
	if guest_login: await session.login()
	online_available = false
	account_changed.emit(false)

## 删号成功后与登出同样回到游客；返回服务端结果供界面提示。
func delete_account(password: String) -> Dictionary:
	var result := await AccountSession.delete_account(client, password)
	if result.ok:
		account.clear(account_path)
		await session.forget_identity()
		await session.login()
		online_available = false
		account_changed.emit(false)
	return result

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
