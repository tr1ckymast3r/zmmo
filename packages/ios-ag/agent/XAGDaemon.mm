// XAGDaemon.mm — CPDistributedMessagingCenter daemon
//
// Message protocol (mirrors XoaInfoD's handlers):
//   deviceFullInfo      → collect all device properties
//   changeDevice:       → apply spoofed device info (model, version, serial, IMEI)
//   changeCarrier:      → apply carrier spoof
//   changeGPS:          → apply GPS coordinates
//   changeLocale:       → apply language/timezone
//   reset               → keychain wipe + kill services + regenerate IDs
//   backupRRS:          → backup app data + device state
//   restoreRRS:         → restore from backup
//   wipeApp:            → wipe single app data
//   killApp:            → kill app by bundleID
//   openApp:            → open app
//   runCommand:         → execute shell command
//   checkIP             → return current IP

#import "XAGDaemon.h"
#import "XAGDeviceInfo.h"
#import "XAGSpoofer.h"
#import "XAGRRS.h"
#import <rocketbootstrap/rocketbootstrap.h>
#import <AppSupport/CPDistributedMessagingCenter.h>

#define XAG_MACH_SERVICE @"com.zmmo.iosag"

@interface XAGDaemon ()
@property (nonatomic, strong) CPDistributedMessagingCenter *center;
@property (nonatomic, assign) BOOL running;
@end

@implementation XAGDaemon

+ (instancetype)shared {
    static XAGDaemon *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[XAGDaemon alloc] init]; });
    return instance;
}

- (BOOL)start {
    // Get RocketBootstrap port
    self.center = [CPDistributedMessagingCenter centerNamed:XAG_MACH_SERVICE];
    if (!self.center) {
        NSLog(@"[XAG] Failed to create MessagingCenter");
        return NO;
    }

    // Register message handlers
    [self registerHandlers];

    // Start serving
    rocketbootstrap_distributedmessagingcenter_apply(self.center);
    [self.center runServerOnCurrentThread];

    self.running = YES;
    return YES;
}

- (void)stop {
    self.running = NO;
    [self.center runServerOnCurrentThread]; // unblock
}

- (void)registerHandlers {
    __weak typeof(self) weakSelf = self;

    // ── Device Info ──
    [self.center registerForMessageName:@"deviceFullInfo"
                                 target:weakSelf
                               selector:@selector(handleDeviceFullInfo:userInfo:)];

    // ── Device Change ──
    [self.center registerForMessageName:@"changeDevice"
                                 target:weakSelf
                               selector:@selector(handleChangeDevice:userInfo:)];

    [self.center registerForMessageName:@"changeCarrier"
                                 target:weakSelf
                               selector:@selector(handleChangeCarrier:userInfo:)];

    [self.center registerForMessageName:@"changeGPS"
                                 target:weakSelf
                               selector:@selector(handleChangeGPS:userInfo:)];

    [self.center registerForMessageName:@"changeLocale"
                                 target:weakSelf
                               selector:@selector(handleChangeLocale:userInfo:)];

    // ── RRS ──
    [self.center registerForMessageName:@"reset"
                                 target:weakSelf
                               selector:@selector(handleReset:userInfo:)];

    [self.center registerForMessageName:@"backupRRS"
                                 target:weakSelf
                               selector:@selector(handleBackupRRS:userInfo:)];

    [self.center registerForMessageName:@"restoreRRS"
                                 target:weakSelf
                               selector:@selector(handleRestoreRRS:userInfo:)];

    [self.center registerForMessageName:@"wipeApp"
                                 target:weakSelf
                               selector:@selector(handleWipeApp:userInfo:)];

    [self.center registerForMessageName:@"listBackups"
                                 target:weakSelf
                               selector:@selector(handleListBackups:userInfo:)];

    // ── App Management ──
    [self.center registerForMessageName:@"killApp"
                                 target:weakSelf
                               selector:@selector(handleKillApp:userInfo:)];

    [self.center registerForMessageName:@"openApp"
                                 target:weakSelf
                               selector:@selector(handleOpenApp:userInfo:)];

    // ── Utility ──
    [self.center registerForMessageName:@"runCommand"
                                 target:weakSelf
                               selector:@selector(handleRunCommand:userInfo:)];

    [self.center registerForMessageName:@"checkIP"
                                 target:weakSelf
                               selector:@selector(handleCheckIP:userInfo:)];

    NSLog(@"[XAG] Registered %d message handlers", 14);
}

// ────────────────────────────────────────
#pragma mark - Handlers
// ────────────────────────────────────────

- (NSDictionary *)handleDeviceFullInfo:(NSString *)name userInfo:(NSDictionary *)info {
    return [[XAGDeviceInfo shared] deviceFullInfo];
}

