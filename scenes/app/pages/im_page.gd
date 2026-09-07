extends AppPage
## 消息占位：B2 会话列表 / 单聊 / 群聊。这里先把 WsClient 状态显示出来，证明长连接封装已接到壳里。

var realtime: Label

func _init() -> void:
	page_title = "Chats"

func _build_body() -> void:
	placeholder(tr("Chats land in B2: conversations, 1:1 and group chat, images, read receipts."))
	realtime = GameUi.label("", 12, GameUi.MUTED)
	realtime.name = "Realtime"
	body.add_child(realtime)
	if Net.ws != null:
		Net.ws.state_changed.connect(_on_ws_state)
		_on_ws_state(Net.ws.state)

func _on_ws_state(state: int) -> void:
	var names := {
		WsClient.State.IDLE: tr("idle"), WsClient.State.CONNECTING: tr("connecting"), WsClient.State.OPEN: tr("connected"),
		WsClient.State.RECONNECT_WAIT: tr("reconnecting"), WsClient.State.PAUSED: tr("paused"),
	}
	realtime.text = tr("Realtime: %s") % str(names.get(state, state))
