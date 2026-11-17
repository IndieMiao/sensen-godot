// GENSEN_VOICE_MEDIA_QA_V1: QA starts only its manual voice panel, no map/login/notification bridges.
#import <Foundation/Foundation.h>
@interface G3Spike : NSObject
@end
@implementation G3Spike
+ (void)load {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Class voice = NSClassFromString(@"VoiceIOS");
        if (voice) [voice performSelector:@selector(setup)];
    });
}
@end
