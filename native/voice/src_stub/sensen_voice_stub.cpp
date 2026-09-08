// 桌面（macOS 编辑器 / 测试）空实现：同一个类名与信号，is_available() 恒 false。
// 桌面真要说话得接社区的 godot-livekit，本仓库暂不带。
#include "sensen_voice.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

SensenVoice *SensenVoice::singleton = nullptr;

SensenVoice *SensenVoice::get_singleton() { return singleton; }
SensenVoice::SensenVoice() { singleton = this; }
SensenVoice::~SensenVoice() { if (singleton == this) singleton = nullptr; }

void SensenVoice::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_available"), &SensenVoice::is_available);
	ClassDB::bind_method(D_METHOD("connect_room", "url", "token"), &SensenVoice::connect_room);
	ClassDB::bind_method(D_METHOD("disconnect_room"), &SensenVoice::disconnect_room);
	ClassDB::bind_method(D_METHOD("set_mic", "enabled"), &SensenVoice::set_mic);
	ClassDB::bind_method(D_METHOD("set_volume", "identity", "volume"), &SensenVoice::set_volume);
	ClassDB::bind_method(D_METHOD("speakers"), &SensenVoice::speakers);
	ClassDB::bind_method(D_METHOD("poll"), &SensenVoice::poll);
	ADD_SIGNAL(MethodInfo("connected"));
	ADD_SIGNAL(MethodInfo("disconnected", PropertyInfo(Variant::STRING, "reason")));
	ADD_SIGNAL(MethodInfo("speaking", PropertyInfo(Variant::STRING, "identity"), PropertyInfo(Variant::BOOL, "speaking")));
	ADD_SIGNAL(MethodInfo("error", PropertyInfo(Variant::STRING, "message")));
}

bool SensenVoice::is_available() const { return false; }
void SensenVoice::connect_room(const String &, const String &) {}
void SensenVoice::disconnect_room() {}
void SensenVoice::set_mic(bool) {}
void SensenVoice::set_volume(const String &, double) {}
PackedStringArray SensenVoice::speakers() const { return last_speakers; }
void SensenVoice::poll() {}
