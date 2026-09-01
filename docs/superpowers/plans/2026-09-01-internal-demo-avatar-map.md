# 2026-09-04 内部 Demo 实施计划：avatar + 地图端到端

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让决策者在一台 Android 真机上点完「打开 → 落在真实位置 → 周围有路人角色和留言气泡 → 拖拽有惯性、双击平滑放大 → 进换装房换一身 → 回地图角色已更新」这条链。

**Architecture:** 沿用已验证的方案 A——Mapbox 原生 MapView 垫底 + Godot 透明层渲染角色，单一权威位姿在 Godot。本次新增：定位驱动的「home 锚点」概念（自己 + 近处路人 + 全部 marker 都相对 home 摆放，不写绝对经纬度）、部件 denylist、design token 层。

**Tech Stack:** Godot 4.7.2 / GDScript / gdUnit4；Android 插件 Kotlin（GodotPlugin v2）；Mapbox Maps SDK v11。

**Spec:** `docs/superpowers/specs/2026-09-01-internal-demo-avatar-map-design.md`（commit 68f7d82）

## Global Constraints

- **测试基线**：现有 110 用例必须保持全绿，新增测试累加。跑法 `tools/run_tests.sh`，单目录 `tools/run_tests.sh res://tests/map`。
- **Android targetSdk = 36**（`export_presets.cfg:31` 的 `gradle_build/target_sdk` 为空 → 取 Godot 默认，`godot-src/platform/android/java/app/config.gradle:9`）。targetSdk ≥ 31 时**单独请求 `ACCESS_FINE_LOCATION` 会被系统直接忽略**：必须 manifest 同时声明 FINE + COARSE，并用 `OS.request_permissions()`（**复数**）一次提交。单数版 `OS.request_permission("...")` 是静默失败陷阱（两个方法都存在，`godot-src/core/core_bind.cpp:856-857`）。
- **演示内容一律相对 home 锚点存储**，不得写死经纬度。pawn 存的是绝对经纬度且 `_teleport()` 只重投影不改坐标（`map_poc.gd:222`），写死会让用户定位到非上海时所有内容落到 `CULL_FACTOR = 4.0` 之外被剔除。
- **`assets/avatar/parts_manifest.json` 是管线产物**，`tools/pipeline/extract_parts.gd:25-32` 每次转换全量覆写，**禁止往里手工加字段**。
- **主题类型变体不得删除**：`AccentButton`、`AccentPillButton`、`PillButton`、`RoundButton`、`ChipPanel`（`tests/ui/test_app_theme.gd:39-48` 守护，删一个对应场景就静默回退成默认灰按钮）。
- **48dp 触摸目标不得破坏**：`Button` stylebox 的 `content_margin_top/bottom = 14.0`、`left/right = 16.0`、`default_font_size = 16`（同上测试守护）。
- **缩放基准不得改**：`canvas_items` + `expand`，viewport 360x640，桌面 override 720x1280。
- **主色**：`#34D399`，按下态 `#059669`。
- **插件信号必须 `CONNECT_DEFERRED`**（Android UI 线程 emitSignal，不 deferred 直接碰场景树会炸）。`MapboxMap` 是 `@MainThread` API，读状态只能走 UI 线程写入的缓存。
- **不得回退移动端列表滚动机制**（PASS 冒泡 + 全局死区 24，引擎 `NOTIFICATION_SCROLL_BEGIN`）。
- 提交信息用中文，沿用现有 `git log` 风格（`feat:` / `fix:` / `spec:` 前缀 + 中文正文）。

## 与 spec 的两处偏差（已在对应任务里说明理由）

1. **定位实现改用 AOSP `LocationManager`，不做 Mapbox provider 的 30 分钟验证。** spec §6③ 把 Mapbox 自带 provider 列为优先路径，理由是「省掉 Play Services 依赖」——但 `LocationManager` 是 AOSP 框架 API，**同样零额外依赖**，且没有 API 形状的不确定性。既然优选理由不成立，直接走退路是严格更优：省掉 30 分钟验证，也消掉 spec §8 里「provider 走不通 +0.3 天吃光缓冲」这条风险。首次定影慢的问题用 `getLastKnownLocation()`（两个 provider 取最新）先补一发解决。
2. **Task 1 比 spec 写的更小。** spec §6① 说要「null 时回落 `default_config()`」，但 `Avatar.load_outfit()`（`modules/avatar/avatar_service.gd:33-35`）**已经内置了这个回落**——返回 null 的是底层 `LocalOutfitStore`，门面已经守卫过了。所以只需换一个调用，不需要额外守卫。

## File Structure

**新建**
| 文件 | 职责 |
|---|---|
| `modules/ui/design_tokens.gd` | 设计取值单一来源（色板/间距/圆角/字阶/触摸目标） |
| `assets/avatar/demo_denylist.json` | demo 部件剔除名单（独立于管线产物） |
| `scenes/map_poc/demo_markers.json` | 留言 marker 假数据，坐标为相对 home 的米偏移 |
| `scenes/map_poc/marker_layer.gd` | marker 图钉 + 气泡的 Control 层，负责地理→屏幕投影与显隐 |
| `tests/map/test_map_self_outfit.gd` | 换装闭环回归 |
| `tests/map/test_map_bridge_location.gd` | MapBridge 定位契约 |
| `tests/map/test_map_home_anchoring.gd` | 定位重锚（一票否决项）回归 |
| `tests/map/test_map_fling.gd` | 惯性与双击判定 |
| `tests/map/test_marker_layer.gd` | marker 相对锚定与数据完整性 |
| `tests/catalog/test_demo_denylist.gd` | denylist 过滤回归 |
| `tests/ui/test_design_tokens.gd` | token 与主题同源 |

**修改**
| 文件 | 改动 |
|---|---|
| `scenes/map_poc/map_poc.gd` | 换装闭环、home 重锚、marker 层挂载、惯性/双击 |
| `scenes/map_poc/map_bridge.gd` | 加 `location_update` 信号与 `start_location()` 默认空转 |
| `scenes/map_poc/map_bridge_android.gd` | 权限请求 + 定位信号转发 |
| `modules/avatar/catalog/part_catalog.gd` | `apply_denylist()` / `load_denylist()` |
| `modules/avatar/avatar_service.gd` | 载入 denylist |
| `tools/android/overlay/AndroidManifest.xml` | FINE + COARSE 权限声明 |
| `tools/android/overlay/GodotMapPlugin.kt` | `location_update` 信号 + `startLocation()` |
| `assets/ui/app_theme.tres` | 取值对齐 design token |
| `tools/unity_export/samples.json` | 补普通部件 |

`scenes/map_poc/map_bridge_ios.gd` **不改**——基类的 `start_location()` 是空转，iOS 直接继承，场景靠 3 秒超时回落默认点。`map_poc.tscn` 也**不改**——marker 层在代码里创建挂载，避免手工编辑场景文件。

---

### Task 1: 换装闭环回写地图

**Files:**
- Modify: `scenes/map_poc/map_poc.gd:331-333`
- Test: `tests/map/test_map_self_outfit.gd`（新建）

**Interfaces:**
- Consumes: `Avatar.load_outfit() -> AvatarConfig`（已存在，内部已回落默认装扮）
- Produces: `map_poc.gd` 的 `self_config() -> AvatarConfig`，Task 4 的 `_spawn_home_cohort()` 会调用它

- [ ] **Step 1: 写失败测试**

新建 `tests/map/test_map_self_outfit.gd`：

```gdscript
extends GdUnitTestSuite
## 回归：地图上"我"的角色必须读换装房存档，而不是默认装扮。
## 历史缺陷：map_poc.gd 写死 Avatar.slot_table.default_config()，换装闭环是断的。

const MapPoc := preload("res://scenes/map_poc/map_poc.gd")
const TEST_USER := "test_map_self"
const SAVE_PATH := "user://avatar/outfit_%s.json" % TEST_USER

var _prev_user := ""

func before_test() -> void:
	_prev_user = Avatar.user_id
	Avatar.user_id = TEST_USER

func after_test() -> void:
	Avatar.user_id = _prev_user
	DirAccess.remove_absolute(SAVE_PATH)

func test_self_config_reads_saved_outfit() -> void:
	var pool := Avatar.catalog.parts_for_slot(&"hairHat")
	if pool.size() < 2:
		push_warning("转换产物缺失或部件不足，跳过")
		return
	var cfg := Avatar.slot_table.default_config()
	var want: String = pool[pool.size() - 1].id
	cfg.slots[&"hairHat"] = want
	assert_int(Avatar.save_outfit(cfg)).is_equal(OK)

	var node = auto_free(MapPoc.new())
	assert_str(str(node.self_config().slots[&"hairHat"])).is_equal(want)

func test_self_config_falls_back_when_no_save() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	var node = auto_free(MapPoc.new())
	assert_object(node.self_config()).is_not_null()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/map/test_map_self_outfit.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'self_config' in base 'Node3D'`

- [ ] **Step 3: 实现**

在 `scenes/map_poc/map_poc.gd` 的 `_spawn_pawns()` 上方新增：

```gdscript
## 自己的角色装扮：读换装房存档。Avatar.load_outfit()（avatar_service.gd:33-35）
## 内部已在无存档时回落 slot_table.default_config()，此处不需要再守卫 null。
func self_config() -> AvatarConfig:
	return Avatar.load_outfit()
```

把 `_spawn_pawns()` 里的第一行改掉：

```gdscript
func _spawn_pawns() -> void:
	# 自己：固定站在初始地图中心，读换装房存档（立即生成）
	_add_pawn(START_LAT, START_LNG, self_config(), "idle")
```

- [ ] **Step 4: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/map/test_map_self_outfit.gd`
Expected: PASS（2 个用例）

- [ ] **Step 5: 跑全量回归**

Run: `tools/run_tests.sh`
Expected: 全绿，用例数 = 110 + 2

- [ ] **Step 6: 提交**

```bash
git add scenes/map_poc/map_poc.gd tests/map/test_map_self_outfit.gd
git commit -m "feat(demo): 地图上的自己读换装房存档，打通换装闭环

