// XAGPlug3/Tweak.x — Target: com.apple.managedconfiguration.profiled
// Hooks MobileGestalt AND CoreTelephony at C function level
// Key advantage: profiled is a background daemon, rarely checked by anti-tamper
//
// Hooked functions:
//   MGCopyAnswer → fake HWModelStr, ProductVersion, SerialNumber, UniqueDeviceID
//   CTServerConnectionCopyMobileEquipmentInfo → fake IMEI, IMEISV, MEID
//   IOSerialNumber → fake serial (via IOKit hook)

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <substrate.h>

#define XAG_CONFIG @"/var/mobile/Library/Preferences/com.zmmo.iosag.plist"

static NSDictionary *loadConfig(void) { return [NSDictionary dictionaryWithContentsOfFile:XAG_CONFIG] ?: @{}; }
static BOOL enabled(void) { return [loadConfig()[@"enabled"] boolValue]; }
static NSString *cfg(NSString *k) { return loadConfig()[k]; }

// ── MobileGestalt hook ──
static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef key);

static CFTypeRef hooked_MGCopyAnswer(CFStringRef key) {
    if (!enabled()) return orig_MGCopyAnswer(key);
    NSString *k = (__bridge NSString *)key;

    if ([k isEqualToString:@"HWModelStr"] || [k isEqualToString:@"ProductType"]) {
        NSString *v = cfg(@"fake_model");
        if (v.length) return (__bridge_retained CFTypeRef)v;
    }
    if ([k isEqualToString:@"ProductVersion"]) {
        NSString *v = cfg(@"fake_version");
        if (v.length) return (__bridge_retained CFTypeRef)v;
    }
    if ([k isEqualToString:@"UniqueDeviceID"]) {
        NSString *v = cfg(@"fake_udid");
        if (v.length) return (__bridge_retained CFTypeRef)v;
    }
    if ([k isEqualToString:@"SerialNumber"]) {
        NSString *v = cfg(@"fake_serial");
        if (v.length) return (__bridge_retained CFTypeRef)v;
    }
    if ([k isEqualToString:@"DieId"] || [k isEqualToString:@"ChipID"]) {
        return (__bridge_retained CFTypeRef)@(arc4random());
    }
    return orig_MGCopyAnswer(key);
}

// ── CoreTelephony IMEI hook ──
typedef CFDictionaryRef (*CTCopyFunc)(void*, void*);
static CTCopyFunc orig_CTServerConnectionCopyMobileEquipmentInfo = NULL;

static CFDictionaryRef hooked_CTServerConnectionCopyMobileEquipmentInfo(void *a, void *b) {
    if (!enabled() || !orig_CTServerConnectionCopyMobileEquipmentInfo)
        return orig_CTServerConnectionCopyMobileEquipmentInfo(a, b);

    NSString *imei = cfg(@"fake_imei");
    if (!imei.length) return orig_CTServerConnectionCopyMobileEquipmentInfo(a, b);

    // Return fake dictionary
    return (__bridge_retained CFDictionaryRef)@{
        @"kCTMobileEquipmentInfoIMEI": imei,
        @"kCTMobileEquipmentInfoIMEISV": [imei substringToIndex:MIN(8, imei.length)],
        @"kCTMobileEquipmentInfoMEID": @"",
    };
}

// ── IOKit serial hook (IOSerialNumber) ──
// The IOKit function IOSerialNumber returns the device serial
// We hook it via CFURL / the registry entry read

static CFTypeRef (*orig_IORegistryEntryCreateCFProperty)(void*, CFStringRef, void*, uint32_t);

static CFTypeRef hooked_IORegistryEntryCreateCFProperty(void *entry, CFStringRef key, void *allocator, uint32_t options) {
    CFTypeRef result = orig_IORegistryEntryCreateCFProperty(entry, key, allocator, options);
    if (!enabled()) return result;

    NSString *keyStr = (__bridge NSString *)key;
    if ([keyStr isEqualToString:@"IOPlatformSerialNumber"]) {
        NSString *fake = cfg(@"fake_serial");
        if (fake.length) {
            if (result) CFRelease(result);
            return (__bridge_retained CFTypeRef)fake;
        }
    }
    return result;
}

// ── Notification: reload config on change ──
static void configChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *d, CFDictionaryRef u) {
    NSLog(@"[XAGPlug3] Config changed — reloading hooks");
}

%ctor {
    NSLog(@"[XAGPlug3] Loading — targeting com.apple.managedconfiguration.profiled");

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL, configChanged,
        CFSTR("com.zmmo.iosag.configChanged"), NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);

    // Hook MobileGestalt
    void *mg = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    if (mg) {
        void *sym = dlsym(mg, "MGCopyAnswer");
        if (sym) {
            MSHookFunction(sym, (void *)hooked_MGCopyAnswer, (void **)&orig_MGCopyAnswer);
            NSLog(@"[XAGPlug3] Hooked MGCopyAnswer");
        }
    }

    // Hook CoreTelephony IMEI
    void *ct = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_LAZY);
    if (ct) {
        void *sym = dlsym(ct, "_CTServerConnectionCopyMobileEquipmentInfo");
        if (sym) {
            MSHookFunction(sym, (void *)hooked_CTServerConnectionCopyMobileEquipmentInfo,
                          (void **)&orig_CTServerConnectionCopyMobileEquipmentInfo);
            NSLog(@"[XAGPlug3] Hooked CTServerConnectionCopyMobileEquipmentInfo");
        }
    }

    // Hook IOKit serial
    void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (iokit) {
        void *sym = dlsym(iokit, "IORegistryEntryCreateCFProperty");
        if (sym) {
            MSHookFunction(sym, (void *)hooked_IORegistryEntryCreateCFProperty,
                          (void **)&orig_IORegistryEntryCreateCFProperty);
            NSLog(@"[XAGPlug3] Hooked IORegistryEntryCreateCFProperty");
        }
    }

    NSLog(@"[XAGPlug3] Ready — spoofing %s", enabled() ? "ENABLED" : "DISABLED");
}
