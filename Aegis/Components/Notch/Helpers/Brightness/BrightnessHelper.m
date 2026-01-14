//
//  BrightnessHelper.m
//  Aegis
//

#import "BrightnessHelper.h"
#import <dlfcn.h>

NSString * const AegisBrightnessChangedNotification = @"AegisBrightnessChanged";

// Function pointer types for DisplayServices functions
typedef int (*DisplayServicesGetBrightnessFunc)(CGDirectDisplayID display, float *brightness);
typedef int (*DisplayServicesSetBrightnessFunc)(CGDirectDisplayID display, float brightness);
typedef int (*DisplayServicesRegisterFunc)(CGDirectDisplayID display, CGDirectDisplayID displayObserver, void (*callback)(CGDirectDisplayID, void *));
typedef int (*DisplayServicesUnregisterFunc)(CGDirectDisplayID display, CGDirectDisplayID displayObserver);

static void BrightnessChangeCallback(CGDirectDisplayID display, void *userInfo) {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:AegisBrightnessChangedNotification
        object:nil
        userInfo:nil];
}

@implementation BrightnessHelper {
    BOOL isMonitoring;
    void *displayServicesHandle;
    DisplayServicesGetBrightnessFunc getBrightnessFunc;
    DisplayServicesSetBrightnessFunc setBrightnessFunc;
    DisplayServicesRegisterFunc registerFunc;
    DisplayServicesUnregisterFunc unregisterFunc;
}

+ (BrightnessHelper *)shared {
    static BrightnessHelper *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[BrightnessHelper alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        isMonitoring = NO;
        [self loadDisplayServicesFramework];
    }
    return self;
}

- (void)loadDisplayServicesFramework {
    // Load the DisplayServices framework dynamically
    displayServicesHandle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY);

    if (!displayServicesHandle) {
        NSLog(@"Failed to load DisplayServices framework: %s", dlerror());
        return;
    }

    // Load function pointers
    getBrightnessFunc = (DisplayServicesGetBrightnessFunc)dlsym(displayServicesHandle, "DisplayServicesGetBrightness");
    setBrightnessFunc = (DisplayServicesSetBrightnessFunc)dlsym(displayServicesHandle, "DisplayServicesSetBrightness");
    registerFunc = (DisplayServicesRegisterFunc)dlsym(displayServicesHandle, "DisplayServicesRegisterForBrightnessChangeNotifications");
    unregisterFunc = (DisplayServicesUnregisterFunc)dlsym(displayServicesHandle, "DisplayServicesUnregisterForBrightnessChangeNotifications");

    if (!getBrightnessFunc || !setBrightnessFunc || !registerFunc || !unregisterFunc) {
        NSLog(@"Failed to load DisplayServices functions: %s", dlerror());
    }
}

- (float)getBrightness {
    if (!getBrightnessFunc) {
        return 0.0;
    }

    float brightness = 0.0;
    getBrightnessFunc(CGMainDisplayID(), &brightness);
    return brightness;
}

- (void)setBrightness:(float)brightness {
    if (!setBrightnessFunc) {
        return;
    }

    setBrightnessFunc(CGMainDisplayID(), brightness);
}

- (void)startMonitoring {
    if (!isMonitoring && registerFunc) {
        registerFunc(
            CGMainDisplayID(),
            CGMainDisplayID(),
            BrightnessChangeCallback
        );
        isMonitoring = YES;
    }
}

- (void)stopMonitoring {
    if (isMonitoring && unregisterFunc) {
        unregisterFunc(
            CGMainDisplayID(),
            CGMainDisplayID()
        );
        isMonitoring = NO;
    }
}

- (void)dealloc {
    [self stopMonitoring];

    if (displayServicesHandle) {
        dlclose(displayServicesHandle);
    }
}

@end