map_poc 原先写死 slot_table.default_config()，换完装回地图看不到变化。
Avatar.load_outfit() 已内置无存档回落，直接换调用即可。
场景切换用 change_scene_to_file（整场景重建），返回刷新是免费的，不需要刷新机制。"
```

---

### Task 2: MapBridge 定位接口

**Files:**
- Modify: `scenes/map_poc/map_bridge.gd`、`scenes/map_poc/map_bridge_android.gd`
- Test: `tests/map/test_map_bridge_location.gd`（新建）

**Interfaces:**
- Produces:
  - `MapBridge` 信号 `location_update(lat: float, lng: float, accuracy: float)` — Task 4 连接它
  - `MapBridge.start_location() -> void` — 默认空转；Task 4 调用它
  - `MapBridgeAndroid` 覆写 `start_location()` 与 `poll()`
- Consumes: Task 3 提供的插件方法 `startLocation()` 与插件信号 `location_update`

- [ ] **Step 1: 写失败测试**

新建 `tests/map/test_map_bridge_location.gd`：

```gdscript
extends GdUnitTestSuite
## MapBridge 定位契约：接口必须存在且默认空转。
## iOS/桌面没有定位实现，直接继承基类空转，场景靠 3 秒超时回落默认点——
## 抽象层不能因为某个平台没实现就在场景里写 if platform。

func test_base_bridge_exposes_location_contract() -> void:
	var b := MapBridge.new()
	assert_bool(b.has_signal("location_update")).is_true()
	assert_bool(b.has_method("start_location")).is_true()
	b.start_location() # 默认实现必须安全空转，不抛错

func test_ios_bridge_inherits_noop_location() -> void:
	## iOS 桥不覆写定位：继承基类空转即可，别在 iOS 侧写半吊子实现
	var b := MapBridgeIOS.new()
	assert_bool(b.has_signal("location_update")).is_true()
	b.start_location()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/map/test_map_bridge_location.gd`
Expected: FAIL — `has_signal("location_update")` 返回 false

- [ ] **Step 3: 基类加接口**

在 `scenes/map_poc/map_bridge.gd` 的 `signal map_ready` 下方新增：

```gdscript
## 定位回传（Android 实现发出；无定位能力的平台不发）。accuracy 单位米，越小越准。
signal location_update(lat: float, lng: float, accuracy: float)
```

在 `poll()` 上方新增：

```gdscript
## 启动定位订阅（含运行时权限）。默认空转——iOS/桌面无实现，
## 调用方（map_poc）靠 HOME_TIMEOUT_S 超时回落默认点。
func start_location() -> void:
	pass
```

- [ ] **Step 4: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/map/test_map_bridge_location.gd`
Expected: PASS（2 个用例）

- [ ] **Step 5: Android 桥实现**

把 `scenes/map_poc/map_bridge_android.gd` 整体替换为：

```gdscript
class_name MapBridgeAndroid
extends MapBridge
## Android 实现：包装 GodotMap 插件 singleton（GodotMapPlugin.kt）。

## Android 12+（本工程 targetSdk 取 Godot 默认 36）要求 FINE 与 COARSE 在同一次
## 运行时请求里提交，否则系统直接忽略。OS.request_permissions()（复数）一次提交
## manifest 中全部危险权限；单数版 OS.request_permission("...FINE_LOCATION")
## 会静默失败（无弹窗、无回调）——这是本模块最容易翻车的点。
const LOCATION_PERMS := [
	"android.permission.ACCESS_FINE_LOCATION",
	"android.permission.ACCESS_COARSE_LOCATION",
]
## 授权对话框的等待上限（poll 帧数）。用户点"拒绝"后不该无限轮询。
const PERMISSION_POLL_LIMIT := 600
const PERMISSION_POLL_EVERY := 15

var _plugin: Object
var _awaiting_permission := false
var _poll_frames := 0

func _init() -> void:
	_plugin = Engine.get_singleton("GodotMap")
	# 插件在 Android UI 线程 emitSignal，必须 deferred 回主循环再碰场景树
	_plugin.connect("map_ready", func(): map_ready.emit(), CONNECT_DEFERRED)
	_plugin.connect("location_update",
		func(lat: float, lng: float, acc: float): location_update.emit(lat, lng, acc),
		CONNECT_DEFERRED)

func create_map(token: String, lat: float, lng: float, zoom: float) -> void:
	_plugin.createMap(token, lat, lng, zoom)

func set_camera(lat: float, lng: float, zoom: float, bearing: float, pitch: float) -> void:
	_plugin.setCamera(lat, lng, zoom, bearing, pitch)

func set_map_visible(visible: bool) -> void:
	_plugin.setMapVisible(visible)

func get_pixel_ratio() -> float:
	return maxf(float(_plugin.getPixelRatio()), 0.5)

func camera_info() -> String:
	return _plugin.getCameraInfo()

func start_location() -> void:
	if _has_location_permission():
		_plugin.startLocation()
		return
	OS.request_permissions()
	_awaiting_permission = true
	_poll_frames = 0

## request_permissions() 是异步的（系统弹窗），授权结果没有 GDScript 信号，
## 只能轮询 get_granted_permissions()。授权到手就启动定位；拒绝或超时就放弃，
## 场景那边的 3 秒超时会接管回落。
func poll() -> void:
	if not _awaiting_permission:
		return
	_poll_frames += 1
	if _poll_frames > PERMISSION_POLL_LIMIT:
		_awaiting_permission = false
		push_warning("MapBridgeAndroid: 定位授权等待超时，放弃定位")
		return
	if _poll_frames % PERMISSION_POLL_EVERY != 0:
		return
	if _has_location_permission():
		_awaiting_permission = false
		_plugin.startLocation()

func _has_location_permission() -> bool:
	var granted := OS.get_granted_permissions()
	for p in LOCATION_PERMS:
		if granted.has(p):
			return true
	return false
```

- [ ] **Step 6: 跑全量回归**

Run: `tools/run_tests.sh`
Expected: 全绿，用例数 = 112 + 2

- [ ] **Step 7: 提交**

```bash
git add scenes/map_poc/map_bridge.gd scenes/map_poc/map_bridge_android.gd tests/map/test_map_bridge_location.gd
git commit -m "feat(demo): MapBridge 加定位接口，Android 侧走 request_permissions 复数版

targetSdk 36 下单独请求 FINE 会被系统忽略，必须用 OS.request_permissions()
一次提交 manifest 里的 FINE+COARSE。授权结果无 GDScript 信号，靠 poll()
轮询 get_granted_permissions()，拒绝或 600 帧超时即放弃。
iOS/桌面继承基类空转，场景靠超时回落。"
```

---

### Task 3: Android 插件定位实现 + manifest 权限

**Files:**
- Modify: `tools/android/overlay/AndroidManifest.xml:19-20`（追加）、`tools/android/overlay/GodotMapPlugin.kt`

**Interfaces:**
- Produces: 插件方法 `startLocation()`、插件信号 `location_update(Double, Double, Double)` — Task 2 的 Android 桥消费

本任务是 Kotlin，**没有单元测试**——验证靠 Task 10 的真机构建。GDScript 侧的契约已由 Task 2 覆盖。

**为什么不用 Mapbox 自带的 location provider**（偏离 spec §6③ 的优先路径）：spec 选它的理由是「省掉 Play Services 依赖」，但 `LocationManager` 是 AOSP 框架 API，同样零额外依赖，而且没有 API 形状的不确定性。既然优选理由不成立，直接用确定能跑的那条，顺带消掉 spec §8 里「provider 走不通 +0.3 天」这条风险。

- [ ] **Step 1: manifest 加权限**

在 `tools/android/overlay/AndroidManifest.xml` 第 20 行（`ACCESS_NETWORK_STATE` 那行）之后插入：

```xml
    <!-- 定位：Android 12+（targetSdk≥31）必须同时声明 FINE 与 COARSE，并在同一次
         运行时请求中提交；只声明/只请求 FINE 会被系统直接忽略（无弹窗无回调）。 -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

- [ ] **Step 2: 插件加 import 与状态字段**

在 `tools/android/overlay/GodotMapPlugin.kt` 的 import 区（第 3-8 行 `android.*` 那组）补上：

```kotlin
import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
```

在 `companion object` 里 `TAG` 之后新增：

```kotlin
        /**
         * last-known 定位的时效上界。超过这个岁数的缓存定位不能用来定锚点——
         * GDScript 侧 _resolve_home() 锁的是**第一个**定位并丢弃后续更新，
         * 所以一发"上周在别的城市"的陈旧缓存会永久钉错演示位置，不会被后到的
         * 真实定位纠正。5 分钟内的定位基本等于当前位置。
         */
        private const val LAST_KNOWN_MAX_AGE_MS = 5 * 60 * 1000L
```

在 `private var mapView: MapView? = null`（第 33 行）之后新增：

```kotlin
    private var locationManager: LocationManager? = null
    private var locationStarted = false

    private val locationListener = LocationListener { loc -> emitLocation(loc) }

    private fun emitLocation(loc: Location) {
        emitSignal("location_update", loc.latitude, loc.longitude, loc.accuracy.toDouble())
    }
```

- [ ] **Step 3: 注册信号**

把 `getPluginSignals()`（第 42-44 行）替换为：

```kotlin
    override fun getPluginSignals() = setOf(
        SignalInfo("map_ready"),
        SignalInfo(
            "location_update",
            Double::class.javaObjectType,
            Double::class.javaObjectType,
            Double::class.javaObjectType,
        ),
    )
