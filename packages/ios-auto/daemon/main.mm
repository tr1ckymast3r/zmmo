// daemon/main.mm — ZMMO ios-auto entry point (WSDaemon clone)
// WebSocket server + Lua engine + MCP + App farming + Device control

#import <Foundation/Foundation.h>
#import "WSDaemon.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"[ZMMO-AUTO] ios-auto v0.1.0 starting...");

        WSDaemon *daemon = [[WSDaemon alloc] init];
        [daemon start];

        NSLog(@"[ZMMO-AUTO] Daemon ready on port 15558");
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
