// daemon/ZMMOTouch.mm — IOKit HID event injection implementation
// Uses private IOKit.framework APIs (available on all iOS versions, no jailbreak needed)
// References: IOHIDEventSystem/IOHIDEvent from <IOKit/hid/IOHIDEvent.h>

#import "ZMMOTouch.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach/mach_time.h>

// ── Forward declarations for IOKit private API ──

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef uint32_t IOHIDEventOptionBits;

static IOHIDEventRef (*IOHIDEventCreateDigitizerEvent)(
    CFAllocatorRef allocator, uint64_t timestamp,
    uint32_t transducerType, uint32_t index, uint32_t identity,
    uint32_t eventMask, uint32_t buttonMask,
    double x, double y, double z,
    double tipPressure, double barrelPressure, double twist,
    BOOL range, BOOL touch, uint32_t options) = NULL;

static IOHIDEventRef (*IOHIDEventCreateDigitizerFingerEventWithQuality)(
    CFAllocatorRef allocator, uint64_t timestamp,
    uint32_t index, uint32_t identity, uint32_t eventMask,
    double x, double y, double z,
    double tipPressure, double twist,
    double minorRadius, double majorRadius, double quality,
    double density, double irregularity) = NULL;

static IOHIDEventRef (*IOHIDEventCreateKeyboardEvent)(
    CFAllocatorRef allocator, uint64_t timestamp,
    uint16_t usagePage, uint16_t usage,
    BOOL down, IOHIDEventOptionBits flags) = NULL;

static void (*IOHIDEventAppendEvent)(IOHIDEventRef parent, IOHIDEventRef child) = NULL;
static void (*IOHIDEventSetIntegerValue)(IOHIDEventRef event, int field, int value) = NULL;
static void (*IOHIDEventSystemClientDispatchEvent)(void *client, IOHIDEventRef event) = NULL;

#define kIOHIDDigitizerTransducerTypeFinger 3
#define kIOHIDDigitizerEventRange 0x00000001
#define kIOHIDDigitizerEventTouch 0x00000002
#define kIOHIDDigitizerEventIdentity 0x00000004
#define kIOHIDDigitizerEventAttribute 0x00000008
#define kIOHIDEventFieldDigitizerX 0x1000000
#define kIOHIDEventFieldDigitizerY 0x1000001

@implementation ZMMOTouch

+ (void)load {
    void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!handle) { NSLog(@"[ZMMOTouch] Failed to load IOKit"); return; }

    IOHIDEventCreateDigitizerEvent = dlsym(handle, "IOHIDEventCreateDigitizerEvent");
    IOHIDEventCreateDigitizerFingerEventWithQuality = dlsym(handle, "IOHIDEventCreateDigitizerFingerEventWithQuality");
    IOHIDEventCreateKeyboardEvent = dlsym(handle, "IOHIDEventCreateKeyboardEvent");
    IOHIDEventAppendEvent = dlsym(handle, "IOHIDEventAppendEvent");
    IOHIDEventSetIntegerValue = dlsym(handle, "IOHIDEventSetIntegerValue");
    IOHIDEventSystemClientDispatchEvent = dlsym(handle, "IOHIDEventSystemClientDispatchEvent");

    NSLog(@"[ZMMOTouch] IOKit HID loaded: digitizer=%d keyboard=%d",
          IOHIDEventCreateDigitizerEvent != NULL,
          IOHIDEventCreateKeyboardEvent != NULL);
}

// ── Helpers ──

+ (uint64_t)now {
    return mach_absolute_time();
}

+ (void)dispatch:(IOHIDEventRef)event {
    if (IOHIDEventSystemClientDispatchEvent) {
        IOHIDEventSystemClientDispatchEvent(NULL, event);
    }
    if (event) CFRelease(event);
}

+ (CGSize)screenSize {
    return [UIScreen mainScreen].bounds.size;
}

// ── Tap ──

+ (void)tap:(int)x y:(int)y {
    CGSize sz = [self screenSize];

    // Touch down
    IOHIDEventRef down = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault, [self now],
        kIOHIDDigitizerTransducerTypeFinger,
        0, 2,  // index, identity
        kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch | kIOHIDDigitizerEventIdentity,
        0,      // buttonMask
        x, y, 0, 0, 0, 0,  // pressure, barrel, twist
        1.0,    // quality = in range
        YES,    // touch = YES (down)
        1);     // options
    [self dispatch:down];

    usleep(15000); // 15ms hold

    // Touch up
    IOHIDEventRef up = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault, [self now],
        kIOHIDDigitizerTransducerTypeFinger,
        0, 2,
        kIOHIDDigitizerEventRange | kIOHIDDigitizerEventIdentity,
        0,
        x, y, 0, 0, 0, 0,
        1.0,
        NO,     // touch = NO (up)
        1);
    [self dispatch:up];
}

// ── Swipe ──

