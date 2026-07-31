// XAGSpoofer.mm — Spoof config management + plug notification

#import "XAGSpoofer.h"
#import <CoreFoundation/CoreFoundation.h>

#define XAG_CONFIG @"/var/mobile/Library/Preferences/com.zmmo.iosag.plist"
#define XAG_FAKE_MG @"/var/mobile/Library/CoreServices/MobileGestalt_Fake.plist"

@implementation XAGSpoofer

+ (instancetype)shared {
    static XAGSpoofer *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[XAGSpoofer alloc] init]; });
    return instance;
}

- (NSMutableDictionary *)loadConfig {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:XAG_CONFIG];
    return saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];
}

- (void)saveConfig:(NSDictionary *)config {
    [config writeToFile:XAG_CONFIG atomically:YES];
    // Notify plugs
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.zmmo.iosag.configChanged"),
        NULL, NULL, YES);
}

- (NSDictionary *)readConfig {
    return @{@"config": [self loadConfig]};
}

- (NSDictionary *)applyDeviceChange:(NSString *)model
                         iosVersion:(NSString *)version
                             serial:(NSString *)serial
                               imei:(NSString *)imei
                             enable:(BOOL)enable {
    NSMutableDictionary *cfg = [self loadConfig];
    cfg[@"enabled"] = @(enable);
    if (model.length)   cfg[@"fake_model"] = model;
    if (version.length) cfg[@"fake_version"] = version;
    if (serial.length)  cfg[@"fake_serial"] = serial;
    if (imei.length)    cfg[@"fake_imei"] = imei;
    cfg[@"fake_udid"] = [self randomUUID];

    [self saveConfig:cfg];
    [self generateFakePlists:cfg];
    [self killRelevantServices];

    return @{
        @"status": @"Device info changed",
        @"enabled": @(enable),
        @"fake_model": cfg[@"fake_model"] ?: @"",
        @"fake_version": cfg[@"fake_version"] ?: @"",
        @"fake_serial": cfg[@"fake_serial"] ?: @"",
        @"fake_imei": cfg[@"fake_imei"] ?: @"",
        @"fake_udid": cfg[@"fake_udid"] ?: @"",
    };
}

- (NSDictionary *)applyCarrierChange:(NSDictionary *)info {
    NSMutableDictionary *cfg = [self loadConfig];
    cfg[@"fake_carrier_enabled"] = @YES;
    if (info[@"carrierName"])    cfg[@"fake_carrierName"] = info[@"carrierName"];
    if (info[@"mobileCountryCode"]) cfg[@"fake_mcc"] = info[@"mobileCountryCode"];
    if (info[@"mobileNetworkCode"]) cfg[@"fake_mnc"] = info[@"mobileNetworkCode"];
    if (info[@"isoCountryCode"]) cfg[@"fake_iso"] = info[@"isoCountryCode"];
    [self saveConfig:cfg];
    return @{@"status": @"Carrier changed"};
}

- (NSDictionary *)applyGPS:(double)lat lon:(double)lon {
    NSMutableDictionary *cfg = [self loadConfig];
    cfg[@"fake_latitude"] = @(lat);
    cfg[@"fake_longitude"] = @(lon);
    cfg[@"gps_enabled"] = @YES;
    [self saveConfig:cfg];

    // Write separate GPS plist for Plug4
    [[NSDictionary dictionaryWithContentsOfFile:XAG_CONFIG] ?: @{} writeToFile:
     @"/var/mobile/Library/Preferences/com.zmmo.gps.plist" atomically:YES];

    return @{@"status": @"GPS set", @"lat": @(lat), @"lon": @(lon)};
}

- (NSDictionary *)applyLocale:(NSDictionary *)info {
    NSMutableDictionary *cfg = [self loadConfig];
    if (info[@"locale"])   cfg[@"fake_locale"] = info[@"locale"];
    if (info[@"language"]) cfg[@"fake_language"] = info[@"language"];
    if (info[@"timezone"]) cfg[@"fake_timezone"] = info[@"timezone"];
    [self saveConfig:cfg];
    return @{@"status": @"Locale changed"};
}

// ── Helpers ──

- (NSString *)randomUUID {
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString *str = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, uuid);
    CFRelease(uuid);
    return str;
}

- (void)generateFakePlists:(NSDictionary *)cfg {
    NSDictionary *mgFake = @{
        @"HWModelStr": cfg[@"fake_model"] ?: @"",
        @"ProductType": cfg[@"fake_model"] ?: @"",
        @"ProductVersion": cfg[@"fake_version"] ?: @"",
        @"UniqueDeviceID": cfg[@"fake_udid"] ?: @"",
        @"SerialNumber": cfg[@"fake_serial"] ?: @"",
    };
    [mgFake writeToFile:XAG_FAKE_MG atomically:YES];
}

- (void)killRelevantServices {
    // Same services XoaInfo kills after device change
    NSArray *services = @[
        @"AppStore", @"appstored", @"accountsd", @"akd",
        @"itunesstored", @"itunescloudd", @"mDNSResponder",
        @"nsurlsessiond", @"pkd", @"configd", @"networkd",
        @"Preference", @"Preferences", @"wifid", @"wirelessproxd",
        @"mobileassetd"
    ];
    for (NSString *svc in services) {
        system([[NSString stringWithFormat:@"/usr/bin/killall -9 %@ 2>/dev/null", svc] UTF8String]);
    }
    NSLog(@"[XAG] Killed %lu services after device change", (unsigned long)services.count);
}

@end
