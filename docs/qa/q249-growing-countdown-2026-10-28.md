# q(249) 主键与 Today 成熟倒计时一致

SGODOT-354 后续，版本 0.2.14。基座 farm-dev `7c3d9ef0`（含 q(249) 批准原文 `cdd30210`）；用户于 2026-10-28 16:18 批准。开工已读取 SGODOT-197，LOCK-02 的行动、体力价和琥珀态保持；按方案本条不改变这些锁定属性。

## 实现

主行动键 `Growing` 副行和 Today 共用一个成熟时间格式函数。所有作物（含普通作物、快熟系列、快熟萝卜及果树）剩余 ≤300000ms 写 m:ss，沿现有客户端时间投影每秒更新；超过五分钟仍按分钟向上取整，双单位仍省略 Ready in，保留 80px 键面约束。快熟萝卜的 45 秒写法保持；田格倒计时、种子静态时长及服务端均无变更。

HOME-1 页脚已在 #536 实现，本次核对现有回归：目标 Lv2–4 只写 Upgrading is free of Energy；目标 Lv5 起保留 fills Energy to the new max。不重复修改。

## 验证与实拍

回归覆盖八种作物标识的五分钟及小数秒边界、20m / 2h / 19h 58m，Growing 不可执行；普通/快熟/教学/果树随客户端投影逐秒倒计时，成熟切换 Harvest 或 Pick。原快熟萝卜、果园、HOME-1 页脚与主键长度格式测试继续运行。

实拍使用独立 userdir `gensen-liubang-q249`、仅监听 127.0.0.1:3195 的当前基座服务和隔离测试号。通过真实 reducer 播种、客户端 Water 命令回包；相机/站位使用既有 plotface QA 定位。普通生菜经本地 dev/skip 准备到剩约 5:03，再按真实墙钟捕获边界，不加速录像。截图与视频来自真实游戏渲染，不改显示文本。

本地材料 `output/liubang-q249/`。最新基座补拍改前 Cress 主键 Ready in 1m / Today 0:10；此前 #536 的同类改前图仍在 354 评论 81b8b459。桌面 Metal 实拍不代表 Android/真机或整条新手流程验收。

- 定向五组 **52/52**、report_889、exit 0。
- 完整 **tests/p0 + tests/ui_kit 1928/1928**、189组、0 errors/failures/flaky/skipped/orphans，report_890、exit 0。用原生游戏模式跑 gdUnit，未用 editor/import。首次 headless 命令被 gdUnit 的模式检查拒绝（未执行用例），随后按游戏模式执行以上两轮。
- 实拍检查读取已显示的 Today 行及主键：Cress 0:10 至 0:01 每秒都有同值帧，并最终切到 Harvest；普通生菜 6m、5:00、4:59、4:58 均有主键/Today同值帧。Today 已有的250ms面板刷新节流保持，跨秒瞬间可短暂落后主键；本次统一格式规则，并未承诺两控件逐帧锁步。对照图取稳定同值帧；视频保持真实墙钟节奏。
- 正常实拍退出仍有既有5个 ObjectDB warning，不宣称修复。首次改前启动漏设 SENSEN_P0，仅进入本地隔离的旧入口、超时退出，补环境选项后重新捕获成功；该失败画面不上传。

最终两段视频为 Cress **12.16s**、普通生菜 **10.64s**，按逐帧墙钟差编码并解码核图。改前/改后、五分钟边界原图、对照图、视频抽帧、两段视频、JSON证据及测试摘要传354。所有本人捕获/测试进程及3195服务已停，按记录PID用ps确认无残留；无ADB、装机、生产部署或存档迁移。


## headless 颜色断言补充（奕星转哪吒）

已在 PR 留“还有增量，先别合”。在修改前使用 `--headless --ignoreHeadlessMode` 运行 test_p1_fast_crops，复现三条颜色断言失败（report_891、exit100）：headless 的空渲染服务器让 MultiMesh.get_instance_color() 全部返回0；这是渲染后端读回限制，不是植株变成了黑色。

按方案2，CropField 的 ColorBatch（继承 MultiMeshInstance3D）在 PackedColorArray 中保留本批次实际提交的实例颜色。田格、细节层及收获副本共用 resize_instances / set_instance_color 路径，设置渲染实例色时直接使用记录值；记录随实例数缩小或清空。颜色公式、网格、材质及实例数不变，每个实例仅多保留一份RGBA值。

原用例改读该记录，保留同网格作物颜色不同的断言；收获副本从原先只查R/B、允许GPU量化误差，改为检查精确RGBA，并确认田格层清空后副本仍保留自己的颜色。没有 headless 特判或提前 return，没有跳过颜色覆盖。全仓库测试已无 get_instance_color 读回依赖。

headless 定向 **15/15，0 errors/failures/skipped/orphans、exit0，report_892**（包含q249新增的两条测试）。带窗口验证继续使用 addons/gdUnit4/runtest.sh，避免调用会先运行 --import 的 tools/run_tests.sh。q249画面沿用本卡 b7676e46 的12份材料，本次补测试证据。

增量最终带窗口全量 **1942/1942，190组，0 errors/failures/flaky/skipped/orphans、exit0，report_893**：p0 + ui_kit 1928，加共享 CropField 14。原测试在带窗口与headless均通过，无新增跳过。进程正常退出，未启动本地服务/ADB或editor/import；增量测试报告传354。
