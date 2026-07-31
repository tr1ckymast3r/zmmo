// ZMMOBackup.mm — App data backup/restore/wipe
// iOS app containers: /var/mobile/Containers/Data/Application/<UUID>/
// Groups: /var/mobile/Containers/Shared/AppGroup/<UUID>/

#import "ZMMOBackup.h"
#import <dlfcn.h>

#define ZMMO_BACKUP_DIR @"/var/mobile/ZMMOBackups"

@interface ZMMOBackup ()
@property (nonatomic, strong) NSFileManager *fm;
@end

@implementation ZMMOBackup

+ (instancetype)shared {
    static ZMMOBackup *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ZMMOBackup alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _fm = [NSFileManager defaultManager];
        // Ensure backup directory exists
        [_fm createDirectoryAtPath:ZMMO_BACKUP_DIR
       withIntermediateDirectories:YES
                        attributes:nil
                             error:nil];
    }
    return self;
}

// ────────────────────────────────────────
#pragma mark - App Discovery
// ────────────────────────────────────────

- (NSString *)containerPathForBundleID:(NSString *)bundleID {
    // Search /var/mobile/Containers/Data/Application/ for the app's container
    NSString *appDir = @"/var/mobile/Containers/Data/Application";
    NSArray *uuids = [self.fm contentsOfDirectoryAtPath:appDir error:nil];

    for (NSString *uuid in uuids) {
        NSString *plistPath = [appDir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@/.com.apple.mobile_container_manager.metadata.plist", uuid]];

        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        NSString *bid = meta[@"MCMMetadataIdentifier"];
        if ([bid isEqualToString:bundleID]) {
            return [appDir stringByAppendingPathComponent:uuid];
        }
    }
    return nil;
}

- (NSArray *)appGroupPathsForBundleID:(NSString *)bundleID {
    NSMutableArray *groups = [NSMutableArray array];
    NSString *groupDir = @"/var/mobile/Containers/Shared/AppGroup";
    NSArray *uuids = [self.fm contentsOfDirectoryAtPath:groupDir error:nil];

    for (NSString *uuid in uuids) {
        NSString *plistPath = [groupDir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@/.com.apple.mobile_container_manager.metadata.plist", uuid]];

        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        NSString *bid = meta[@"MCMMetadataIdentifier"];
        if ([bid hasPrefix:bundleID] || [bid containsString:bundleID]) {
            [groups addObject:[groupDir stringByAppendingPathComponent:uuid]];
        }
    }
    return groups;
}

- (NSDictionary *)listInstalledApps {
    // Scan /var/containers/Bundle/Application for .app bundles
    // and /Applications for system apps
    NSMutableArray *apps = [NSMutableArray array];

    NSArray *searchDirs = @[
        @"/var/containers/Bundle/Application",
        @"/Applications"
    ];

    for (NSString *dir in searchDirs) {
        NSArray *contents = [self.fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *item in contents) {
            NSString *itemPath = [dir stringByAppendingPathComponent:item];

            // Look for .app bundles
            if ([item hasSuffix:@".app"]) {
                NSString *infoPath = [itemPath stringByAppendingPathComponent:@"Info.plist"];
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
                if (info[@"CFBundleIdentifier"]) {
                    [apps addObject:@{
                        @"bundleID": info[@"CFBundleIdentifier"],
                        @"name": info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: item,
                        @"version": info[@"CFBundleShortVersionString"] ?: @"?",
                        @"path": itemPath,
                    }];
                }
            } else {
                // Subdirectory — scan for .app inside
                NSString *possibleApp = [itemPath stringByAppendingPathComponent:
                    [[self.fm contentsOfDirectoryAtPath:itemPath error:nil] firstObject]];
                if ([possibleApp hasSuffix:@".app"]) {
                    NSString *infoPath = [possibleApp stringByAppendingPathComponent:@"Info.plist"];
                    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
                    if (info[@"CFBundleIdentifier"]) {
                        [apps addObject:@{
                            @"bundleID": info[@"CFBundleIdentifier"],
                            @"name": info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: item,
                            @"version": info[@"CFBundleShortVersionString"] ?: @"?",
                            @"path": possibleApp,
                        }];
                    }
                }
            }
        }
    }

    return @{@"apps": apps, @"count": @(apps.count)};
}

// ────────────────────────────────────────
#pragma mark - Backup
// ────────────────────────────────────────

- (NSDictionary *)backupApp:(NSString *)bundleID
                   filename:(NSString *)filename
                    comment:(NSString *)comment
                    timeout:(NSTimeInterval)timeout {

    NSString *containerPath = [self containerPathForBundleID:bundleID];
    if (!containerPath) {
        return @{@"error": @"App container not found", @"bundleID": bundleID};
    }

    NSString *backupDir = [ZMMO_BACKUP_DIR stringByAppendingPathComponent:filename];

    // Remove old backup if exists
    [self.fm removeItemAtPath:backupDir error:nil];
    [self.fm createDirectoryAtPath:backupDir withIntermediateDirectories:YES attributes:nil error:nil];

    // Run cp via NSTask or use NSFileManager copy
    // For large data, use shell command
    NSString *cmd = [NSString stringWithFormat:
        @"/bin/cp -R '%@' '%@/' 2>&1", containerPath, backupDir];

    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/bin/sh"];
    [task setArguments:@[@"-c", cmd]];

    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];

    [task launch];

    // Wait with timeout
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block BOOL timedOut = NO;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [task waitUntilExit];
        dispatch_semaphore_signal(sem);
    });

    long result = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW,
        (int64_t)(timeout * NSEC_PER_SEC)));

    if (result != 0) {
        timedOut = YES;
        [task terminate];
    }

    // Copy app groups too
    NSArray *groupPaths = [self appGroupPathsForBundleID:bundleID];
    for (NSString *gp in groupPaths) {
        NSString *groupName = [gp lastPathComponent];
        NSString *groupDst = [backupDir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"AppGroup_%@", groupName]];
        [self.fm copyItemAtPath:gp toPath:groupDst error:nil];
    }

    // Write metadata
    NSDictionary *meta = @{
        @"bundleID": bundleID,
        @"comment": comment,
        @"backupDate": [[NSDate date] description],
        @"filename": filename,
        @"groups": @(groupPaths.count),
        @"timedOut": @(timedOut),
    };
    [meta writeToFile:[backupDir stringByAppendingPathComponent:@"backup.json"] atomically:YES];

    // Calculate size
    unsigned long long size = [self directorySize:backupDir];

    return @{
        @"status": timedOut ? @"partial" : @"ok",
        @"filename": filename,
        @"bundleID": bundleID,
        @"size": @(size),
        @"groups": @(groupPaths.count),
        @"path": backupDir,
    };
}

