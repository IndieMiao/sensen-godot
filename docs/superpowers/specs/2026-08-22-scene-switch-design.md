# App 内场景切换（换装房间 ↔ 压测场景）

日期：2026-08-22 · 已获用户批准（方案 A）

两个场景各加一个常驻按钮互相跳转（`get_tree().change_scene_to_file`），主场景固定为换装房间；导出不再需要临时改 main_scene（docs/mobile_export.md 同步删除该步骤）。`Avatar` autoload 跨场景存活：存档/缓存在切换后有效（期望行为）；旧场景节点由 change_scene 释放。场景路径为常量，失败分支仅 push_error。验证口径：全量测试无回归 + 两场景 headless 冒烟 + 真机双向切换走查；不为一行胶水加单测。改动：dressing_room.tscn/.gd、stress_test.tscn/.gd、docs/mobile_export.md，约 25 行。

否决方案：独立启动菜单场景（多一个场景文件，零收益，YAGNI）。
