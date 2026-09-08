#include "sensen_push.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <objc/message.h>
#include <objc/runtime.h>

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable.hpp>

using namespace godot;

// UserNotifications 不在 Godot 导出的 Xcode 工程的链接列表里（.gdextension 也没法加系统框架）：
// 运行时 dlopen 一次，类用 NSClassFromString 取，编译期不产生对框架符号的引用（同 PhotosUI 的做法）。
static bool load_user_notifications() {
	static void *handle = dlopen("/System/Library/Frameworks/UserNotifications.framework/UserNotifications", RTLD_NOW);
	return handle != nullptr;
}

// 本地声明要用的两个接口：不 import 头文件，就不会在编译期引用框架符号。
@protocol SensenUNCenter <NSObject>
- (void)requestAuthorizationWithOptions:(NSUInteger)options completionHandler:(void (^)(BOOL granted, NSError *error))handler;
- (void)getNotificationSettingsWithCompletionHandler:(void (^)(id settings))handler;
- (void)setDelegate:(id)delegate;
@end

// UNAuthorizationOptions：Badge=1<<0, Sound=1<<1, Alert=1<<2。
static const NSUInteger kAuthOptions = (1 << 0) | (1 << 1) | (1 << 2);
// UNNotificationPresentationOptions：Badge=1<<0, Sound=1<<1, List=1<<3, Banner=1<<4。
static const NSUInteger kPresentOptions = (1 << 0) | (1 << 1) | (1 << 3) | (1 << 4);
// UNAuthorizationStatus：NotDetermined=0, Denied=1, Authorized=2, Provisional=3, Ephemeral=4。
static const NSInteger kStatusNotDetermined = 0;
static const NSInteger kStatusDenied = 1;

static id un_center() {
	if (!load_user_notifications()) {
		return nil;
	}
	Class cls = NSClassFromString(@"UNUserNotificationCenter");
	if (cls == nil) {
		return nil;
	}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	return [cls performSelector:@selector(currentNotificationCenter)];
#pragma clang diagnostic pop
}

/// NSDictionary（可能嵌套、可能带非 JSON 值）→ Godot Dictionary，只留字符串与数字。
/// 推送 payload 里本来就只有路由用的 id（正文不进推送，见 E2），不做递归展开。
static Dictionary to_dictionary(NSDictionary *info) {
	Dictionary out;
	for (NSString *key in info) {
		if (![key isKindOfClass:[NSString class]]) {
			continue;
		}
		id value = info[key];
		if ([value isKindOfClass:[NSString class]]) {
			out[String([key UTF8String])] = String([(NSString *)value UTF8String]);
		} else if ([value isKindOfClass:[NSNumber class]]) {
			out[String([key UTF8String])] = (double)[(NSNumber *)value doubleValue];
		}
	}
	return out;
}

static void deliver_notification(id notification, bool opened) {
	SensenPush *push = SensenPush::get_singleton();
	if (push == nullptr || notification == nil) {
		return;
	}
	// UNNotification.request.content.userInfo —— 用 KVC 走，免得引框架头文件。
	id request = [notification valueForKey:@"request"];
	id content = request != nil ? [request valueForKey:@"content"] : nil;
	id info = content != nil ? [content valueForKey:@"userInfo"] : nil;
	Dictionary payload;
	if ([info isKindOfClass:[NSDictionary class]]) {
		payload = to_dictionary((NSDictionary *)info);
	}
	push->call_deferred("_deliver_notification", payload, opened);
}

/// UNUserNotificationCenterDelegate：不声明协议一致性，系统按选择器调用，实现了就够。
@interface SensenPushDelegate : NSObject
@end

@implementation SensenPushDelegate

- (void)userNotificationCenter:(id)center willPresentNotification:(id)notification withCompletionHandler:(void (^)(NSUInteger))completionHandler {
	deliver_notification(notification, false);
	completionHandler(kPresentOptions); // 应用在前台时也把横幅显出来
}

- (void)userNotificationCenter:(id)center didReceiveNotificationResponse:(id)response withCompletionHandler:(void (^)(void))completionHandler {
	deliver_notification(response != nil ? [response valueForKey:@"notification"] : nil, true);
	completionHandler();
}

@end

static SensenPushDelegate *push_delegate() {
	static SensenPushDelegate *shared = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		shared = [[SensenPushDelegate alloc] init];
	});
	return shared;
}

static String hex_token(NSData *data) {
	const unsigned char *bytes = (const unsigned char *)data.bytes;
	NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
	for (NSUInteger i = 0; i < data.length; i++) {
		[hex appendFormat:@"%02x", bytes[i]];
	}
	return String([hex UTF8String]);
}

// —— app delegate 注入 ——
// Godot 的 iOS app delegate 不转发 didRegisterForRemoteNotifications*，而这两个回调只会发给
// UIApplication.delegate。所以运行时往它的类上装两个方法：原本没有就直接加（绝大多数情况），
// 已经有就交换实现并在自己这份里回调原实现（别人也装过的话不能把人家挤掉）。
static void sensen_did_register(id self_obj, SEL _cmd, UIApplication *app, NSData *token) {
	SensenPush *push = SensenPush::get_singleton();
	if (push != nullptr) {
		push->call_deferred("_deliver_token", hex_token(token));
	}
	SEL original = NSSelectorFromString(@"sensen_original_didRegisterForRemoteNotificationsWithDeviceToken:");
	if ([self_obj respondsToSelector:original]) {
		((void (*)(id, SEL, UIApplication *, NSData *))objc_msgSend)(self_obj, original, app, token);
	}
}