// ────────────────────────────────────────
#pragma mark - Restore
// ────────────────────────────────────────

- (NSDictionary *)restoreBackup:(NSString *)filename timeout:(NSTimeInterval)timeout {
    NSString *backupDir = [ZMMO_BACKUP_DIR stringByAppendingPathComponent:filename];
    if (![self.fm fileExistsAtPath:backupDir]) {
        return @{@"error": @"Backup not found", @"filename": filename};
    }

    // Read metadata
    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:
        [backupDir stringByAppendingPathComponent:@"backup.json"]];
    NSString *bundleID = meta[@"bundleID"];
    if (!bundleID) {
        return @{@"error": @"No bundleID in backup metadata"};
    }

    NSString *containerPath = [self containerPathForBundleID:bundleID];
    if (!containerPath) {
        return @{@"error": @"App container not found (is app installed?)", @"bundleID": bundleID};
    }

    // Kill the app first
    NSString *killCmd = [NSString stringWithFormat:@"/usr/bin/killall '%@' 2>/dev/null", bundleID];
    system([killCmd UTF8String]);

    // Remove current container contents and restore backup
    NSString *restoreCmd = [NSString stringWithFormat:
        @"/bin/rm -rf '%@'/* && /bin/cp -R '%@'/ \"%@/\" 2>&1",
        containerPath, backupDir, containerPath];

    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/bin/sh"];
    [task setArguments:@[@"-c", restoreCmd]];
    [task launch];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block int exitCode = -1;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [task waitUntilExit];
        exitCode = [task terminationStatus];
        dispatch_semaphore_signal(sem);
    });

    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW,
        (int64_t)(timeout * NSEC_PER_SEC)));

    if (exitCode != 0) {
        [task terminate];
    }

    return @{
        @"status": exitCode == 0 ? @"ok" : @"error",
        @"filename": filename,
        @"bundleID": bundleID,
        @"exitCode": @(exitCode),
    };
}

