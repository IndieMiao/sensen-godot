# 2026-09-04 内部 Demo 双端交接文档

分支：`feat/internal-demo-2026-09-04` ｜ 归档日期：2026-09-01 ｜ 撰写人：Task 10（双端构建与真机验收）

## 0. 先说清楚这份文档是什么

这台执行本任务的机器**没有接 Android 设备、没有接 iOS 设备**（`adb devices` 为空），
也**没有屏幕录制/无障碍权限**——headless 编辑器能跑，但没有人能看见它。所以：

- 凡是需要"看屏幕""摸手机""点弹窗"的验收项，本文档一律标记为**人工验收**，
  并写清楚要看什么、什么算过、什么算翻车——不代表已经验证，只是把路铺好。
- 凡是能用测试/构建命令诚实跑出结果的，标记为**机器验证**，并点名具体是哪条命令、
  哪个测试用例。
- **本文档没有勾选任何一条我没有亲眼确认的验收项。** 这是本任务最重要的约束。

拿到手机的人应该能拿着这份文档从头做到尾，不需要再去翻 9 个任务的实现细节。

---

## 1. 结论速览

| 项目 | 结果 |
|---|---|
| 全量测试 | **绿**：151 test cases，0 errors / 0 failures / 0 flaky / 0 skipped / 0 orphans，exit code 0 |
| Android 构建 | **成功**：`build/sensen-demo-debug.apk`，130,756,968 字节，exit code 0 |
| iOS 构建 | **卡在已知坑**：编译、链接、SPM 依赖解析全部通过，最后一步 CodeSign 的私钥签名操作卡死在钥匙串授权弹窗（`SecurityAgent`），headless 会话没有屏幕可点，人工在场跑同一条命令预期可以过 |
| Android 真机验收 | 未做（无设备）——10 条清单全部转为人工验收 |
| iOS 真机验收 | 未做（无设备 + 构建未落地）——按 spec §2 降级，本文档即留证 |

---

## 2. 构建与安装命令（人工接手时直接抄）

### 2.1 Android

```bash
cd /Volumes/ACASIS/projects/sensen-godot
tools/android/setup_android_build.sh
godot --headless --path . --export-debug "Android" build/sensen-demo-debug.apk
adb install -r build/sensen-demo-debug.apk
```

- **包名（真实值，来自 `export_presets.cfg`）：`com.sensen.avatarphase1`**
- App 显示名：SensenAvatar
- 本次任务已经跑过这两条命令并成功产出 APK；`build/` 不入库，如果人工验收时
  分支上又有新提交，请重新跑一遍这两条命令再装机，不要用本次遗留的 APK 兜底。
- 唤起方式：手机桌面找图标点开，不需要 `adb shell am start`（没有已知的
  launcher activity 别名问题）。

### 2.2 iOS（非阻断）

```bash
cd /Volumes/ACASIS/projects/sensen-godot
tools/ios/setup_ios_g3.sh
cd build/ios
https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 \
xcodebuild -project sensen.xcodeproj -scheme sensen -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath dd-dev -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=53LT77CV6R CODE_SIGN_STYLE=Automatic build
```

- Team ID `53LT77CV6R` 是本机 Xcode 已登录的免费个人团队（"Shaojie Zhang (Personal
  Team)"），**7 天有效期，必须当天装机**，过期需要在 Xcode GUI 里重新选一次 Team。
- **本次卡点**：`codesign` 进程在 `SecKeyCreateSignature`（用私钥对 app 签名）
  这一步挂死，`sample` 采样确认它在等 `SecurityAgent`（钥匙串授权 GUI 弹窗）—
  这正是 `docs/superpowers/plans/2026-08-31-3dmap-g3-ios-transparency.md` 记录的
  "已踩坑①：钥匙串授权挂死"，只是这次卡在签名私钥而不是 SPM 拉取凭据。
  **人工在 Mac 屏幕前跑同一条命令时，弹窗会正常出现，点一次"始终允许"即可**，
  之后同一签名身份不会再弹（前提是没换 Mac 或清过登录钥匙串）。
- 卡点之前的所有步骤（Godot 导出、pbxproj 注入 G3Spike.mm/MapUnderlay.swift、
  SPM 拉取 mapbox-maps-ios、编译、链接、CopySwiftLibs、dSYM 生成）**全部无错误
  通过**，说明代码本身没问题，纯粹是签名授权这一步需要人在场点一下。
- 装机（真人在场、接好手机后）：
  ```bash
  xcrun devicectl list devices   # 拿 UDID
  xcrun devicectl device install app --device <UDID> \
    dd-dev/Build/Products/Debug-iphoneos/sensen.app
  xcrun devicectl device process launch --device <UDID> com.sensen.mapg3
  ```
