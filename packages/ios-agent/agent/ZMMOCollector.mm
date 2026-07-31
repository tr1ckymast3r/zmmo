// ZMMOCollector.mm — Device info collection
// Mirrors KidsInfoHelper: 5 data sources
//   1. IOKit (serial, model, board)
//   2. MobileGestalt (device traits, HWModelStr, etc.)
//   3. sysctl (kernel info, hw.*)
//   4. SCDynamicStore (WiFi, IP, DNS — optional, can fail gracefully)
//   5. LSApplicationWorkspace (installed apps)

#import "ZMMOCollector.h"
#import <IOKit/IOKitLib.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <sys/mount.h>
#import <mach/mach.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>

// MobileGestalt private framework (loaded dynamically)
// Keys documented at: https://iphonedevwiki.net/index.php/MobileGestalt
typedef id (*MGQueryFunc)(CFStringRef key);

@interface ZMMOCollector ()
@property (nonatomic, strong) NSDictionary *cachedInfo;
@end

@implementation ZMMOCollector

+ (instancetype)shared {
    static ZMMOCollector *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ZMMOCollector alloc] init];
    });
    return instance;
}

// ────────────────────────────────────────
#pragma mark - 1. IOKit
// ────────────────────────────────────────

- (NSString *)ioPlatformString:(NSString *)key {
    io_service_t platform = IOServiceGetMatchingService(kIOMasterPortDefault,
        IOServiceMatching("IOPlatformExpertDevice"));
    if (!platform) return nil;

    CFTypeRef prop = IORegistryEntryCreateCFProperty(platform,
        (__bridge CFStringRef)key, kCFAllocatorDefault, 0);
    IOObjectRelease(platform);

    if (!prop) return nil;

    NSString *result = nil;
    if (CFGetTypeID(prop) == CFStringGetTypeID()) {
        result = (__bridge_transfer NSString *)prop;
    } else if (CFGetTypeID(prop) == CFDataGetTypeID()) {
        NSData *data = (__bridge_transfer NSData *)prop;
        result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!result) {
            // Hex encode binary data
            const uint8_t *bytes = data.bytes;
            NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
            for (NSUInteger i = 0; i < data.length; i++) {
                [hex appendFormat:@"%02x", bytes[i]];
            }
            result = hex;
        }
    } else {
        CFRelease(prop);
        return nil;
    }
    return result;
}

- (NSDictionary *)collectIOKit {
    return @{
        @"serialNumber":           [self ioPlatformString:@"IOPlatformSerialNumber"] ?: @"",
        @"IOPlatformUUID":         [self ioPlatformString:@"IOPlatformUUID"] ?: @"",
        @"model":                  [self ioPlatformString:@"model"] ?: @"",
        @"boardId":                [self ioPlatformString:@"board-id"] ?: @"",
        @"regulatoryModelNumber":  [self ioPlatformString:@"regulatory-model-number"] ?: @"",
        @"mlbSerialNumber":        [self ioPlatformString:@"mlb-serial-number"] ?: @"",
    };
}

// ────────────────────────────────────────
#pragma mark - 2. MobileGestalt
// ────────────────────────────────────────

- (NSString *)mgString:(NSString *)key {
    // Dynamically load MobileGestalt
    static MGQueryFunc MGCopyAnswer = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
        if (handle) {
            MGCopyAnswer = (MGQueryFunc)dlsym(handle, "MGCopyAnswer");
        }
    });

    if (!MGCopyAnswer) return nil;

    CFStringRef result = MGCopyAnswer((__bridge CFStringRef)key);
    if (!result) return nil;
    return (__bridge_transfer NSString *)result;
}

- (NSNumber *)mgBool:(NSString *)key {
    static MGQueryFunc MGCopyAnswer = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
        if (handle) {
            MGCopyAnswer = (MGQueryFunc)dlsym(handle, "MGCopyAnswer");
        }
    });

    if (!MGCopyAnswer) return @NO;

    CFBooleanRef result = MGCopyAnswer((__bridge CFStringRef)key);
    if (!result) return @NO;
    return @(CFBooleanGetValue(result));
}

