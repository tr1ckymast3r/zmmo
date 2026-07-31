// daemon/LuaEngine.h

#import <Foundation/Foundation.h>

@interface LuaEngine : NSObject
- (NSDictionary *)execute:(NSString *)script args:(NSArray *)args;
- (NSDictionary *)stop;
- (NSDictionary *)handleAPI:(NSString *)action body:(NSData *)body;
- (NSString *)status;
@end
