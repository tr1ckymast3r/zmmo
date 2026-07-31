// ZMMOHTTPServer.h — Lightweight HTTP server using BSD sockets
// Purpose: Replace GCDWebServer with a minimal dependency-free implementation
// Handles: GET/POST with query params and JSON body parsing

#import <Foundation/Foundation.h>

typedef NSDictionary* _Nonnull (^ZMMORouteHandler)(NSString * _Nonnull method,
                                                    NSDictionary * _Nonnull params,
                                                    NSData * _Nullable body);

@interface ZMMOHTTPServer : NSObject

- (instancetype _Nonnull)initWithPort:(int)port;

/// Register a route. Example: [server addRoute:@"/changedevice" handler:^...]
- (void)addRoute:(NSString * _Nonnull)path handler:(ZMMORouteHandler _Nonnull)handler;

/// Start listening. Returns NO if port already in use.
- (BOOL)start;

/// Stop the server and release the socket.
- (void)stop;

@end
