// daemon/main.mm — ZMMO ios-rmt entry point
// Screen mirroring + audio streaming + touch injection

#import <Foundation/Foundation.h>
#import "RMTDaemon.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"[ZMMO-RMT] ios-rmt v0.1.0 starting...");
        RMTDaemon *daemon = [[RMTDaemon alloc] init];
        [daemon start];
        NSLog(@"[ZMMO-RMT] Ready — stream:8000 control:8888");
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
