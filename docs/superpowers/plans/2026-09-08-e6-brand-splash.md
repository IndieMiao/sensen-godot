# 三端品牌开屏（E6 / R11 的可先做部分，实施记录）

- 日期：2026-09-08 ｜ 分支：`feat/next-feature` ｜ Plane：SGODOT-66（**卡片仍阻塞**）
- 上游：`2026-09-08-remaining-tasks.md` §3「SSLAUNCH B1 品牌 / 商店名 / 域名」
- 性质：实施记录 + 交接。**未提交**；未装机。

## 0. 结论

| 项 | 结果 |
|---|---|
| 做了什么 | 三端开屏链路全部接上（Godot boot_splash / iOS storyboard / Android 12+ 系统开屏），素材是占位件 |
| 为什么现在做 | 链路与素材解耦：B1 到手后是「换一个 SVG + 改两个颜色 + 重跑脚本」，不动代码与配置结构 |
| 新增测试 | `tests/app/test_brand_splash.gd` 9 例，全绿零孤儿 |
| 全量 | **907 例 / 0 errors / 0 failures / 0 orphans**（含 §4 修掉的既有失败，与被它掩盖的 6 条） |
| 未验证 | iOS / Android 系统开屏的真机观感——系统在 Godot 起来之前绘制，进程内截不到图 |
| 没动 | 包名 / Bundle ID / 商店名（定版属 E6 本体，阻塞于 SSLAUNCH B1 与 A9） |

## 1. 做了什么

**占位素材与单一来源**
- `assets/brand/logo_mark.svg`：手写唯一源，512×512、居中、透明底。
- `modules/brand/brand.gd`（`Brand`）：开屏底色、标识主色、七个生成物路径与期望边长、`PLACEHOLDER` 开关。
  `SPLASH_BG` 直接取 `DesignTokens.UI_PAPER`，不再复制一份色值。
- `tools/brand/render_brand_assets.gd` + `tools/brand/render.sh`：从 SVG 生成 7 个 PNG（引擎开屏、
  旧版启动图标、自适应前景 / 背景 / monochrome、iOS @2x / @3x）。生成物提交进仓库。

**三端接线**
- `project.godot` `[application]`：`boot_splash/{image,bg_color,fullsize,use_filter}`，`config/icon` 指向品牌 SVG。
- `export_presets.cfg` `[preset.0.options]`：四个 `launcher_icons/*`。
- `export_presets.cfg` `[preset.1.options]`：`storyboard/{use_custom_bg_color,custom_bg_color,custom_image@2x,custom_image@3x}`。

**守护**
- `tests/app/test_brand_splash.gd`：三端字面值与 `Brand` 对齐、生成物尺寸、透明角、自适应 66% 安全区、
  白剪影、显示名与 Android `package/name` 一致、`PLACEHOLDER` 翻牌提醒。
- `docs/release-process.md` §5.1 第 9 条（占位不得提审）+ §5.1.2（三端各读哪个文件、为什么不碰 themes.xml）。
- `assets/brand/README.md`：B1 落地后的换素材清单。

## 2. 关键决定

1. **安卓侧不改 `themes.xml`，只改 `launcher_icons/*`。** 自动生成的 `GodotAppSplashTheme` 引用
   `@mipmap/icon_background` 与 `@drawable/splash_icon`，这两个资源由导出预设和 boot splash 在导出时生成。
   `android/build` 是 gitignore 的、重装模板即丢（同 B5 地图垫底改独立 AAR 的原因），所以定制一律不写进去。
   也因此不需要 `gradle_build/custom_theme_attributes`。
2. **开屏底色 = 壳的纸色 `UI_PAPER`。** 开屏切进登录页不能闪色，测试锁住这条等式。
3. **`image_scale_mode` 留引擎默认**：枚举语义没从二进制里核准，不写猜的值。
4. **不动包名 / Bundle ID。** 改它会连带废掉 Firebase OAuth client 与 iOS 描述文件，属 A9 一起做。
   现状两端占位不一致（Android `com.sensen.avatarphase1` / iOS `com.sensen.mapg3`），已记在 README。
5. **`PLACEHOLDER` 做成会失败的断言**：品牌定版后必须有人主动翻牌，顺手被指回发布前检查。

## 3. 踩坑记录（对后续任务有用）

- **Godot 4.7 的 iOS 预设没有 `storyboard/use_launch_screen_storyboard`**（storyboard 常开）。
  按旧版文档写这个键是死键，导出器静默忽略——正是「配置写了但没生效」那类假成功。
  核准办法：`strings <godot 二进制> | grep '^storyboard/'`。同法核准了 `boot_splash/*`、
  `launcher_icons/*`、`gradle_build/custom_theme_attributes`。
- **`Image.load_from_file()` 会刷 `this will not work on export` 警告**（每次调用一条）。
  要断言磁盘上的原图就用 `FileAccess.get_file_as_bytes()` + `Image.load_png_from_buffer()`，
  语义也更对：导出器消费的就是磁盘那份 PNG，不是导入后的纹理。
