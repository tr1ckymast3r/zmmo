// daemon/WebSocket.h — Binary WebSocket frame handler

#import <Foundation/Foundation.h>

@interface WebSocket : NSObject
+ (NSData *)binaryFrame:(NSData *)payload;
+ (NSData *)textFrame:(NSString *)text;
@end