// ────────────────────────────────────────
#pragma mark - Wipe
// ────────────────────────────────────────

- (NSDictionary *)wipeApp:(NSString *)bundleID timeout:(NSTimeInterval)timeout {
    NSString *containerPath = [self containerPathForBundleID:bundleID];
    if (!containerPath) {
        return @{@"error": @"App container not found", @"bundleID": bundleID};
    }

    // Kill app
    system([[@"/usr/bin/killall " stringByAppendingString:bundleID] UTF8String]);

    // Wipe container contents (keep directory)
    NSString *wipeCmd = [NSString stringWithFormat:
        @"/bin/rm -rf '%@'/* '%@'/.* 2>/dev/null; /bin/mkdir -p '%@'/Documents '%@'/Library '%@'/tmp",
        containerPath, containerPath, containerPath, containerPath, containerPath];

    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/bin/sh"];
    [task setArguments:@[@"-c", wipeCmd]];
    [task launch];
    [task waitUntilExit];

    return @{
        @"status": @"ok",
        @"bundleID": bundleID,
    };
}

// ────────────────────────────────────────
#pragma mark - Backup List
// ────────────────────────────────────────

- (NSDictionary *)listBackups {
    NSMutableArray *backups = [NSMutableArray array];
    NSArray *contents = [self.fm contentsOfDirectoryAtPath:ZMMO_BACKUP_DIR error:nil];

    for (NSString *item in contents) {
        NSString *itemPath = [ZMMO_BACKUP_DIR stringByAppendingPathComponent:item];
        NSString *metaPath = [itemPath stringByAppendingPathComponent:@"backup.json"];
        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
        unsigned long long size = [self directorySize:itemPath];

        [backups addObject:@{
            @"filename": item,
            @"bundleID": meta[@"bundleID"] ?: @"?",
            @"comment": meta[@"comment"] ?: @"",
            @"date": meta[@"backupDate"] ?: @"?",
            @"size": @(size),
        }];
    }

    return @{@"backups": backups, @"count": @(backups.count)};
}

- (NSDictionary *)removeBackup:(NSString *)filename {
    NSString *path = [ZMMO_BACKUP_DIR stringByAppendingPathComponent:filename];
    NSError *err = nil;
    [self.fm removeItemAtPath:path error:&err];
    if (err) {
        return @{@"error": err.localizedDescription, @"filename": filename};
    }
    return @{@"status": @"removed", @"filename": filename};
}

// ────────────────────────────────────────
#pragma mark - Helpers
// ────────────────────────────────────────

- (unsigned long long)directorySize:(NSString *)path {
    unsigned long long size = 0;
    NSDirectoryEnumerator *enumerator = [self.fm enumeratorAtPath:path];
    for (NSString *file in enumerator) {
        NSDictionary *attrs = [self.fm attributesOfItemAtPath:
            [path stringByAppendingPathComponent:file] error:nil];
        size += [attrs[NSFileSize] unsignedLongLongValue];
    }
    return size;
}

@end
