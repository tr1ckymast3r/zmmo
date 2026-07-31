// XAGDeviceInfo.mm — Full device info collector
// Sources: IOKit, MobileGestalt, CoreTelephony (IMEI), sysctl

#import "XAGDeviceInfo.h"
#import <IOKit/IOKitLib.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <sys/mount.h>
#import <mach/mach.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <dlfcn.h>

typedef id (*MGQueryFunc)(CFStringRef);

@interface XAGDeviceInfo ()
@property (nonatomic, strong) NSDictionary *cachedInfo;
@end

@implementation XAGDeviceInfo

+ (instancetype)shared {
    static XAGDeviceInfo *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[XAGDeviceInfo alloc] init]; });
    return instance;
}

// ── IOKit ──
- (NSString *)ioPlatformString:(NSString *)key {
    io_service_t platform = IOServiceGetMatchingService(kIOMasterPortDefault,
        IOServiceMatching("IOPlatformExpertDevice"));
    if (!platform) return nil;
    CFTypeRef prop = IORegistryEntryCreateCFProperty(platform, (__bridge CFStringRef)key, kCFAllocatorDefault, 0);
    IOObjectRelease(platform);
    if (!prop) return nil;
    NSString *result = nil;
    if (CFGetTypeID(prop) == CFStringGetTypeID()) {
        result = (__bridge_transfer NSString *)prop;
    } else if (CFGetTypeID(prop) == CFDataGetTypeID()) {
        NSData *data = (__bridge_transfer NSData *)prop;
        result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!result) {
            const uint8_t *b = data.bytes;
            NSMutableString *hex = [NSMutableString stringWithCapacity:data.length*2];
            for (NSUInteger i=0; i<data.length; i++) [hex appendFormat:@"%02x", b[i]];
            result = hex;
        }
    } else { CFRelease(prop); return nil; }
    return result;
}

- (NSDictionary *)collectIOKit {
    return @{
        @"serialNumber": [self ioPlatformString:@"IOPlatformSerialNumber"] ?: @"",
        @"IOPlatformUUID": [self ioPlatformString:@"IOPlatformUUID"] ?: @"",
        @"model": [self ioPlatformString:@"model"] ?: @"",
        @"boardId": [self ioPlatformString:@"board-id"] ?: @"",
        @"mlbSerialNumber": [self ioPlatformString:@"mlb-serial-number"] ?: @"",
    };
}

// ── MobileGestalt ──
- (NSString *)mgString:(NSString *)key {
    static MGQueryFunc MGCopyAnswer = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
        if (h) MGCopyAnswer = (MGQueryFunc)dlsym(h, "MGCopyAnswer");
    });
    if (!MGCopyAnswer) return nil;
    CFStringRef r = MGCopyAnswer((__bridge CFStringRef)key);
    return r ? (__bridge_transfer NSString *)r : nil;
}

- (NSDictionary *)collectMobileGestalt {
    return @{
        @"HWModelStr": [self mgString:@"HWModelStr"] ?: @"",
        @"ProductType": [self mgString:@"ProductType"] ?: @"",
        @"ProductVersion": [self mgString:@"ProductVersion"] ?: @"",
        @"BuildVersion": [self mgString:@"BuildVersion"] ?: @"",
        @"UniqueDeviceID": [self mgString:@"UniqueDeviceID"] ?: @"",
        @"DeviceClass": [self mgString:@"DeviceClass"] ?: @"",
        @"DeviceColor": [self mgString:@"DeviceColor"] ?: @"",
        @"SerialNumber": [self mgString:@"SerialNumber"] ?: @"",
        @"DieID": [self mgString:@"DieId"] ?: @"",
        @"ChipID": [self mgString:@"ChipID"] ?: @"",
        @"RegionalCode": [self mgString:@"RegionalCode"] ?: @"",
        @"ScreenWidth": [self mgString:@"MainScreenWidth"] ?: @"",
        @"ScreenHeight": [self mgString:@"MainScreenHeight"] ?: @"",
        @"ScreenScale": [self mgString:@"MainScreenScale"] ?: @"",
        @"BasebandVersion": [self mgString:@"BasebandVersion"] ?: @"",
    };
}

// ── CoreTelephony (IMEI) ──
- (NSDictionary *)collectCoreTelephony {
    NSMutableDictionary *ct = [NSMutableDictionary dictionary];

    void *handle = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_LAZY);
    if (handle) {
        // CTServerConnectionCopyMobileEquipmentInfo (private API)
        typedef CFDictionaryRef (*CTCopyFunc)(void*, void*);
        CTCopyFunc CTCopy = (CTCopyFunc)dlsym(handle, "_CTServerConnectionCopyMobileEquipmentInfo");
        if (CTCopy) {
            CFDictionaryRef info = CTCopy(NULL, NULL);
            if (info) {
                ct[@"IMEI"] = [(__bridge NSDictionary *)info objectForKey:@"kCTMobileEquipmentInfoIMEI"] ?: @"";
                ct[@"IMEISV"] = [(__bridge NSDictionary *)info objectForKey:@"kCTMobileEquipmentInfoIMEISV"] ?: @"";
                ct[@"MEID"] = [(__bridge NSDictionary *)info objectForKey:@"kCTMobileEquipmentInfoMEID"] ?: @"";
                CFRelease(info);
            }
        }
        dlclose(handle);
    }
    return ct;
}

