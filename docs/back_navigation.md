# 返回导航(系统返回手势)处理方案

> 调研日期 2026-09-01,基于本项目 Godot **4.7.2.stable** + 安卓 gradle 模板 **targetSdk 36**。
> 结论已按两端拆分:**安卓必须处理;iOS 决定不做手势返回**(页面内放返回按钮即可)。
> 本文供正式开发时参考,所有机制均核实到 Godot 源码 / PR / 官方文档级别,链接见文末。

## 0. 结论速览

- Godot 做宿主时,OS 眼里整个 app 只是**单 Activity / 单 UIViewController**,没有系统级页面栈。
  "历史页面"必须在引擎内自建导航栈(Router),返回事件驱动这个栈。
- 安卓:Godot 会把返回手势/返回键转成 `NOTIFICATION_WM_GO_BACK_REQUEST` 通知发给场景树,
  接住它 pop 自己的栈即可;**必须先关掉 `quit_on_go_back`**,否则返回直接退 app。
- 栈空时的正确行为是**回后台不退出**(Android 12+ 系统规范),Godot 无内置 API,
  需在现有 GodotPlugin v2 插件里加一个 `moveTaskToBack(true)` 方法。
- 预测性返回(Android 14+ 的手势预览动画)Godot 不支持,降级为普通转场动画——
  Unity / React Native 同样如此,属业界公认可接受的降级(仅 Flutter 做到了完整支持)。
- 这套"框架内栈 + 拦截返回 + 栈空交还系统"的架构与 Flutter / RN / Unity 完全一致,是成熟路线。

## 1. 问题本质

原生 client 的"历史页面"是 Activity/Fragment 栈(安卓)或 UINavigationController 栈(iOS),
系统边缘手势操作的就是这个栈。引擎宿主下所有"页面"都是引擎内部绘制的 Control 场景,
系统没有栈可回退:

- **安卓**:系统仍会派发返回事件(手势与三键导航的返回键同源),app 负责响应。
- **iOS**:系统**根本没有全局返回手势**——左缘右滑是 `UINavigationController` 私有的
  `interactivePopGestureRecognizer`(iOS 26 新增的 `interactiveContentPopGestureRecognizer`
  同样只作用于 navigation controller),不用它就没有。Flutter 的 iOS 滑动返回是在框架内
  从零重实现的(`_CupertinoBackGestureDetector`,写死左缘 20pt)。

## 2. 安卓:必须做的事

### 2.1 事件链路(Godot 4.7,源码级)

```
系统返回手势/返回键
  → GodotActivity: onBackPressedDispatcher.addCallback { godotFragment?.onBackPressed() }   (androidx)
  → Godot.onBackPressed() → 各插件 GodotPlugin.onMainBackPressed()(返回值被忽略,插件无法消费事件)
  → GodotLib.back() (JNI) → DisplayServerAndroid → WINDOW_EVENT_GO_BACK_REQUEST
  → Window: 向窗口内所有节点广播 NOTIFICATION_WM_GO_BACK_REQUEST(常量在 Node 上,值 1007)
            + 发出 go_back_requested 信号
  → SceneTree: 若 quit_on_go_back == true → 直接退出
```

### 2.2 必做清单

1. **项目设置** `application/config/quit_on_go_back = false`(默认 true;
   运行时等价写法 `get_tree().quit_on_go_back = false`)。
