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

// Forward-declare both the public and private variants of the method so the
// compiler knows the selectors exist without needing private headers.
// macOS 26.3 uses the public name; later 26.x builds renamed it with a
// leading underscore. We override both to stay robust across beta changes.
@interface NSWindow (NSDisplayCycle_Private)
- (void)postWindowNeedsUpdateConstraints;
- (void)_postWindowNeedsUpdateConstraints;
@end

@implementation AegisOverlayWindow

- (void)postWindowNeedsUpdateConstraints {
    @try {
        [super postWindowNeedsUpdateConstraints];
    } @catch (NSException *exception) {
        // macOS 26 throws here for borderless overlay windows.
        // Safe to suppress — NSHostingView re-requests on the next cycle.
    }
}

- (void)_postWindowNeedsUpdateConstraints {
    @try {
        [super _postWindowNeedsUpdateConstraints];
    } @catch (NSException *exception) {
        // macOS 26 renamed postWindowNeedsUpdateConstraints to this private
        // variant in a later 26.x build. Same suppression applies.
    }
}

@end

@implementation AegisOverlayPanel

- (void)postWindowNeedsUpdateConstraints {
    @try {
        [super postWindowNeedsUpdateConstraints];
    } @catch (NSException *exception) {
        // macOS 26 throws here for borderless panel windows.
        // Safe to suppress — NSHostingView re-requests on the next cycle.
    }
}

- (void)_postWindowNeedsUpdateConstraints {
    @try {
        [super _postWindowNeedsUpdateConstraints];
    } @catch (NSException *exception) {
        // macOS 26 renamed postWindowNeedsUpdateConstraints to this private
        // variant in a later 26.x build. Same suppression applies.
    }
}

@end
