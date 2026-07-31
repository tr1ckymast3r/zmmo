// Tweak.x — ZMMODeviceProof MobileSubstrate tweak
// Hooks into iOS system frameworks to return spoofed device info
// Equivalent to KidsAutov4's DeviceProof.dylib
//
// Architecture:
//   1. On load: listen for CFNotification "com.zmmo.devicechanged"
//   2. Read config from com.zmmo.deviceinfo.plist
//   3. Hook system calls → return fake values when spoofing enabled
//
// Hooked functions:
//   - UIDevice: model, systemVersion, name, identifierForVendor
//   - MobileGestalt: MGGetStringAnswer, MGGetBoolAnswer
//   - sysctl/sysctlbyname: hw.model, kern.osproductversion, etc.
//   - CLLocationManager: GPS spoof (via delegate)
//   - NSLocale: preferredLanguages
//   - NSTimeZone: localTimeZone, systemTimeZone

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <sys/sysctl.h>
#import <dlfcn.h>
#import <CoreFoundation/CoreFoundation.h>

// ────────────────────────────────────────
#pragma mark - Config Management
// ────────────────────────────────────────

#define ZMMO_CONFIG @"/var/mobile/Library/Preferences/com.zmmo.deviceinfo.plist"
#define ZMMO_GPS_CONFIG @"/var/mobile/Library/Preferences/com.zmmo.gpsfake.plist"

static NSDictionary *loadConfig(void) {
    return [NSDictionary dictionaryWithContentsOfFile:ZMMO_CONFIG] ?: @{};
}

static BOOL isSpoofEnabled(void) {
    return [loadConfig()[@"enabled"] boolValue];
}

static NSString *fakeModel(void) {
    return loadConfig()[@"fake_model"] ?: @"";
}

static NSString *fakeVersion(void) {
    return loadConfig()[@"fake_version"] ?: @"";
}

static NSString *fakeName(void) {
    return loadConfig()[@"fake_name"] ?: @"";
}

static NSString *fakeLocale(void) {
    return loadConfig()[@"fake_locale"] ?: @"";
}

static BOOL isGPSSpoofEnabled(void) {
    return [loadConfig()[@"gps_enabled"] boolValue];
}

static NSDictionary *gpsConfig(void) {
    return [NSDictionary dictionaryWithContentsOfFile:ZMMO_GPS_CONFIG] ?: @{};
}

// ────────────────────────────────────────
#pragma mark - Notification Listener
// ────────────────────────────────────────

static void configChanged(CFNotificationCenterRef center,
                          void *observer,
                          CFStringRef name,
                          const void *object,
                          CFDictionaryRef userInfo) {
    NSLog(@"[ZMMOTweak] Config changed notification received — reloading...");
    // Config is re-read on each hook call (loadConfig())
}

%ctor {
    NSLog(@"[ZMMOTweak] ZMMODeviceProof.dylib loaded — registering hooks");

    // Listen for config changes from ios-agent daemon
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        configChanged,
        CFSTR("com.zmmo.devicechanged"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );

    NSLog(@"[ZMMOTweak] Hooks registered. Spoofing %s",
          isSpoofEnabled() ? "ENABLED" : "DISABLED");
}

// ────────────────────────────────────────
#pragma mark - UIDevice Hooks
// ────────────────────────────────────────

%hook UIDevice

- (NSString *)model {
    if (isSpoofEnabled()) {
        NSString *m = fakeModel();
        if (m.length > 0) return m;
    }
    return %orig;
}

- (NSString *)systemVersion {
    if (isSpoofEnabled()) {
        NSString *v = fakeVersion();
        if (v.length > 0) return v;
    }
    return %orig;
}

- (NSString *)name {
    if (isSpoofEnabled()) {
        NSString *n = fakeName();
        if (n.length > 0) return n;
    }
    return %orig;
}

- (NSUUID *)identifierForVendor {
    // Return a random UUID when spoofing
    if (isSpoofEnabled()) {
        return [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000001"];
    }
    return %orig;
}

%end

// ────────────────────────────────────────
#pragma mark - MobileGestalt Hooks (C functions)
// ────────────────────────────────────────

// MobileGestalt is a private framework accessed via dlsym
// We hook the C functions directly using fishhook or MSHookFunction

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef key);

