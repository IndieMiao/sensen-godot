extends Node
## AppRouter 场景栈测试探针：记录 setup 参数与 suspend/resume 次数。
var args := {}
var suspended := 0
var resumed := 0

func setup(p_args: Dictionary) -> void:
	args = p_args

func suspend() -> void:
	suspended += 1

func resume() -> void:
	resumed += 1
