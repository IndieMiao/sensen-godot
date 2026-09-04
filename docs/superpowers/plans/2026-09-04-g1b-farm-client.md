# G1-B 农场客户端 Implementation Plan

> 逐任务执行，每个 Task 独立评审。服务端（G1-A）已上线 `https://farm.sensenjoy.cn`，
> 本计划只做 Godot 侧。

**Goal:** 让玩家在农场里用手势完成 荒地 → 清理 → 翻土 → 播种 → 照料 → 收获 的完整循环，
田格状态由服务端持有，客户端只做视觉预测；HUD 显示金币/种子/田况/成熟提示；导演模式能在
三分钟内走完一个游戏日。

**Design:** 服务端契约见 `docs/superpowers/specs/2026-09-04-g1a-farm-server-design.md`
（§4.2 命令集、§7 HTTP、§4.1 状态字段）。**客户端不算钱、不算 XP、不算 `ready_at`**
（方案 D4）：只预测田格的视觉状态好让动作立刻播，回包按 `version` 覆盖，漂移一律服务端为准。

## Global Constraints

- **薄预测器**：`modules/farm_predict` 只碰 `cells` 的视觉态，绝不碰钱包、库存数量、XP、
  关系、章节。任何「算出一个数给玩家看」的冲动都属于服务端。
- **断网进只读 + 横幅，不排队离线命令**（方案 §3 D4）。重连后 `GET /farms/me` 全量覆盖。
- **导演命令只对 `qa=true` 实例生效**，正式实例服务端返回 403；客户端不做本地时间加速。
- 用户可见文案一律英文；代码注释中文，写清「为什么」。
- **不能破坏的既有断言**（见 §已知雷区）：`prop_count() == 16`、相机公式、
  `exit_btn.pressed` 只有一个连接、缺蓝图不崩、360×800 下顶栏不重叠。
- 每个 Task 一次提交，`tools/run_tests.sh` 必须全绿。

## 已知雷区（Explore 摸出来的，实现时逐条避开）

| 雷 | 位置 | 规避 |
|---|---|---|
| `prop_count()` 精确断言 16 | `tests/farm/test_farm_scene.gd:25` | 作物挂**新建的 `Crops` 节点**，不进 `Props` |
| 相机公式被逐位钉死 | `test_farm_scene.gd:43-45` | 不动 `_update_camera()` |
| `exit_btn.pressed` 连接数 == 1 | `test_farm_scene.gd:47` | 不往 ExitButton 上再连信号 |
| 顶栏 360×800 不重叠 | `test_farm_scene.gd:82` | HUD 新元素放**底部与右侧**，不进 TopBar |
| `_process` 每帧无条件抢动画 | `farm.gd:103-107` | 加 `_action_lock`，劳作动画期间不被 walk/idle 覆盖 |
| `RigActivity` 在 16 m 处休眠动画 | `rig_activity.gd:8-9,55-63` | 农场相机距离正好 16，劳作动画不播先查这里 |
| 摇杆按矩形吃事件 | `touch_stick.gd:22,40-51` | 刷子走 `_unhandled_input` 的 drag 分支；摇杆矩形内的 drag 已被 `accept_event()` 吃掉 |
| 只有 idle/run/walk 三条动画 | `assets/avatar/base/animations.res` | 五种劳作动作全部走占位登记表 + 程序化回退 |

## File Structure

```
modules/net/
  api_client.gd        HTTPRequest 封装：鉴权、超时、幂等重试、时间偏移、断线态
  farm_session.gd      会话：登录 → 建/取农场 → 发命令 → version 对账
modules/farm_predict/
  cell_predictor.gd    田格视觉预测（只碰 cells，纯函数 + 待确认队列）
modules/farm/
  crop_field.gd        作物 MultiMesh 渲染（4 阶段 × 4 作物）
  labour_brush.gd      网格刷子：拖拽轨迹 → 逐格命中队列
  action_runner.gd     动作队列：逐格播动画 + 发命令 + 动画占位回退
  anim_placeholders.gd 占位登记表加载与回退策略
scenes/farm/
  farm.gd / farm.tscn  接线（Crops 节点、刷子、HUD、导演面板）
  farm_hud.gd          金币/种子栏/田况/成熟提示/断线横幅
  director_panel.gd    QA 导演面板（倍率/跳日/田况）
assets/avatar/base/anim_placeholders.json   动画占位登记表
tests/{net,farm_predict,farm}/…
```

---

### Task 1: `modules/net` — API 客户端与会话

**Files:** 新建 `modules/net/api_client.gd`、`modules/net/farm_session.gd`；
`tests/net/test_api_client.gd`、`test_farm_session.gd`。