- (NSDictionary *)collectMobileGestalt {
    return @{
        @"HWModelStr":              [self mgString:@"HWModelStr"] ?: @"",
        @"ProductType":             [self mgString:@"ProductType"] ?: @"",
        @"ProductVersion":          [self mgString:@"ProductVersion"] ?: @"",
        @"BuildVersion":            [self mgString:@"BuildVersion"] ?: @"",
        @"UniqueDeviceID":          [self mgString:@"UniqueDeviceID"] ?: @"",
        @"DeviceClass":             [self mgString:@"DeviceClass"] ?: @"",
        @"DeviceColor":             [self mgString:@"DeviceColor"] ?: @"",
        @"EnclosureColor":          [self mgString:@"EnclosureColor"] ?: @"",
        @"DieID":                   [self mgString:@"DieId"] ?: @"",
        @"ChipID":                  [self mgString:@"ChipID"] ?: @"",
        @"RegionalCode":            [self mgString:@"RegionalCode"] ?: @"",
        @"DeviceName":              [self mgString:@"UserAssignedDeviceName"] ?: @"",
        @"ScreenScale":             [self mgString:@"MainScreenScale"] ?: @"",
        @"ScreenWidth":             [self mgString:@"MainScreenWidth"] ?: @"",
        @"ScreenHeight":            [self mgString:@"MainScreenHeight"] ?: @"",
        @"BasebandVersion":         [self mgString:@"BasebandVersion"] ?: @"",
        @"BasebandBootloader":      [self mgString:@"BasebandBootloaderVersion"] ?: @"",
        @"InternalBuild":           [self mgBool:@"InternalBuild"] ?: @NO,
        @"Jailbroken":              [self mgBool:@"sbIsDefaultBoot" /* jailbreak detection */ ] ?: @NO,
    };
}

// ────────────────────────────────────────
#pragma mark - 3. sysctl
// ────────────────────────────────────────

- (NSString *)sysctlString:(NSString *)name {
    char result[256];
    size_t size = sizeof(result);
    if (sysctlbyname([name UTF8String], result, &size, NULL, 0) == 0) {
        return [NSString stringWithCString:result encoding:NSUTF8StringEncoding];
    }
    return nil;
}

- (uint64_t)sysctlUint64:(NSString *)name {
    uint64_t result = 0;
    size_t size = sizeof(result);
    sysctlbyname([name UTF8String], &result, &size, NULL, 0);
    return result;
}

- (int32_t)sysctlInt32:(NSString *)name {
    int32_t result = 0;
    size_t size = sizeof(result);
    sysctlbyname([name UTF8String], &result, &size, NULL, 0);
    return result;
}

- (NSDictionary *)collectSysctl {
    struct utsname uts;
    uname(&uts);

    return @{
        @"nodename":        [NSString stringWithCString:uts.nodename encoding:NSUTF8StringEncoding],
        @"sysname":         [NSString stringWithCString:uts.sysname encoding:NSUTF8StringEncoding],
        @"release":         [NSString stringWithCString:uts.release encoding:NSUTF8StringEncoding],
        @"version":         [NSString stringWithCString:uts.version encoding:NSUTF8StringEncoding],
        @"machine":         [NSString stringWithCString:uts.machine encoding:NSUTF8StringEncoding],

        @"hw.machine":      [self sysctlString:@"hw.machine"] ?: @"",
        @"hw.model":        [self sysctlString:@"hw.model"] ?: @"",
        @"hw.ncpu":         @([self sysctlInt32:@"hw.ncpu"]),
        @"hw.physmem":      @([self sysctlUint64:@"hw.physmem"]),
        @"hw.cpufrequency": @([self sysctlUint64:@"hw.cpufrequency"]),
        @"hw.memsize":      @([self sysctlUint64:@"hw.memsize"]),
        @"hw.cachelinesize": @([self sysctlInt32:@"hw.cachelinesize"]),
        @"hw.cpufamily":    @([self sysctlInt32:@"hw.cpufamily"]),
        @"hw.cpusubfamily": @([self sysctlInt32:@"hw.cpusubfamily"]),
        @"hw.cputype":      @([self sysctlInt32:@"hw.cputype"]),
        @"hw.cpusubtype":   @([self sysctlInt32:@"hw.cpusubtype"]),

        @"kern.osversion":           [self sysctlString:@"kern.osversion"] ?: @"",
        @"kern.osproductversion":    [self sysctlString:@"kern.osproductversion"] ?: @"",
        @"kern.boottime":           @([self sysctlUint64:@"kern.boottime"]),

        @"vm.free_page_count":      @([self sysctlInt32:@"vm.free_page_count"]),
        @"vm.page_size":            @([self sysctlInt32:@"vm.pagesize"]),

        @"security.mac.lockdown_mode": @([self sysctlInt32:@"security.mac.lockdown_mode"]),
    };
}

