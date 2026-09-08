// C2 推送（iOS）：UserNotifications 授权 + APNs 远程注册的薄桥接。
// 拿到的是 **APNs device token**（十六进制串），不是 FCM token——iOS 侧不引 Firebase SDK，
// 服务端直连 APNs（server/src/http/apns.ts）。Android 走 Kotlin 插件拿 FCM token。
#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class SensenPush : public Object {
	GDCLASS(SensenPush, Object)

	static SensenPush *singleton;
	String device_token;

protected:
	static void _bind_methods();

public:
	static SensenPush *get_singleton();
	SensenPush();
	~SensenPush();

	/// 系统有 UserNotifications（iOS 10+）。桌面恒 false。
	bool is_available() const;
	/// 弹（或复用上次的）通知权限结果，走 `authorization(granted)` 信号。
	void request_authorization();
	/// 向 APNs 注册；成功走 `token_ready(token)`，失败走 `token_failed(reason)`。
	/// 没有 aps-environment 授权文件时必定失败——这就是「没配好推送证书」的信号。
	void register_for_remote();
	/// 最近一次拿到的 token；没有就是空串。
	String token() const;
	/// "ios" / ""（桌面）。
	String platform() const;

	/// 原生回调统一走这三个入口（主线程 / deferred）。
	void _deliver_authorization(bool granted);
	void _deliver_token(const String &token);
	void _deliver_token_failed(const String &reason);
	/// opened=false 是前台横幅，true 是用户点开了。
	void _deliver_notification(const Dictionary &payload, bool opened);
};

} // namespace godot
