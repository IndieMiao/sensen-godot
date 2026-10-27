# SGODOT-341：教学田倒计时与 Ready

依据：不知火舞 341 `635c4082`、340 `fc814d17` S3/S5、定稿帧 GUIDE-S3 `90:163654`、q(97) / q(217)。奕星经大乔要求另开小 PR，基于 #516 定版 `c27deb33`，合并顺序 **#516 → #517 → 本 PR**。#516 分支和 PR 头不动，三个一起给用户看图后由奕星合入。

## 复用与范围

普通农场没有逐田生长徽标的绘制入口；现有主键/Today 已用 `P0Session.current()` → `P0Logic.project()` 按接收后的真实时间投影 `ready_in`，到期改成 ready，并由 session 触发已有的服务端刷新。本次只接显示，沿用这条时间链、`P0Logic.duration`、现有 `UiStatusBadge.COUNTDOWN`（时钟＋时间胶囊）及 `READY`（绿色勾），不新增计时器、图标或状态种类。

S4 `t_sow_rest` 的 marks 只有生菜快捷栏，不含 plot。因此生长事实不能依赖当前教学目标或记住上次水滴：引导期间读取服务端 `quick_seeds` 元数据识别快熟教学作物，再按每块实际 `plots` 的 growing / ready 状态显示。冷进入、走开重进可从当前视图重建；普通作物和普通号不新增标记，不按 step 名或本地步骤表推断。缺 `ready_in` 时不伪造 0:45 或成熟。

时钟胶囊按既有 m:ss 格式走；成熟后同一徽标换 Ready 并去掉时间胶囊。收获为 tilled 后逐格收起；无教学作物元数据、引导结束、面板/放置/离场、画外时隐藏。沿用 #516 的 Pip 避让，只挪新徽标，且连同时间胶囊完整避让，不移动名字条、角色或相机。

## 验证

- 定向 `test_p1_guide_world.gd` **19/19**，report_863；新增三条覆盖：S4 无 plot 目标与无历史的冷进入；0:45→0:44→Ready 且原视图不被减时；缺计时/普通作物不显示、收获与结束清理；整个胶囊避让 Pip、面板/画外/离场隐藏。
- 最终 `tests/p0 + tests/ui_kit` **1818/1818，182 组，0 errors/failures/skipped/orphans，exit 0，report_864**。基线是 c27deb33 的1815加本次3条，未混报周瑜此前临时合 farm-dev 的结果。
- 桌面 Metal 独立 userdir `gensen-liubang-341-crop-countdown`，真实本地 P0 服务 `127.0.0.1:3189`，服务源码沿用 #518 完整快照 `fef95d49`。隔离新号经真实 reducer 的 ack/建家/交谈/两次播种到 t_water；客户端通过实际 `P0Session.send` 队列发送两次 Water，由真实 HTTP 服务确认。
- 两个计时均在 **0:45** 时实拍；此时服务端已到 t_sow_rest 且无 plot marks。随后真实等待，没有 dev skip、修改时钟或把状态改为成熟；逐秒记录到 0:01，再转 Ready。约46.7秒后服务端两格都是 ready、步骤是 t_harvest_quick；真实收获第一格，只收起第一枚 Ready。
- 两张 PNG 分别为“两枚时钟＋0:45”和“两枚 Ready”；原始录屏连续约50.4秒，交付视频截取最后连续 **8.12秒**，展示最后倒计时、Ready 与单格收获，按原墙钟 VFR 编码、不加速。两张图与抽帧已实际查看。

材料和可复现脚本在 `output/liubang-341-crop-countdown/`；图片、视频、抽帧、服务端/布尔/逐秒记录及测试摘要上传 [SGODOT-341](https://plane.sensenjoy.cn/zili/browse/SGODOT-341/)。

这轮验证的是客户端命令路径和视觉状态，不冒称原生触摸操作、完整引导步行主线、Android/真机或性能验收。此前 #516 的真实 viewport Water 点击证据仍单独保留。既有五个 ObjectDB 退出 warning 未消除；全量断言报告为零 errors/failures/orphans。无用户数据/存档格式/部署/装机操作，无 --import/--editor 或 ADB；不进0.2.12，普通号 guide_v3 仍关。本人测试与捕获 Godot 已退出，3189 本地服和父进程按记下的 PID 停止。
