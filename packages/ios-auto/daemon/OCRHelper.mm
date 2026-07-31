// daemon/OCRHelper.mm — OCR + image recognition bridge
// Actual OCR runs in the SpringBoard dylib via Vision framework
// Daemon sends commands via Darwin notifications

#import "OCRHelper.h"
#import <CoreFoundation/CoreFoundation.h>

@implementation OCRHelper

- (NSDictionary *)findText:(CGRect)region {
    // Request OCR via notification → dylib handles Vision framework
    NSDictionary *request = @{
        @"action": @"findText",
        @"x": @(region.origin.x), @"y": @(region.origin.y),
        @"w": @(region.size.width), @"h": @(region.size.height)
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    // Post notification — dylib will process and save result to temp file
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.zmmo.iosauto.ocrRequest"),
        (__bridge CFStringRef)json, NULL, YES);

    // Wait briefly for result
    usleep(500000); // 500ms

    // Read result
    NSString *resultPath = @"/tmp/zmmo_ocr_result.json";
    NSDictionary *result = [NSJSONSerialization JSONObjectWithData:
        [NSData dataWithContentsOfFile:resultPath] options:0 error:nil];
    return result ?: @{@"text": @"", @"status": @"no_result"};
}

- (NSDictionary *)captureScreen {
    NSDictionary *request = @{@"action": @"captureScreen"};
    NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.zmmo.iosauto.ocrRequest"),
        (__bridge CFStringRef)[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding],
        NULL, YES);

    usleep(500000);
    NSDictionary *result = [NSJSONSerialization JSONObjectWithData:
        [NSData dataWithContentsOfFile:@"/tmp/zmmo_screen_result.json"] options:0 error:nil];
    return result ?: @{@"path": @"", @"status": @"no_result"};
}

- (NSDictionary *)handleAPI:(NSString *)action body:(NSData *)body {
    if ([action isEqualToString:@"findText"]) {
        NSDictionary *p = body ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : @{};
        return [self findText:CGRectMake([p[@"x"] floatValue], [p[@"y"] floatValue],
                                          [p[@"w"] floatValue], [p[@"h"] floatValue])];
    }
    if ([action isEqualToString:@"captureScreen"]) {
        return [self captureScreen];
    }
    if ([action isEqualToString:@"findImage"]) {
        // Template matching via Vision framework
        NSDictionary *p = body ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : @{};
        NSDictionary *request = @{@"action": @"findImage", @"template": p[@"template"] ?: @"",
                                  @"threshold": p[@"threshold"] ?: @0.8};
        NSData *d = [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.zmmo.iosauto.ocrRequest"),
            (__bridge CFStringRef)[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding],
            NULL, YES);
        usleep(500000);
        return [NSJSONSerialization JSONObjectWithData:
                [NSData dataWithContentsOfFile:@"/tmp/zmmo_match_result.json"] options:0 error:nil] ?: @{};
    }
    return @{@"error": [NSString stringWithFormat:@"unknown: %@", action]};
}

@end
