extends Control
## 启动决策：年龄门 → 条款同意 → （有会话）壳 / （无会话）登录页。带 --qa-scene 时不干预。
## 单独一页而不是让 AppRouter._ready 决定：autoload 里做导航会和 QA 参数跳转抢时序。

static func decide(signed_in: bool, first_run: FirstRun = null) -> String:
	var fr := first_run if first_run != null else FirstRun.load_state()
	return fr.next_route(signed_in)

func _ready() -> void:
	if not AppRouter.qa_scene_path(OS.get_cmdline_user_args()).is_empty():
		return
	call_deferred("_go")

func _go() -> void:
	var signed_in: bool = Net.auth != null and Net.auth.is_signed_in()
	AppRouter.go_to_route(decide(signed_in))
