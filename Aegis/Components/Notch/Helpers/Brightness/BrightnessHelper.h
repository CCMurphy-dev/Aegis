//
//  BrightnessHelper.h
//  Aegis
//

#ifndef BrightnessHelper_h
#define BrightnessHelper_h

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Notification name that will be posted when brightness changes
extern NSString * _Nonnull const AegisBrightnessChangedNotification;

@interface BrightnessHelper : NSObject

+ (BrightnessHelper * _Nonnull)shared;

/// Get current brightness level (0.0 - 1.0)
- (float)getBrightness;

/// Set brightness level (0.0 - 1.0)
- (void)setBrightness:(float)brightness;

/// Start monitoring brightness changes
- (void)startMonitoring;

/// Stop monitoring brightness changes
- (void)stopMonitoring;

@end

#endif /* BrightnessHelper_h */
