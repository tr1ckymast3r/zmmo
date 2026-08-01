// daemon/AppFarming.mm — Account farming: backup/restore/wipe app containers
// Works by copying app data directories to/from backup storage

#import "AppFarming.h"
#import <dlfcn.h>

#define FARM_DIR @"/var/mobile/Library/ZMMO/ios-auto/farms"

@interface AppFarming ()
@property (nonatomic, strong) NSFileManager *fm;
@end

@implementation AppFarming

- (instancetype)init {
    self = [super init];
    if (self) {
        _fm = [NSFileManager defaultManager];
        [_fm createDirectoryAtPath:FARM_DIR withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return self;
}

// ── Container path lookup (same as XAGRRS) ──

- (NSString *)containerPathForBundleID:(NSString *)bundleID {
    NSString *appDir = @"/var/mobile/Containers/Data/Application";
    NSArray *uuids = [_fm contentsOfDirectoryAtPath:appDir error:nil];
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

// ── openAcc — restore app data for specific account ──

- (NSDictionary *)openAcc:(NSString *)bundleID account:(NSString *)accName {
    if (!bundleID || !accName) return @{@"error": @"bundleID + accName required"};

    // Kill app first
    system([[NSString stringWithFormat:@"/usr/bin/killall %@ 2>/dev/null", bundleID] UTF8String]);

    NSString *containerPath = [self containerPathForBundleID:bundleID];
    NSString *backupPath = [NSString stringWithFormat:@"%@/%@/%@", FARM_DIR, bundleID, accName];

    if (![_fm fileExistsAtPath:backupPath]) {
        return @{@"error": @"Account backup not found. Use backupAcc first.", @"accName": accName};
    }

    // Wipe current app data using NSFileManager (no shell calls)
    for (NSString *sub in @[@"Documents", @"Library", @"tmp"]) {
        NSString *targetDir = [containerPath stringByAppendingPathComponent:sub];
        [self.fm removeItemAtPath:targetDir error:nil];
        [self.fm createDirectoryAtPath:targetDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    // Also recreate Library/Caches
    NSString *cachesDir = [containerPath stringByAppendingPathComponent:@"Library/Caches"];
    [self.fm createDirectoryAtPath:cachesDir withIntermediateDirectories:YES attributes:nil error:nil];

    // Copy backup data in
    for (NSString *sub in @[@"Documents", @"Library", @"tmp"]) {
        NSString *src = [backupPath stringByAppendingPathComponent:sub];
        NSString *dst = [containerPath stringByAppendingPathComponent:sub];
        [_fm removeItemAtPath:dst error:nil];
        if ([_fm fileExistsAtPath:src]) [_fm copyItemAtPath:src toPath:dst error:nil];
    }

    // Open app using LSApplicationWorkspace (no shell)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        void *ls = dlopen("/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY);
        if (ls) {
            void *ws = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
            if (ws) {
                void (*openApp)(CFStringRef) = dlsym(ws, "SBSLaunchApplicationWithIdentifier");
                if (!openApp) openApp = dlsym(ws, "_SBSLaunchApplicationWithIdentifier");
                if (openApp) openApp((__bridge CFStringRef)bundleID);
            }
        }
    });

    return @{@"status": @"opened", @"bundleID": bundleID, @"accName": accName};
}

// ── backupAcc — save current app data ──

- (NSDictionary *)backupAcc:(NSString *)bundleID account:(NSString *)accName {
    if (!bundleID || !accName) return @{@"error": @"bundleID + accName required"};

    // Kill app
    system([[NSString stringWithFormat:@"/usr/bin/killall %@ 2>/dev/null", bundleID] UTF8String]);

    NSString *containerPath = [self containerPathForBundleID:bundleID];
    if (!containerPath) return @{@"error": @"Container not found", @"bundleID": bundleID};

    NSString *backupPath = [NSString stringWithFormat:@"%@/%@/%@", FARM_DIR, bundleID, accName];
    [_fm removeItemAtPath:backupPath error:nil];

    for (NSString *sub in @[@"Documents", @"Library", @"tmp"]) {
        NSString *src = [containerPath stringByAppendingPathComponent:sub];
        NSString *dst = [backupPath stringByAppendingPathComponent:sub];
        [_fm createDirectoryAtPath:[dst stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
        if ([_fm fileExistsAtPath:src]) [_fm copyItemAtPath:src toPath:dst error:nil];
    }

    // Metadata
    [@{@"bundleID": bundleID, @"accName": accName, @"date": [[NSDate date] description]}
     writeToFile:[backupPath stringByAppendingPathComponent:@"account.json"] atomically:YES];

    return @{@"status": @"backed_up", @"bundleID": bundleID, @"accName": accName, @"path": backupPath};
}

// ── restoreAcc — alias for openAcc ──

- (NSDictionary *)restoreAcc:(NSString *)bundleID account:(NSString *)accName {
    return [self openAcc:bundleID account:accName];
}

// ── deleteAcc — remove saved account data ──

- (NSDictionary *)deleteAcc:(NSString *)bundleID account:(NSString *)accName {
    if (!bundleID || !accName) return @{@"error": @"bundleID + accName required"};
    NSString *backupPath = [NSString stringWithFormat:@"%@/%@/%@", FARM_DIR, bundleID, accName];
    [_fm removeItemAtPath:backupPath error:nil];
    return @{@"status": @"deleted", @"bundleID": bundleID, @"accName": accName};
}

// ── resetApp — wipe all app data ──

- (NSDictionary *)resetApp:(NSString *)bundleID {
    if (!bundleID) return @{@"error": @"bundleID required"};
    system([[NSString stringWithFormat:@"/usr/bin/killall %@ 2>/dev/null", bundleID] UTF8String]);
    NSString *containerPath = [self containerPathForBundleID:bundleID];
    if (!containerPath) return @{@"error": @"Container not found"};

    for (NSString *sub in @[@"Documents", @"Library", @"tmp"]) {
        NSString *targetDir = [containerPath stringByAppendingPathComponent:sub];
        [self.fm removeItemAtPath:targetDir error:nil];
        [self.fm createDirectoryAtPath:targetDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSString *cachesDir = [containerPath stringByAppendingPathComponent:@"Library/Caches"];
    [self.fm createDirectoryAtPath:cachesDir withIntermediateDirectories:YES attributes:nil error:nil];
    return @{@"status": @"reset", @"bundleID": bundleID};
}

// ── cleanAllAcc — remove all farm backups for an app ──

- (NSDictionary *)cleanAllAcc:(NSString *)bundleID {
    if (!bundleID) return @{@"error": @"bundleID required"};
    NSString *farmPath = [NSString stringWithFormat:@"%@/%@", FARM_DIR, bundleID];
    [_fm removeItemAtPath:farmPath error:nil];
    return @{@"status": @"cleaned", @"bundleID": bundleID};
}

// ── API router ──

- (NSDictionary *)handleAPI:(NSString *)action body:(NSData *)body {
    NSDictionary *p = body ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : @{};
    NSString *b = p[@"bundleID"] ?: @"";
    NSString *a = p[@"accName"] ?: @"";

    if ([action isEqualToString:@"openAcc"])    return [self openAcc:b account:a];
    if ([action isEqualToString:@"backupAcc"])  return [self backupAcc:b account:a];
    if ([action isEqualToString:@"restoreAcc"]) return [self restoreAcc:b account:a];
    if ([action isEqualToString:@"deleteAcc"])  return [self deleteAcc:b account:a];
    if ([action isEqualToString:@"resetApp"])   return [self resetApp:b];
    if ([action isEqualToString:@"cleanAllAcc"])return [self cleanAllAcc:b];
    if ([action isEqualToString:@"list"]) {
        NSArray *apps = [_fm contentsOfDirectoryAtPath:FARM_DIR error:nil] ?: @[];
        return @{@"apps": apps, @"farmDir": FARM_DIR};
    }
    return @{@"error": [NSString stringWithFormat:@"unknown: %@", action]};
}

- (NSString *)status {
    NSArray *apps = [_fm contentsOfDirectoryAtPath:FARM_DIR error:nil] ?: @[];
    return [NSString stringWithFormat:@"%lu apps farmed", (unsigned long)apps.count];
}

@end
