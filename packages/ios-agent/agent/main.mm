// ZMMO ios-agent — Entry point
// Equivalent to KidsAutov4's kidsdaemon main()
// Runs as LaunchDaemon on jailbroken iOS

#import <Foundation/Foundation.h>
#import "ZMMOHTTPServer.h"
#import "ZMMOCollector.h"
#import "ZMMOSpoofer.h"
#import "ZMMOBackup.h"

#define ZMMO_PORT 15555
#define ZMMO_VERSION "0.1.0"

static ZMMOHTTPServer *server = nil;

static void handleSignal(int sig) {
    NSLog(@"[ZMMO] Received signal %d, shutting down...", sig);
    [server stop];
    exit(0);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"[ZMMO] ios-agent v%s starting on port %d", ZMMO_VERSION, ZMMO_PORT);

        // Setup signal handlers for clean shutdown
        signal(SIGTERM, handleSignal);
        signal(SIGINT, handleSignal);

        // iOS daemon — LaunchDaemon KeepAlive handles lifecycle
        // No need for macOS-only disableSuddenTermination on iOS

        // Start HTTP server with route handlers
        server = [[ZMMOHTTPServer alloc] initWithPort:ZMMO_PORT];

        // ── Device Info routes ──
        [server addRoute:@"/deviceinfo" handler:^(NSString *method, NSDictionary *params, NSData *body) {
            return [[ZMMOCollector shared] collectAllInfo];
        }];

        [server addRoute:@"/deviceinfo/raw" handler:^(NSString *method, NSDictionary *params, NSData *body) {
            return [[ZMMOCollector shared] collectRawInfo];
        }];

        // ── Property routes (GET = read current, POST = save config) ──
        [server addRoute:@"/props" handler:^(NSString *method, NSDictionary *params, NSData *body) {
            if ([method isEqualToString:@"GET"]) {
                return [[ZMMOSpoofer shared] readCurrentConfig];
            } else {
                NSDictionary *config = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
                return [[ZMMOSpoofer shared] saveConfig:config];
            }
        }];

        // ── changedevice — Apply spoofed properties ──
        [server addRoute:@"/changedevice" handler:^(NSString *method, NSDictionary *params, NSData *body) {
            NSString *model = params[@"model"];
            NSString *ios   = params[@"ios"];
            return [[ZMMOSpoofer shared] applyDeviceChange:model iosVersion:ios];
        }];

        // ── changeregion — Set region/proxy ──
        [server addRoute:@"/changeregion" handler:^(NSString *method, NSDictionary *params, NSData *body) {
            NSString *host = params[@"host"] ?: @"checkip.amazonaws.com";
            NSString *ip   = params[@"ipaddress"];
            return [[ZMMOSpoofer shared] applyRegion:host ipAddress:ip];
        }];

        // ── GPS spoof ──
        [server addRoute:@"/setgps" handler:^(NSString *method, NSDictionary *params, NSData *body) {
            double lat = [params[@"lat"] doubleValue];
            double lon = [params[@"lon"] doubleValue];
            return [[ZMMOSpoofer shared] applyGPS:lat lon:lon];
        }];

        // ── App backup/restore/wipe ──
        [server addRoute:@"/getapplist" handler:^(NSString *method, NSDictionary *params, NSData *body) {
            return [[ZMMOBackup shared] listInstalledApps];
        }];

        [server addRoute:@"/backupapps" handler:^(NSString *method, NSDictionary *params, NSData *body) {
            NSString *bundleID = params[@"bundleid"];
            NSString *filename = params[@"filename"];
            NSString *comment  = params[@"cmt"] ?: @"";
            NSTimeInterval timeout = [params[@"timeout"] doubleValue] ?: 40.0;
            return [[ZMMOBackup shared] backupApp:bundleID filename:filename comment:comment timeout:timeout];
        }];

        [server addRoute:@"/restorerrs" handler:^(NSString *method, NSDictionary *params, NSData *body) {
            NSString *filename = params[@"filename"];
            NSTimeInterval timeout = [params[@"timeout"] doubleValue] ?: 180.0;
            return [[ZMMOBackup shared] restoreBackup:filename timeout:timeout];
        }];

        [server addRoute:@"/wipeapps" handler:^(NSString *method, NSDictionary *params, NSData *body) {
            NSString *bundleID = params[@"bundleid"];
            NSTimeInterval timeout = [params[@"timeout"] doubleValue] ?: 30.0;
            return [[ZMMOBackup shared] wipeApp:bundleID timeout:timeout];
        }];

        [server addRoute:@"/backuplist" handler:^(NSString *method, NSDictionary *params, NSData *body) {
            return [[ZMMOBackup shared] listBackups];
        }];

        [server addRoute:@"/backupremove" handler:^(NSString *method, NSDictionary *params, NSData *body) {
            NSString *filename = params[@"filename"];
            return [[ZMMOBackup shared] removeBackup:filename];
        }];

        // ── Status / health ──
        [server addRoute:@"/status" handler:^(NSString *method, NSDictionary *params, NSData *body) {
            return @{
                @"status": @"running",
                @"version": @ZMMO_VERSION,
                @"port": @(ZMMO_PORT),
                @"uptime": @([[NSProcessInfo processInfo] systemUptime])
            };
        }];

        [server addRoute:@"/license" handler:^(NSString *method, NSDictionary *params, NSData *body) {
            // Placeholder — license check will be implemented later
            if ([params[@"getkey"] length] > 0) {
                return @{@"key": @"ZMMO-FREE-TRIAL", @"valid": @YES};
            }
            return @{@"valid": @YES, @"expiresAt": @"2099-12-31", @"maxDevices": @99};
        }];

        BOOL started = [server start];
        if (!started) {
            NSLog(@"[ZMMO] FATAL: Failed to start server on port %d", ZMMO_PORT);
            return 1;
        }

        NSLog(@"[ZMMO] Server listening on http://localhost:%d", ZMMO_PORT);

        // Run loop forever (block main thread)
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
