class_name VoiceBridgeNative
extends VoiceBridge
## 原生 LiveKit 插件的薄包装（C4）。插件侧只暴露十来个方法，音频链路全在原生层。
## 插件未装时不会被构造（见 VoiceBridgeFactory）。
##
## 信号名与参数由插件约定：connected() / disconnected(reason) / speaking(identity, speaking) / error(message)。

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

func available() -> bool:
	return _plugin != null

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
