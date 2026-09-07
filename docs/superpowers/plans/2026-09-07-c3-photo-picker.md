# C3 Photo Picker —— 实施记录（2026-09-07 晚）

对应 Plane SGODOT-97。目标：两端系统选图器（免相册权限）多图选取回 Godot，压缩 / 尺寸限制后给 feed 发布器（B3）
与 IM 图片消息（B2）。

## 1. 结构：三层

| 层 | 位置 | 说明 |
|---|---|---|
| GDScript 入口 | `modules/media/photo_picker.gd`（`PhotoPicker`） | `await PhotoPicker.new().pick(max_count)` → `{ok, code, items:[{path, bytes, width, height, mime}]}`；后端按可用性选：原生单例 → DisplayServer 原生文件框 → UNSUPPORTED；`picker` 可注入 |
| 预处理 | `modules/media/image_prep.gd`（`ImagePrep`） | 长边缩到 2048、转 JPEG（0.85）、带尺寸；读不出返回 `{}` |
| iOS 原生 | `native/photo_picker/`（GDExtension，godot-cpp） | `PHPickerViewController`（iOS 14+，免权限）；选完在原生层解码（HEIC 也行）、按 EXIF 摆正、缩到 max_side、JPEG 落 `NSTemporaryDirectory()/sensen_picks/`，信号 `picked(paths, error)` |
| Android 原生 | `native/photo_picker/android/`（Godot 插件 v2，Kotlin → AAR） | Android 13+ `ACTION_PICK_IMAGES`（系统 Photo Picker，免权限）；老系统 `ACTION_OPEN_DOCUMENT`；后台线程解码 + EXIF + 缩放 + JPEG 落 cacheDir；同名单例、同名信号 |
| 桌面 | `native/photo_picker/src_stub/` | 空实现，只为让编辑器 / 测试进程加载 `.gdextension` 不报错；桌面真正选图走 `DisplayServer.file_dialog_show` |

单例名统一 `SensenPhotoPicker`，方法 `is_available() / is_picking() / pick_images(max_count, max_side, jpeg_quality)`，
信号 `picked(paths: PackedStringArray, error: String)`。GDScript 层不区分平台。

## 2. 决策与坑

- **iOS 用 GDExtension 而不是 .gdip 插件**：4.x 的 iOS 插件要拿引擎头文件编，godot-cpp 是官方支持路径，也和
  SGODOT-6「iOS 桥迁 GDExtension」方向一致。godot-cpp 没有 4.7 分支，用 4.5 分支 + 本机 `godot --dump-extension-api`
  的 API 生成绑定（`build_ios.sh` 每次重 dump）；`build_profile.json` 只编五个类，几十秒。
- **PhotosUI 不用链**：`.gdextension` 没法给 Xcode 工程加系统框架，代码里 `dlopen` PhotosUI，类名全部
  `NSClassFromString`，编译期不产生框架符号引用。
- **静态库要合成一个**：Godot 导出的 Xcode 工程只链 `.gdextension` 里那一个 `.a`，`libtool -static` 把 godot-cpp
  合进来。导出后 `nm` 确认 `sensen_photo_picker_init` 在可执行文件里（Godot 用 `-Wl,-U` + dlsym 找它）。
- **桌面要有库**：导出（无头编辑器）会把 `.gdextension` 写进 `.godot/extension_list.cfg`，之后桌面每次启动
  报三行「No GDExtension library found」——所以有 macOS 空实现。构建产物（iOS .a、macOS .dylib）**进仓库**，
  免得没装工具链的人导出失败；`android/bin` 的 AAR 同理待定。
- **Android 编译**：本机没有 gradle / JDK，用 Android Studio 自带 jbr + gradle wrapper；`org.godotengine:godot:4.7.2.stable`
  是 Kotlin 2.x 编的，插件也要 Kotlin 2.1 + AGP 8.7。AndroidX 要 `android.useAndroidX=true`。
- `build/` 加了 `.gdignore`：导出输出里的 Apple 优化 PNG（CgBI）会让编辑器扫描时报 ERR_FILE_CORRUPT。

## 3. 验证

- 单测 `tests/media/test_photo_picker.gd`（4）：缩图转 JPEG、坏文件跳过、注入 picker 按上限截断、测试进程无原生单例。
- 真机：探针页多了「Pick photos」和 `picker: native/dialog/none` 标签；`SENSEN_QA_PICK=1` 让 social 流在探针页
  弹选图器，人选完截 `photos_picked`。iPhone 13 上标签显示 `picker: native`（GDExtension 已装进包并加载）。

## 4. 待做

- 把 `PhotoPicker.pick()` 接进聊天页（图片消息）与 feed 发布器（多图）；上传要 R2 真桶或开发期本地存储。
- Android 真机验证（本机没有 Android 设备）；AAR 是否进仓库。
- template_release 版 iOS 静态库（发布链 SGODOT-70）。
