// ZMMOSpoofer.h — Property spoofing (equivalent to KidsAutov4's changedevice)
// Generates fake plists, writes config, notifies tweak dylib

#import <Foundation/Foundation.h>

@interface ZMMOSpoofer : NSObject

+ (instancetype _Nonnull)shared;

/// Read current config from com.zmmo.deviceinfo.plist
- (NSDictionary * _Nonnull)readCurrentConfig;

/// Save config (write to plist)
- (NSDictionary * _Nonnull)saveConfig:(NSDictionary * _Nullable)config;

/// Apply device change — generate all fake plists
- (NSDictionary * _Nonnull)applyDeviceChange:(NSString * _Nullable)model
                                  iosVersion:(NSString * _Nullable)iosVersion;

/// Apply region/proxy spoof
- (NSDictionary * _Nonnull)applyRegion:(NSString * _Nullable)host
                             ipAddress:(NSString * _Nullable)ip;

/// Apply GPS spoof
- (NSDictionary * _Nonnull)applyGPS:(double)lat lon:(double)lon;

@end
