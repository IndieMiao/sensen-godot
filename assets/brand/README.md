# 品牌素材（占位）

品牌决策 = **SSLAUNCH B1（Todo）**，未拍板。这里的标识是占位件，
`modules/brand/brand.gd` 的 `Brand.PLACEHOLDER` 为 `true` 期间不得提审
（`docs/release-process.md` §5.1 第 9 条会拦住）。

## 目录

| 路径 | 性质 | 说明 |
|---|---|---|
| `logo_mark.svg` | **手写，唯一源** | 512×512 viewBox、内容居中、背景透明 |
| `generated/*.png` | 生成物，提交进仓库 | 由 `tools/brand/render.sh` 从上面那份 SVG 产出 |

生成物必须进仓库：引擎读 `boot_splash`、导出器读 `launcher_icons` / `storyboard`，
都发生在构建期，CI 不会现场跑一遍生成。

## B1 落地后怎么换（按顺序）

1. **换标识**：用正式标识覆盖 `logo_mark.svg`。保持 512×512 viewBox、内容居中、背景透明，
   否则 `tools/brand/render_brand_assets.gd` 里的 `SVG_BASE` 与自适应安全区计算要跟着改。
2. **改颜色**：`modules/brand/brand.gd` 的 `SPLASH_BG` / `MARK_INK`。
   `SPLASH_BG` 默认取 `DesignTokens.UI_PAPER`（壳的纸色）——开屏底色必须等于登录页底色，
   不然开屏切进登录页会闪一下。要用别的底色，就得同时接受这一闪，或者一起改壳。
3. **重新生成**：`tools/brand/render.sh`（需要 `GODOT_BIN` 或 PATH 里有 `godot`）。
4. **同步三处字面值**——引擎与导出器不读 `Brand`，读的是各自配置文件：
   - `project.godot` → `[application]`：`boot_splash/bg_color`、`config/icon`
   - `export_presets.cfg` → `[preset.1.options]`：`storyboard/custom_bg_color`
   - 路径类的键（`boot_splash/image`、`launcher_icons/*`、`storyboard/custom_image@2x|3x`）
     文件名没变就不用动
5. **跑测试**：`tools/run_tests.sh res://tests/app/test_brand_splash.gd`。
   漂移会红并指出漏了哪一端。
6. **翻牌**：`Brand.PLACEHOLDER` 改 `false`，同时改
   `tests/app/test_brand_splash.gd::test_placeholder_flag_still_marks_brand_as_undecided` 那条断言。
7. **真机看一眼**：三端开屏都不在 Godot 场景树里，截图截不到，只能肉眼确认（见下）。

## 不在本卡范围内

包名 / Bundle ID / 商店名定版属 **E6 / R11（SGODOT-66）**，本目录只管开屏与图标素材。
现状两端占位还不一致（Android `com.sensen.avatarphase1` / iOS `com.sensen.mapg3`），
故意没动：改包名会连带废掉 Firebase OAuth client 与 iOS 描述文件，要和 A9 一起做。

## 已验证 / 未验证

- 已验证：生成链、三端配置字面值、素材形状（尺寸 / 透明角 / 自适应安全区 / 白剪影）——
  全部由 `tests/app/test_brand_splash.gd` 覆盖。
- **未验证（需真机肉眼）**：iOS 启动画面实际观感、Android 12+ 系统开屏实际观感。
  两者都由系统在 Godot 起来之前绘制，进程内截不到图。
