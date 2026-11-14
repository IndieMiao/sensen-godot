// iOS 启动引导：延迟拉起 MapUnderlay（Swift 无 +load，用 ObjC 引导）。
// 历史：本文件最初是 G3 透明验证 spike（橙色垫底，2026-08-31 真机通过，见
// docs/superpowers/plans/2026-08-31-3dmap-g3-ios-transparency.md 与 git 历史 cd7a777）。
#import <Foundation/Foundation.h>

@interface G3Spike : NSObject
@end

@implementation G3Spike
+ (void)load {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
        Class cls = NSClassFromString(@"MapUnderlay");
        if (cls) {
            [cls performSelector:@selector(setup)];
        } else {
            NSLog(@"[G3Spike] MapUnderlay 类缺失（Swift 文件未编入？）");
        }
        Class apple = NSClassFromString(@"AppleSignIn");
        if (apple) {
            [apple performSelector:@selector(setup)];
        } else {
            NSLog(@"[G3Spike] AppleSignIn 类缺失（Swift 文件未编入？）");
        }
        Class notify = NSClassFromString(@"LocalNotify");   // SGODOT-356，inject_local_notify.py 编入
        if (notify) {
            [notify performSelector:@selector(setup)];
        } else {
            NSLog(@"[G3Spike] LocalNotify 类缺失（Swift 文件未编入？）");
        }
        Class google = NSClassFromString(@"GoogleSignInIOS");   // SGODOT-487，inject_local_notify.py 编入
        if (google) {
            [google performSelector:@selector(setup)];
        } else {
            NSLog(@"[G3Spike] GoogleSignInIOS 类缺失（Swift 文件未编入？）");
        }
    });
}
@end
