// ZMMOBackup.h — App data backup/restore/wipe (equivalent to KidsAutov4 RRS)

#import <Foundation/Foundation.h>

@interface ZMMOBackup : NSObject

+ (instancetype _Nonnull)shared;

/// List installed third-party apps (bundleID + name + version)
- (NSDictionary * _Nonnull)listInstalledApps;

/// Backup app data → ~/ZMMOBackups/<filename>/
- (NSDictionary * _Nonnull)backupApp:(NSString * _Nonnull)bundleID
                            filename:(NSString * _Nonnull)filename
                             comment:(NSString * _Nonnull)comment
                             timeout:(NSTimeInterval)timeout;

/// Restore app data from backup
- (NSDictionary * _Nonnull)restoreBackup:(NSString * _Nonnull)filename
                                timeout:(NSTimeInterval)timeout;

/// Wipe app data (delete container)
- (NSDictionary * _Nonnull)wipeApp:(NSString * _Nonnull)bundleID
                           timeout:(NSTimeInterval)timeout;

/// List all backups
- (NSDictionary * _Nonnull)listBackups;

/// Remove a backup
- (NSDictionary * _Nonnull)removeBackup:(NSString * _Nonnull)filename;

@end
