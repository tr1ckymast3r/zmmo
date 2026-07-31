// XAGSpoofer.h — Device property spoofing (mirrors XoaInfo's fake info system)

#import <Foundation/Foundation.h>

@interface XAGSpoofer : NSObject

+ (instancetype)shared;

- (NSDictionary *)readConfig;
- (NSDictionary *)applyDeviceChange:(NSString *)model iosVersion:(NSString *)version
                             serial:(NSString *)serial imei:(NSString *)imei enable:(BOOL)enable;
- (NSDictionary *)applyCarrierChange:(NSDictionary *)carrierInfo;
- (NSDictionary *)applyGPS:(double)lat lon:(double)lon;
- (NSDictionary *)applyLocale:(NSDictionary *)localeInfo;

@end
