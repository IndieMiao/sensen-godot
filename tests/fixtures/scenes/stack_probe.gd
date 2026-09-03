extends Node
## AppRouter 场景栈测试探针：记录 setup 参数与 suspend/resume 次数。
## 2026-09-04 终审 C1 补：还带一个 Camera3D + WorldEnvironment，照抄
## farm.gd/dressing_room.gd/map_poc.gd 的协议（_ready() 抢相机；suspend() 交出
## 相机与环境所有权，resume() 收回），用来在 tests/ui/test_app_router_stack.gd
## 里断言"压栈场景真的接管了视口的当前相机"——探针原来是个裸 Node，这正是
## C1 那两个 Critical 缺陷在真机被摸出来之前，没有任何测试能发现它们的原因。

var args := {}
var suspended := 0
var resumed := 0
var back_locked := false

@onready var cam: Camera3D = $Camera3D
@onready var world_env: WorldEnvironment = $WorldEnvironment
var _saved_environment: Environment

func setup(p_args: Dictionary) -> void:
	args = p_args

func _ready() -> void:
	cam.make_current()

func is_back_navigation_locked() -> bool:
	return back_locked

func suspend() -> void:
	suspended += 1
	cam.current = false
	if world_env.environment:
		_saved_environment = world_env.environment
	world_env.environment = null

func resume() -> void:
	resumed += 1
	cam.make_current()
	world_env.environment = _saved_environment
