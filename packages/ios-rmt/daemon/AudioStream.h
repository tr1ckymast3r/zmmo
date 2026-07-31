// daemon/AudioStream.h

#import <Foundation/Foundation.h>

@interface AudioStream : NSObject
- (NSDictionary *)start;
- (NSDictionary *)stop;
- (BOOL)isActive;
@end