- 手机上还需要：设置 → 通用 → VPN 与设备管理 → 信任该开发者证书。

---

## 3. Android 验收清单（spec §9 / Step 3）—— 机器验证 vs 人工验收

| # | 验收项 | 归类 | 说明 |
|---|---|---|---|
| 1 | 开 App → **权限弹窗出现** | **人工验收** | 装机后点开 App，几秒内应看到系统定位权限弹窗（精确定位/大致定位二选一样式）。**没弹窗 = 单数 `request_permission()` 的坑回归了**——本次代码检查确认 `scenes/map_poc/map_bridge_android.gd:48` 调用的是复数 `OS.request_permissions()`（正确写法），但复数调用本身**不能证明系统一定会弹窗**，这取决于 manifest 权限声明、targetSdk 行为、以及设备是否已经记住过选择——必须肉眼确认。 |
| 2 | 授权后落到自己真实位置，角色站在脚下 | **人工验收** | 需要真实 GPS + 肉眼看角色是否站在正确街区。 |
| 3 | **换个远离上海人民广场的地点再测**：周围仍有路人角色和 ≥3 个可点 marker | **人工验收（一票否决项）** | 见下方"重点关注"第 2 条，这是本次重构存在的唯一理由，必须真测。 |
| 4 | 拒绝权限 → 不崩，3 秒后落到上海，路人和 marker 照常可见 | **部分机器验证 + 人工验收** | 机器验证：`tests/map/test_map_home_anchoring.gd::test_timeout_fallback_uses_shanghai_default` 断言 3 秒超时后 `home_lat/lng` 回落 `START_LAT/LNG`；`map_poc.gd:142` 确认无条件挂了这个超时回调（拒绝/无权限/桌面无插件都会触发）。**不能机器验证的**：真实点击"拒绝"之后 App 是否真的不崩溃、UI 是否卡死——这只能在设备上试。 |
| 5 | 选"大致位置" → 不崩，定位照常生效 | **人工验收** | 代码上 `LOCATION_PERMS` 同时列了 FINE 和 COARSE，`_has_location_permission()` 两者任一满足即可继续（`map_bridge_android.gd:9-12,69-74`），逻辑上支持"大致位置"，但**运行时系统真给的是哪种精度、定位是否真的回调**必须设备验证。 |
| 6 | 快速甩动地图有惯性衰减；双击平滑放大（不是瞬变） | **机器验证（逻辑）+ 人工验收（手感）** | `tests/map/test_map_fling.gd` 全绿，覆盖：fling 衰减到停止、纬度钳制、单帧限幅、双指捏合不误触发双击、`_tween_zoom` 确实是渐变而非瞬变、连续双击会杀掉前一个 tween。这些证明**状态机行为正确**，但"手感是否顺滑"是主观体验，需要真手指在真屏幕上试。 |
| 7 | 点 marker 弹气泡，中文显示正常无豆腐块 | **部分机器验证 + 人工验收** | 机器验证：`tests/map/test_marker_layer.gd`（≥3 marker、气泡文案、坐标跟随 home 而非绝对经纬度、单次只开一个气泡）全绿；全局 CJK 字体已在 `project.godot:28` 配置为 `res://assets/ui/fonts/NotoSansSC-Regular.otf`。**不能机器验证**：字体文件在真机渲染管线里是否真的生效、有没有系统替换成方块——必须肉眼看。 |
| 8 | 进换装房换上装/发型 → 保存 → 返回地图，自己的角色已更新 | **部分机器验证 + 人工验收** | 机器验证：`tests/integration/test_dressing_flow.gd::test_full_dressing_flow`、`tests/map/test_map_self_outfit.gd`（读取已保存装扮 / 无存档时回落默认）全绿，证明数据层闭环没问题。**不能机器验证**：地图场景里那个具体的 3D 角色模型是否真的按新装扮重新渲染出来——这是渲染层的事，测试只测到了数据。 |
| 9 | 全程 UI 视觉统一（薄荷绿 token），无残留旧灰绿按钮 | **部分机器验证 + 人工验收** | 机器验证：`tests/ui/test_design_tokens.gd`（13 条）+ `tests/ui/test_app_theme.gd`（7 条）全绿，确认 accent 色值、字号阶梯、间距网格、触控目标尺寸都从 `DesignTokens` 单一来源取值。**不能机器验证**：有没有漏改的场景文件把颜色写死成旧灰绿——这类回归只能靠人逐屏翻。 |
| 10 | denylist 里的部件不出现在换装列表 | **机器验证** | `tests/catalog/test_demo_denylist.gd` 全绿，包括 `test_denied_part_disappears_from_slot_pool`、`test_shipped_denylist_file_is_valid`（校验随包 `assets/avatar/demo_denylist.json` 格式与内容有效）。这条可以认为已经充分验证，人工验收时顺手扫一眼换装列表确认即可，不是重点。 |

