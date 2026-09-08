// C4 语音（iOS）：LiveKit 的薄桥接。真正的音频链路在 Swift 侧（SensenVoice.swift，用
// client-sdk-swift），这里只负责把 GDScript 的调用转过去、并把状态快照翻成信号。
//
// 为什么是「快照 + poll」而不是回调：Swift 类在 App target 里、GDExtension 在静态库里，
// 编译期互不可见（靠 NSClassFromString 找）；让 Swift 回调进 C++ 要额外的函数指针注册，
// 而 VoiceBridge 本来就有每帧 poll() 的约定，取快照最省事也最好排查。
#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class SensenVoice : public Object {
	GDCLASS(SensenVoice, Object)

	static SensenVoice *singleton;
	/// 上一帧的状态，用来差分出信号。0=IDLE 1=CONNECTING 2=CONNECTED 3=RECONNECTING
	int last_state = 0;
	PackedStringArray last_speakers;

protected:
	static void _bind_methods();

public:
	static SensenVoice *get_singleton();
	SensenVoice();
	~SensenVoice();

	/// Swift 侧的 SensenVoiceCore 在不在（没连 LiveKit SDK 的包里就没有）。
	bool is_available() const;
	void connect_room(const String &url, const String &token);
	void disconnect_room();
	/// token 不允许发布时 Swift 侧会忽略并保持静音——闸门在服务端签的 token 上。
	void set_mic(bool enabled);
	void set_volume(const String &identity, double volume);
	PackedStringArray speakers() const;
	/// 每帧调用：取快照，与上一帧比，变了才发信号。
	void poll();
};

} // namespace godot
