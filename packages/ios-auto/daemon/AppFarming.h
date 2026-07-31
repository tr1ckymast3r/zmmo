// daemon/AppFarming.h — App account farming (mirrors iOSAutomate farming API)

#import <Foundation/Foundation.h>

@interface AppFarming : NSObject
- (NSDictionary *)openAcc:(NSString *)bundleID account:(NSString *)accName;
- (NSDictionary *)backupAcc:(NSString *)bundleID account:(NSString *)accName;
- (NSDictionary *)restoreAcc:(NSString *)bundleID account:(NSString *)accName;
- (NSDictionary *)deleteAcc:(NSString *)bundleID account:(NSString *)accName;
- (NSDictionary *)resetApp:(NSString *)bundleID;
- (NSDictionary *)cleanAllAcc:(NSString *)bundleID;
- (NSDictionary *)handleAPI:(NSString *)action body:(NSData *)body;
- (NSString *)status;
@end
