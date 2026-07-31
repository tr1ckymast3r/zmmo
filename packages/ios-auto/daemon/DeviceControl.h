// daemon/DeviceControl.h

#import <Foundation/Foundation.h>

@interface DeviceControl : NSObject
- (NSDictionary *)fakeLocation:(double)lat lon:(double)lon;
- (NSDictionary *)setProxy:(NSString *)proxy;
- (NSDictionary *)gesture:(NSDictionary *)params;
- (NSDictionary *)handleAPI:(NSString *)action body:(NSData *)body;
@end