2. **唯一的 Router autoload** 处理通知(见 §4 骨架)。
   注意 [godot#105324](https://github.com/godotengine/godot/issues/105324)(open):
   通知会广播给**所有**节点——只在 Router 一处处理,严禁各场景各自监听,否则一次返回触发多次。
3. **栈空时回后台**:在现有 v2 插件(如 GodotMap)里加方法,GDScript 侧
   `Engine.get_singleton("GodotMap").move_task_to_back()` 调用:

   ```kotlin
   @UsedByGodot
   fun moveTaskToBack() { activity?.moveTaskToBack(true) }
   ```

   不要用 `get_tree().quit()`——Android 12+ 系统对根 Activity 的返回语义就是"任务移后台、
   保留热启动";自杀式退出在系统看来像闪退(Flutter 文档明确警告过这一点)。
   Godot 全引擎唯一一处 `moveTaskToBack` 在安卓编辑器内部(GodotGame.kt),不暴露给导出的游戏。

### 2.3 targetSdk 36(Android 16)的三个坑

背景:Android 16 上 target 36 的应用**默认启用预测性返回**,系统不再派发
`KEYCODE_BACK` / 不再调用 `Activity.onBackPressed()`。
Godot 在 [PR #117653](https://github.com/godotengine/godot/pull/117653)(2026-04 合并,
4.7 里程碑,并随 targetSdk 35→36 一起 backport 进 4.6.3)把返回处理迁移到 androidx
`OnBackPressedDispatcher`,所以 **4.7.2 上通知仍然可靠送达**。但有三个衍生事实:

1. **返回不再产生按键事件**:Android 16 设备上系统返回不会生成
   `InputEventKey`(physical `Key::BACK`)。**不要**把返回绑定到输入动作
   (如 `ui_cancel`)——那条路在新系统上是死的,只能用通知。
   (Android ≤15 设备上老的 KEYCODE_BACK 路径仍在,会同时产生按键事件和通知,
   这也是只在 Router 一处处理的又一理由。)
2. **系统"回桌面"预览动画被抑制**:Godot 注册的是常驻回调,系统认为 app 永远自己
   处理返回,所以即使栈空、即使 `quit_on_go_back = true`,也看不到 Android 14+ 捏合
   回桌面的预测性动画。Flutter 通过"栈深 > 1 时才注册回调"解决了此问题
   (`SystemNavigator.setFrameworkHandlesBack` 动态注册/注销);Godot 没做,
   要做需自定义 Activity 改 gradle 模板,一期不建议。
3. **手势进度事件拿不到**:Godot 只转发最终触发,不转发
   `handleOnBackStarted/Progressed/Cancelled`。想做"应用内页面跟手预览"需要自定义
   插件/Activity 转发 `OnBackAnimationCallback` 进度到 GDScript,完全 DIY。
   参照:Unity 6 官方的 `predictiveBackSupport` 也只做到回桌面动画、不暴露进度;
   RN 至今靠 manifest 关掉预测性返回硬扛。**降级为普通(非跟手)转场动画即可。**

### 2.4 相关已知 issue(开发时留意)

- [#105324](https://github.com/godotengine/godot/issues/105324)(open):通知广播给所有节点。
- [#101457](https://github.com/godotengine/godot/issues/101457)(已修,4.4):历史上出现过一次按压触发两次通知;若升级引擎后行为异常,优先怀疑此类回归。
- [#64940](https://github.com/godotengine/godot/issues/64940)(open):`quit_on_go_back` 的老行为报告。
- 版本警示:4.5 维护分支曾出现"targetSdk 已升 36 但未 backport #117653"的窗口——
  **换引擎版本时必须真机回归返回手势**(Android 16 设备上未修复版本的表现是:通知不触发、app 直接被系统结束)。

## 3. iOS:决定与事实记录

**决定:不做滑动返回手势。** 页面内 UI 返回按钮承担全部返回导航,iOS 侧零额外工作
(Router 的 `pop()` 由按钮调用,与安卓通知殊途同归)。

留档的事实(将来若翻案,少走弯路):

- iOS 无系统全局返回手势,自实现是唯一路径(Flutter 即如此)。做法:
  `InputEventScreenTouch/ScreenDrag` 识别左缘 `20.0 * DisplayServer.screen_get_scale()`
  像素内起手、水平位移主导后接管,progress 驱动转场,松手 >50% 或横向速度超阈值 commit。
  现成插件无"手指跟随的交互式 pop"成品(GDTIM 等手势库只有离散 swipe 触发)。
- 左缘无系统手势冲突、无触摸延迟(边缘延迟只在上/下缘)。
- 相关导出设置(运行时改无效,导出时定死):`display/window/ios/suppress_ui_gesture`
  (默认 true,defer 全部边缘)、`hide_home_indicator`(默认 true;
  [#104411](https://github.com/godotengine/godot/issues/104411):它会让底缘 defer 失效,
  只影响底缘 Home 手势,与返回无关)。
- iOS 26 原生已支持全屏任意位置右滑返回,自实现的 20pt 边缘版体验会落后于原生
  (Flutter 同样有此差距,[flutter#180309](https://github.com/flutter/flutter/issues/180309))。

## 4. 推荐架构与代码骨架

```
Router (autoload, 唯一返回处理点)
 ├─ 栈: Array[Control 全屏场景],push()/pop() + Tween 转场(0.25~0.35s,TRANS_CUBIC/EASE_OUT)
 ├─ 安卓: _notification(NOTIFICATION_WM_GO_BACK_REQUEST) → pop();栈空 → 插件 moveTaskToBack
 ├─ iOS / 通用: 页面内返回按钮 → 同一个 pop()
 └─ 细节: 转场期间屏蔽底层输入;pop 前若有 LineEdit 聚焦先收软键盘;需要拦截返回的页面
          (如"再按一次退出"、表单未保存确认)通过 can_pop 回调挂到 Router,而不是自听通知
```

```gdscript
# router.gd — autoload "Router"
extends Node

var _stack: Array[Control] = []

func _ready() -> void:
    get_tree().quit_on_go_back = false  # 双保险,项目设置里也关

func push(screen: Control) -> void:
    # ...入栈 + 转场动画,转场期间屏蔽输入...
    _stack.push_back(screen)

func pop() -> void:
    if _stack.size() <= 1:
        _leave_app()
        return
    var top := _stack.pop_back()
    # 顶层页面可实现 can_pop() 拦截(未保存确认等)
    # ...出栈转场动画...

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_GO_BACK_REQUEST:
        pop()

func _leave_app() -> void:
    if OS.get_name() == "Android":
        var plugin := Engine.get_singleton("GodotMap")  # 或专门的宿主插件
        if plugin:
            plugin.moveTaskToBack()
        # 没有插件时宁可什么都不做,也不要 get_tree().quit()
    # iOS: 根页面返回无操作,符合平台规范(app 不自杀)
```

## 5. 先例对照(为什么这条路是对的)

| 运行时 | 返回事件接法 | 栈空行为 | 预测性返回 |
|---|---|---|---|
| Flutter | `PopScope`(3.16 起替代 WillPopScope);引擎按栈深动态注册/注销 OnBackInvokedCallback | `SystemNavigator.pop()`,系统播回桌面动画 | 最完整:回桌面动画 + 应用内跟手转场(3.38 起默认) |
| React Native | `BackHandler`(走老 onBackPressed 路径) | 默认退出 | 不支持,官方建议 manifest 关掉;Android 16 逼迁移中 |
| Unity | `KeyCode.Escape` 约定 + `Input.backButtonLeavesApp` | 系统默认 | Unity 6 起仅回桌面动画,无进度 API |
| **Godot 4.7(本项目)** | `NOTIFICATION_WM_GO_BACK_REQUEST` | 需自建插件 moveTaskToBack | 不支持,常驻回调还会抑制回桌面动画 |

共同架构:**框架内导航栈 + 拦截系统返回 + 栈空交还系统**。Godot 的能力介于 RN 与 Unity 之间,
缺口(动态注册回调、进度事件)都有明确的 DIY 路径,一期不做。

## 6. 参考链接

- Godot 官方:[Handling quit requests](https://docs.godotengine.org/en/stable/tutorials/inputs/handling_quit_requests.html);ProjectSettings `application/config/quit_on_go_back`;`SceneTree.quit_on_go_back`
- [godot PR #117653](https://github.com/godotengine/godot/pull/117653) — target 36 返回修复(4.7 / 4.6.3+)
- [Android 16 行为变更](https://developer.android.com/about/versions/16/behavior-changes-16)(target 36 默认预测性返回、停发 KEYCODE_BACK)
- [Android 12 行为变更](https://developer.android.com/about/versions/12/behavior-changes-all)(根 Activity 返回 = 移后台)
- [Android 预测性返回指南](https://developer.android.com/guide/navigation/custom-back/predictive-back-gesture)
- Flutter:[predictive back 迁移文档](https://docs.flutter.dev/release/breaking-changes/android-predictive-back)、[`SystemNavigator.setFrameworkHandlesBack`](https://api.flutter.dev/flutter/services/SystemNavigator/setFrameworkHandlesBack.html)
- Unity:[`PlayerSettings.Android.predictiveBackSupport`](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/PlayerSettings.Android-predictiveBackSupport.html)
- RN:[BackHandler](https://reactnative.dev/docs/backhandler)、[#34529 预测性返回缺口](https://github.com/facebook/react-native/issues/34529)
