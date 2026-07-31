// daemon/TouchInject.h

#import <Foundation/Foundation.h>

@interface TouchInject : NSObject
- (void)handleTouchCommand:(NSString *)json;
@end
