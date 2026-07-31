// main.mm — ZMMO ios-ag entry point (mirrors XoaInfoD)
// RocketBootstrap daemon with CPDistributedMessagingCenter IPC

#import <Foundation/Foundation.h>
#import "XAGDaemon.h"
#import "XAGDeviceInfo.h"
#import "XAGSpoofer.h"
#import "XAGRRS.h"

static void handleSignal(int sig) {
    NSLog(@"[XAG] Signal %d, stopping...", sig);
    [[XAGDaemon shared] stop];
    exit(0);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"[XAG] ios-ag v0.1.0 — RocketBootstrap daemon starting...");
        signal(SIGTERM, handleSignal);
        signal(SIGINT, handleSignal);

        // Init singletons
        [XAGDeviceInfo shared];
        [XAGSpoofer shared];
        [XAGRRS shared];

        BOOL ok = [[XAGDaemon shared] start];
        if (!ok) {
            NSLog(@"[XAG] FATAL: Daemon startup failed");
            return 1;
        }

        NSLog(@"[XAG] Daemon ready — IPC via RocketBootstrap CPDistributedMessagingCenter");
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