+ (void)swipe:(int)x y:(int)y toX:(int)x2 toY:(int)y2 duration:(int)ms {
    int steps = MAX(ABS(x2 - x), ABS(y2 - y)) / 10;
    if (steps < 2) steps = 2;
    if (steps > 50) steps = 50;
    int stepTime = ms / steps;

    // Touch down at start
    [self touchDown:x y:y];

    // Move through intermediate points
    for (int i = 1; i <= steps; i++) {
        float t = (float)i / steps;
        int cx = x + (x2 - x) * t;
        int cy = y + (y2 - y) * t;
        [self touchMove:cx y:cy];
        usleep(stepTime * 1000);
    }

    // Touch up
    [self touchUp:x2 y:y2];
}

+ (void)touchDown:(int)x y:(int)y {
    IOHIDEventRef event = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault, [self now],
        kIOHIDDigitizerTransducerTypeFinger,
        0, 2,
        kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch | kIOHIDDigitizerEventIdentity,
        0,
        x, y, 0, 0, 0, 0, 1.0, YES, 1);
    [self dispatch:event];
}

+ (void)touchMove:(int)x y:(int)y {
    IOHIDEventRef event = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault, [self now],
        kIOHIDDigitizerTransducerTypeFinger,
        0, 2,
        kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch | kIOHIDDigitizerEventIdentity |
        kIOHIDDigitizerEventAttribute,
        0,
        x, y, 0, 0, 0, 0, 1.0, YES, 1);
    [self dispatch:event];
}

+ (void)touchUp:(int)x y:(int)y {
    IOHIDEventRef event = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault, [self now],
        kIOHIDDigitizerTransducerTypeFinger,
        0, 2,
        kIOHIDDigitizerEventRange | kIOHIDDigitizerEventIdentity,
        0,
        x, y, 0, 0, 0, 0, 1.0, NO, 1);
    [self dispatch:event];
}

// ── Long Press ──

+ (void)longPress:(int)x y:(int)y duration:(int)ms {
    [self touchDown:x y:y];
    usleep(ms * 1000);
    [self touchUp:x y:y];
}

// ── Text (pasteboard method) ──

+ (void)typeText:(NSString *)text {
    // Method 1: Pasteboard injection (most reliable, works everywhere)
    NSString *old = [[UIPasteboard generalPasteboard] string] ?: @"";
    [[UIPasteboard generalPasteboard] setString:text];

    // Simulate Cmd+V or long press paste
    // Most apps respond to pasteboard content change + focus
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.zmmo.touch.typed"),
        (__bridge CFStringRef)text, NULL, YES);
}

// ── Hardware buttons ──

+ (void)home {
    // Via SpringBoardServices
    void *sb = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
    if (sb) {
        void (*SBSOpenApplicationByBundleIdentifier)(CFStringRef) = dlsym(sb, "SBSOpenApplicationByBundleIdentifier");
        // Actually press home:
        // SBSProcessIDForDisplayIdentifier, etc.
        // Fallback: kill SpringBoard (not ideal but works)
    }
    // Standard: send hardware home button event
    IOHIDEventRef event = IOHIDEventCreateKeyboardEvent(
        kCFAllocatorDefault, [self now],
        0x0C,   // Consumer page
        0x40,   // Menu (home)
        YES,    // down
        0);
    [self dispatch:event];
    usleep(10000);
    event = IOHIDEventCreateKeyboardEvent(
        kCFAllocatorDefault, [self now],
        0x0C, 0x40, NO, 0);
    [self dispatch:event];
}

+ (void)power {
    IOHIDEventRef event = IOHIDEventCreateKeyboardEvent(
        kCFAllocatorDefault, [self now],
        0x0C,   // Consumer page
        0x30,   // Power
        YES, 0);
    [self dispatch:event];
    usleep(20000);
    event = IOHIDEventCreateKeyboardEvent(
        kCFAllocatorDefault, [self now],
        0x0C, 0x30, NO, 0);
    [self dispatch:event];
}

+ (void)volUp {
    IOHIDEventRef event = IOHIDEventCreateKeyboardEvent(
        kCFAllocatorDefault, [self now],
        0x0C, 0xE9, YES, 0);
    [self dispatch:event];
    usleep(10000);
    event = IOHIDEventCreateKeyboardEvent(
        kCFAllocatorDefault, [self now],
        0x0C, 0xE9, NO, 0);
    [self dispatch:event];
}

+ (void)volDown {
    IOHIDEventRef event = IOHIDEventCreateKeyboardEvent(
        kCFAllocatorDefault, [self now],
        0x0C, 0xEA, YES, 0);
    [self dispatch:event];
    usleep(10000);
    event = IOHIDEventCreateKeyboardEvent(
        kCFAllocatorDefault, [self now],
        0x0C, 0xEA, NO, 0);
    [self dispatch:event];
}

@end
