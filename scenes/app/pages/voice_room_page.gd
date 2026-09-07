extends AppPage
## 语音房占位（压栈子页）：B6 UI + C4 LiveKit 桥 + D5 token/信令；进 Demo 与否看 SSLAUNCH F2。

func _init() -> void:
	page_title = "Voice room"
	stacked = true

func _build_body() -> void:
	placeholder(tr("Voice room lands in B6 (UI), C4 (LiveKit bridge) and D5 (token/signaling)."))
