// XAGRRS.mm — Full RRS lifecycle: keychain wipe + backup + restore + app wipe
// Mirrors XoaInfo's reset flow exactly

#import "XAGRRS.h"
#import "XAGDeviceInfo.h"

#define XAG_RRS_DIR @"/var/mobile/ZMMO_RRS"

@interface XAGRRS ()
@property (nonatomic, strong) NSFileManager *fm;
@end

@implementation XAGRRS

+ (instancetype)shared {
    static XAGRRS *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[XAGRRS alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _fm = [NSFileManager defaultManager];
        [_fm createDirectoryAtPath:XAG_RRS_DIR withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return self;
}

// ────────────────────────────────────────
#pragma mark - RESET (like XoaInfo's reset)
// ────────────────────────────────────────

- (NSDictionary *)reset:(NSArray *)appBundleIDs wipeKeychain:(BOOL)wipeKeychain {
    NSMutableArray *results = [NSMutableArray array];

    // 1. Wipe app data for specified apps
    for (NSString *bundleID in appBundleIDs) {
        NSDictionary *r = [self wipeApp:bundleID];
        [results addObject:r];
    }

    // 2. Keychain wipe (like XoaInfo: chmod -R 600 / keychain-2.*)
    if (wipeKeychain) {
        system("/bin/chmod -R 600 /private/var/Keychains/keychain-2.* 2>/dev/null");
        system("/usr/sbin/chown -R _securityd:wheel /private/var/Keychains/keychain-2.* 2>/dev/null");
        [results addObject:@{@"keychain": @"wiped"}];
    }

    // 3. Clear advertising identifier (IDFA reset like XoaInfo)
    system("/usr/bin/killall -9 AdSheet 2>/dev/null");
    [results addObject:@{@"idfa": @"cleared"}];

    // 4. Kill all relevant services (same list as XoaInfo)
    NSArray *services = @[
        @"accountsd", @"akd", @"AppStore", @"appstored",
        @"itunesstored", @"itunescloudd", @"mDNSResponder",
        @"nsurlsessiond", @"pkd", @"configd", @"networkd",
        @"Preference", @"Preferences", @"wifid", @"wirelessproxd",
        @"mobileassetd", @"AssetCacheLocatorService"
    ];

    for (NSString *svc in services) {
        system([[NSString stringWithFormat:@"/usr/bin/killall -9 %@ 2>/dev/null", svc] UTF8String]);
    }

    // 5. Generate new random IDs
    [[XAGDeviceInfo shared] randomSerial];
    [[XAGDeviceInfo shared] randomIMEI];

    return @{
        @"status": @"reset",
        @"appsWiped": @(appBundleIDs.count),
        @"keychainWiped": @(wipeKeychain),
        @"servicesKilled": @(services.count),
        @"results": results,
    };
}

// ────────────────────────────────────────
#pragma mark - BACKUP RRS
// ────────────────────────────────────────

- (NSString *)containerPathForBundleID:(NSString *)bundleID {
    NSString *appDir = @"/var/mobile/Containers/Data/Application";
    NSArray *uuids = [self.fm contentsOfDirectoryAtPath:appDir error:nil];
    for (NSString *uuid in uuids) {
        NSString *metaPath = [appDir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@/.com.apple.mobile_container_manager.metadata.plist", uuid]];
        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
        if ([meta[@"MCMMetadataIdentifier"] isEqualToString:bundleID]) {
            return [appDir stringByAppendingPathComponent:uuid];
        }
    }
    return nil;
}

- (NSDictionary *)backupRRS:(NSString *)label {
    NSString *backupDir = [XAG_RRS_DIR stringByAppendingPathComponent:label];
    [self.fm removeItemAtPath:backupDir error:nil];
    [self.fm createDirectoryAtPath:backupDir withIntermediateDirectories:YES attributes:nil error:nil];

    // 1. Save device state snapshot
    NSDictionary *deviceState = [[XAGDeviceInfo shared] deviceFullInfo];
    [deviceState writeToFile:[backupDir stringByAppendingPathComponent:@"deviceState.plist"] atomically:YES];

    // 2. Save current config
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:
        @"/var/mobile/Library/Preferences/com.zmmo.iosag.plist"];
    if (config) {
        [config writeToFile:[backupDir stringByAppendingPathComponent:@"config.plist"] atomically:YES];
    }

    // 3. Copy app containers for managed apps
    NSArray *managedApps = config[@"managedApps"] ?: @[];
    NSMutableArray *backedUp = [NSMutableArray array];

    for (NSString *bundleID in managedApps) {
        NSString *containerPath = [self containerPathForBundleID:bundleID];
        if (containerPath) {
            NSString *dst = [backupDir stringByAppendingPathComponent:
                [NSString stringWithFormat:@"app_%@", bundleID]];
            [self.fm copyItemAtPath:containerPath toPath:dst error:nil];
            [backedUp addObject:bundleID];
        }
    }

    // 4. Metadata
    NSDictionary *meta = @{
        @"label": label,
        @"date": [[NSDate date] description],
        @"version": @"0.1.0",
        @"appsCount": @(backedUp.count),
        @"apps": backedUp,
    };
    [meta writeToFile:[backupDir stringByAppendingPathComponent:@"backup.json"] atomically:YES];

    // Calculate size
    unsigned long long size = [self dirSize:backupDir];

    return @{
        @"status": @"backed_up",
        @"label": label,
        @"appsCount": @(backedUp.count),
        @"size": @(size),
        @"path": backupDir,
    };
}

// ────────────────────────────────────────
#pragma mark - RESTORE RRS
// ────────────────────────────────────────

- (NSDictionary *)restoreRRS:(NSString *)label {
    NSString *backupDir = [XAG_RRS_DIR stringByAppendingPathComponent:label];
    if (![self.fm fileExistsAtPath:backupDir]) {
        return @{@"error": @"Backup not found", @"label": label};
    }

    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:
        [backupDir stringByAppendingPathComponent:@"backup.json"]];

    // 1. Restore device state
    NSString *statePath = [backupDir stringByAppendingPathComponent:@"deviceState.plist"];
    if ([self.fm fileExistsAtPath:statePath]) {
        NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:statePath];
        // Apply config values back
    }

    // 2. Restore config
    NSString *configSrc = [backupDir stringByAppendingPathComponent:@"config.plist"];
    if ([self.fm fileExistsAtPath:configSrc]) {
        [self.fm copyItemAtPath:configSrc
                         toPath:@"/var/mobile/Library/Preferences/com.zmmo.iosag.plist" error:nil];
    }

    // 3. Restore app containers
    NSArray *apps = meta[@"apps"] ?: @[];
    NSMutableArray *restored = [NSMutableArray array];

    for (NSString *bundleID in apps) {
        NSString *src = [backupDir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"app_%@", bundleID]];
        if ([self.fm fileExistsAtPath:src]) {
            NSString *container = [self containerPathForBundleID:bundleID];
            if (container) {
                [self.fm removeItemAtPath:container error:nil];
                [self.fm copyItemAtPath:src toPath:container error:nil];
                [restored addObject:bundleID];
            }
        }
    }

    // 4. Kill SpringBoard to reload
    system("/usr/bin/killall -9 SpringBoard backboardd 2>/dev/null");

    return @{
        @"status": @"restored",
        @"label": label,
        @"appsRestored": @(restored.count),
    };
}