static CFTypeRef hooked_MGCopyAnswer(CFStringRef key) {
    if (!isSpoofEnabled()) return orig_MGCopyAnswer(key);

    NSString *keyStr = (__bridge NSString *)key;

    // Device model
    if ([keyStr isEqualToString:@"HWModelStr"] ||
        [keyStr isEqualToString:@"ProductType"]) {
        NSString *m = fakeModel();
        if (m.length > 0) return (__bridge_retained CFTypeRef)m;
    }

    // iOS version
    if ([keyStr isEqualToString:@"ProductVersion"]) {
        NSString *v = fakeVersion();
        if (v.length > 0) return (__bridge_retained CFTypeRef)v;
    }

    // Device name
    if ([keyStr isEqualToString:@"UserAssignedDeviceName"] ||
        [keyStr isEqualToString:@"DeviceName"]) {
        NSString *n = fakeName();
        if (n.length > 0) return (__bridge_retained CFTypeRef)n;
    }

    // Locale
    if ([keyStr isEqualToString:@"RegionCode"] ||
        [keyStr isEqualToString:@"RegionalCode"]) {
        return (__bridge_retained CFTypeRef)@"LL/A";
    }

    // Screen
    if ([keyStr isEqualToString:@"MainScreenWidth"]) {
        return (__bridge_retained CFTypeRef)@(1170);
    }
    if ([keyStr isEqualToString:@"MainScreenHeight"]) {
        return (__bridge_retained CFTypeRef)@(2532);
    }
    if ([keyStr isEqualToString:@"MainScreenScale"]) {
        return (__bridge_retained CFTypeRef)@(3.0);
    }

    // UniqueDeviceID → fake
    if ([keyStr isEqualToString:@"UniqueDeviceID"]) {
        return (__bridge_retained CFTypeRef)@"00000000-0000000000000000";
    }

    // DieID / ChipID → generate random
    if ([keyStr isEqualToString:@"DieId"] || [keyStr isEqualToString:@"DieId"]) {
        return (__bridge_retained CFTypeRef)@(arc4random());
    }

    return orig_MGCopyAnswer(key);
}

static CFTypeRef (*orig_MGCopyAnswerWithError)(CFStringRef key, CFErrorRef *error);

// ────────────────────────────────────────
#pragma mark - sysctl Hooks
// ────────────────────────────────────────

static int (*orig_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp,
                                 const void *newp, size_t newlen);

static int hooked_sysctlbyname(const char *name, void *oldp, size_t *oldlenp,
                                const void *newp, size_t newlen) {
    if (isSpoofEnabled() && oldp && oldlenp) {
        NSString *nsName = [NSString stringWithCString:name encoding:NSUTF8StringEncoding];

        if ([nsName isEqualToString:@"hw.model"]) {
            NSString *m = fakeModel();
            if (m.length > 0) {
                const char *cs = [m UTF8String];
                size_t csLen = strlen(cs) + 1;
                if (*oldlenp >= csLen) {
                    memcpy(oldp, cs, csLen);
                    *oldlenp = csLen;
                    return 0;
                }
            }
        }

        if ([nsName isEqualToString:@"hw.machine"]) {
            NSString *m = fakeModel();
            if (m.length > 0) {
                const char *cs = [m UTF8String];
                size_t csLen = strlen(cs) + 1;
                if (*oldlenp >= csLen) {
                    memcpy(oldp, cs, csLen);
                    *oldlenp = csLen;
                    return 0;
                }
            }
        }

        if ([nsName isEqualToString:@"kern.osproductversion"]) {
            NSString *v = fakeVersion();
            if (v.length > 0) {
                const char *cs = [v UTF8String];
                size_t csLen = strlen(cs) + 1;
                if (*oldlenp >= csLen) {
                    memcpy(oldp, cs, csLen);
                    *oldlenp = csLen;
                    return 0;
                }
            }
        }
    }

    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

static int (*orig_sysctl)(int *name, u_int namelen, void *oldp, size_t *oldlenp,
                           const void *newp, size_t newlen);

static int hooked_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp,
                          const void *newp, size_t newlen) {
    // Only hook if spoofing enabled and we're reading
    if (isSpoofEnabled() && oldp && oldlenp && name[0] == CTL_HW && namelen >= 2) {
        if (name[1] == HW_MODEL || name[1] == HW_MACHINE) {
            NSString *m = fakeModel();
            if (m.length > 0) {
                const char *cs = [m UTF8String];
                size_t csLen = strlen(cs) + 1;
                if (*oldlenp >= csLen) {
                    memcpy(oldp, cs, csLen);
                    *oldlenp = csLen;
                    return 0;
                }
            }
        }
    }

    return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
}

