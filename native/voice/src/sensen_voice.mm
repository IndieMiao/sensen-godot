#include "sensen_voice.h"

#import <Foundation/Foundation.h>

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

using namespace godot;

// Swift 侧的门面。类在 App target 里（SensenVoice.swift），本静态库编译期看不见它，
// 所以只声明要用的选择器，运行时 NSClassFromString 取——同 PhotosUI / UserNotifications 的做法。
@protocol SensenVoiceCoreFacade <NSObject>
- (void)connectRoom:(NSString *)url token:(NSString *)token;
- (void)disconnectRoom;
- (void)setMic:(BOOL)enabled;
- (void)setVolumeFor:(NSString *)identity volume:(double)volume;
/// {state:NSNumber, speakers:NSArray<NSString*>, error:NSString, reason:NSString}
- (NSDictionary *)snapshot;
@end

static id<SensenVoiceCoreFacade> voice_core() {
	static id<SensenVoiceCoreFacade> shared = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		// Swift 类的 ObjC 名字由 @objc(SensenVoiceCore) 固定，不带模块前缀。
		Class cls = NSClassFromString(@"SensenVoiceCore");
		if (cls != nil && [cls respondsToSelector:@selector(shared)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
			shared = [cls performSelector:@selector(shared)];
#pragma clang diagnostic pop
		}
	});
	return shared;
}

SensenVoice *SensenVoice::singleton = nullptr;

SensenVoice *SensenVoice::get_singleton() { return singleton; }

SensenVoice::SensenVoice() { singleton = this; }

SensenVoice::~SensenVoice() {
	if (singleton == this) {
		singleton = nullptr;
	}
}

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

bool SensenVoice::is_available() const { return voice_core() != nil; }

void SensenVoice::connect_room(const String &url, const String &token) {
	id<SensenVoiceCoreFacade> core = voice_core();
	if (core == nil) {
		return;
	}
	NSString *u = [NSString stringWithUTF8String:url.utf8().get_data()];
	NSString *t = [NSString stringWithUTF8String:token.utf8().get_data()];
	[core connectRoom:u token:t];
}

void SensenVoice::disconnect_room() {
	[voice_core() disconnectRoom];
}

void SensenVoice::set_mic(bool enabled) {
	[voice_core() setMic:(BOOL)enabled];
}

void SensenVoice::set_volume(const String &identity, double volume) {
	id<SensenVoiceCoreFacade> core = voice_core();
	if (core == nil) {
		return;
	}
	[core setVolumeFor:[NSString stringWithUTF8String:identity.utf8().get_data()] volume:volume];
}

PackedStringArray SensenVoice::speakers() const { return last_speakers; }

void SensenVoice::poll() {
	id<SensenVoiceCoreFacade> core = voice_core();
	if (core == nil) {
		return;
	}
	NSDictionary *snap = [core snapshot];
	if (![snap isKindOfClass:[NSDictionary class]]) {
		return;
	}
	// 说话的人：先发变化，再更新缓存——UI 只关心「谁开始说 / 谁停了」。
	PackedStringArray now_speaking;
	id raw = snap[@"speakers"];
	if ([raw isKindOfClass:[NSArray class]]) {
		for (id item in (NSArray *)raw) {
			if ([item isKindOfClass:[NSString class]]) {
				now_speaking.push_back(String([(NSString *)item UTF8String]));
			}
		}
	}
	for (int i = 0; i < now_speaking.size(); i++) {
		if (last_speakers.find(now_speaking[i]) == -1) {
			emit_signal("speaking", now_speaking[i], true);
		}
	}
	for (int i = 0; i < last_speakers.size(); i++) {
		if (now_speaking.find(last_speakers[i]) == -1) {
			emit_signal("speaking", last_speakers[i], false);
		}
	}
	last_speakers = now_speaking;

	NSNumber *state_num = snap[@"state"];
	int state = state_num != nil ? [state_num intValue] : 0;
	if (state != last_state) {
		int previous = last_state;
		last_state = state;
		if (state == 2) {
			emit_signal("connected");
		} else if (state == 0 && previous != 0) {
			NSString *reason = snap[@"reason"];
			emit_signal("disconnected", String(reason != nil ? [reason UTF8String] : ""));
		}
	}

	NSString *error = snap[@"error"];
	if ([error isKindOfClass:[NSString class]] && error.length > 0) {
		emit_signal("error", String([error UTF8String]));
	}
}
