# G3 结果：iOS 透明合成真机验证 ✅ 通过（免引擎补丁）

日期：2026-08-31 ｜ 分支：`poc/3dmap-g3-ios` ｜ 设备：iPhone 15（iOS 26 系）
上游：方案 spec §6.2 曾判"iOS 是全方案最脆弱一环，需 spike/patch/fork"——**本关卡以最低成本路径通过**。

## 结论

**Godot 4.7.2 官方引擎（未打任何补丁）在 iOS 真机上可以透明合成**：垫在 Godot 视图之下的
原生 UIView（亮橙 + "G3 UNDERLAY" 白字）透过透明视口清晰可见，角色正常渲染在其上。
方案 A（原生 Mapbox MapView 垫底 + Godot 透明层）的 iOS 路线成立，无需引擎 patch、
无需 SwiftGodotKit/libgodot fork、无引擎版本分裂。

## 为什么调研时判"挡死"而实际能通

调研的证据链没错但漏了一条路径：`FEATURE_WINDOW_TRANSPARENCY` 在 iOS 确实被注释禁用
（drivers/apple_embedded/display_server_apple_embedded.mm）——但那只是 DisplayServer 的
**窗口透明 feature 上报**。真正决定合成的是 **Metal 渲染驱动**：

- `drivers/metal/rendering_context_driver_metal.cpp:111/258`：
  `layer->setOpaque(!OS::get_singleton()->is_layered_allowed())`
- `main/main.cpp:2760`：`_allow_layered = GLOBAL_DEF("display/window/per_pixel_transparency/allowed")`
- 即：**工程开了 `per_pixel_transparency/allowed`（我们为 Android G1 已开），
  iOS Metal 层在创建时就被引擎自己设为非不透明**，feature 开关根本不在这条链上。
  2023 年社区失败案例是 GLES/MoltenVK 时代（GDTOpenGLLayer 硬编码 opaque=YES 仍在，
  但我们走 Metal RD，不经过它）。

## 生效条件（三件套，缺一不可）

1. `display/window/per_pixel_transparency/allowed = true`（project.godot，已有）
2. 根视口 `transparent_bg = true`（map_poc `_ready` 已设）
3. **运行时把 UIKit 侧收拾干净**：UIWindow/Godot 视图的 backgroundColor 置 clear、
   垫底视图插到 Godot 视图之下（`tools/ios/G3Spike.mm`，后续由正式 iOS 地图插件承担——
   这与 Android 插件的 `shouldBeOnTop()=false` 职责对称）

## 复现

```sh
tools/ios/setup_ios_g3.sh   # 导出工程 + 注入 spike（首次需 Xcode 选一次 Team）
# 构建/装机命令见脚本尾部提示；手机需信任开发者证书（设置→通用→VPN与设备管理）
```

已踩坑速查：iOS 26 模拟器拒装 x86_64（官方模板 sim 库仅 x86_64，且 Godot 的 Metal
驱动不支持模拟器——**iOS 透明验证只能真机**）；`devicectl` 拉起报 profile 未信任 =
手机上还没点信任；免费个人团队证书 7 天有效期。

## G3 收尾后的 iOS 待办（转入正常开发，不再是研究风险）

1. 正式 iOS 地图插件（GodotMapPlugin 的 iOS 孪生）：Mapbox iOS SDK（SPM）+
   `window_get_native_handle(WINDOW_VIEW)` 垫 MapView + setCamera/getPixelRatio 桥 +
   清背景逻辑内置——G3Spike.mm 即其雏形
2. 相机同步在 iOS 端复验（G2 清单同款，`presentsWithTransaction` 备用）
3. G4 性能矩阵补 iOS 侧（真机 Metal 合成开销、发热）
4. 导出链自动化：pbxproj 注入改为 Godot iOS 插件/export plugin 正规化