static void sensen_did_fail(id self_obj, SEL _cmd, UIApplication *app, NSError *error) {
	SensenPush *push = SensenPush::get_singleton();
	if (push != nullptr) {
		NSString *reason = error.localizedDescription ?: @"unknown";
		push->call_deferred("_deliver_token_failed", String([reason UTF8String]));
	}
	SEL original = NSSelectorFromString(@"sensen_original_didFailToRegisterForRemoteNotificationsWithError:");
	if ([self_obj respondsToSelector:original]) {
		((void (*)(id, SEL, UIApplication *, NSError *))objc_msgSend)(self_obj, original, app, error);
	}
}

static void install_one(Class cls, SEL selector, IMP replacement, const char *types, NSString *keep_name) {
	Method existing = class_getInstanceMethod(cls, selector);
	if (existing == NULL) {
		class_addMethod(cls, selector, replacement, types);
		return;
	}
	// 已有实现：搬到 sensen_original_… 上留着，再把原槽位换成我们的。
	SEL keep = NSSelectorFromString(keep_name);
	class_addMethod(cls, keep, method_getImplementation(existing), method_getTypeEncoding(existing));
	method_setImplementation(existing, replacement);
}

static void install_delegate_hooks() {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		id delegate = UIApplication.sharedApplication.delegate;
		if (delegate == nil) {
			return;
		}
		Class cls = object_getClass(delegate);
		install_one(cls, @selector(application:didRegisterForRemoteNotificationsWithDeviceToken:),
				(IMP)sensen_did_register, "v@:@@",
				@"sensen_original_didRegisterForRemoteNotificationsWithDeviceToken:");
		install_one(cls, @selector(application:didFailToRegisterForRemoteNotificationsWithError:),
				(IMP)sensen_did_fail, "v@:@@",
				@"sensen_original_didFailToRegisterForRemoteNotificationsWithError:");
	});
}

// —— GDExtension 侧 ——

SensenPush *SensenPush::singleton = nullptr;

SensenPush *SensenPush::get_singleton() { return singleton; }

SensenPush::SensenPush() { singleton = this; }

SensenPush::~SensenPush() {
	if (singleton == this) {
		singleton = nullptr;
	}
}

void SensenPush::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_available"), &SensenPush::is_available);
	ClassDB::bind_method(D_METHOD("request_authorization"), &SensenPush::request_authorization);
	ClassDB::bind_method(D_METHOD("register_for_remote"), &SensenPush::register_for_remote);
	ClassDB::bind_method(D_METHOD("token"), &SensenPush::token);
	ClassDB::bind_method(D_METHOD("platform"), &SensenPush::platform);
	// 原生线程回调经 call_deferred 走这几个入口，必须绑出来。
	ClassDB::bind_method(D_METHOD("_deliver_authorization", "granted"), &SensenPush::_deliver_authorization);
	ClassDB::bind_method(D_METHOD("_deliver_token", "token"), &SensenPush::_deliver_token);
	ClassDB::bind_method(D_METHOD("_deliver_token_failed", "reason"), &SensenPush::_deliver_token_failed);
	ClassDB::bind_method(D_METHOD("_deliver_notification", "payload", "opened"), &SensenPush::_deliver_notification);
	ADD_SIGNAL(MethodInfo("authorization", PropertyInfo(Variant::BOOL, "granted")));
	ADD_SIGNAL(MethodInfo("token_ready", PropertyInfo(Variant::STRING, "token")));
	ADD_SIGNAL(MethodInfo("token_failed", PropertyInfo(Variant::STRING, "reason")));
	ADD_SIGNAL(MethodInfo("notification", PropertyInfo(Variant::DICTIONARY, "payload"), PropertyInfo(Variant::BOOL, "opened")));
}

bool SensenPush::is_available() const {
	return un_center() != nil;
}

void SensenPush::request_authorization() {
	id<SensenUNCenter> center = (id<SensenUNCenter>)un_center();
	if (center == nil) {
		call_deferred("_deliver_authorization", false);
		return;
	}
	[center setDelegate:push_delegate()];
	install_delegate_hooks();
	// 先看已有状态：已经拒过就不再弹（系统也不会弹第二次），直接回结果，
	// 免得上层以为「弹了但用户没反应」。
	[center getNotificationSettingsWithCompletionHandler:^(id settings) {
		NSNumber *status = settings != nil ? [settings valueForKey:@"authorizationStatus"] : nil;
		NSInteger value = status != nil ? [status integerValue] : kStatusNotDetermined;
		if (value == kStatusDenied) {
			SensenPush::get_singleton()->call_deferred("_deliver_authorization", false);
			return;
		}
		if (value != kStatusNotDetermined) {
			SensenPush::get_singleton()->call_deferred("_deliver_authorization", true);
			return;
		}
		[center requestAuthorizationWithOptions:kAuthOptions
				completionHandler:^(BOOL granted, NSError *error) {
					SensenPush::get_singleton()->call_deferred("_deliver_authorization", (bool)granted);
				}];
	}];
}

void SensenPush::register_for_remote() {
	install_delegate_hooks();
	dispatch_async(dispatch_get_main_queue(), ^{
		[UIApplication.sharedApplication registerForRemoteNotifications];
	});
}

String SensenPush::token() const { return device_token; }

String SensenPush::platform() const { return String("ios"); }

void SensenPush::_deliver_authorization(bool granted) { emit_signal("authorization", granted); }

void SensenPush::_deliver_token(const String &token) {
	device_token = token;
	emit_signal("token_ready", token);
}

void SensenPush::_deliver_token_failed(const String &reason) { emit_signal("token_failed", reason); }

void SensenPush::_deliver_notification(const Dictionary &payload, bool opened) {
	emit_signal("notification", payload, opened);
}