```

- [ ] **Step 4: 实现 startLocation()**

在 `getCameraInfo()`（文件末尾）之前插入：

```kotlin
    /**
     * 启动定位订阅。权限由 GDScript 侧的 OS.request_permissions() 拿（Android 12+
     * 必须 FINE+COARSE 同请求），本方法只在已授权时工作，未授权直接放弃——
     * GDScript 那边有 3 秒超时会回落默认点。
     */
    @UsedByGodot
    fun startLocation() {
        runOnUiThread {
            if (locationStarted) return@runOnUiThread
            val act = getActivity() ?: return@runOnUiThread
            val fine = act.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
            val coarse = act.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
            if (!fine && !coarse) {
                Log.w(TAG, "定位权限未授予，startLocation 放弃（GDScript 侧靠超时回落）")
                return@runOnUiThread
            }
            val lm = act.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                ?: return@runOnUiThread
            locationManager = lm
            locationStarted = true

            // 先补一发 last-known：冷启动 GPS 首次定影可能要几十秒，而 demo 只等 3 秒。
            // 两个 provider 都取，谁的时间戳新用谁。
            val candidates = mutableListOf<Location>()
            for (p in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
                try {
                    lm.getLastKnownLocation(p)?.let(candidates::add)
                } catch (e: Exception) {
                    Log.w(TAG, "getLastKnownLocation($p) 失败: ${e.message}")
                }
            }
            // ⚠️ 必须卡时效：GDScript 侧 _resolve_home() 锁第一个定位并丢弃后续更新，
            // 陈旧缓存定位会永久钉错位置且不会被真实定位纠正。拒绝时要打日志——
            // "缓存太旧被拒"和"根本没有缓存"在 logcat 里否则长得一样，人工排查会卡住。
            candidates.maxByOrNull { it.time }?.let {
                val ageMs = System.currentTimeMillis() - it.time
                if (ageMs <= LAST_KNOWN_MAX_AGE_MS) {
                    Log.i(TAG, "last-known 定位 ${it.latitude},${it.longitude} acc=${it.accuracy}")
                    emitLocation(it)
                } else {
                    Log.i(TAG, "last-known 定位已过期 ${ageMs / 1000}s，丢弃，等实时定位")
                }
            }

            // 再订阅持续更新：有 FINE 用 GPS，只有 COARSE 就退 NETWORK
            val provider = if (fine) LocationManager.GPS_PROVIDER else LocationManager.NETWORK_PROVIDER
            try {
                lm.requestLocationUpdates(provider, 2000L, 5f, locationListener)
                Log.i(TAG, "定位订阅启动 provider=$provider")
            } catch (e: Exception) {
                Log.e(TAG, "requestLocationUpdates 失败: ${e.message}")
            }
        }
    }

    override fun onMainDestroy() {
        runOnUiThread {
            try {
                locationManager?.removeUpdates(locationListener)
            } catch (e: Exception) {
                Log.w(TAG, "removeUpdates 失败: ${e.message}")
            }
        }
        super.onMainDestroy()
    }
```

- [ ] **Step 5: 构建 APK 验证编译通过**

```bash
tools/android/setup_android_build.sh
godot --headless --path . --export-debug "Android" build/sensen-demo-debug.apk
```

Expected: 构建成功，无 Kotlin 编译错误。

- [ ] **Step 6: 装机看 logcat 确认权限弹窗与定位回传**

```bash
adb install -r build/sensen-demo-debug.apk
adb logcat -c
adb shell am start -n com.sensen.avatarphase1/com.sensen.avatarphase1.GodotAppLauncher
adb logcat | grep -E "GodotMapPlugin|location"
```

Expected：屏幕出现定位权限弹窗（**没弹窗就是踩了单数 request_permission 的坑，回 Task 2 检查**）；授权后 logcat 出现 `last-known 定位 <lat>,<lng>` 与 `定位订阅启动 provider=gps`。

- [ ] **Step 7: 提交**

```bash
git add tools/android/overlay/AndroidManifest.xml tools/android/overlay/GodotMapPlugin.kt
git commit -m "feat(demo): Android 插件定位实现（AOSP LocationManager）

manifest 同时声明 FINE+COARSE（targetSdk 36 的硬要求）。
不走 Mapbox 自带 provider：spec 选它是为了省 Play Services 依赖，
但 LocationManager 同样零依赖且无 API 不确定性，直接用确定能跑的。
先发 last-known（两个 provider 取最新）再订阅更新，规避 GPS 冷启动几十秒
而 demo 只等 3 秒的问题。onMainDestroy 里注销订阅。"
```

---

### Task 4: 演示内容相对锚定 + 延迟 spawn（一票否决项）

**Files:**
- Modify: `scenes/map_poc/map_poc.gd`
- Test: `tests/map/test_map_home_anchoring.gd`（新建）

**Interfaces:**
- Consumes: Task 1 的 `self_config()`；Task 2 的 `MapBridge.location_update` 信号与 `start_location()`
- Produces:
  - `home_lat: float` / `home_lng: float` — Task 8 的 marker 层用同一个锚点
  - `_resolve_home(lat: float, lng: float) -> void` — Task 8 在这里插一行挂 marker
  - `_spawn_home_cohort()` / `_spawn_la_fixture()` — 替代原 `_spawn_pawns()`
  - `_spawn_queue` 每项新增 `cohort` 键，取值 `"self"` / `"near"` / `"la"`

- [ ] **Step 1: 写失败测试**

新建 `tests/map/test_map_home_anchoring.gd`：

```gdscript
extends GdUnitTestSuite
## 回归（一票否决项）：定位到任何地方，自己与近处路人都必须跟着 home 锚点走。
##
## 历史缺陷：pawn 存绝对经纬度（map_poc.gd:335-341），而 _teleport() 只重投影
## 不改坐标（:222 _reposition_pawns）。定位到非上海人民广场的任何位置，近处角色
## 全部落在 CULL_FACTOR=4.0×相机距离之外被剔除，地图上空无一人——验收第一条直接挂。
##
## 洛杉矶那 10 个是跨洋剔除 + 浮动原点的压测夹具，不是演示内容，必须保持绝对坐标。

const MapPoc := preload("res://scenes/map_poc/map_poc.gd")
const TOKYO_LAT := 35.6812
const TOKYO_LNG := 139.7671

func _make() -> Node:
	var n = auto_free(MapPoc.new())
	n._rng.seed = 20260901
	return n

func test_home_cohort_follows_resolved_location() -> void:
	var n := _make()
	n._resolve_home(TOKYO_LAT, TOKYO_LNG)
	var near := 0
	for spec in n._spawn_queue:
		if spec.cohort == "la":
			continue
		near += 1
		var d := MapGeoMath.geo_to_world(spec.lat, spec.lng, TOKYO_LAT, TOKYO_LNG).length()
		assert_bool(d <= MapPoc.NEAR_SPREAD_M * 1.05).is_true()
	assert_int(near).is_equal(MapPoc.PAWNS_NEAR_COUNT + 1) # 12 路人 + 自己

func test_self_is_first_out_of_queue() -> void:
	var n := _make()
	n._resolve_home(TOKYO_LAT, TOKYO_LNG)
	assert_str(str(n._spawn_queue[0].cohort)).is_equal("self")

func test_la_fixture_keeps_absolute_coords() -> void:
	var n := _make()
	n._spawn_la_fixture()
	n._resolve_home(TOKYO_LAT, TOKYO_LNG)
	var la := 0
	for spec in n._spawn_queue:
		if spec.cohort != "la":
			continue
		la += 1
		assert_bool(absf(spec.lat - MapPoc.LA_LAT) < 0.1).is_true()
	assert_int(la).is_equal(MapPoc.PAWNS_LA_COUNT)

func test_resolve_home_is_idempotent() -> void:
	## 首个定位或超时先到者生效；后续定位更新不得再挪锚点，
	## 否则演示中途所有角色和 marker 会整体位移。
	var n := _make()
	n._resolve_home(TOKYO_LAT, TOKYO_LNG)
	var count := n._spawn_queue.size()
	n._resolve_home(1.0, 1.0)
	assert_int(n._spawn_queue.size()).is_equal(count)
	assert_float(n.home_lat).is_equal_approx(TOKYO_LAT, 1e-9)

func test_timeout_fallback_uses_shanghai_default() -> void:
	var n := _make()
	n._resolve_home(MapPoc.START_LAT, MapPoc.START_LNG)
	assert_float(n.home_lat).is_equal_approx(MapPoc.START_LAT, 1e-9)
	assert_bool(n._spawn_queue.size() > MapPoc.PAWNS_NEAR_COUNT).is_true()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/map/test_map_home_anchoring.gd`
Expected: FAIL — `Nonexistent function '_resolve_home'`

- [ ] **Step 3: 加常量与状态**

在 `scenes/map_poc/map_poc.gd` 的 `const REANCHOR_DIST_M := 3000.0` 之后新增：

```gdscript
## 等首个定位的上限；超时就用 START_LAT/LNG 当 home，演示内容照常可见。
const HOME_TIMEOUT_S := 3.0
```

在 `var _chip_locked := false` 之后新增：

```gdscript
## "我的位置"：定位成功则为真实位置，超时/无定位则回落 START_LAT/LNG。
## 自己、近处路人、全部 marker 都相对它摆放——绝不写死经纬度。
var home_lat := START_LAT
var home_lng := START_LNG
var _home_resolved := false
```

- [ ] **Step 4: 重写 spawn 逻辑**

把 `_spawn_pawns()`（第 331-342 行）整体替换为：

```gdscript
## 自己 + 近处路人，全部相对 home 摆放。绝不写死经纬度：写死的话定位到任何
## 非上海的位置，这些角色都会落在 CULL_FACTOR×相机距离之外被剔除，地图空无一人。
func _spawn_home_cohort() -> void:
	# push_front：自己排队头，第一个出队，玩家最先看到自己
	_spawn_queue.push_front({"lat": home_lat, "lng": home_lng,
		"cfg": self_config(), "anim": "idle", "cohort": "self"})
	for i in PAWNS_NEAR_COUNT:
		var off := _rand_offset_deg(NEAR_SPREAD_M, home_lat)
		_spawn_queue.append({"lat": home_lat + off.y, "lng": home_lng + off.x,
			"cfg": _random_config(), "anim": _rand_anim(), "cohort": "near"})

