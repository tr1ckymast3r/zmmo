// daemon/DeviceControl.mm — Location spoof + proxy + touch/gesture

#import "DeviceControl.h"
#import <CoreLocation/CoreLocation.h>
#import <CFNetwork/CFNetwork.h>

@implementation DeviceControl

- (NSDictionary *)fakeLocation:(double)lat lon:(double)lon {
    NSDictionary *gps = @{@"lat": @(lat), @"lon": @(lon), @"enabled": @YES};
    [gps writeToFile:@"/var/mobile/Library/Preferences/com.zmmo.gps.plist" atomically:YES];

    // Notify system
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.zmmo.iosag.configChanged"), NULL, NULL, YES);

    return @{@"status": @"GPS set", @"lat": @(lat), @"lon": @(lon)};
}

- (NSDictionary *)setProxy:(NSString *)proxyStr {
    // Format: "ip:port:user:pass" or "ip:port"
    NSArray *parts = [proxyStr componentsSeparatedByString:@":"];
    if (parts.count < 2) return @{@"error": @"format: ip:port[:user:pass]"};

    NSString *ip = parts[0];
    int port = [parts[1] intValue];
    NSString *user = parts.count > 2 ? parts[2] : nil;
    NSString *pass = parts.count > 3 ? parts[3] : nil;

    NSMutableDictionary *proxy = [NSMutableDictionary dictionary];
    proxy[@"HTTPEnable"] = @YES;
    proxy[@"HTTPProxy"] = ip;
    proxy[@"HTTPPort"] = @(port);
    proxy[@"HTTPSEnable"] = @YES;
    proxy[@"HTTPSProxy"] = ip;
    proxy[@"HTTPSPort"] = @(port);

    if (user) {
        proxy[@"HTTPProxyAuthenticated"] = @YES;
        proxy[@"HTTPProxyUsername"] = user;
        proxy[@"HTTPProxyPassword"] = pass ?: @"";
    }

    // Write to SystemConfiguration proxy store
    NSString *proxyPath = @"/var/mobile/Library/Preferences/com.zmmo.proxy.plist";
    [proxy writeToFile:proxyPath atomically:YES];

    // Apply via CFNetwork
    system([[NSString stringWithFormat:@"/usr/bin/killall -9 networkd configd 2>/dev/null"] UTF8String]);

    return @{@"status": @"proxy set", @"ip": ip, @"port": @(port)};
}

- (NSDictionary *)gesture:(NSDictionary *)params {
    NSString *type = params[@"type"] ?: @"tap";
    int x = [params[@"x"] intValue];
    int y = [params[@"y"] intValue];
    int x2 = [params[@"x2"] intValue];
    int y2 = [params[@"y2"] intValue];

    if ([type isEqualToString:@"tap"]) {
        system([[NSString stringWithFormat:@"/usr/bin/autotouch inputText '%d %d tap' 2>/dev/null", x, y] UTF8String]);
    } else if ([type isEqualToString:@"swipe"]) {
        system([[NSString stringWithFormat:@"/usr/bin/autotouch inputText '%d %d swipe %d %d' 2>/dev/null", x, y, x2, y2] UTF8String]);
    } else if ([type isEqualToString:@"home"]) {
        system("/usr/bin/killall -9 SpringBoard backboardd 2>/dev/null");
    } else if ([type isEqualToString:@"power"]) {
        system([[NSString stringWithFormat:@"/usr/bin/autotouch inputText 'power' 2>/dev/null"] UTF8String]);
    } else if ([type isEqualToString:@"volUp"]) {
        system([[NSString stringWithFormat:@"/usr/bin/autotouch inputText 'volUp' 2>/dev/null"] UTF8String]);
    } else if ([type isEqualToString:@"volDown"]) {
        system([[NSString stringWithFormat:@"/usr/bin/autotouch inputText 'volDown' 2>/dev/null"] UTF8String]);
    }

    return @{@"type": type, @"x": @(x), @"y": @(y)};
}

- (NSDictionary *)handleAPI:(NSString *)action body:(NSData *)body {
    NSDictionary *p = body ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : @{};

    if ([action isEqualToString:@"fakeLocation"]) {
        return [self fakeLocation:[p[@"lat"] doubleValue] lon:[p[@"lon"] doubleValue]];
    }
    if ([action isEqualToString:@"clearLocation"]) {
        return [self fakeLocation:0 lon:0]; // Disable
    }
    if ([action isEqualToString:@"setProxy"]) {
        return [self setProxy:p[@"proxy"] ?: @""];
    }
    if ([action isEqualToString:@"gesture"]) {
        return [self gesture:p];
    }
    if ([action isEqualToString:@"reboot"]) {
        system("/usr/bin/launchctl reboot userspace 2>/dev/null || /usr/bin/reboot 2>/dev/null");
        return @{@"rebooting": @YES};
    }
    return @{@"error": [NSString stringWithFormat:@"unknown: %@", action]};
}

@end
