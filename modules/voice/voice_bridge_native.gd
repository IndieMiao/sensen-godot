class_name VoiceBridgeNative
extends VoiceBridge
## 原生 LiveKit 插件的薄包装（C4）。插件侧只暴露十来个方法，音频链路全在原生层。
## 插件未装时不会被构造（见 VoiceBridgeFactory）。
##
## 信号名与参数由插件约定：connected() / disconnected(reason) / speaking(identity, speaking) / error(message)。
## iOS 侧的信号是 poll() 里对着状态快照差分出来的（Swift → C++ 不做回调），所以**每帧必须 poll**，
## 否则连上了 UI 也不知道。

var _plugin: Object

func _init() -> void:
	if not Engine.has_singleton(VoiceBridgeFactory.SINGLETON):
		return
	_plugin = Engine.get_singleton(VoiceBridgeFactory.SINGLETON)
	# CONNECT_DEFERRED：插件回调来自原生线程，不能在那儿直接动场景树。
	for pair in [["connected", "_on_connected"], ["disconnected", "_on_disconnected"],
			["speaking", "_on_speaking"], ["error", "_on_error"]]:
		if _plugin.has_signal(pair[0]):
			_plugin.connect(pair[0], Callable(self, pair[1]), CONNECT_DEFERRED)

## 单例存在不代表能说话：桌面的空实现与「没注入 LiveKit 的 iOS 包」都会回 false。
func available() -> bool:
	return _plugin != null and bool(_plugin.call("is_available"))

func connect_room(url: String, token: String) -> void:
	if _plugin == null:
		return
	state = State.CONNECTING
	_plugin.call("connect_room", url, token)

func disconnect_room() -> void:
	if _plugin == null:
		return
	state = State.IDLE
	_plugin.call("disconnect_room")

func set_mic(enabled: bool) -> void:
	if _plugin != null:
		_plugin.call("set_mic", enabled)

func set_volume(identity: String, volume: float) -> void:
	if _plugin != null:
		_plugin.call("set_volume", identity, clampf(volume, 0.0, 1.0))

## 每帧调用：原生层在这里把状态变化翻成信号。
func poll() -> void:
	if _plugin != null and _plugin.has_method("poll"):
		_plugin.call("poll")

func speakers() -> PackedStringArray:
	if _plugin == null:
		return PackedStringArray()
	var raw = _plugin.call("speakers")
	return PackedStringArray(raw) if raw is PackedStringArray or raw is Array else PackedStringArray()

func _on_connected() -> void:
	state = State.CONNECTED
	connected.emit()

func _on_disconnected(reason: String) -> void:
	state = State.IDLE
	disconnected.emit(reason)

func _on_speaking(identity: String, speaking: bool) -> void:
	speaking_changed.emit(identity, speaking)

func _on_error(message: String) -> void:
	error.emit(message)