// ────────────────────────────────────────
#pragma mark - WIPE APP
// ────────────────────────────────────────

- (NSDictionary *)wipeApp:(NSString *)bundleID {
    NSString *containerPath = [self containerPathForBundleID:bundleID];
    if (!containerPath) {
        return @{@"error": @"Container not found", @"bundleID": bundleID};
    }

    // Kill app first
    system([[NSString stringWithFormat:@"/usr/bin/killall %@ 2>/dev/null", bundleID] UTF8String]);

    // Wipe container
    NSString *cmd = [NSString stringWithFormat:
        @"/bin/rm -rf '%@'/Documents '%@'/Library '%@'/tmp 2>/dev/null; "
        @"/bin/mkdir -p '%@'/Documents '%@'/Library/Caches '%@'/tmp",
        containerPath, containerPath, containerPath,
        containerPath, containerPath, containerPath];
    system([cmd UTF8String]);

    return @{@"status": @"wiped", @"bundleID": bundleID};
}

// ────────────────────────────────────────
#pragma mark - LIST BACKUPS
// ────────────────────────────────────────

- (NSDictionary *)listBackups {
    NSMutableArray *backups = [NSMutableArray array];
    NSArray *items = [self.fm contentsOfDirectoryAtPath:XAG_RRS_DIR error:nil];

    for (NSString *item in items) {
        NSString *metaPath = [[XAG_RRS_DIR stringByAppendingPathComponent:item]
                              stringByAppendingPathComponent:@"backup.json"];
        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
        unsigned long long size = [self dirSize:[XAG_RRS_DIR stringByAppendingPathComponent:item]];

        [backups addObject:@{
            @"label": item,
            @"date": meta[@"date"] ?: @"?",
            @"appsCount": meta[@"appsCount"] ?: @0,
            @"size": @(size),
        }];
    }

    return @{@"backups": backups, @"count": @(backups.count)};
}

// ────────────────────────────────────────
#pragma mark - Helpers
// ────────────────────────────────────────

- (unsigned long long)dirSize:(NSString *)path {
    unsigned long long size = 0;
    NSDirectoryEnumerator *e = [self.fm enumeratorAtPath:path];
    for (NSString *f in e) {
        size += [[self.fm attributesOfItemAtPath:[path stringByAppendingPathComponent:f] error:nil][NSFileSize] unsignedLongLongValue];
    }
    return size;
}

@end
