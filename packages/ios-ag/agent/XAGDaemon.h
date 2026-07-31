// XAGDaemon.h — RocketBootstrap-based IPC daemon (mirrors XoaInfoD)
// Uses CPDistributedMessagingCenter instead of raw sockets

#import <Foundation/Foundation.h>

@interface XAGDaemon : NSObject

+ (instancetype)shared;

/// Start daemon: get RocketBootstrap port, register message handlers, run loop
- (BOOL)start;

/// Stop daemon
- (void)stop;

@end