// ────────────────────────────────────────
#pragma mark - 4. Network / WiFi
// ────────────────────────────────────────

- (NSDictionary *)collectNetworkInfo {
    NSMutableDictionary *network = [NSMutableDictionary dictionary];

    // Get all interfaces
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) return network;

    struct ifaddrs *temp = interfaces;
    while (temp) {
        if (temp->ifa_addr && temp->ifa_addr->sa_family == AF_INET) {
            NSString *name = [NSString stringWithCString:temp->ifa_name encoding:NSUTF8StringEncoding];

            // IP address
            char addrBuf[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &((struct sockaddr_in *)temp->ifa_addr)->sin_addr, addrBuf, sizeof(addrBuf));
            NSString *ip = [NSString stringWithCString:addrBuf encoding:NSUTF8StringEncoding];

            if ([name isEqualToString:@"en0"]) {
                network[@"wifi_ip"] = ip;
            } else if ([name isEqualToString:@"pdp_ip0"] || [name isEqualToString:@"pdp_ip1"]) {
                network[@"cellular_ip"] = ip;
            } else if ([name hasPrefix:@"lo0"]) {
                network[@"localhost"] = ip;
            }
        }
        temp = temp->ifa_next;
    }
    freeifaddrs(interfaces);

    // Disk space
    struct statfs fs;
    if (statfs("/", &fs) == 0) {
        uint64_t totalBytes = fs.f_bsize * fs.f_blocks;
        uint64_t freeBytes  = fs.f_bsize * fs.f_bfree;
        network[@"diskTotal"] = @(totalBytes);
        network[@"diskFree"] = @(freeBytes);
    }

    return network;
}

// ────────────────────────────────────────
#pragma mark - 5. Full Collection
// ────────────────────────────────────────

- (NSDictionary *)collectAllInfo {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];

    info[@"iokit"]          = [self collectIOKit];
    info[@"mobilegestalt"]  = [self collectMobileGestalt];
    info[@"sysctl"]         = [self collectSysctl];
    info[@"network"]        = [self collectNetworkInfo];

    info[@"collectedAt"]    = [[NSDate date] description];
    info[@"agentVersion"]   = @"0.1.0";

    self.cachedInfo = info;
    return info;
}

- (NSDictionary *)collectRawInfo {
    // Full dump for debugging / initial setup
    NSMutableDictionary *raw = [NSMutableDictionary dictionary];

    // All props from collectAllInfo
    [raw addEntriesFromDictionary:[self collectAllInfo]];

    // Current locale/timezone
    raw[@"locale"]    = [[NSLocale currentLocale] localeIdentifier];
    raw[@"languages"] = [NSLocale preferredLanguages];
    raw[@"timezone"]  = [[NSTimeZone localTimeZone] name];

    // Process info
    raw[@"processName"] = [[NSProcessInfo processInfo] processName];
    raw[@"hostName"]    = [[NSProcessInfo processInfo] hostName];
    raw[@"osVersion"]   = [[NSProcessInfo processInfo] operatingSystemVersionString];
    raw[@"processorCount"] = @([[NSProcessInfo processInfo] processorCount]);
    raw[@"physicalMemory"] = @([[NSProcessInfo processInfo] physicalMemory]);

    // Preference plists
    NSDictionary *globalPrefs = [NSDictionary dictionaryWithContentsOfFile:
        @"/var/mobile/Library/Preferences/.GlobalPreferences.plist"];
    raw[@"globalPreferences"] = globalPrefs ?: @{};

    return raw;
}

@end
