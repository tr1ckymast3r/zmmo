// XAGRRS.h — Retention/Restore/Save system (mirrors XoaInfo's RRS)

#import <Foundation/Foundation.h>

@interface XAGRRS : NSObject

+ (instancetype)shared;

/// Reset: wipe app data + optionally keychain, kill services
- (NSDictionary *)reset:(NSArray *)appBundleIDs wipeKeychain:(BOOL)wipeKeychain;

/// Save RRS: backup app containers + device state
- (NSDictionary *)backupRRS:(NSString *)label;

/// Restore RRS: restore app data + device state from backup
- (NSDictionary *)restoreRRS:(NSString *)label;

/// Wipe single app data
- (NSDictionary *)wipeApp:(NSString *)bundleID;

/// List saved backups
- (NSDictionary *)listBackups;

@end