- (NSDictionary *)handleChangeDevice:(NSString *)name userInfo:(NSDictionary *)info {
    NSString *model   = info[@"model"]   ?: @"";
    NSString *version = info[@"version"] ?: @"";
    NSString *serial  = info[@"serial"]  ?: [[XAGDeviceInfo shared] randomSerial];
    NSString *imei    = info[@"imei"]    ?: [[XAGDeviceInfo shared] randomIMEI];
    BOOL enable = [info[@"enable"] boolValue];

    return [[XAGSpoofer shared] applyDeviceChange:model
                                      iosVersion:version
                                          serial:serial
                                            imei:imei
                                          enable:enable];
}

- (NSDictionary *)handleChangeCarrier:(NSString *)name userInfo:(NSDictionary *)info {
    return [[XAGSpoofer shared] applyCarrierChange:info];
}

- (NSDictionary *)handleChangeGPS:(NSString *)name userInfo:(NSDictionary *)info {
    double lat = [info[@"lat"] doubleValue];
    double lon = [info[@"lon"] doubleValue];
    return [[XAGSpoofer shared] applyGPS:lat lon:lon];
}

- (NSDictionary *)handleChangeLocale:(NSString *)name userInfo:(NSDictionary *)info {
    return [[XAGSpoofer shared] applyLocale:info];
}

- (NSDictionary *)handleReset:(NSString *)name userInfo:(NSDictionary *)info {
    NSArray *appBundleIDs = info[@"apps"] ?: @[];
    BOOL wipeKeychain = [info[@"wipeKeychain"] boolValue];
    return [[XAGRRS shared] reset:appBundleIDs wipeKeychain:wipeKeychain];
}

- (NSDictionary *)handleBackupRRS:(NSString *)name userInfo:(NSDictionary *)info {
    NSString *label = info[@"label"] ?: @"auto";
    return [[XAGRRS shared] backupRRS:label];
}

- (NSDictionary *)handleRestoreRRS:(NSString *)name userInfo:(NSDictionary *)info {
    NSString *label = info[@"label"];
    if (!label) return @{@"error": @"label required"};
    return [[XAGRRS shared] restoreRRS:label];
}

- (NSDictionary *)handleWipeApp:(NSString *)name userInfo:(NSDictionary *)info {
    NSString *bundleID = info[@"bundleID"];
    if (!bundleID) return @{@"error": @"bundleID required"};
    return [[XAGRRS shared] wipeApp:bundleID];
}

- (NSDictionary *)handleListBackups:(NSString *)name userInfo:(NSDictionary *)info {
    return [[XAGRRS shared] listBackups];
}

- (NSDictionary *)handleKillApp:(NSString *)name userInfo:(NSDictionary *)info {
    NSString *bundleID = info[@"bundleID"];
    if (!bundleID) return @{@"error": @"bundleID required"};
    // Kill app by bundleID
    NSString *cmd = [NSString stringWithFormat:@"/usr/bin/killall '%@' 2>/dev/null", bundleID];
    system([cmd UTF8String]);
    return @{@"status": @"killed", @"bundleID": bundleID};
}

- (NSDictionary *)handleOpenApp:(NSString *)name userInfo:(NSDictionary *)info {
    NSString *bundleID = info[@"bundleID"];
    if (!bundleID) return @{@"error": @"bundleID required"};
    // Open via SpringBoardServices
    NSString *cmd = [NSString stringWithFormat:@"/usr/bin/open com.%@.app:// 2>/dev/null || \
                      /usr/bin/uiopen %@ 2>/dev/null", bundleID, bundleID];
    system([cmd UTF8String]);
    return @{@"status": @"opened", @"bundleID": bundleID};
}

- (NSDictionary *)handleRunCommand:(NSString *)name userInfo:(NSDictionary *)info {
    NSString *cmd = info[@"command"];
    if (!cmd) return @{@"error": @"command required"};

    FILE *fp = popen([cmd UTF8String], "r");
    if (!fp) return @{@"error": @"popen failed"};

    NSMutableString *output = [NSMutableString string];
    char buf[4096];
    while (fgets(buf, sizeof(buf), fp)) {
        [output appendString:[NSString stringWithUTF8String:buf]];
    }
    int status = pclose(fp);

    return @{@"status": @"executed", @"exitCode": @(status), @"output": output};
}

- (NSDictionary *)handleCheckIP:(NSString *)name userInfo:(NSDictionary *)info {
    NSString *host = info[@"host"] ?: @"checkip.amazonaws.com";
    // Use curl to check IP
    NSString *cmd = [NSString stringWithFormat:@"/usr/bin/curl -s --max-time 5 %@ 2>/dev/null", host];
    FILE *fp = popen([cmd UTF8String], "r");
    NSString *ip = @"unknown";
    if (fp) {
        char buf[256] = {0};
        if (fgets(buf, sizeof(buf), fp)) {
            ip = [[NSString stringWithUTF8String:buf] stringByTrimmingCharactersInSet:
                  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        pclose(fp);
    }
    return @{@"ip": ip, @"host": host};
}

@end
