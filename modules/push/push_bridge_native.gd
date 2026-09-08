class_name PushBridgeNative
extends PushBridge
## 原生推送插件的薄包装（C2）。插件侧方法：is_available / request_authorization /
## register_for_remote / token / platform；信号：authorization(granted) /
## token_ready(token) / token_failed(reason) / notification(payload, opened)。
## 插件未装时不会被构造（见 PushBridgeFactory）。

var _plugin: Object

func _init() -> void:
	if not Engine.has_singleton(PushBridgeFactory.SINGLETON):
		return
	_plugin = Engine.get_singleton(PushBridgeFactory.SINGLETON)
	# CONNECT_DEFERRED：回调来自系统线程 / app delegate，不能在那儿直接动场景树。
	for pair in [["authorization", "_on_authorization"], ["token_ready", "_on_token"],
			["token_failed", "_on_token_failed"], ["notification", "_on_notification"]]:
		if _plugin.has_signal(pair[0]):
			_plugin.connect(pair[0], Callable(self, pair[1]), CONNECT_DEFERRED)

func available() -> bool:
	return _plugin != null and bool(_plugin.call("is_available"))

func request_authorization() -> void:
	if _plugin != null:
		_plugin.call("request_authorization")

func register_for_remote() -> void:
	if _plugin != null:
		_plugin.call("register_for_remote")

func token() -> String:
	return str(_plugin.call("token")) if _plugin != null else ""

func platform() -> String:
	if _plugin == null:
		return ""
	var p := str(_plugin.call("platform"))
	return p if not p.is_empty() else PushApi.default_platform()

func _on_authorization(granted: bool) -> void:
	authorization.emit(granted)

func _on_token(t: String) -> void:
	token_ready.emit(t)

func _on_token_failed(reason: String) -> void:
	token_failed.emit(reason)

## opened=false 是前台横幅（系统已经显示过了），这里只关心用户真点开的那次。
func _on_notification(payload: Dictionary, opened: bool) -> void:
	if opened:
		notification_opened.emit(payload)
