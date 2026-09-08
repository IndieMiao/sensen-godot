class_name PushService
extends RefCounted
## C2 + D7 的接线：原生桥拿 token → 报给服务端；登出 / 关通知时注销。
##
## 时机：**登录成功之后**才问通知权限（冷启动就弹是最容易被拒的做法，拒了这辈子都要用户
## 自己去设置里开回来）。token 是异步来的，可能一直不来，所以这里不 await，靠信号推进。
##
## 幂等：同一个 token 只报一次；换账号登录时先把旧 token 从旧账号名下注销，再报到新账号
##（服务端 upsert 也会改归属，两头都做是为了断网时状态不会烂在中间）。
## 落盘：最后一次报上去的 token 存 UiState——重启后登出时还知道该注销哪个。

const STATE_KEY := "push_token"

signal registered(token: String)
## 用户点开了一条通知；payload 只有路由用的 id（正文不进推送）。转给上层做跳转。
signal opened(payload: Dictionary)

var bridge: PushBridge
var api: PushApi
## 注入点：报错用（可空）。
var on_error: Callable

var last_token := ""
var busy := false

func _init(p_bridge: PushBridge = null, p_api: PushApi = null) -> void:
	bridge = p_bridge
	api = p_api
	if bridge != null:
		bridge.authorization.connect(_on_authorization)
		bridge.token_ready.connect(_on_token)
		bridge.token_failed.connect(_on_token_failed)
		bridge.notification_opened.connect(func(p: Dictionary): opened.emit(p))

func usable() -> bool:
	return bridge != null and api != null and bridge.available()

## 登录成功后调用：问权限（已经问过就直接拿上次结果）。
func start() -> void:
	if not usable():
		return
	bridge.request_authorization()

## 用户在设置里关掉通知，或者登出：把当前 token 从服务端撤掉。
## 断网时撤不掉也照样忘记它——登出后没有 token 可以再调这个接口了，留着也没用。
## 残留的后果有限：通知本来就不带正文，且下次有人在这台机器登录时服务端 upsert 会改归属。
func stop() -> void:
	var token := _saved_token()
	if token.is_empty() or api == null:
		_forget()
		return
	await api.unregister(token)
	_forget()

func _on_authorization(granted: bool) -> void:
	if granted:
		bridge.register_for_remote()
	elif on_error.is_valid():
		on_error.call("PUSH_DENIED")

func _on_token_failed(reason: String) -> void:
	if on_error.is_valid():
		on_error.call(reason)

func _on_token(token: String) -> void:
	await report(token)

## 把 token 报给服务端。返回是否报成功（重复的 token 直接算成功，不打服务端）。
func report(token: String) -> bool:
	if api == null or token.strip_edges().is_empty() or busy:
		return false
	if token == _saved_token():
		last_token = token
		return true
	busy = true
	var r: Dictionary = await api.register(token, bridge.platform() if bridge != null else "")
	busy = false
	if not bool(r.get("ok", false)):
		if on_error.is_valid():
			on_error.call(str(r.get("code", "UNKNOWN")))
		return false
	last_token = token
	UiState.write({STATE_KEY: token})
	registered.emit(token)
	return true

func _saved_token() -> String:
	return str(UiState.read().get(STATE_KEY, ""))

func _forget() -> void:
	last_token = ""
	UiState.write({STATE_KEY: ""})