// ── Carrier Info ──
- (NSDictionary *)carrierInfo {
    NSMutableDictionary *carrier = [NSMutableDictionary dictionary];

    void *handle = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_LAZY);
    if (handle) {
        // CTGetSignalBars, CTCopyCarrierBundleValue, etc.
        // For now: read from UserDefaults (where some jailbreak tools store carrier)
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:
            @"/var/mobile/Library/Preferences/com.apple.carrier.plist"];
        if (prefs) [carrier addEntriesFromDictionary:prefs];
        dlclose(handle);
    }
    return carrier;
}

// ── sysctl ──
- (NSString *)sysctlString:(NSString *)name {
    char buf[256]; size_t s = sizeof(buf);
    return (sysctlbyname([name UTF8String], buf, &s, NULL, 0) == 0)
        ? [NSString stringWithCString:buf encoding:NSUTF8StringEncoding] : nil;
}

- (NSDictionary *)collectSysctl {
    struct utsname uts; uname(&uts);
    return @{
        @"machine": [NSString stringWithCString:uts.machine encoding:NSUTF8StringEncoding],
        @"hw.model": [self sysctlString:@"hw.model"] ?: @"",
        @"hw.ncpu": @([self sysctlInt32:@"hw.ncpu"]),
        @"hw.physmem": @([self sysctlUint64:@"hw.physmem"]),
        @"hw.memsize": @([self sysctlUint64:@"hw.memsize"]),
        @"kern.osversion": [self sysctlString:@"kern.osversion"] ?: @"",
        @"kern.boottime": @([self sysctlUint64:@"kern.boottime"]),
    };
}

- (int32_t)sysctlInt32:(NSString *)name {
    int32_t v=0; size_t s=sizeof(v);
    sysctlbyname([name UTF8String], &v, &s, NULL, 0);
    return v;
}

- (uint64_t)sysctlUint64:(NSString *)name {
    uint64_t v=0; size_t s=sizeof(v);
    sysctlbyname([name UTF8String], &v, &s, NULL, 0);
    return v;
}

// ── Network ──
- (NSDictionary *)collectNetwork {
    NSMutableDictionary *net = [NSMutableDictionary dictionary];
    struct ifaddrs *ifaces = NULL;
    if (getifaddrs(&ifaces) != 0) return net;
    struct ifaddrs *p = ifaces;
    while (p) {
        if (p->ifa_addr && p->ifa_addr->sa_family == AF_INET) {
            NSString *name = [NSString stringWithCString:p->ifa_name encoding:NSUTF8StringEncoding];
            char ip[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &((struct sockaddr_in*)p->ifa_addr)->sin_addr, ip, sizeof(ip));
            if ([name isEqualToString:@"en0"]) net[@"wifi_ip"] = [NSString stringWithCString:ip encoding:NSUTF8StringEncoding];
            if ([name hasPrefix:@"pdp_ip"]) net[@"cellular_ip"] = [NSString stringWithCString:ip encoding:NSUTF8StringEncoding];
        }
        p = p->ifa_next;
    }
    freeifaddrs(ifaces);

    struct statfs fs;
    if (statfs("/", &fs) == 0) {
        net[@"diskTotal"] = @(fs.f_bsize * fs.f_blocks);
        net[@"diskFree"] = @(fs.f_bsize * fs.f_bfree);
    }
    return net;
}

// ── Full Info ──
- (NSDictionary *)deviceFullInfo {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"iokit"] = [self collectIOKit];
    info[@"mobileGestalt"] = [self collectMobileGestalt];
    info[@"coreTelephony"] = [self collectCoreTelephony];
    info[@"sysctl"] = [self collectSysctl];
    info[@"network"] = [self collectNetwork];
    info[@"carrier"] = [self carrierInfo];
    info[@"collectedAt"] = [[NSDate date] description];
    self.cachedInfo = info;
    return info;
}

// ── Random Generators ──

- (NSString *)randomSerial {
    // iPhone serial format: 12 chars (e.g. F2LVB2B8JCLX)
    static const char charset[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    char serial[13];
    for (int i=0; i<12; i++) serial[i] = charset[arc4random_uniform(36)];
    serial[12] = '\0';
    return [NSString stringWithCString:serial encoding:NSASCIIStringEncoding];
}

- (NSString *)randomIMEI {
    // IMEI: 15 digits with Luhn check
    // First 8: TAC (Type Allocation Code), 6: serial, 1: Luhn
    NSMutableString *imei = [NSMutableString string];
    // Use known TAC prefix (Apple)
    [imei appendString:@"35686808"];
    for (int i=0; i<6; i++) [imei appendFormat:@"%d", arc4random_uniform(10)];

    // Luhn checksum
    int sum=0;
    for (int i=0; i<14; i++) {
        int d = [imei characterAtIndex:i] - '0';
        if (i%2==0) { d*=2; if (d>9) d-=9; }
        sum += d;
    }
    int check = (10 - (sum%10)) % 10;
    [imei appendFormat:@"%d", check];
    return imei;
}

@end