## 洛杉矶夹具：验证跨洋剔除 + 浮动原点重锚，不是演示内容，坐标保持绝对，
## 不跟随定位——改成相对就失去了这个夹具的意义。
func _spawn_la_fixture() -> void:
	for i in PAWNS_LA_COUNT:
		var off := _rand_offset_deg(LA_SPREAD_M, LA_LAT)
		_spawn_queue.append({"lat": LA_LAT + off.y, "lng": LA_LNG + off.x,
			"cfg": _random_config(), "anim": _rand_anim(), "cohort": "la"})

## 确定"我的位置"并把演示内容锚上去。首个有效定位与 3 秒超时先到者生效；
## 之后的定位更新不再改锚点（避免演示中途所有内容整体位移）。
func _resolve_home(lat: float, lng: float) -> void:
	if _home_resolved:
		return
	_home_resolved = true
	home_lat = lat
	home_lng = lng
	_teleport(lat, lng)
	_spawn_home_cohort()

func _on_location_update(lat: float, lng: float, _accuracy: float) -> void:
	_resolve_home(lat, lng)
```

- [ ] **Step 5: 改 `_ready()` 接线**

把 `_ready()`（第 79-108 行）替换为：

```gdscript
func _ready() -> void:
	_rng.seed = 20260829 # 固定种子：装机验证时角色分布可复现
	get_viewport().transparent_bg = true
	$Sun.rotation_degrees = Vector3(-55, 30, 0)
	_spawn_la_fixture() # 压测夹具先排队；home 队列等定位确定后再插
	_wire_buttons()

	# 窗口尺寸变化（旋屏/分屏/折叠屏）会改变两层的像素↔米换算基准，必须重推相机
	get_viewport().size_changed.connect(func(): _camera_dirty = true)

	map = _make_bridge()
	if map:
		map.map_ready.connect(_on_map_ready)
		map.location_update.connect(_on_location_update)
		map.set_map_visible(true)
		pixel_ratio = map.get_pixel_ratio()
		var token := _load_token()
		if token.is_empty():
			_set_dot(DOT_ERR, false)
			chip_title.text = "缺少地图密钥"
			chip_sub.text = "在工程根放置 mapbox_token.txt 后重新构建"
			_chip_locked = true
		else:
			map.create_map(token, START_LAT, START_LNG, zoom)
			_set_dot(DOT_WAIT, true) # 连接中：呼吸闪烁
		map.start_location()
	else:
		_set_dot(DOT_WAIT, false)
		chip_title.text = "地图预览"
		chip_sub.text = "桌面运行，无地图插件"
		_chip_locked = true
	# 定位兜底：拒绝授权 / 定位慢 / 桌面无插件，3 秒后一律回落上海默认点。
	# 没有这条，_spawn_home_cohort 永远不会被调用，地图上只剩洛杉矶夹具。
	get_tree().create_timer(HOME_TIMEOUT_S).timeout.connect(
		func(): _resolve_home(START_LAT, START_LNG))
	_camera_dirty = true
```

- [ ] **Step 6: 改「飞洛杉矶」与芯片文案**

把 `_on_fly_pressed()`（第 275-278 行）替换为：

```gdscript
func _on_fly_pressed() -> void:
	_in_la = not _in_la
	fly_btn.text = "回我的位置" if _in_la else "飞洛杉矶"
	_teleport(LA_LAT, LA_LNG) if _in_la else _teleport(home_lat, home_lng)
```

把 `_refresh_chip()` 里的标题行（第 142 行）改成：

```gdscript
	chip_title.text = "洛杉矶" if _in_la else "我的位置"
```

- [ ] **Step 7: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/map/test_map_home_anchoring.gd`
Expected: PASS（5 个用例）

- [ ] **Step 8: 跑全量回归**

Run: `tools/run_tests.sh`
Expected: 全绿，用例数 = 114 + 5

- [ ] **Step 9: 提交**

```bash
git add scenes/map_poc/map_poc.gd tests/map/test_map_home_anchoring.gd
git commit -m "fix(demo): 演示内容跟随定位重锚，修掉'定位到非上海就空无一人'

pawn 存的是绝对经纬度，_teleport() 只重投影不改坐标，所以定位一旦落在
上海人民广场之外，近处角色全被 CULL_FACTOR=4.0 剔除，地图上一个人没有。
改法：自己+近处路人改相对 home 摆放，等首个定位或 3 秒超时确定 home 后
再入队 spawn（避免先按上海生成再挪动的可见跳变）。
洛杉矶那 10 个是跨洋剔除/浮动原点的压测夹具，保持绝对坐标不动。"
```

---

### Task 5: 部件 denylist 过滤

**Files:**
- Create: `assets/avatar/demo_denylist.json`
- Modify: `modules/avatar/catalog/part_catalog.gd`、`modules/avatar/avatar_service.gd`
- Test: `tests/catalog/test_demo_denylist.gd`（新建）

**Interfaces:**
- Produces:
  - `PartCatalog.apply_denylist(ids: PackedStringArray) -> int`（返回实际剔除数）
  - `PartCatalog.load_denylist(path: String) -> PackedStringArray`（static）

- [ ] **Step 1: 写失败测试**

新建 `tests/catalog/test_demo_denylist.gd`：

```gdscript
extends GdUnitTestSuite
## demo denylist：剔除的部件不得出现在 parts_for_slot()——换装列表与地图随机
## 路人配置池都走它。
##
## 名单必须独立于 assets/avatar/parts_manifest.json：后者是管线产物，
## tools/pipeline/extract_parts.gd:25-32 每次转换全量重建后覆写，
## 手工写进去的字段会被静默擦除，隐藏部件下次转换后又冒出来。

const MANIFEST := "res://assets/avatar/parts_manifest.json"
const TMP := "user://test_denylist.json"

func after_test() -> void:
	DirAccess.remove_absolute(TMP)

func _write(text: String) -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func test_denied_part_disappears_from_slot_pool() -> void:
	var cat := PartCatalog.load_from_file(MANIFEST)
	if cat == null:
		push_warning("转换产物缺失，跳过")
		return
	var pool := cat.parts_for_slot(&"hairHat")
	assert_bool(pool.size() >= 2).is_true()
	var victim: String = pool[0].id
	var before := pool.size()
	assert_int(cat.apply_denylist(PackedStringArray([victim]))).is_equal(1)
	assert_int(cat.parts_for_slot(&"hairHat").size()).is_equal(before - 1)
	assert_bool(cat.has_part(victim)).is_false()

func test_unknown_id_is_ignored_not_error() -> void:
	var cat := PartCatalog.load_from_file(MANIFEST)
	if cat == null:
		return
	assert_int(cat.apply_denylist(PackedStringArray(["no_such_part"]))).is_equal(0)

func test_load_denylist_parses_ids() -> void:
	_write('{"version": 1, "hidden": ["a", "b"]}')
	var ids := PartCatalog.load_denylist(TMP)
	assert_int(ids.size()).is_equal(2)
	assert_str(ids[0]).is_equal("a")

func test_load_denylist_rejects_bad_version() -> void:
	_write('{"version": 99, "hidden": ["a"]}')
	assert_int(PartCatalog.load_denylist(TMP).size()).is_equal(0)

func test_missing_file_is_empty_not_error() -> void:
	assert_int(PartCatalog.load_denylist("user://definitely_not_here.json").size()).is_equal(0)

func test_shipped_denylist_file_is_valid() -> void:
	## 不能只调一次 load_denylist 就算验过：它对"格式正确但名单为空"和"格式写坏"
	## 都返回空数组，两者观察不到区别。所以独立解析一遍 JSON 做对照。
	## Step 7 要人工手改这个文件，写坏了只会静默变成"没剔除任何东西"。
	var path := "res://assets/avatar/demo_denylist.json"
	assert_bool(FileAccess.file_exists(path)).is_true()
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_int(typeof(data)).is_equal(TYPE_DICTIONARY)
	assert_int(int(data.get("version", -1))).is_equal(PartCatalog.DENYLIST_VERSION)
	assert_int(typeof(data.get("hidden"))).is_equal(TYPE_ARRAY)
	var hidden: Array = data.get("hidden")
	assert_int(PartCatalog.load_denylist(path).size()).is_equal(hidden.size())
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/catalog/test_demo_denylist.gd`
Expected: FAIL — `Nonexistent function 'apply_denylist'`

- [ ] **Step 3: PartCatalog 加两个方法**

在 `modules/avatar/catalog/part_catalog.gd` 的 `const REQUIRED_FIELDS` 之后新增：

```gdscript
const DENYLIST_VERSION := 1
```

在文件末尾（`all_ids()` 之后）新增：

```gdscript
## 从可选集合里剔除若干部件（付费高级部件在统一 toon shader 下呈平面色，
## 本周不做专用 shader，先不让它们出现在换装列表和随机路人池里）。
## 返回实际剔除数量；名单里不存在的 id 静默忽略。
func apply_denylist(ids: PackedStringArray) -> int:
	var removed := 0
	for id in ids:
		var meta: AvatarPartMeta = _by_id.get(id)
		if meta == null:
			continue
		_by_id.erase(id)
		var arr: Array = _by_slot.get(meta.slot, [])
		arr.erase(meta)
		removed += 1
	return removed

## 读 demo 剔除名单。**独立于 parts_manifest.json**——后者是管线产物，
## extract_parts.gd 每次转换全量覆写，写进去的标记必被擦除。
## 文件缺失或格式非法都返回空数组（不剔除），不阻断启动。
static func load_denylist(path: String) -> PackedStringArray:
	if not FileAccess.file_exists(path):
		return PackedStringArray()
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != DENYLIST_VERSION:
		push_warning("PartCatalog: denylist 版本/格式非法 %s" % path)
		return PackedStringArray()
	var raw = data.get("hidden")
	if typeof(raw) != TYPE_ARRAY:
		push_warning("PartCatalog: denylist 缺 hidden 数组 %s" % path)
		return PackedStringArray()
	var out := PackedStringArray()
	for x in raw:
		out.append(str(x))
	return out
```

- [ ] **Step 4: 建名单文件**

新建 `assets/avatar/demo_denylist.json`：

