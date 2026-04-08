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

/// Base NSWindow subclass for all Aegis overlay windows.
/// Overrides postWindowNeedsUpdateConstraints to catch the ObjC exception
/// thrown by macOS 26 for borderless overlay windows.
#import <AppKit/AppKit.h>
@interface AegisOverlayWindow : NSWindow
@end

/// Base NSPanel subclass for Aegis panel windows.
/// Same macOS 26 postWindowNeedsUpdateConstraints fix as AegisOverlayWindow.
@interface AegisOverlayPanel : NSPanel
@end

#endif /* BrightnessHelper_h */