**Interfaces:**
- `ApiClient.new(base_url: String)`；`request(method, path, body, token) -> Dictionary`
  （`{ok, status, json, error}`），内部 `HTTPRequest`，超时 10 s。
- `install_key()`：首装生成 128 位随机十六进制存 `user://install_key.txt`，之后复用。
- `FarmSession`：`login()`、`ensure_farm(region_id, layout_patch_id, revision)`、
  `send(type, payload) -> Dictionary`、`refresh()`；信号
  `state_changed(state, version)`、`offline_changed(offline)`、`rejected(code, detail)`。
- 时间偏移：每次回包记 `server_time - Time.get_unix_time_from_system()*1000`，
  `server_now()` 用它换算——**客户端本地时钟不可信，成熟判定必须用服务端时间**。

**Steps:**
- [ ] `api_client.gd`：`HTTPRequest` 挂在传入的 `Node` 上（`RefCounted` 不能 add_child）；
      非 2xx 不抛，返回结构化结果。
- [ ] 幂等重试：网络超时时**同 key 原样重发**；收到 409 `VERSION_CONFLICT` 时用回包里的
      新 version **换新 key** 重发一次（spec §7.3 的客户端协议）。
- [ ] 断线：连续两次网络层失败 → `offline_changed(true)`，此后 `send()` 直接拒绝并提示，
      **不排队**；`refresh()` 成功即退出只读态。
- [ ] 测试用一个假的 transport（注入函数）跑，不打真网络：覆盖 200/409 两种/422/超时重试/
      断线进出。

**Acceptance:** 无网络依赖的单测全绿；`send()` 在 409 后自动对账成功。

---

### Task 2: `modules/farm_predict` — 薄预测器

**Files:** 新建 `modules/farm_predict/cell_predictor.gd`；`tests/farm_predict/test_cell_predictor.gd`。

**Interfaces:**
- `CellPredictor.new(cells: Dictionary)`；`predict(type, payload) -> Dictionary`（返回受影响
  格的**预测视觉态**，不改权威副本）；`commit(server_cells, version)`；`pending() -> Array`。
- 只处理 `clear_cells / till_cells / sow_cells / apply_care / harvest_cells` 五条，
  其余命令一律不预测（钱、XP、关系都不归它管）。

**Steps:**
- [ ] 状态机与服务端 `handlers/farming.ts` 逐条对齐：`wild→cleared→tilled→sown→growing`，
      收获回 `tilled`。**成熟是派生**：`ready_at <= server_now()`。
- [ ] 预测失败（本地判定就不合法）时直接不预测，让服务端返回 422 说明原因。
- [ ] `commit()` 用服务端 `cells` **整体覆盖**，不做 diff 合并——漂移一律服务端为准。
- [ ] 判别性测试：预测与服务端对同一条命令序列的 `cells` 结果一致（用 G1-A 的账本脚本片段）。

**Acceptance:** 预测器与服务端状态机在五条命令上逐格一致；覆盖后无残留预测。

---

### Task 3: 作物渲染（4 作物 × 4 阶段 MultiMesh）

**Files:** 新建 `modules/farm/crop_field.gd`、`tests/farm/test_crop_field.gd`；
改 `scenes/farm/farm.tscn`（加 `Crops` 节点）、`farm.gd`。

**Interfaces:** `CropField.new(bp, world_scale)`；`sync(cells: Dictionary, now_ms: int)`；
每种作物一个 `MultiMeshInstance3D`，实例 transform 用 `bp.cell_to_world(c)`。

**Steps:**
- [ ] 四个可见阶段按 `care_done_at → ready_at` 的进度分段（0/⅓/⅔/成熟），成熟阶段加一点
      抬升或颜色区分——**阶段是渲染派生量，不进状态**。
- [ ] 灰盒外观：`BoxMesh` 按阶段缩放 + 顶点色；`wild` 画杂草小方块，`tilled` 不画。
- [ ] `Crops` 是 `Props` 的**同级**新节点，`prop_count()` 不受影响。
- [ ] 测试：给定 cells 与时间，断言每个 MultiMesh 的 `instance_count` 与阶段分布。

**Acceptance:** 12 格不同状态能正确渲染；`test_farm_scene.gd` 全部照旧通过。

---

### Task 4: 网格刷子与动作队列

**Files:** 新建 `modules/farm/labour_brush.gd`、`modules/farm/action_runner.gd`；
`tests/farm/test_labour_brush.gd`、`test_action_runner.gd`；改 `farm.gd`。

**Interfaces:**
- `LabourBrush.trace(points: PackedVector2Array, project: Callable) -> Array[Vector2i]`
  ——纯函数，把屏幕轨迹投到地面并去重成有序格列表，方便单测。
