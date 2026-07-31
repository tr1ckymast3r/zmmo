// XAGDeviceInfo.h — Full device info collector (mirrors XoaInfo's DeviceInfoHelper)
// Sources: IOKit, MobileGestalt, CoreTelephony, sysctl, SCDynamicStore

#import <Foundation/Foundation.h>

@interface XAGDeviceInfo : NSObject

+ (instancetype)shared;

/// Full device state snapshot (all sources)
- (NSDictionary *)deviceFullInfo;

/// Generate random serial number (iPhone format)
- (NSString *)randomSerial;

/// Generate random IMEI (15 digits, Luhn check)
- (NSString *)randomIMEI;

/// Current carrier info from CoreTelephony
- (NSDictionary *)carrierInfo;

@end
