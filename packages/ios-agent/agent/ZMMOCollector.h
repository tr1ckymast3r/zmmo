// ZMMOCollector.h — Device info collector (equivalent to KidsInfoHelper)
// Collects all hardware/software properties from the iOS device

#import <Foundation/Foundation.h>

@interface ZMMOCollector : NSObject

+ (instancetype _Nonnull)shared;

/// Full structured device info (model, serial, version, etc.)
- (NSDictionary * _Nonnull)collectAllInfo;

/// Raw system properties (sysctl, IOKit, MobileGestalt dump)
- (NSDictionary * _Nonnull)collectRawInfo;

@end