## 4. iOS 验收清单（spec §9 / Step 5）—— 全部人工验收

| # | 验收项 | 归类 | 说明 |
|---|---|---|---|
| 1 | 除定位外跑通同一条链（iOS 定位空转，3 秒后落到上海默认点，路人与 marker 照常可见） | **人工验收，且本次未装机** | iOS 构建本身卡在钥匙串授权（见 §2.2），没有产出可安装的 .app/.ipa 落地验证。逻辑层面 `MapBridgeIOS`（`tests/map/test_map_bridge_location.gd::test_ios_bridge_inherits_noop_location`）继承了 no-op 定位，理论上会触发与 Android 拒绝权限同样的 3 秒兜底路径，但**没有真机验证过**。 |

不影响本周目标达成（spec 明确 iOS 非阻断）；构建链已按 spec §2 降级为本文档留证。

---

## 5. 重点关注（来自九个任务评审中容易漏掉的坑）

1. **权限弹窗必须真的出现。** 如果开 App 后没有任何系统权限弹窗，大概率是踩了
   单数 `OS.request_permission()`（静默失败、无弹窗无回调）的坑，退回 Task 2/3
   检查 `map_bridge_android.gd`。当前代码用的是复数 `request_permissions()`，
   逻辑上是对的，但**这条必须肉眼确认弹窗真的弹了**，不能只看代码。

2. **务必在远离上海人民广场的地点测一次**，确认周围仍有路人角色和 ≥3 个可点
   marker。这是 Task 4"演示内容相对锚定"存在的唯一理由——重构前的老实现是
   "定位到非上海就空无一人"（见 commit `4c9c20b`），这条验收是对那次修复的
   一票否决式复验。代码路径：`map_poc.gd::_on_location_update` → `_resolve_home`
   → `_spawn_home_cohort` + `marker_layer.set_home`，全部相对 `home_lat/lng`
   摆放，不写死经纬度——但"相对定位"这件事本身，只有真的换个城市测才算数。

3. **三条降级路径都要走一遍**：拒绝权限、选"大致位置"、3 秒超时无定位。
   三条都不能崩溃，且降级之后演示内容（路人、marker）必须仍然可见——不能因为
   定位失败就变成空地图。三条路径共用同一个"3 秒超时回落上海"兜底
   （`map_poc.gd:36,142`），但触发方式不同，行为可能有差异，建议三条都单独试。

4. ~~**`glass3` 的贴图选型没有过肉眼确认，值得扫一眼。**~~
   **已确认（2026-09-02）**：用 `tools/dev/render_part_previews.gd` 离屏渲出来看过，
   `T_skin05_glass_D 1.png` 这个覆盖是对的——金框圆墨镜，贴图不错位不拉伸。
   唯一可说的是镜片在 Unity 侧本有一份 alpha 材质（`M_skin05_glass_alpha.mat`），
   我们的管线对 socket 部件只取排序第一个 `.mat`（正好是标准 toon 的那份），
   于是镜片渲成不透明深色。作为墨镜看是合理的，**保留**。

5. **`assets/avatar/thumbs/` 下每个部件缩略图都是同一张 64×64 占位图**
   （25 个 PNG 文件逐一核对，尺寸均为 64×64，属于既有素材流水线的缺口，
   不是本次九个任务引入的问题）。这意味着**换装房里的部件按钮目前视觉上
   互相分不清**——这不是本次验收的阻断项，但会让计划里遗留的"逐个截图部件
   来选 denylist"这一步比听起来难得多：截图也认不出是哪个部件，只能靠文件名
   /索引对照。如果后续要扩充 denylist 或部件池，建议先补缩略图生成，否则
   纯靠肉眼在换装房里挨个试穿。

   **已缓解（2026-09-02）**：`assets/avatar/thumbs/` 那批占位图仍未修（管线缺口
   照旧），但运行时有了 `PartThumbnailer` 离屏渲染，换装房里的按钮已经能互相
   分清；挑件也不必再装机试穿——`tools/dev/render_part_previews.gd` 可以把
   manifest 里每个部件批量渲成 PNG 直接看（**必须带窗口跑**，headless 的 dummy
   渲染驱动下 SubViewport 取不到图像，存出来是全透明）。

