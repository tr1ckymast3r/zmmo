// daemon/ZMMOTouch.h — Native IOKit HID touch injection (zero external deps)
// No autotouch needed. Direct IOHIDEventSystemClient API.

#import <Foundation/Foundation.h>

@interface ZMMOTouch : NSObject

/// Tap at absolute screen coordinates
+ (void)tap:(int)x y:(int)y;

/// Swipe from (x,y) to (x2,y2) with duration in milliseconds
+ (void)swipe:(int)x y:(int)y toX:(int)x2 toY:(int)y2 duration:(int)ms;

/// Long press at coordinates
+ (void)longPress:(int)x y:(int)y duration:(int)ms;

/// Type text via pasteboard injection (standard method)
+ (void)typeText:(NSString *)text;

/// Home button
+ (void)home;

/// Power button (lock screen)
+ (void)power;

/// Volume up
+ (void)volUp;

/// Volume down
+ (void)volDown;

@end
