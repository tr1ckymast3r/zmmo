// ZMMOSpoofer.mm — Property spoofing
// Traffic flow (mirrors KidsAutov4):
//   1. Save config → /var/mobile/Library/Preferences/com.zmmo.deviceinfo.plist
//   2. Generate fake plists:
//      a. MobileGestalt_Fake.plist
//      b. CoreSuggestionsInternals_Fake.plist
//      c. InfoMobileSafari_Fake.plist
//   3. Post CFNotification to wake up tweak dylib
//   4. Tweak dylib reads config → hooks return fake values

#import "ZMMOSpoofer.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>

#define ZMMO_CONFIG_DIR  @"/var/mobile/Library/Preferences"
#define ZMMO_CONFIG_FILE @"com.zmmo.deviceinfo.plist"

// KidsAutov4-style fake plist paths
#define ZMMO_FAKE_MOBILEGESTALT   @"/var/mobile/Library/CoreServices/MobileGestalt_Fake.plist"
#define ZMMO_FAKE_CORESUGGESTIONS @"/var/mobile/Library/CoreSuggestionsInternals_Fake.plist"
#define ZMMO_FAKE_SAFARI          @"/var/mobile/Library/InfoMobileSafari_Fake.plist"
#define ZMMO_FAKE_GLOBALPREFS     @"/var/mobile/Library/Preferences/.GlobalPreferences_m.plist"

// CFNotification for IPC to dylib
#define ZMMO_NOTIFY_CHANGED CFSTR("com.zmmo.devicechanged")

@interface ZMMOSpoofer ()
@property (nonatomic, strong) NSMutableDictionary *config;
@end

@implementation ZMMOSpoofer

+ (instancetype)shared {
    static ZMMOSpoofer *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ZMMOSpoofer alloc] init];
        [instance loadConfig];
    });
    return instance;
}

- (NSString *)configPath {
    return [ZMMO_CONFIG_DIR stringByAppendingPathComponent:ZMMO_CONFIG_FILE];
}

- (void)loadConfig {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:[self configPath]];
    self.config = saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];

    // Defaults
    if (!self.config[@"enabled"]) self.config[@"enabled"] = @NO;
    if (!self.config[@"fake_model"]) self.config[@"fake_model"] = @"";
    if (!self.config[@"fake_version"]) self.config[@"fake_version"] = @"";
    if (!self.config[@"fake_name"]) self.config[@"fake_name"] = @"";
    if (!self.config[@"fake_locale"]) self.config[@"fake_locale"] = @"";
}

- (void)saveConfigToDisk {
    [[self config] writeToFile:[self configPath] atomically:YES];
}

- (void)notifyTweakDylib {
    // Post Darwin notification — ZMMODeviceProof.dylib listens for this
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        ZMMO_NOTIFY_CHANGED,
        NULL, NULL, YES
    );
}

// ────────────────────────────────────────
#pragma mark - API
// ────────────────────────────────────────

- (NSDictionary *)readCurrentConfig {
    [self loadConfig];
    return @{
        @"config": self.config,
        @"fakePlistsExist": @{
            @"mobilegestalt":   @([[NSFileManager defaultManager] fileExistsAtPath:ZMMO_FAKE_MOBILEGESTALT]),
            @"coresuggestions": @([[NSFileManager defaultManager] fileExistsAtPath:ZMMO_FAKE_CORESUGGESTIONS]),
            @"safari":          @([[NSFileManager defaultManager] fileExistsAtPath:ZMMO_FAKE_SAFARI]),
            @"globalprefs":     @([[NSFileManager defaultManager] fileExistsAtPath:ZMMO_FAKE_GLOBALPREFS]),
        }
    };
}

- (NSDictionary *)saveConfig:(NSDictionary *)config {
    if (config) {
        [self.config addEntriesFromDictionary:config];
        [self saveConfigToDisk];
        [self notifyTweakDylib];
        return @{@"status": @"saved", @"config": self.config};
    }
    return @{@"error": @"No config provided"};
}

- (NSDictionary *)applyDeviceChange:(NSString *)model iosVersion:(NSString *)iosVersion {
    if (!model && !iosVersion) {
        return @{@"error": @"Provide at least model or ios parameter"};
    }

    if (model) self.config[@"fake_model"] = model;
    if (iosVersion) self.config[@"fake_version"] = iosVersion;
    self.config[@"enabled"] = @YES;

    [self saveConfigToDisk];

    // Generate all fake plists
    BOOL ok = [self generateFakePlists];
    [self notifyTweakDylib];

    if (ok) {
        return @{
            @"status": @"Device info has been changed successfully.",
            @"fake_model": self.config[@"fake_model"] ?: @"",
            @"fake_version": self.config[@"fake_version"] ?: @"",
        };
    } else {
        return @{
            @"status": @"Device info has been unsuccessfully changed.",
            @"error": @"Failed to write fake plist(s)",
        };
    }
}