6. **iOS 免费个人团队证书 7 天有效期，装机必须当天完成。** Team ID
   `53LT77CV6R`，从签发日起算 7 天后证书失效，App 会拒绝启动，需要重新连
   Xcode 走一遍签名流程。如果 iOS 验收拖过这个窗口，直接按"未验收"处理，
   不要假设旧证书还能用。

---

## 6. 本次机器验证的原始证据

### 6.1 全量测试

```
tools/run_tests.sh
...
Overall Summary: 151 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans |
Executed test suites: (30/30)
Executed test cases : (151/151)
Total execution time: 4s 937ms
Exit code: 0
```

（计划预期用例数"约 110 + 32"≈142，实际 151，属正常范围内的增量。）

### 6.2 Android 构建

```
$ tools/android/setup_android_build.sh
android/build 已就绪（模板 4.7.2 + GodotMap 插件覆盖层）

$ godot --headless --path . --export-debug "Android" build/sensen-demo-debug.apk
...
[ DONE ] export
$ echo $?
0

$ ls -la build/sensen-demo-debug.apk
-rw-r--r-- 1 zhangshaojie staff 130756968 9月 1 17:41 build/sensen-demo-debug.apk
```

### 6.3 iOS 构建

```
$ tools/ios/setup_ios_g3.sh
...
pbxproj 注入完成（spike + swift + SPM）

$ cd build/ios && https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 \
  xcodebuild -project sensen.xcodeproj -scheme sensen -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath dd-dev -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=53LT77CV6R CODE_SIGN_STYLE=Automatic build
...
Resolve Package Graph                              # SPM 解析成功
...（编译 G3Spike.mm / MapUnderlay.swift，若干无害 warning）
CopySwiftLibs .../sensen.app                        # 通过
CodeSign .../sensen.app                             # 卡死于此，进程状态 sleeping，5 分钟无进展
```

`sample` 对卡死的 `codesign` 子进程采样确认调用栈停在：

```
SecCodeSignerAddSignatureWithErrors → ... → SGN_SignAll → SecKeyCreateSignature
  → SecKeyRunAlgorithmAndCopyResult → ... → ClientSession::generateSignature
  → mach_msg（等待 securityd 应答）
```

`ps -ef` 同时确认存在一个等待中的
`/System/Library/.../SecurityAgent.bundle/.../SecurityAgent` 进程——即钥匙串
授权弹窗，headless 会话无屏幕可点，判定为已知坑复现，遂终止进程
（`kill -9`，已确认无残留子进程）。

---

## 7. 涉及的源码位置索引（方便人工验收时对照）

- 定位权限：`scenes/map_poc/map_bridge_android.gd`
- 定位/演示内容相对锚定：`scenes/map_poc/map_poc.gd`（`_on_location_update` /
  `_resolve_home` / `_spawn_home_cohort` / `HOME_TIMEOUT_S`）
- 手势惯性与双击缩放：`scenes/map_poc/map_poc.gd`（`_step_fling` / `_tween_zoom` /
  `_is_double_tap`）
- Marker/气泡：`scenes/map_poc/marker_layer.gd`
- Design token：`modules/ui/design_tokens.gd`（单一来源）
- denylist：`assets/avatar/demo_denylist.json` + 消费逻辑见
  `modules/avatar/catalog/part_catalog.gd`（`parts_for_slot()`）
- glass3 贴图覆盖：`tools/unity_export/overrides.json`（`glass3.albedo`）
- 部件缩略图：`assets/avatar/thumbs/*.png`（25 个文件，全部 64×64 占位图）
- Android 包名/签名配置：`export_presets.cfg`（`[preset.0.options]`）
- iOS bundle id/Team 占位：`export_presets.cfg`（`[preset.1.options]`，
  `application/app_store_team_id="ABCDE12345"` 是占位符，实际用命令行
  `DEVELOPMENT_TEAM=53LT77CV6R` 覆盖）

---

## 8. 最终全分支评审的结果与残留（2026-09-01 追记）

十个任务完成后做了一次全分支评审（覆盖跨任务交互，这是每个任务的单独评审看不到的层面），
findings 已在 `35e66ac`..`477ff7e` 五个提交里修完，并过了一轮范围内 re-review。测试 151 → 155。

### 8.1 修掉的一个 Critical——它命中的正是阻断链最后一步

`GodotMapPlugin.startLocation()` 的 `locationStarted` 闩死后永不复位，而 GDScript 侧的
`_home_resolved` 是**每场景实例**的，`change_scene_to_file` 会重建地图场景。于是：

