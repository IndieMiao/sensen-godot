class_name PushBridge
extends RefCounted
## C2 推送原生插件的**抽象**（与 VoiceBridge 同一套路数）：上层只面向这个接口。实现：
##   - iOS：GDExtension 走 UserNotifications + APNs，拿到的是 **APNs device token**
##   - Android：Godot 插件走 firebase-messaging，拿到的是 **FCM registration token**
##   - 桌面 / 插件缺席：PushBridgeFactory.make() 返回 null，什么也不注册（服务端也会按 SCHEMA 拒掉）
##
## 权限与 token 是两件事：先问用户要通知权限（可能被拒），拿到授权后才向系统注册远程推送，
## token 是异步回来的，可能一直不来（飞行模式 / 沙箱异常），所以失败要有出口。

signal token_ready(token: String)
signal token_failed(reason: String)
signal authorization(granted: bool)
## 用户点开了一条通知：payload 里只有路由用的 id（正文不进推送，见 E2）。
signal notification_opened(payload: Dictionary)

## 平台是否具备推送能力。
func available() -> bool:
	return false

## 弹系统通知权限弹窗（已经问过就直接回上次结果）。结果走 authorization 信号。
func request_authorization() -> void:
	pass

## 向系统注册远程推送；成功后 token 走 token_ready 信号。要先拿到授权。
func register_for_remote() -> void:
	pass

## 最近一次拿到的 token（没有就是空串）。
func token() -> String:
	return ""

## 服务端要按平台分发：iOS 的是 APNs token，Android 的是 FCM token。
func platform() -> String:
	return PushApi.default_platform()
