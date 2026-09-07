#include "sensen_photo_picker.h"

#import <Foundation/Foundation.h>
#import <PhotosUI/PhotosUI.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// PhotosUI 不在 Godot 导出的 Xcode 工程的链接列表里，.gdextension 也没法加系统框架：
// 运行时 dlopen 一次，类名全部用 NSClassFromString 取，编译期不产生对框架符号的引用。
static bool load_photos_ui() {
	static void *handle = dlopen("/System/Library/Frameworks/PhotosUI.framework/PhotosUI", RTLD_NOW);
	return handle != nullptr;
}

/// 长边缩到 max_side（<=0 不缩），顺带把 EXIF 方向画正、HEIC 转位图。
static UIImage *normalize_image(UIImage *img, int max_side) {
	CGSize size = img.size;
	CGFloat longest = MAX(size.width, size.height);
	if (longest <= 0) {
		return nil;
	}
	CGFloat factor = (max_side > 0 && longest > max_side) ? (CGFloat)max_side / longest : 1.0;
	CGSize target = CGSizeMake(MAX(1, floor(size.width * factor)), MAX(1, floor(size.height * factor)));
	UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
	format.scale = 1.0;
	format.opaque = YES;
	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:target format:format];
	return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
		[img drawInRect:CGRectMake(0, 0, target.width, target.height)];
	}];
}

static UIViewController *top_view_controller() {
	UIWindow *window = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if ([scene isKindOfClass:[UIWindowScene class]]) {
			for (UIWindow *w in ((UIWindowScene *)scene).windows) {
				if (w.isKeyWindow) {
					window = w;
				}
			}
		}
	}
	if (window == nil) {
		window = UIApplication.sharedApplication.delegate.window;
	}
	UIViewController *vc = window.rootViewController;
	while (vc.presentedViewController != nil) {
		vc = vc.presentedViewController;
	}
	return vc;
}

@interface SensenPickerDelegate : NSObject <PHPickerViewControllerDelegate>
@property(nonatomic) int maxSide;
@property(nonatomic) float quality;
@end

@implementation SensenPickerDelegate

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
	[picker dismissViewControllerAnimated:YES completion:nil];
	int maxSide = self.maxSide;
	float quality = self.quality;
	NSArray<PHPickerResult *> *items = results;
	// 解码 + 缩放在后台队列做，一张 12MP 的 HEIC 要几百毫秒，别卡主线程。
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"sensen_picks"];
		[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
		NSMutableArray *slots = [NSMutableArray arrayWithCapacity:items.count];
		for (NSUInteger i = 0; i < items.count; i++) {
			[slots addObject:[NSNull null]];
		}
		dispatch_group_t group = dispatch_group_create();
		[items enumerateObjectsUsingBlock:^(PHPickerResult *result, NSUInteger idx, BOOL *stop) {
			NSItemProvider *provider = result.itemProvider;
			if (![provider canLoadObjectOfClass:[UIImage class]]) {
				return;
			}
			dispatch_group_enter(group);
			[provider loadObjectOfClass:[UIImage class] completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
				UIImage *image = [object isKindOfClass:[UIImage class]] ? (UIImage *)object : nil;
				UIImage *normalized = image != nil ? normalize_image(image, maxSide) : nil;
				NSData *jpeg = normalized != nil ? UIImageJPEGRepresentation(normalized, quality) : nil;
				if (jpeg != nil) {
					NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.jpg", [[NSUUID UUID] UUIDString]]];
					if ([jpeg writeToFile:path atomically:YES]) {
						@synchronized(slots) {
							slots[idx] = path;
						}
					}
				}
				dispatch_group_leave(group);
			}];
		}];
		dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
		dispatch_async(dispatch_get_main_queue(), ^{
			PackedStringArray out;
			for (id slot in slots) {
				if ([slot isKindOfClass:[NSString class]]) {
					out.push_back(String([(NSString *)slot UTF8String]));
				}
			}
			if (SensenPhotoPicker::get_singleton() != nullptr) {
				SensenPhotoPicker::get_singleton()->_deliver(out, "");
			}
		});
	});
}

@end

static SensenPickerDelegate *g_delegate = nil;

SensenPhotoPicker *SensenPhotoPicker::singleton = nullptr;

SensenPhotoPicker *SensenPhotoPicker::get_singleton() {
	return singleton;
}

SensenPhotoPicker::SensenPhotoPicker() {
	singleton = this;
}

SensenPhotoPicker::~SensenPhotoPicker() {
	if (singleton == this) {
		singleton = nullptr;
	}
}

void SensenPhotoPicker::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_available"), &SensenPhotoPicker::is_available);
	ClassDB::bind_method(D_METHOD("is_picking"), &SensenPhotoPicker::is_picking);
	ClassDB::bind_method(D_METHOD("pick_images", "max_count", "max_side", "jpeg_quality"), &SensenPhotoPicker::pick_images, DEFVAL(9), DEFVAL(2048), DEFVAL(0.85f));
	ADD_SIGNAL(MethodInfo("picked", PropertyInfo(Variant::PACKED_STRING_ARRAY, "paths"), PropertyInfo(Variant::STRING, "error")));
}

bool SensenPhotoPicker::is_available() const {
	if (@available(iOS 14.0, *)) {
		return load_photos_ui() && NSClassFromString(@"PHPickerViewController") != nil;
	}
	return false;
}

bool SensenPhotoPicker::is_picking() const {
	return picking;
}

bool SensenPhotoPicker::pick_images(int max_count, int max_side, float jpeg_quality) {
	if (picking || !is_available()) {
		return false;
	}
	Class config_class = NSClassFromString(@"PHPickerConfiguration");
	Class picker_class = NSClassFromString(@"PHPickerViewController");
	Class filter_class = NSClassFromString(@"PHPickerFilter");
	if (config_class == nil || picker_class == nil || filter_class == nil) {
		return false;
	}
	picking = true;
	int count = MAX(1, max_count);
	int side = max_side;
	float quality = MIN(1.0f, MAX(0.1f, jpeg_quality));
	dispatch_async(dispatch_get_main_queue(), ^{
		PHPickerConfiguration *config = [[config_class alloc] init];
		config.selectionLimit = count;
		config.filter = [filter_class imagesFilter];
		if (@available(iOS 15.0, *)) {
			config.selection = PHPickerConfigurationSelectionOrdered;
		}
		PHPickerViewController *picker = [[picker_class alloc] initWithConfiguration:config];
		g_delegate = [SensenPickerDelegate new];
		g_delegate.maxSide = side;
		g_delegate.quality = quality;
		picker.delegate = g_delegate;
		UIViewController *host = top_view_controller();
		if (host == nil) {
			if (SensenPhotoPicker::get_singleton() != nullptr) {
				SensenPhotoPicker::get_singleton()->_deliver(PackedStringArray(), "NO_VIEW_CONTROLLER");
			}
			return;
		}
		[host presentViewController:picker animated:YES completion:nil];
	});
	return true;
}

void SensenPhotoPicker::_deliver(const PackedStringArray &paths, const String &error) {
	picking = false;
	g_delegate = nil;
	emit_signal("picked", paths, error);
}
