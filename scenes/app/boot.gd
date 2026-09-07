extends Control
## 启动决策：磁盘上有会话 → 壳；没有 → 登录页。带 --qa-scene 时不干预，AppRouter 会自己跳。
## 单独一页而不是让 AppRouter._ready 决定：autoload 里做导航会和 QA 参数跳转抢时序。

static func decide(signed_in: bool) -> String:
	return AppRoutes.SHELL if signed_in else AppRoutes.LOGIN

func _ready() -> void:
	if not AppRouter.qa_scene_path(OS.get_cmdline_user_args()).is_empty():
		return
	call_deferred("_go")

func _go() -> void:
	var signed_in: bool = Net.auth != null and Net.auth.is_signed_in()
	if decide(signed_in) == AppRoutes.SHELL:
		AppRouter.go_to_shell()
	else:
		AppRouter.go_to_login()