- `ActionRunner`：`enqueue(cells, action)`；`step(dt)`；信号 `cell_started(cell)`、
  `cell_done(cell)`、`queue_empty()`。每格 `ACTION_S = 2.0` 秒（与 PRD §6.3 一致）。

**Steps:**
- [ ] `farm.gd::_unhandled_input` 加 `InputEventScreenDrag` 分支：累积轨迹点；抬手时
      `trace()` 出格列表 → `ActionRunner.enqueue()`。**摇杆矩形内的 drag 已被吃掉**，不会打架。
- [ ] 点按替代：现有 tap 分支在**选中了工具**时改为对单格执行动作，未选工具时仍是移动。
- [ ] 行级工具：`row_tool` 为真时把命中格扩展到整畦 3 格，但**仍逐格播放**（PRD §6.3）。
- [ ] `_action_lock`：队列非空时 `_process` 不再用 walk/idle 覆盖动画。
- [ ] 每格动作：先本地预测 → 播动画 → 发命令 → 回包对账。

**Acceptance:** 拖过三格产生三条命令、按序播放；`test_farm_scene.gd:58` 的缺蓝图守卫仍过。

---

### Task 5: 天气照料与动画占位

**Files:** 新建 `assets/avatar/base/anim_placeholders.json`、
`modules/farm/anim_placeholders.gd`；`tests/farm/test_anim_placeholders.gd`。

**Steps:**
- [ ] 登记表：`clip_id / 引用者 / 占位策略 / 状态`。六条劳作动作
      （clear/till/sow/water/drain/shelter）目前**全部是占位**——rig 只有 idle/run/walk。
- [ ] 回退：缺 clip 时播 idle + 程序化俯身（Tween 改 rig 的 rotation/position），
      QA 构建在头顶显示占位标记。
- [ ] 守卫测试：**数据引用的每个动作要么有真实 clip，要么在登记表里**——这条是 D9 的原话，
      新增动作时忘了登记会立刻炸。
- [ ] 三种田况的照料动作按 `care_weather` 选：晴 water、雨 drain、风 shelter；
      VFX 用简单粒子或颜色闪烁占位。

**Acceptance:** 六条动作都能播（真实或回退）；守卫测试对未登记的新动作报错。

---

### Task 6: HUD

**Files:** 新建 `scenes/farm/farm_hud.gd`；改 `farm.tscn`、`farm.gd`。

**Steps:**
- [ ] 顶部只长期显示**金币**（PRD §7.1 L472：XP 与关系不进 HUD）；用 `ChipPanel`。
- [ ] 底部：种子栏（`ThumbChoiceButton` 选作物）+ 工具条（`RailButton` 五种动作）。
- [ ] 田况 chip（晴/雨/风）+ 「下一次成熟」倒计时——倒计时用**服务端时间**换算。
- [ ] 断线横幅用 `ToastPanel`，只读态下工具条禁用。
- [ ] **所有新元素放底部与右侧**，不进 TopBar，否则 `test_farm_scene.gd:82` 会炸。
- [ ] 360×800 桌面渲染截图核对（`tools/dev/g0_preview.gd` 加 farm HUD 模式）。

**Acceptance:** 360×800 下不重叠、可点；`tools/run_tests.sh` 全绿。

---

### Task 7: 导演模式 v1

**Files:** 新建 `scenes/farm/director_panel.gd`；改 `farm.gd`。

**Steps:**
- [ ] 入口：长按 Title 三秒（不额外占屏幕），或命令行 `--qa`。
- [ ] 面板（`BottomSheet`）：时间倍率、跳到下一日、指定田况。三者都发对应的
      `qa_*` 命令给服务端——**客户端不本地加速时间**。
- [ ] 正式实例服务端返回 403，面板据此显示「此农场非 QA 实例」而不是静默失败。
- [ ] 测试：面板发出的命令类型与 payload 正确；403 时的提示路径。

**Acceptance:** 在 QA 农场上能三分钟走完一日；正式农场上明确拒绝。

---

## 出口

- `tools/run_tests.sh` 全绿（现有 314 条 + 新增）。
- 连真实服务端跑通：登录 → 建农场 → 清理/翻土/播种/照料 → 等成熟 → 收获，状态在服务端。
- 杀进程重开后 `GET /farms/me` 恢复到下一可行动作。
- 导演模式三分钟走完一日。
- 桌面 360×800 截图与真机各一轮。

## 估算

Task 1 1.5 ｜ 2 1 ｜ 3 1.5 ｜ 4 2.5 ｜ 5 1.5 ｜ 6 1 ｜ 7 1 = **10 人天**