- **新脚本的 `class_name` 要先 `--import` 才进全局类缓存**，否则 `--script` 跑的工具脚本里
  `Identifier "Brand" not declared`。`tools/brand/render.sh` 因此是 import → 生成 → import。
- 导出预设里空着的 `launcher_icons/*` 不是「没有图标」：导出器会生成 44 字节的纯色占位
  `icon_background.webp`，构建照样过，Android 12+ 开屏就是那个占位色。

## 4. 顺带发现并已修掉：CI 从 2026-09-08 00:48Z 起连红 17 次

`gh run list --workflow godot.yml`：最后一次成功是 `2026-09-08T00:43:36Z`，紧接着的下一次
（`00:48:32Z`，提交 `49460d6 test(map): 手势穿壳回归…`）开始失败，之后连红 17 次约 8 小时。
失败点固定是 `tests/app/test_map_gestures_through_shell.gd::test_drag_reaches_the_map_and_moves_the_camera`。

**根因是用例写法，不是产品 bug。** 该用例用 `Vector2.is_equal_approx`（容差 1e-5）断言拖拽后经纬度"变了"。
位移量正比于 `map_poc._cam_distance()`，而它取 `DisplayServer.window_get_size().y / pixel_ratio`
——headless 是 dummy driver，窗口尺寸为 0，被那一行自带的下限守卫钳到 1 m，
于是一次 120 px 拖拽只挪 ~1.4e-6°，比容差还小，被判成"没动"。
产品代码是对的：原生 Mapbox 视图是全窗口的，`窗口物理像素 / pixel_ratio` 正是 Mapbox 要的逻辑像素高度，
那行下限守卫的注释本来就写着"headless/未就绪时窗口尺寸可能为 0"。

**改法**：断言与量级无关的不变量——向下拖 → 内容跟着下移 → 视点北移，所以 `center_lat` 必须变大，
且纯竖直拖拽不该改 `center_lng`。反证用例同步从"约等于没变"改成严格相等，
否则 headless 下"其实动了一点"也会通过。两种模式（headless / 有窗口）各 7/7 绿。

顺带踩到的坑：**别把 lat / lng 塞进 `Vector2` 再比较**。`Vector2` 是 float32，31° 量级精度约 2e-6，
正好把这点变化吃掉；改用严格相等时会直接暴露成 `121.473701 vs 121.473700`。用 `float`（f64）局部变量。

### 4.1 另外两件事（量出来的，都不是本卡引入，其中第二件未处理）

1. **失败会让 gdUnit4 放弃同套件剩余用例。** 原版这个套件在 headless 下只跑 1 条就中止，
   所以 CI 报的"892 例"是被截断的数字——这 7 条里有 6 条从未在 CI 跑过。修好后全量 907/907。
2. **CI 的 ObjectDB 守卫从未生效。** `godot.yml` 里是 `grep -q "ObjectDB instances leaked"`，
   而 Godot 实际输出是 `35 ObjectDB instances were leaked at exit`（中间多个 `were`），匹配不上。
   实测 pristine HEAD（`2b0b744`，把本卡改动全部挪开后跑）全量就有 **35 条泄漏**；
   同一基线换回原版手势测试仍是 35 条，所以与本卡、与手势修复都无关。
   CHANGELOG 的 `Fixed` 里"测试进程里的 ObjectDB 泄漏警告"这条目前与事实不符（Q6 / SGODOT-79）。
   **未处理**：修好 grep 会让 CI 立刻因这 35 条转红，所以"先修泄漏还是先修守卫"要先定，不该顺手改。

## 5. 手工验收（需真人，且必须真机）

三端开屏都不在 Godot 场景树里，`get_screenshot` 与 Godot 自身截图都拍不到，只能肉眼：

1. iPhone 装包 → 冷启动，启动画面应是纸色底 + 居中绿色图钉，且**切进登录页时不闪色**。
2. 安卓装包 → 冷启动，Android 12+ 系统开屏同上；桌面图标是自适应图标（长按看形状裁切正常）；
   系统开「主题图标」后图标应变成单色剪影。
3. 桌面 `godot --path .` → 窗口图标与启动开屏为品牌标识。

## 6. 下一步

- 等 **SSLAUNCH B1**：按 `assets/brand/README.md` 走 7 步，E6 / R11 才能置 Done。
- 与 **A9** 一起定包名 / Bundle ID，届时两端占位统一。
- CI 已随本轮修绿（§4）；下一次 push 应该能第一次真正跑到 `Android debug APK` 那个 job——
  它此前一直因测试 job 失败被跳过，产物从未产出过，首跑结果要看一眼。
- §4.1 第 2 条（ObjectDB 守卫失效 + 35 条既有泄漏）待定，需要决定先修泄漏还是先修守卫。
