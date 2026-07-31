// XAGPlug4/Tweak.x — Target: com.apple.springboard + com.apple.UIKit
// GPS spoof via CLLocation hook + OTRHook per-app spoofing system
//
// OTRHook = On-The-Run Hook — different fake values per app
// Reads per-app config from separate plist files

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <substrate.h>
#import <dlfcn.h>

#define XAG_CONFIG @"/var/mobile/Library/Preferences/com.zmmo.iosag.plist"
#define XAG_GPS_CONFIG @"/var/mobile/Library/Preferences/com.zmmo.gps.plist"

static NSDictionary *loadConfig(NSString *path) {
    return [NSDictionary dictionaryWithContentsOfFile:path] ?: @{};
}
static BOOL gpsEnabled(void) { return [loadConfig(XAG_CONFIG)[@"gps_enabled"] boolValue]; }

// ──────────────────────────
// GPS Spoof (CLLocation hook)
// ──────────────────────────

%hook CLLocation

- (CLLocationCoordinate2D)coordinate {
    if (gpsEnabled()) {
        NSDictionary *gps = loadConfig(XAG_GPS_CONFIG);
        double lat = [gps[@"fake_latitude"] doubleValue];
        double lon = [gps[@"fake_longitude"] doubleValue];
        if (lat != 0 && lon != 0) {
            CLLocationCoordinate2D c; c.latitude=lat; c.longitude=lon;
            return c;
        }
    }
    return %orig;
}

- (CLLocationDistance)altitude { return gpsEnabled() ? 0.0 : %orig; }
- (CLLocationAccuracy)horizontalAccuracy { return gpsEnabled() ? 5.0 : %orig; }

%end

// ──────────────────────────
// OTRHook — Per-App Spoofing
// ──────────────────────────
// Reads: /var/mobile/Library/Preferences/com.zmmo.otrhook.<bundleID>.plist
// If exists for current app, applies app-specific spoof values

@interface OTREngine : NSObject
+ (instancetype)shared;
- (NSDictionary *)configForBundleID:(NSString *)bundleID;
- (BOOL)isOTREnabled;
@end

%hook OTREngine

+ (instancetype)shared {
    static OTREngine *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[OTREngine alloc] init]; });
    return instance;
}

- (BOOL)isOTREnabled {
    // Check if per-app config exists for current app
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *otrPath = [NSString stringWithFormat:
        @"/var/mobile/Library/Preferences/com.zmmo.otrhook.%@.plist", bundleID];
    return [[NSFileManager defaultManager] fileExistsAtPath:otrPath];
}

- (NSDictionary *)configForBundleID:(NSString *)bundleID {
    if (!bundleID) return @{};
    NSString *path = [NSString stringWithFormat:
        @"/var/mobile/Library/Preferences/com.zmmo.otrhook.%@.plist", bundleID];
    return [NSDictionary dictionaryWithContentsOfFile:path] ?: @{};
}

%end

// ──────────────────────────
// Per-App UIDevice Override
// ──────────────────────────

%hook UIDevice

- (NSString *)model {
    if ([[OTREngine shared] isOTREnabled]) {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        NSDictionary *otr = [[OTREngine shared] configForBundleID:bundleID];
        NSString *m = otr[@"fake_model"];
        if (m.length) return m;
    }
    // Fallback to global config
    NSString *m = loadConfig(XAG_CONFIG)[@"fake_model"];
    if ([loadConfig(XAG_CONFIG)[@"enabled"] boolValue] && m.length) return m;
    return %orig;
}

- (NSString *)systemVersion {
    if ([[OTREngine shared] isOTREnabled]) {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        NSDictionary *otr = [[OTREngine shared] configForBundleID:bundleID];
        NSString *v = otr[@"fake_version"];
        if (v.length) return v;
    }
    NSString *v = loadConfig(XAG_CONFIG)[@"fake_version"];
    if ([loadConfig(XAG_CONFIG)[@"enabled"] boolValue] && v.length) return v;
    return %orig;
}

%end

// ──────────────────────────
// NSLocale / NSTimeZone
// ──────────────────────────

%hook NSLocale

+ (NSArray *)preferredLanguages {
    NSString *lang = loadConfig(XAG_CONFIG)[@"fake_language"];
    if ([loadConfig(XAG_CONFIG)[@"enabled"] boolValue] && lang.length) return @[lang];
    return %orig;
}

+ (NSLocale *)currentLocale {
    NSString *loc = loadConfig(XAG_CONFIG)[@"fake_locale"];
    if ([loadConfig(XAG_CONFIG)[@"enabled"] boolValue] && loc.length)
        return [NSLocale localeWithLocaleIdentifier:loc];
    return %orig;
}

%end

%hook NSTimeZone

+ (NSTimeZone *)systemTimeZone {
    NSString *tz = loadConfig(XAG_CONFIG)[@"fake_timezone"];
    if ([loadConfig(XAG_CONFIG)[@"enabled"] boolValue] && tz.length)
        return [NSTimeZone timeZoneWithName:tz];
    return %orig;
}

%end

// ──────────────────────────
// Constructor
// ──────────────────────────

%ctor {
    NSLog(@"[XAGPlug4] Loaded — GPS + OTRHook + Locale");
    // Hooks are auto-registered by Logos %hook
}
