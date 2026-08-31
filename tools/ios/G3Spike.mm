// G3 spike：验证 Godot iOS 渲染层能否透明合成（方案A 的 iOS 命门）。
// 判定：垫底橙色视图透出角色四周 = PASS；仍是黑/灰底 = 运行时路死，转引擎 patch。
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static void g3_apply(void) {
    UIWindow *w = UIApplication.sharedApplication.windows.firstObject;
    if (!w) { NSLog(@"[G3] no window yet"); return; }
    UIView *root = w.rootViewController.view;
    NSLog(@"[G3] window=%@ rootVC=%@ rootView=%@", w, w.rootViewController, root);

    // 垫底视图：亮橙 + 白色斜排大字，透出来即 PASS
    UIView *bg = [[UIView alloc] initWithFrame:w.bounds];
    bg.backgroundColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.15 alpha:1.0];
    bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, w.bounds.size.height, 140)];
    lb.text = @"G3 UNDERLAY · G3 UNDERLAY";
    lb.font = [UIFont boldSystemFontOfSize:56];
    lb.textColor = UIColor.whiteColor;
    lb.textAlignment = NSTextAlignmentCenter;
    lb.center = CGPointMake(w.bounds.size.width / 2, w.bounds.size.height / 2);
    lb.transform = CGAffineTransformMakeRotation(-M_PI_4);
    [bg addSubview:lb];
    [w insertSubview:bg atIndex:0];

    // 透明化整条链：window 背景、root 起的全部视图与图层、所有 CAMetalLayer
    w.backgroundColor = UIColor.clearColor;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        v.opaque = NO;
        v.backgroundColor = UIColor.clearColor;
        [stack addObjectsFromArray:v.subviews];
        NSMutableArray<CALayer *> *ls = [NSMutableArray arrayWithObject:v.layer];
        while (ls.count) {
            CALayer *l = ls.lastObject;
            [ls removeLastObject];
            if ([l isKindOfClass:[CAMetalLayer class]]) {
                l.opaque = NO;
                NSLog(@"[G3] CAMetalLayer %@ -> opaque=NO fmt=%ld", l, (long)((CAMetalLayer *)l).pixelFormat);
            }
            if (l.sublayers) {
                [ls addObjectsFromArray:l.sublayers];
            }
        }
    }
    NSLog(@"[G3] applied. root.layer=%@ sublayers=%@", root.layer, root.layer.sublayers);
}

@interface G3Spike : NSObject
@end

@implementation G3Spike
+ (void)load {
    // 引擎视图就绪后再动手；8s 补一发防层重建（重复插的垫底视图无害）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ g3_apply(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ g3_apply(); });
}
@end