```json
{
	"version": 1,
	"hidden": []
}
```

- [ ] **Step 5: AvatarService 载入名单**

在 `modules/avatar/avatar_service.gd` 的 `const BASE_RIG_SCENE` 之后新增：

```gdscript
## demo 部件剔除名单。独立文件而非 manifest 字段——manifest 是管线产物会被覆写。
const DENYLIST_PATH := "res://assets/avatar/demo_denylist.json"
```

把 `_ready()` 里 catalog 那段（第 16-19 行）改成：

```gdscript
	catalog = PartCatalog.load_from_file(MANIFEST_PATH)
	if catalog == null:
		push_error("AvatarService: manifest 加载失败，先运行转换管线")
		catalog = PartCatalog.new()
	var denied := catalog.apply_denylist(PartCatalog.load_denylist(DENYLIST_PATH))
	if denied > 0:
		print("AvatarService: demo denylist 剔除 %d 个部件" % denied)
```

- [ ] **Step 6: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/catalog/test_demo_denylist.gd`
Expected: PASS（6 个用例）

- [ ] **Step 7: 出基线 APK，交决策者确认剔除名单**

```bash
tools/android/setup_android_build.sh
godot --headless --path . --export-debug "Android" build/sensen-demo-debug.apk
adb install -r build/sensen-demo-debug.apk
```

在换装房逐个槽位翻一遍，**每个部件截图**，交决策者圈出效果差的（`spec §6②`：不由实施者单方面判"难看"）。把决策者圈定的 id 填进 `assets/avatar/demo_denylist.json` 的 `hidden` 数组。

- [ ] **Step 8: 填名单后再跑一次全量回归**

Run: `tools/run_tests.sh`
Expected: 全绿，用例数 = 119 + 6

- [ ] **Step 9: 提交**

```bash
git add modules/avatar/catalog/part_catalog.gd modules/avatar/avatar_service.gd \
        assets/avatar/demo_denylist.json tests/catalog/test_demo_denylist.gd
git commit -m "feat(demo): 部件 denylist 过滤，剔除效果差的付费高级部件