> 地图 → 换装房 → 回地图，新场景调 `start_location()` 被闩挡掉 → 不补发 last-known、不重新订阅
> → 室内静止设备（`minDistance=5f` + FINE 下只订 GPS）拿不到定位 → 3 秒后回落**上海**
> → 幂等锁让此后所有真实定位被丢弃，整场演示锁死在上海人民广场，而芯片仍显示"我的位置"。

演示者做完换装返回的那一下就会触发。已修：last-known 补发提到闩之前、闩只包住订阅、
`locationStarted` 改为订阅成功后才置位、并同时改成 GPS+NETWORK 双 provider 订阅
（室内 GPS 可能几分钟不出定位）。

**人工验收时请专门验这条**：站在室内不动，地图 → 换装房 → 回地图，看是否仍在真实位置。

### 8.2 一条挂起项（代码经两位评审确认正确，但无自动化测试）

回落锚点被真实定位纠正时，**已经实例化**的角色（`_pawns`）的坐标位移路径没有测试覆盖——
没有测试把 `_process()` 推进到足以填充 `_pawns`。已入队未实例化的那半（`_spawn_queue`）有测试。
若这条真坏了，表现是：纠正发生后，先前已出现的角色留在旧位置不跟着走。
§3 的"慢答权限弹窗 + 远离上海实测"那条正好会走到这条路径，人工验收时留意。

### 8.3 明确留给目视会话的一项（评审建议不要盲改）

**design token 没有触达两个场景。** `map_poc.tscn` 与 `dressing_room.tscn` 里存在 per-node
样式覆盖，且仍是重铸前的取值：

| 位置 | 现值 | 应为 |
|---|---|---|
| `map_poc.tscn:16-18` 加载条 | `#4fb894`（旧薄荷绿） | `ACCENT` `#34d399` |
| `map_poc.gd:59` `DOT_OK` 状态点 | `#4fb894` | `ACCENT` |
| `map_poc.tscn:66` Title | `#262a30`（冷灰） | `INK` `#123028` |
| `map_poc.tscn:73,81` Sub/Debug | `#6b7075`（冷灰） | `INK_SUB` `#7d9089`（鼠尾草绿） |
| `dressing_room.tscn:13-23,61` 抽屉 | 自带 StyleBox，圆角 20 | 主题的 `RADIUS_SHEET` 22 |

后果：同屏会出现两种不同的绿。`design_tokens.gd` 里"改这两个文件就够、不必翻场景"这句
**目前不成立**——修掉这些覆盖之后才成立。这是**计划自身的缺陷**（Task 7 的 steps 从未把
§6⑥ 承诺的应用面变成可执行步骤），不是实施问题。

约 15 行改动，但它是本分支上第一个**必须有人看着屏幕**才能改的东西，所以排在目视验证会话里做，
不要盲改。同时要把 `design_tokens.gd:7-8` 那句承诺改准。

一句话自查：`grep -rn "Color(" scenes/` 一秒就能列全这些残留，不需要逐屏翻。

### 8.4 仍在延期的 minor（评审已逐条三角，判定可留）

- `test_map_self_outfit` 的 `pool<2` 跳过守卫（`hairHat` 有 4 个部件，断言实际总会执行）
- `start_location()` 无重入守卫（单一调用点）
- `getSystemService` 取不到 `LocationManager` 时静默 return（缺一行日志）
- `test_timeout_fallback` 未走 `_ready()` 的定时器接线（测它要么真等 3 秒、要么把常量做成可注入，不划算）
- `glass3` 贴图选择未目视确认（见 §5）
- `.tres` 里的 `;` 注释若用编辑器打开并保存可能被剥掉（已验证能解析）
- `MarkerLayer._toggle()` 无越界守卫、`sync()` 每 marker 重算一次 base、`load_specs()` 不校验元素类型
- `_unhandled_input` 已承担 6 类职责（拆分建议放在真机手势验证之后）
- **`get_process_delta_time()` 当作"距上次拖拽采样的时间"**：若真机单帧派发多个 `ScreenDrag`，
  每个采样都除以整帧 dt，会系统性低估 `_fling_vel`。这是手感调参问题，需要真机 trace
  拖拽事件频率 vs 渲染帧率才能定量——请和 §3 的"甩动手感是否顺滑"一起看。

### 8.5 一条被撤销的 finding

先前记录的"`int(0.3 * 1000.0)` 因 IEEE-754 实际是 299ms"经复核**不成立**：
`0.3 * 1000.0` 在 binary64 里精确等于 `300.0`，`int()` 得到 300。已撤销，别去"修"它。
