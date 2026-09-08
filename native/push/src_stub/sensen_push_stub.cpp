// 桌面（macOS 编辑器 / 测试）用的空实现：同一个类名与信号，is_available() 恒 false，
// 让 .gdextension 在桌面也有库可载。桌面没有推送通道，PushBridgeFactory 会返回 null。
#include "sensen_push.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

SensenPush *SensenPush::singleton = nullptr;

SensenPush *SensenPush::get_singleton() { return singleton; }
SensenPush::SensenPush() { singleton = this; }
SensenPush::~SensenPush() { if (singleton == this) singleton = nullptr; }

void SensenPush::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_available"), &SensenPush::is_available);
	ClassDB::bind_method(D_METHOD("request_authorization"), &SensenPush::request_authorization);
	ClassDB::bind_method(D_METHOD("register_for_remote"), &SensenPush::register_for_remote);
	ClassDB::bind_method(D_METHOD("token"), &SensenPush::token);
	ClassDB::bind_method(D_METHOD("platform"), &SensenPush::platform);
	ADD_SIGNAL(MethodInfo("authorization", PropertyInfo(Variant::BOOL, "granted")));
	ADD_SIGNAL(MethodInfo("token_ready", PropertyInfo(Variant::STRING, "token")));
	ADD_SIGNAL(MethodInfo("token_failed", PropertyInfo(Variant::STRING, "reason")));
	ADD_SIGNAL(MethodInfo("notification", PropertyInfo(Variant::DICTIONARY, "payload"), PropertyInfo(Variant::BOOL, "opened")));
}

bool SensenPush::is_available() const { return false; }
void SensenPush::request_authorization() {}
void SensenPush::register_for_remote() {}
String SensenPush::token() const { return device_token; }
String SensenPush::platform() const { return String(); }

void SensenPush::_deliver_authorization(bool granted) { emit_signal("authorization", granted); }
void SensenPush::_deliver_token(const String &token) { device_token = token; emit_signal("token_ready", token); }
void SensenPush::_deliver_token_failed(const String &reason) { emit_signal("token_failed", reason); }
void SensenPush::_deliver_notification(const Dictionary &payload, bool opened) { emit_signal("notification", payload, opened); }
