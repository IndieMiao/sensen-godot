class_name AuthSession
extends RefCounted
## 登录会话状态机 + 持久化。只管「有没有会话、token 是否该刷新」，不管登录方式本身——
## 邮箱验证码 / Sign in with Apple / Google 的具体调用在 B1 登录页与 C1 插件里，它们拿到
## id_token 后调 complete_sign_in()；刷新逻辑通过 refresher 注入（B1 接 Firebase securetoken）。
##
## 状态：SIGNED_OUT → SIGNING_IN → SIGNED_IN ⇄ REFRESHING → SIGNED_OUT。
## 时钟可注入：token 过期判定不能依赖测试机的真实时间。

signal changed(state: int)

enum State { SIGNED_OUT, SIGNING_IN, SIGNED_IN, REFRESHING }

const PATH := "user://auth_session.json"
## 提前多少毫秒算「该刷新了」：请求在路上时 token 过期照样 401，留一分钟余量。
const REFRESH_SKEW_MS := 60_000

var state := State.SIGNED_OUT
var user_id := ""
## D2 账号服务给的自有 user id；登录后 AccountApi.sign_in() 回填，服务端不可达时为空。
var server_user_id := ""
var email := ""
var id_token := ""
var refresh_token := ""
var expires_at_ms := 0
## "password" / "apple.com" / "google.com" / "dev"
var provider := ""
var last_error := ""

## () -> int（毫秒）。默认系统时间。
var now_provider: Callable
## (refresh_token: String) -> Dictionary {ok:bool, id_token, refresh_token, expires_in_s:int, fatal:bool, error}
## 协程或同步都可以（调用处一律 await）。fatal=true 表示刷新令牌本身已失效，应当登出。
var refresher: Callable

func is_signed_in() -> bool:
	return (state == State.SIGNED_IN or state == State.REFRESHING) and not id_token.is_empty()

## ApiClient.token_provider 的目标：未登录时返回空串，让 client 退回它自己的 token 字段。
func access_token() -> String:
	return id_token if is_signed_in() else ""

func now_ms() -> int:
	if now_provider.is_valid():
		return int(now_provider.call())
	return int(Time.get_unix_time_from_system() * 1000.0)

func begin_sign_in() -> void:
	last_error = ""
	_set_state(State.SIGNING_IN)

func complete_sign_in(p_user_id: String, p_id_token: String, p_refresh_token: String, expires_in_s: int, p_provider: String, p_email := "") -> void:
	user_id = p_user_id
	server_user_id = ""
	email = p_email
	id_token = p_id_token
	refresh_token = p_refresh_token
	expires_at_ms = now_ms() + expires_in_s * 1000
	provider = p_provider
	last_error = ""
	persist()
	_set_state(State.SIGNED_IN)

## AccountApi.sign_in() 成功后回填并落盘。
func set_server_user(id: String) -> void:
	server_user_id = id
	persist()

func fail_sign_in(error: String) -> void:
	last_error = error
	_set_state(State.SIGNED_OUT)

func sign_out() -> void:
	user_id = ""
	server_user_id = ""
	email = ""
	id_token = ""
	refresh_token = ""
	expires_at_ms = 0
	provider = ""
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	_set_state(State.SIGNED_OUT)

func needs_refresh() -> bool:
	return is_signed_in() and now_ms() >= expires_at_ms - REFRESH_SKEW_MS

## 请求前调用：过期就刷新。返回当前是否持有可用会话。
func ensure_fresh() -> bool:
	if not is_signed_in():
		return false
	if not needs_refresh():
		return true
	return await refresh()

## 强制刷新一次（401 之后由 ApiClient.on_unauthorized 触发）。
func refresh() -> bool:
	if not is_signed_in() or not refresher.is_valid():
		return false
	if state == State.REFRESHING:
		return false # 已有刷新在路上，别并发再发一次
	_set_state(State.REFRESHING)
	var r = await refresher.call(refresh_token)
	var result: Dictionary = r if r is Dictionary else {}
	if bool(result.get("ok", false)):
		id_token = str(result.get("id_token", id_token))
		refresh_token = str(result.get("refresh_token", refresh_token))
		expires_at_ms = now_ms() + int(result.get("expires_in_s", 3600)) * 1000
		last_error = ""
		persist()
		_set_state(State.SIGNED_IN)
		return true
	last_error = str(result.get("error", "REFRESH_FAILED"))
	if bool(result.get("fatal", false)):
		sign_out()
		return false
	# 瞬时失败（断网）：保留旧会话，下次再试；调用方拿到 false 自己决定是否只读。
	_set_state(State.SIGNED_IN)
	return false

## 冷启动读回会话。文件坏了当作未登录，不抛错。
func restore() -> bool:
	if not FileAccess.file_exists(PATH):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (parsed is Dictionary):
		return false
	var d: Dictionary = parsed
	var tok := str(d.get("id_token", ""))
	if tok.is_empty():
		return false
	user_id = str(d.get("user_id", ""))
	server_user_id = str(d.get("server_user_id", ""))
	email = str(d.get("email", ""))
	id_token = tok
	refresh_token = str(d.get("refresh_token", ""))
	expires_at_ms = int(d.get("expires_at_ms", 0))
	provider = str(d.get("provider", ""))
	_set_state(State.SIGNED_IN)
	return true

func persist() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"user_id": user_id,
		"server_user_id": server_user_id,
		"email": email,
		"id_token": id_token,
		"refresh_token": refresh_token,
		"expires_at_ms": expires_at_ms,
		"provider": provider,
	}))

func _set_state(v: int) -> void:
	if v == state:
		return
	state = v
	changed.emit(v)