- (NSDictionary *)applyRegion:(NSString *)host ipAddress:(NSString *)ip {
    if (!ip) return @{@"error": @"ipaddress required"};

    self.config[@"region_host"] = host ?: @"";
    self.config[@"region_ip"] = ip;
    [self saveConfigToDisk];

    // Update proxy settings in .GlobalPreferences_m.plist
    NSMutableDictionary *proxyPrefs = [NSMutableDictionary dictionaryWithContentsOfFile:ZMMO_FAKE_GLOBALPREFS] ?:
                                       [NSMutableDictionary dictionary];

    if (host && ip) {
        proxyPrefs[@"HTTPProxy"] = ip;
        proxyPrefs[@"HTTPPort"] = @8888;
        proxyPrefs[@"HTTPEnable"] = @YES;
        proxyPrefs[@"HTTPSProxy"] = ip;
        proxyPrefs[@"HTTPSPort"] = @8888;
        proxyPrefs[@"HTTPSEnable"] = @YES;
    }

    [proxyPrefs writeToFile:ZMMO_FAKE_GLOBALPREFS atomically:YES];
    [self notifyTweakDylib];

    return @{@"status": @"Region/proxy updated", @"ip": ip, @"host": host ?: @""};
}

- (NSDictionary *)applyGPS:(double)lat lon:(double)lon {
    if (lat == 0 && lon == 0) {
        return @{@"error": @"lat and lon required (non-zero)"};
    }

    self.config[@"fake_latitude"] = @(lat);
    self.config[@"fake_longitude"] = @(lon);
    self.config[@"gps_enabled"] = @YES;
    [self saveConfigToDisk];

    // Write GPS fake plist
    NSDictionary *gpsFake = @{
        @"Latitude": @(lat),
        @"Longitude": @(lon),
        @"HorizontalAccuracy": @(5.0),
        @"Timestamp": [[NSDate date] description],
    };

    NSString *gpsPath = [ZMMO_CONFIG_DIR stringByAppendingPathComponent:@"com.zmmo.gpsfake.plist"];
    [gpsFake writeToFile:gpsPath atomically:YES];
    [self notifyTweakDylib];

    return @{
        @"status": @"GPS location set",
        @"lat": @(lat),
        @"lon": @(lon),
    };
}

// ────────────────────────────────────────
#pragma mark - Fake Plist Generation
// ────────────────────────────────────────

- (BOOL)generateFakePlists {
    NSString *model   = self.config[@"fake_model"] ?: @"iPhone14,3";
    NSString *version = self.config[@"fake_version"] ?: @"16.1.2";
    NSString *name    = self.config[@"fake_name"] ?: @"iPhone";
    NSString *locale  = self.config[@"fake_locale"] ?: @"en_US";

    BOOL allOk = YES;

    // a. MobileGestalt_Fake.plist
    NSDictionary *mgFake = @{
        @"HWModelStr":      model,
        @"ProductType":     model,
        @"ProductVersion":  version,
        @"BuildVersion":    @"20B101",
        @"DeviceClass":     @"iPhone",
        @"DeviceName":      name,
    };
    if (![mgFake writeToFile:ZMMO_FAKE_MOBILEGESTALT atomically:YES]) {
        NSLog(@"[ZMMO] Failed to write MobileGestalt_Fake.plist");
        allOk = NO;
    }

    // b. CoreSuggestionsInternals_Fake.plist
    NSDictionary *csFake = @{
        @"DeviceModel":    model,
        @"OSVersion":      version,
        @"DeviceClass":    @"iPhone",
    };
    if (![csFake writeToFile:ZMMO_FAKE_CORESUGGESTIONS atomically:YES]) {
        NSLog(@"[ZMMO] Failed to write CoreSuggestionsInternals_Fake.plist");
        allOk = NO;
    }

    // c. InfoMobileSafari_Fake.plist (User-Agent spoof)
    NSString *ua = [NSString stringWithFormat:
        @"Mozilla/5.0 (iPhone; CPU iPhone OS %@ like Mac OS X) AppleWebKit/605.1.15",
        [version stringByReplacingOccurrencesOfString:@"." withString:@"_"]];
    NSDictionary *safariFake = @{
        @"UserAgent": ua,
        @"DeviceModel": model,
        @"BuildVersion": version,
    };
    if (![safariFake writeToFile:ZMMO_FAKE_SAFARI atomically:YES]) {
        NSLog(@"[ZMMO] Failed to write InfoMobileSafari_Fake.plist");
        allOk = NO;
    }

    // d. .GlobalPreferences_m.plist
    NSDictionary *globalFake = @{
        @"AppleLocale": locale,
        @"AppleLanguages": @[locale],
        @"AppleKeyboards": @[@"en_US@hw=US;sw=QWERTY"],
    };
    if (![globalFake writeToFile:ZMMO_FAKE_GLOBALPREFS atomically:YES]) {
        NSLog(@"[ZMMO] Failed to write .GlobalPreferences_m.plist");
        allOk = NO;
    }

    return allOk;
}

@end