// ────────────────────────────────────────
#pragma mark - NSLocale Hook
// ────────────────────────────────────────

%hook NSLocale

+ (NSString *)preferredLanguages {
    if (isSpoofEnabled()) {
        NSString *loc = fakeLocale();
        if (loc.length > 0) return @[loc];
    }
    return %orig;
}

+ (NSString *)currentLocale {
    if (isSpoofEnabled()) {
        NSString *loc = fakeLocale();
        if (loc.length > 0) {
            return [NSLocale localeWithLocaleIdentifier:loc];
        }
    }
    return %orig;
}

%end

// ────────────────────────────────────────
#pragma mark - NSTimeZone Hook
// ────────────────────────────────────────

%hook NSTimeZone

+ (NSTimeZone *)systemTimeZone {
    NSString *tzStr = loadConfig()[@"fake_timezone"];
    if (isSpoofEnabled() && tzStr.length > 0) {
        return [NSTimeZone timeZoneWithName:tzStr];
    }
    return %orig;
}

- (NSTimeZone *)localTimeZone {
    NSString *tzStr = loadConfig()[@"fake_timezone"];
    if (isSpoofEnabled() && tzStr.length > 0) {
        return [NSTimeZone timeZoneWithName:tzStr];
    }
    return %orig;
}

%end

// ────────────────────────────────────────
#pragma mark - CLLocation GPS Hook
// ────────────────────────────────────────

%hook CLLocation

- (CLLocationCoordinate2D)coordinate {
    if (isGPSSpoofEnabled()) {
        NSDictionary *gps = gpsConfig();
        double lat = [gps[@"Latitude"] doubleValue];
        double lon = [gps[@"Longitude"] doubleValue];
        if (lat != 0 && lon != 0) {
            CLLocationCoordinate2D coord;
            coord.latitude = lat;
            coord.longitude = lon;
            return coord;
        }
    }
    return %orig;
}

- (CLLocationDistance)altitude {
    if (isGPSSpoofEnabled()) {
        return 0.0; // Sea level
    }
    return %orig;
}

- (CLLocationAccuracy)horizontalAccuracy {
    if (isGPSSpoofEnabled()) {
        return 5.0; // High accuracy
    }
    return %orig;
}

%end

// ────────────────────────────────────────
#pragma mark - MSHookFunction setup
// ────────────────────────────────────────

%ctor {
    // Hook C functions using MSHookFunction (Substrate)
    // These must be loaded after dylib is injected

    void *mgHandle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    if (mgHandle) {
        orig_MGCopyAnswer = (void *)dlsym(mgHandle, "MGCopyAnswer");
        if (orig_MGCopyAnswer) {
            MSHookFunction((void *)orig_MGCopyAnswer,
                          (void *)hooked_MGCopyAnswer,
                          (void **)&orig_MGCopyAnswer);
            NSLog(@"[ZMMOTweak] Hooked MGCopyAnswer");
        }
    }

    // Hook sysctl
    MSHookFunction((void *)sysctlbyname,
                  (void *)hooked_sysctlbyname,
                  (void **)&orig_sysctlbyname);
    NSLog(@"[ZMMOTweak] Hooked sysctlbyname");

    MSHookFunction((void *)sysctl,
                  (void *)hooked_sysctl,
                  (void **)&orig_sysctl);
    NSLog(@"[ZMMOTweak] Hooked sysctl");

    NSLog(@"[ZMMOTweak] All C function hooks installed");
}