名单放独立文件而不是 parts_manifest.json：后者是管线产物，
extract_parts.gd 每次转换全量覆写，手工加的字段会被静默擦除。
独立名单还有个好处——调名单不用重跑转换。
不能用 tier 字段筛：tier 是'保留 AnimationPlayer'标记，不是付费等级。"
```

---

### Task 6: 补普通部件填充池子

**Files:**
- Modify: `tools/unity_export/samples.json`、必要时 `tools/unity_export/overrides.json`
- 产物: `assets/avatar/parts_manifest.json`、`assets/avatar/parts/*.res`

**Interfaces:**
- Consumes: Task 5 的 denylist（剔除后池子会变小，本任务补回来）
- Produces: 更多可选部件；`tests/pipeline/test_converted_assets.gd` 覆盖产物完整性

当前只迁移了 15 个部件（hairHat 4、cloth 4、shoes 2、glass 2、body/eyes/messengerBag 各 1），再剔掉几个换装房会显得空。

- [ ] **Step 1: 列出 Unity 侧可选资产**

```bash
ls -1 /Volumes/ACASIS/projects/sensen-unity/Assets/_Gensen/Characters/AvatarPaks/
ls -1 /Volumes/ACASIS/projects/sensen-unity/Assets/_Gensen/Characters/AvatarPaks/hairHat/
ls -1 /Volumes/ACASIS/projects/sensen-unity/Assets/_Gensen/Characters/AvatarPaks/skin01/
```

从中挑 8-10 个**普通**部件（避开决策者在 Task 5 圈出的那类），优先补池子最薄的槽位（shoes、glass、messengerBag 各只有 1-2 个）。

- [ ] **Step 2: 追加进 samples.json**

`tools/unity_export/samples.json` 的数组里按现有格式追加，`tier` 一律填 `0`（tier 1 表示"保留 AnimationPlayer"，普通部件不需要）：

```json
    { "asset": "ap_shoes2",        "tier": 0 },
    { "asset": "ap_glass2",        "tier": 0 }
```

- [ ] **Step 3: 跑转换管线**

```bash
python3 tools/unity_export/convert.py
godot --headless --path . --script tools/pipeline/extract_parts.gd
```

Expected: 输出 `提取完成: N 部件, 0 错误`，N > 15。

- [ ] **Step 4: 处理命名漂移**

若报 `找不到 FBX` / `找不到 albedo 贴图`，在 `tools/unity_export/overrides.json` 里按现有条目格式定点修正（已知漂移：`T_xxx_D 1.png` 副本尾巴、`bag ≠ messengerBag`、socket 件网格在 `BaseCharacter/Models/` 而非部件目录）：

```json
  "shoes2": {
    "albedo": "Assets/_Gensen/Characters/AvatarPaks/.../T_xxx_shoes_D 1.png"
  }
```

改完重跑 Step 3。

**降级条件**：若 Step 4 反复失败超过 1 小时，按 spec §8 直接放弃本任务——不补新部件，只保留 Task 5 的剔除，接受池子偏小。回滚 `samples.json` 即可，其它任务不受影响。

- [ ] **Step 5: 确认 denylist 仍然生效**

Run: `tools/run_tests.sh res://tests/catalog/test_demo_denylist.gd`
Expected: PASS —— 这一步就是在验证「重跑转换后 denylist 不被擦除」（denylist 是独立文件，转换只覆写 manifest）。

- [ ] **Step 6: 跑全量回归**

Run: `tools/run_tests.sh`
Expected: 全绿（`tests/pipeline/test_converted_assets.gd` 会校验新产物）

- [ ] **Step 7: 提交**

```bash
git add tools/unity_export/samples.json tools/unity_export/overrides.json \
        assets/avatar/parts_manifest.json assets/avatar/parts
git commit -m "feat(demo): 补普通部件填充换装池

剔除效果差的部件后池子偏薄，补 8-10 个普通部件（优先 shoes/glass/bag 这几个
只有 1-2 个的槽位）。denylist 是独立文件，重跑转换不受影响。"
```

---

### Task 7: design token + 主题重铸

**Files:**
- Create: `modules/ui/design_tokens.gd`
- Modify: `assets/ui/app_theme.tres`
- Test: `tests/ui/test_design_tokens.gd`（新建）

**Interfaces:**
- Produces: `DesignTokens`（全局 class_name）— Task 8 的气泡样式引用它

必须排在 Task 8 之前，让 marker 气泡直接用 token，避免返工。

- [ ] **Step 1: 写失败测试**

新建 `tests/ui/test_design_tokens.gd`：

```gdscript
extends GdUnitTestSuite
## design token 与主题同源：主题里的关键取值必须能在 DesignTokens 找到对应常量。
## 下周设计会换风格时，这些断言保证"改 token + 同步主题"就够，不会有散落的硬编码。
## 注意本套断言与 tests/ui/test_app_theme.gd 是互补的：那边守 48dp 触摸目标与
## 类型变体存在性，这边守取值来源统一。

const THEME_PATH := "res://assets/ui/app_theme.tres"

func _theme() -> Theme:
	return load(THEME_PATH) as Theme

func test_accent_matches_token() -> void:
	var sb := _theme().get_stylebox(&"normal", &"AccentButton") as StyleBoxFlat
	assert_object(sb).is_not_null()
	assert_bool(sb.bg_color.is_equal_approx(DesignTokens.ACCENT)).is_true()

func test_accent_pressed_matches_deep_token() -> void:
	var sb := _theme().get_stylebox(&"pressed", &"AccentButton") as StyleBoxFlat
	assert_bool(sb.bg_color.is_equal_approx(DesignTokens.ACCENT_DEEP)).is_true()

func test_body_font_size_is_token_default() -> void:
	assert_int(_theme().default_font_size).is_equal(DesignTokens.FONT_BODY)

func test_font_scale_is_five_strictly_descending_steps() -> void:
	var steps := [DesignTokens.FONT_TITLE, DesignTokens.FONT_BODY,
		DesignTokens.FONT_LABEL, DesignTokens.FONT_CAPTION, DesignTokens.FONT_MICRO]
	for i in steps.size() - 1:
		assert_bool(steps[i] > steps[i + 1]).is_true()

func test_spacing_grid_is_4dp_multiples() -> void:
	for v in [DesignTokens.SPACE_1, DesignTokens.SPACE_2, DesignTokens.SPACE_3,
			DesignTokens.SPACE_4, DesignTokens.SPACE_6]:
		assert_int(v % 4).is_equal(0)

func test_container_separation_uses_space_2() -> void:
	var t := _theme()
	assert_int(t.get_constant(&"separation", &"HBoxContainer")).is_equal(DesignTokens.SPACE_2)
	assert_int(t.get_constant(&"separation", &"VBoxContainer")).is_equal(DesignTokens.SPACE_2)

func test_button_padding_matches_touch_target_tokens() -> void:
	var sb := _theme().get_stylebox(&"normal", &"Button") as StyleBoxFlat
	assert_float(sb.content_margin_top).is_equal(float(DesignTokens.BTN_PAD_V))
	assert_float(sb.content_margin_left).is_equal(float(DesignTokens.BTN_PAD_H))

func test_card_radius_token_applied_to_button() -> void:
	var sb := _theme().get_stylebox(&"normal", &"Button") as StyleBoxFlat
	assert_int(sb.corner_radius_top_left).is_equal(DesignTokens.RADIUS_CARD)

func test_sheet_radius_token_applied_to_drawer() -> void:
	var sb := _theme().get_stylebox(&"panel", &"PanelContainer") as StyleBoxFlat
	assert_int(sb.corner_radius_top_left).is_equal(DesignTokens.RADIUS_SHEET)

func test_ink_is_dark_enough_for_contrast() -> void:
	assert_bool(DesignTokens.INK.v < 0.5).is_true()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/ui/test_design_tokens.gd`
Expected: FAIL — `Identifier "DesignTokens" not declared`

- [ ] **Step 3: 建 token 表**

新建 `modules/ui/design_tokens.gd`：

```gdscript
class_name DesignTokens
extends RefCounted
## 统一设计语言的单一取值来源（方向 B：薄荷绿体系化，2026-09-01 决策者选定）。
## app_theme.tres 的每个取值都应能在这里找到对应常量。
## 下周设计会要换风格时，只改这个文件 + 同步 app_theme.tres，不必翻场景。

# —— 色板 ——
const ACCENT := Color("#34d399") # 主行动色（角色短裤薄荷绿）
const ACCENT_DEEP := Color("#059669") # 按下态 / 描边
const INK := Color("#123028") # 主文字（墨色，保证按钮上的对比度）
const INK_SUB := Color("#7d9089") # 次级文字
const SURFACE := Color("#ffffff") # 浮层表面
const SURFACE_SUNK := Color("#f3f6f5") # 凹陷格（部件槽、未选中按钮）
const SURFACE_TINT := Color("#ecf7f2") # 选中态浅薄荷

# —— 4dp 间距栅格 ——
const SPACE_1 := 4
const SPACE_2 := 8
const SPACE_3 := 12
const SPACE_4 := 16
const SPACE_6 := 24

# —— 圆角三档 ——
const RADIUS_SHEET := 22 # 底部抽屉
const RADIUS_CARD := 14 # 卡片 / 部件格 / 气泡 / 普通按钮
const RADIUS_PILL := 21 # 胶囊按钮（= 高度一半）

# —— 字阶五档 ——
const FONT_TITLE := 20
const FONT_BODY := 16
const FONT_LABEL := 13
const FONT_CAPTION := 11
const FONT_MICRO := 9

# —— 触摸目标 ——
## 16 号字约 19 单位高 + 上下各 14 → 约 47~48，达到 48dp 标准。
## 改这两个值会让真机按钮变得点不到（tests/ui/test_app_theme.gd 守护）。
const BTN_PAD_V := 14
const BTN_PAD_H := 16
```

- [ ] **Step 4: 主题取值对齐 token**

编辑 `assets/ui/app_theme.tres`，逐处替换：

| 位置 | 原值 | 新值 | 依据 |
|---|---|---|---|
| `SB_btn_normal` / `SB_btn_pressed` / `SB_btn_focus` 的四个 `corner_radius_*` | `12` | `14` | `RADIUS_CARD` |
| `SB_btn_normal.bg_color` | `Color(0.941, 0.949, 0.957, 1)` | `Color(0.953, 0.965, 0.961, 1)` | `SURFACE_SUNK` #f3f6f5 |
| `SB_btn_pressed.bg_color` | `Color(0.882, 0.902, 0.914, 1)` | `Color(0.925, 0.969, 0.949, 1)` | `SURFACE_TINT` #ecf7f2 |
| `SB_btn_focus.border_color` | `Color(0.31, 0.72, 0.58, 1)` | `Color(0.204, 0.827, 0.6, 1)` | `ACCENT` #34d399 |
| `SB_panel_drawer` 的两个 `corner_radius_top_*` | `20` | `22` | `RADIUS_SHEET` |
| `SB_accent_normal.bg_color` / `SB_pill_accent.bg_color` | `Color(0.498, 0.847, 0.745, 1)` | `Color(0.204, 0.827, 0.6, 1)` | `ACCENT` |
| `SB_accent_pressed.bg_color` / `SB_pill_accent_pressed.bg_color` | `Color(0.41, 0.776, 0.667, 1)` | `Color(0.02, 0.588, 0.412, 1)` | `ACCENT_DEEP` #059669 |
| `SB_accent_normal` / `SB_accent_pressed` 的四个 `corner_radius_*` | `12` | `14` | `RADIUS_CARD` |
| `SB_chip` 的四个 `corner_radius_*` | `14` | `14` | 已符合 `RADIUS_CARD`，不动 |
| `SB_round` / `SB_round_pressed` 的四个 `corner_radius_*` | `20` | `22` | `RADIUS_SHEET`（圆形按钮沿用最大档） |
| `SB_pill*` 的四个 `corner_radius_*` | `21` | `21` | 已符合 `RADIUS_PILL`，不动 |

`[resource]` 段落里：

```
Button/colors/font_color = Color(0.071, 0.188, 0.157, 1)
Button/colors/font_focus_color = Color(0.071, 0.188, 0.157, 1)
Button/colors/font_hover_color = Color(0.071, 0.188, 0.157, 1)
Button/colors/font_pressed_color = Color(0.071, 0.188, 0.157, 1)
```

（四个都从 `Color(0.15, 0.165, 0.19, 1)` 改成 `INK` #123028）

并新增一行（`Label/font_sizes/font_size = 16` 之后）：

```
Label/colors/font_color = Color(0.071, 0.188, 0.157, 1)
```

**不要动**：`default_font_size = 16`、所有 `content_margin_*`、所有 `constants/*separation = 8`、全部类型变体的 `base_type` 行——这些是 `tests/ui/test_app_theme.gd` 守护的基线。

- [ ] **Step 5: 跑两套主题测试确认都通过**

Run: `tools/run_tests.sh res://tests/ui`
Expected: PASS —— 新增 10 个用例 + 原有 `test_app_theme.gd` 7 个用例全绿。若 `test_accent_color_is_mint` 挂了，说明 accent 改成了绿分量不占优的颜色，回 Step 4 检查。

- [ ] **Step 6: 桌面目视检查两个场景**

```bash
godot --path . scenes/map_poc/map_poc.tscn
godot --path . scenes/dressing_room/dressing_room.tscn
```

Expected: 地图 HUD 芯片、缩放/倾角/旋转圆钮、底部胶囊按钮，以及换装房抽屉与部件格，全部呈现统一的白浮层 + 薄荷绿；没有残留的旧灰绿色按钮。

- [ ] **Step 7: 跑全量回归并提交**

Run: `tools/run_tests.sh`
Expected: 全绿

```bash
git add modules/ui/design_tokens.gd assets/ui/app_theme.tres tests/ui/test_design_tokens.gd
git commit -m "feat(ui): design token 重铸，主题取值收敛到单一来源

方向 B（薄荷绿体系化）：主色 #34D399、按下 #059669、4dp 间距栅格、
圆角三档 22/14/21、字阶五档。所有取值集中在 modules/ui/design_tokens.gd。
下周设计会换风格只需改 token 表 + 同步主题两个文件。
48dp 触摸目标与类型变体保持不动（test_app_theme.gd 守护）。"
```

---

### Task 8: Marker / 气泡

**Files:**
- Create: `scenes/map_poc/demo_markers.json`、`scenes/map_poc/marker_layer.gd`
- Modify: `scenes/map_poc/map_poc.gd`
- Test: `tests/map/test_marker_layer.gd`（新建）

**Interfaces:**
- Consumes: Task 4 的 `home_lat` / `home_lng` / `_resolve_home()`；Task 7 的 `DesignTokens`
- Produces: `MarkerLayer.set_home(lat, lng)`、`MarkerLayer.sync(cam, anchor_lat, anchor_lng, cull_r, center_world)`

**本任务是缓冲不够时的首砍项**（spec §8）。若周四结束时进度落后，或 Task 3 的定位遇到意外，直接跳过本任务——其它任务都不依赖它。

- [ ] **Step 1: 写失败测试**

新建 `tests/map/test_marker_layer.gd`：

```gdscript
extends GdUnitTestSuite
## marker 必须相对 home 锚点摆放，不能写死经纬度——写死的话用户定位到任何
## 非上海的位置，marker 会全部落到屏幕外（与 pawn 同一个坑，见 test_map_home_anchoring）。

const TOKYO_LAT := 35.6812
const TOKYO_LNG := 139.7671

func test_specs_load_with_at_least_three_markers() -> void:
	var specs := MarkerLayer.load_specs()
	assert_bool(specs.size() >= 3).is_true()
	for s in specs:
		assert_bool(s.has("east_m") and s.has("north_m")).is_true()
		assert_bool(str(s.get("text", "")).length() > 0).is_true()
		assert_bool(str(s.get("author", "")).length() > 0).is_true()

func test_offsets_stay_within_first_screen_range() -> void:
	## 超出 400m 的 marker 在 z16 首屏就看不见了，演示时等于不存在
	for s in MarkerLayer.load_specs():
		var d := Vector2(float(s.east_m), float(s.north_m)).length()
		assert_bool(d <= 400.0).is_true()

func test_markers_follow_home_not_absolute_coords() -> void:
	var layer = auto_free(MarkerLayer.new())
	layer.set_home(TOKYO_LAT, TOKYO_LNG)
	assert_bool(layer.markers.size() >= 3).is_true()
	# 以东京为锚点时，每个 marker 的世界坐标都应在 home 附近（几百米内）
	for i in layer.markers.size():
		var w := layer.world_position(i, TOKYO_LAT, TOKYO_LNG)
		assert_bool(w.length() < 500.0).is_true()

func test_east_north_map_to_world_axes() -> void:
	## 世界系：x = 东，-z = 北（与 MapGeoMath 一致）
	var layer = auto_free(MarkerLayer.new())
	layer.set_home(TOKYO_LAT, TOKYO_LNG)
	layer.markers[0].east_m = 100.0
	layer.markers[0].north_m = 50.0
	var w := layer.world_position(0, TOKYO_LAT, TOKYO_LNG)
	assert_float(w.x).is_equal_approx(100.0, 0.5)
	assert_float(w.z).is_equal_approx(-50.0, 0.5)

func test_toggle_opens_one_bubble_at_a_time() -> void:
	var layer = auto_free(MarkerLayer.new())
	layer.set_home(TOKYO_LAT, TOKYO_LNG)
	layer._toggle(0)
	assert_bool((layer.markers[0].bubble as Control).visible).is_true()
	layer._toggle(1)
	assert_bool((layer.markers[0].bubble as Control).visible).is_false()
	assert_bool((layer.markers[1].bubble as Control).visible).is_true()
	layer._toggle(1) # 再点一次收起
	assert_bool((layer.markers[1].bubble as Control).visible).is_false()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/map/test_marker_layer.gd`
Expected: FAIL — `Identifier "MarkerLayer" not declared`

- [ ] **Step 3: 建假数据**

新建 `scenes/map_poc/demo_markers.json`（坐标是**相对 home 的米偏移**，不是经纬度）：

```json
{
	"version": 1,
	"markers": [
		{ "east_m": 120.0,  "north_m": 80.0,   "author": "小满",  "text": "今天这儿的云超好看" },
		{ "east_m": -180.0, "north_m": 40.0,   "author": "阿泽",  "text": "楼下这家咖啡新出了桂花拿铁" },
		{ "east_m": 60.0,   "north_m": -150.0, "author": "Nina",  "text": "周六早上这里有市集" },
		{ "east_m": -90.0,  "north_m": -220.0, "author": "老陈",  "text": "这段路在修，绕一下" },
		{ "east_m": 260.0,  "north_m": -60.0,  "author": "豆豆",  "text": "遛狗打卡点" }
	]
}
```

- [ ] **Step 4: 实现 marker 层**

新建 `scenes/map_poc/marker_layer.gd`：

```gdscript
class_name MarkerLayer
extends Control
## 地图留言 marker 与气泡（demo 假数据，接口形状对齐 Unity 的 QueryNewMapMarkerReponse）。
##
## 坐标存"相对 home 的米偏移"而非绝对经纬度：写死经纬度的话，用户定位到任何非
## 上海的位置，marker 会全部落到屏幕外——与 pawn 同一个坑，见 map_poc._resolve_home()。
##
## 渲染在 Godot Control 层（方案 spec §5.4 的归属决策：气泡归 Godot，
## POI/静态标注才归地图 style 侧）。

const DATA_PATH := "res://scenes/map_poc/demo_markers.json"
const DATA_VERSION := 1
const PIN_SIZE := Vector2(28, 28)
const BUBBLE_W := 180.0

## 每项：{east_m, north_m, author, text, pin: Button, bubble: PanelContainer}
var markers: Array[Dictionary] = []
var home_lat := 0.0
var home_lng := 0.0
var _open := -1

static func load_specs(path: String = DATA_PATH) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("MarkerLayer: 数据文件缺失 %s" % path)
		return []
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != DATA_VERSION:
		push_warning("MarkerLayer: 数据版本/格式非法 %s" % path)
		return []
	var raw = data.get("markers")
	return raw if typeof(raw) == TYPE_ARRAY else []

## 锚点确定后才建节点——建早了 home 还是 0,0，marker 会摆在几内亚湾。
func set_home(lat: float, lng: float) -> void:
	home_lat = lat
	home_lng = lng
	if markers.is_empty():
		_build()

func _build() -> void:
	for spec in load_specs():
		var m := {
			"east_m": float(spec.get("east_m", 0.0)),
			"north_m": float(spec.get("north_m", 0.0)),
			"author": str(spec.get("author", "")),
			"text": str(spec.get("text", "")),
		}
		var pin := Button.new()
		pin.theme_type_variation = &"RoundButton"
		pin.custom_minimum_size = PIN_SIZE
		pin.size = PIN_SIZE
		pin.focus_mode = Control.FOCUS_NONE
		pin.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		pin.text = "!"
		pin.visible = false
		add_child(pin)
		var bubble := _make_bubble(m.author, m.text)
		add_child(bubble)
		m["pin"] = pin
		m["bubble"] = bubble
		var idx := markers.size()
		pin.pressed.connect(func(): _toggle(idx))
		markers.append(m)

func _make_bubble(author: String, text: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"ChipPanel"
	p.visible = false
	p.custom_minimum_size.x = BUBBLE_W
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", DesignTokens.SPACE_1)
	p.add_child(v)
	var a := Label.new()
	a.text = author
	a.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	a.add_theme_color_override("font_color", DesignTokens.INK_SUB)
	v.add_child(a)
	var t := Label.new()
	t.text = text
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = BUBBLE_W
	t.add_theme_font_size_override("font_size", DesignTokens.FONT_LABEL)
	t.add_theme_color_override("font_color", DesignTokens.INK)
	v.add_child(t)
	return p

## 同时只开一个气泡；再点同一个收起。
func _toggle(index: int) -> void:
	if _open >= 0 and _open < markers.size():
		(markers[_open].bubble as Control).visible = false
	_open = -1 if _open == index else index
	if _open >= 0:
		(markers[_open].bubble as Control).visible = true

## marker 的世界坐标（米，相对给定锚点）。世界系 x=东、-z=北，与 MapGeoMath 一致。
func world_position(index: int, anchor_lat: float, anchor_lng: float) -> Vector3:
	var m := markers[index]
	var base := MapGeoMath.geo_to_world(home_lat, home_lng, anchor_lat, anchor_lng)
	return base + Vector3(m.east_m, 0.0, -m.north_m)

## 跟随相机把 marker 投到屏幕。与 pawn 同一套剔除口径（距地图中心 > cull_r 隐藏），
## 外加相机背后与出屏两道过滤——unproject_position 对背后的点会给出镜像坐标。
func sync(cam: Camera3D, anchor_lat: float, anchor_lng: float, cull_r: float,
		center_world: Vector3) -> void:
	var rect := get_viewport_rect()
	for i in markers.size():
		var m := markers[i]
		var pin := m.pin as Control
		var bubble := m.bubble as Control
		var w := world_position(i, anchor_lat, anchor_lng)
		var on := w.distance_to(center_world) <= cull_r and not cam.is_position_behind(w)
		var sp := Vector2.ZERO
		if on:
			sp = cam.unproject_position(w)
			on = rect.has_point(sp)
		pin.visible = on
		bubble.visible = on and _open == i
		if not on:
			continue
		pin.position = sp - PIN_SIZE * 0.5
		bubble.position = sp - Vector2(bubble.size.x * 0.5, bubble.size.y + PIN_SIZE.y * 0.6)
```

- [ ] **Step 5: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/map/test_marker_layer.gd`
Expected: PASS（5 个用例）

- [ ] **Step 6: 挂进地图场景**

在 `scenes/map_poc/map_poc.gd` 的 `var _home_resolved := false` 之后新增：

```gdscript
var marker_layer: MarkerLayer = null
```

在 `_ready()` 的 `_wire_buttons()` 之后插入（**代码创建，不改 .tscn**）：

```gdscript
	# marker 层：铺满 HUD 且排在最底，别挡住芯片和按钮。
	# 自身 MOUSE_FILTER_IGNORE 只是让层本身不吞事件，图钉 Button 仍然可点。
	marker_layer = MarkerLayer.new()
	marker_layer.name = "Markers"
	marker_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(marker_layer)
	$HUD.move_child(marker_layer, 0)
```

在 `_resolve_home()` 的 `_spawn_home_cohort()` 之后追加一行：

```gdscript
	if marker_layer:
		marker_layer.set_home(lat, lng)
```

在 `_update_cameras()` 的 `_update_pawns(d)` 之后追加：

```gdscript
	if marker_layer:
		marker_layer.sync(cam, anchor_lat, anchor_lng, d * CULL_FACTOR, center_world)
```

- [ ] **Step 7: 桌面目视验证**

```bash
godot --path . scenes/map_poc/map_poc.tscn
```

Expected: 3 秒后（超时回落上海）出现 5 个图钉；点一个弹出气泡，点另一个前一个收起，再点同一个收起；拖拽地图时图钉跟着地面走，拖出屏幕就消失。

- [ ] **Step 8: 跑全量回归并提交**

Run: `tools/run_tests.sh`
Expected: 全绿

```bash
git add scenes/map_poc/demo_markers.json scenes/map_poc/marker_layer.gd \
        scenes/map_poc/map_poc.gd tests/map/test_marker_layer.gd
git commit -m "feat(demo): 地图留言 marker 与气泡

坐标存相对 home 的米偏移而非绝对经纬度，跟 pawn 同一个重锚口径。
渲染走 Godot Control 层（geo→world→unproject），与 pawn 同一套剔除半径，
外加相机背后与出屏两道过滤。同时只开一个气泡。
marker 层在代码里创建挂载，不改 .tscn。"
```

---

### Task 9: 手势惯性 + 双击缩放

**Files:**
- Modify: `scenes/map_poc/map_poc.gd`
- Test: `tests/map/test_map_fling.gd`（新建）

**Interfaces:**
- Produces: `_step_fling(dt: float)`、`_is_double_tap(now_ms: int, pos: Vector2) -> bool`、`_tween_zoom(target: float)`

**硬约束**：不得破坏现有"PASS 冒泡 + 全局死区 24"的列表滚动机制。本任务只碰 `map_poc.gd` 的 `_unhandled_input`/`_process`，不碰任何 ScrollContainer 相关代码。

- [ ] **Step 1: 写失败测试**

新建 `tests/map/test_map_fling.gd`：

```gdscript
extends GdUnitTestSuite
## 惯性：抬手后地图继续滑行并衰减到停；有手指按下时必须立刻停。
## 决策者点名"当前没有惯性，体验不丝滑"——原实现 InputEventScreenDrag 直接
## _apply_world_delta，抬手即停。

const MapPoc := preload("res://scenes/map_poc/map_poc.gd")

func test_fling_moves_center_east_and_decays_to_stop() -> void:
	var n = auto_free(MapPoc.new())
	var lng0: float = n.center_lng
	n._fling_vel = Vector3(200.0, 0.0, 0.0) # 200 m/s 向东（世界系 +x = 东）
	var steps := 0
	while n._fling_vel.length() >= MapPoc.FLING_MIN_SPEED and steps < 2000:
		n._step_fling(1.0 / 60.0)
		steps += 1
	assert_bool(n.center_lng > lng0).is_true() # 确实向东走了
	assert_bool(steps > 10).is_true() # 不是一帧停死，有滑行手感
	assert_bool(steps < 600).is_true() # 也不会滑个没完（10 秒内停）

func test_touch_down_kills_fling_immediately() -> void:
	var n = auto_free(MapPoc.new())
	n._fling_vel = Vector3(200.0, 0.0, 0.0)
	n._touch_count = 1
	n._step_fling(1.0 / 60.0)
	assert_float(n._fling_vel.length()).is_equal(0.0)

func test_double_tap_window_and_radius() -> void:
	var n = auto_free(MapPoc.new())
	n._last_tap_ms = 1000
	n._last_tap_pos = Vector2(100, 100)
	assert_bool(n._is_double_tap(1200, Vector2(105, 103))).is_true() # 200ms 内、5px 内
	assert_bool(n._is_double_tap(1500, Vector2(100, 100))).is_false() # 超时
	assert_bool(n._is_double_tap(1200, Vector2(200, 200))).is_false() # 距离太远

func test_fling_respects_latitude_clamp() -> void:
	## 极高速向北甩不得把中心拖过 Web Mercator 边界（拖过极点会东西镜像）
	var n = auto_free(MapPoc.new())
	n._fling_vel = Vector3(0.0, 0.0, -5.0e6)
	n._step_fling(1.0)
	assert_bool(n.center_lat <= 85.051129).is_true()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/map/test_map_fling.gd`
Expected: FAIL — `Invalid set index '_fling_vel'`

- [ ] **Step 3: 加常量与状态**

在 `scenes/map_poc/map_poc.gd` 的 `const HOME_TIMEOUT_S := 3.0` 之后新增：

```gdscript
## 抬手惯性：速度按 exp(-DECAY*dt) 衰减，低于 MIN_SPEED 停止。
## EMA 平滑掉单帧抖动，否则最后一帧的抖动会决定整段滑行方向。
const FLING_DECAY := 4.0
const FLING_MIN_SPEED := 0.5 # 米/秒
const FLING_EMA := 0.35
## 双击：300ms 内两次落点相距不超过 32 单位
const DOUBLE_TAP_S := 0.3
const DOUBLE_TAP_MAX_PX := 32.0
```

在 `var marker_layer: MarkerLayer = null` 之后新增：

```gdscript
var _fling_vel := Vector3.ZERO
var _last_tap_ms := 0
var _last_tap_pos := Vector2.ZERO
var _zoom_tween: Tween = null
```

- [ ] **Step 4: 改输入处理**

把 `_unhandled_input()`（第 235-252 行）替换为：

```gdscript
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		_touch_count += 1 if e.pressed else -1
		_touch_count = maxi(_touch_count, 0)
		if e.pressed:
			_fling_vel = Vector3.ZERO # 新触摸立即打断惯性
			if _is_double_tap(Time.get_ticks_msec(), e.position):
				_last_tap_ms = 0
				_tween_zoom(zoom + 1.0)
			else:
				_last_tap_ms = Time.get_ticks_msec()
				_last_tap_pos = e.position
	if e is InputEventScreenDrag and _touch_count <= 1:
		# 抓地拖拽：让按下时的地面点始终跟在手指下（倾角下精确）。
		# 高 pitch 时屏幕上缘一像素对应的地面位移可达 ~0.4d，单次 delta 限幅到 d
		# 防止一次拖拽把地图甩出上百公里。
		var prev = _ground_point(e.position - e.relative)
		var now = _ground_point(e.position)
		if prev != null and now != null:
			var delta := ((prev as Vector3) - (now as Vector3)).limit_length(_cam_distance())
			_apply_world_delta(delta)
			# 惯性速度：位移换算成米/秒后 EMA 平滑，抬手接着走
			var dt := maxf(get_process_delta_time(), 0.001)
			_fling_vel = _fling_vel.lerp(delta / dt, FLING_EMA)
			_camera_dirty = true
	elif e is InputEventMagnifyGesture:
		_set_zoom(zoom + log(e.factor) / log(2.0))
	elif e is InputEventPanGesture:
		_set_pitch(pitch - e.delta.y * 0.2)
```

- [ ] **Step 5: 加惯性与双击实现**

在 `_ground_point()` 之后新增：

```gdscript
## 抬手后的惯性滑行：指数衰减，低于阈值停止。有手指按下时直接清零
## （新触摸打断惯性是原生地图的通用手感）。
func _step_fling(dt: float) -> void:
	if _touch_count > 0 or _fling_vel.length() < FLING_MIN_SPEED:
		_fling_vel = Vector3.ZERO
		return
	_apply_world_delta(_fling_vel * dt)
	_fling_vel *= exp(-FLING_DECAY * dt)
	_camera_dirty = true

## 双击判定：与上一次触摸的时间差与落点距离都在窗口内。
func _is_double_tap(now_ms: int, pos: Vector2) -> bool:
	if _last_tap_ms <= 0:
		return false
	return now_ms - _last_tap_ms <= int(DOUBLE_TAP_S * 1000.0) \
		and pos.distance_to(_last_tap_pos) <= DOUBLE_TAP_MAX_PX

## 双击放大走 Tween 而不是瞬变——瞬变在地图上很跳，是"不丝滑"的另一半。
func _tween_zoom(target: float) -> void:
	if _zoom_tween:
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.tween_method(_set_zoom, zoom, clampf(target, 3.0, 20.0), 0.25) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
```

在 `_process()` 的 `if map: map.poll()` 之后插入：

```gdscript
	_step_fling(_dt)
```

- [ ] **Step 6: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/map/test_map_fling.gd`
Expected: PASS（4 个用例）

- [ ] **Step 7: 确认没破坏列表滚动**

Run: `tools/run_tests.sh`
Expected: 全绿 —— 特别关注 `tests/scenes/test_dressing_room_layout.gd`。若换装房部件列表相关用例挂了，说明动到了滚动机制，**立即回退本任务**（spec §8 的降级条款）。

- [ ] **Step 8: 提交**

```bash
git add scenes/map_poc/map_poc.gd tests/map/test_map_fling.gd
git commit -m "feat(demo): 地图拖拽惯性 + 双击平滑缩放

原实现抬手即停，决策者点名不丝滑。拖拽时把位移换算成米/秒做 EMA 平滑，
松手进入 fling 态按 exp(-4t) 衰减，低于 0.5 m/s 停止，新触摸立即打断。
双击（300ms/32px 窗口）走 Tween 变焦而非瞬变。
只碰 map_poc 的输入处理，不动 PASS 冒泡 + 死区 24 的列表滚动机制。"
```

---

### Task 10: 双端构建与真机验收

**Files:** 无代码改动；产出 `build/sensen-demo-debug.apk` 与 iOS 装机包

**Interfaces:** Consumes 全部前序任务

- [ ] **Step 1: 全量测试必须全绿**

Run: `tools/run_tests.sh`
Expected: 全绿。用例数约为 110 + 32（本计划新增）。**有任何红色不得进入装机验收。**

- [ ] **Step 2: 构建 Android**

```bash
tools/android/setup_android_build.sh
godot --headless --path . --export-debug "Android" build/sensen-demo-debug.apk
adb install -r build/sensen-demo-debug.apk
```

- [ ] **Step 3: 走 Android 阻断验收清单**

逐条勾，任一不过即本周目标未达成：

- [ ] 开 App → **权限弹窗出现**（没弹窗 = 踩了单数 `request_permission` 的坑，回 Task 2）
- [ ] 授权后落到自己真实位置，角色站在脚下
- [ ] **换个远离上海人民广场的地点再测一次**：周围仍有路人角色和 ≥3 个可点 marker
- [ ] 拒绝权限 → 不崩，3 秒后落到上海，路人和 marker 照常可见
- [ ] 选"大致位置" → 不崩，定位照常生效
- [ ] 快速甩动地图有惯性衰减；双击平滑放大（不是瞬变）
- [ ] 点 marker 弹气泡，中文显示正常无豆腐块
- [ ] 进换装房换上装/发型 → 保存 → 返回地图，自己的角色已更新
- [ ] 全程 UI 视觉统一（薄荷绿 token），无残留旧灰绿按钮
- [ ] denylist 里的部件不出现在换装列表

- [ ] **Step 4: 构建 iOS（非阻断）**

```bash
tools/ios/setup_ios_g3.sh
# xcodebuild 命令见 setup 脚本尾部提示
```

免费个人团队证书（53LT77CV6R）**7 天有效期**，必须当天装机。四个已知坑见 `docs/superpowers/plans/2026-08-31-3dmap-g3-ios-transparency.md` 追记：钥匙串授权挂死、SPM 需显式 `https_proxy`、pbxproj 引号锚点两制式、macOS 无 `timeout` 命令。

- [ ] **Step 5: iOS 非阻断验收**

- [ ] 除定位外跑通同一条链（iOS 定位空转，3 秒后落到上海默认点，路人与 marker 照常可见）

构建链翻车则按 spec §2 降级为录屏留证，**不影响本周目标达成**。

- [ ] **Step 6: 录屏留证并归档结果**

把 Android 全链录屏与验收清单勾选结果追记到本计划文件末尾，提交：

```bash
git add docs/superpowers/plans/2026-09-01-internal-demo-avatar-map.md
git commit -m "docs(demo): 2026-09-04 内部 Demo 验收结果归档"
```

---

## 自查记录

- **spec 覆盖**：§6① → Task 1；§6② → Task 5 + Task 6；§6③ → Task 2 + Task 3 + Task 4；§6④ → Task 8；§6⑤ → Task 9；§6⑥ → Task 7；iOS 重建 → Task 10。§9 验收清单逐条落在 Task 10 Step 3/5。§4「明确不做」未派生任务（符合预期）。
- **两处与 spec 的偏差**已在文首「与 spec 的两处偏差」小节列明理由。
- **类型一致性**：`_spawn_queue` 每项的键在 Task 4 定义（`lat`/`lng`/`cfg`/`anim`/`cohort`），`_add_pawn(spec.lat, spec.lng, spec.cfg, spec.anim)` 的既有调用不受影响；`MarkerLayer.set_home` / `sync` / `world_position` 的签名在 Task 8 定义并在同一任务内消费；`DesignTokens` 常量名在 Task 7 定义，Task 8 引用 `FONT_CAPTION` / `FONT_LABEL` / `INK` / `INK_SUB` / `SPACE_1`，均已定义。
