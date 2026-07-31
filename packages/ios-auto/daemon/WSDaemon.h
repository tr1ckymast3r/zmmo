// daemon/WSDaemon.h — Core WebSocket daemon (replaces WSDaemon)
// Port 15558: WebSocket + HTTP API + Web IDE + MCP

#import <Foundation/Foundation.h>

@interface WSDaemon : NSObject

- (void)start;
- (void)stop;

@end
