// daemon/TouchInject.mm — Touch event injection via IOKit HID / autotouch
// Receives JSON commands from WebSocket and translates to touch events

#import "TouchInject.h"
#import <IOKit/hid/IOHIDLib.h>

@implementation TouchInject

- (void)handleTouchCommand:(NSString *)json {
    if (!json) return;

    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *cmd = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!cmd) return;

    NSString *type = cmd[@"type"] ?: @"";
    int x = [cmd[@"x"] intValue];
    int y = [cmd[@"y"] intValue];
    int x2 = [cmd[@"x2"] intValue];
    int y2 = [cmd[@"y2"] intValue];

    if ([type isEqualToString:@"tap"]) {
        [self injectTap:x y:y];
    } else if ([type isEqualToString:@"swipe"]) {
        [self injectSwipe:x y:y x2:x2 y2:y2];
    } else if ([type isEqualToString:@"home"]) {
        system("/usr/bin/killall -9 SpringBoard backboardd 2>/dev/null");
    } else if ([type isEqualToString:@"power"]) {
        [self inject:cmd];
    } else if ([type isEqualToString:@"volumeUp"]) {
        [self inject:cmd];
    } else if ([type isEqualToString:@"volumeDown"]) {
        [self inject:cmd];
    } else if ([type isEqualToString:@"clipboard"]) {
        if (cmd[@"text"]) {
            [[UIPasteboard generalPasteboard] setString:cmd[@"text"]];
        }
    }
}

- (void)injectTap:(int)x y:(int)y {
    system([[NSString stringWithFormat:
        @"/usr/bin/autotouch inputText '%d %d tap' 2>/dev/null", x, y] UTF8String]);
}

- (void)injectSwipe:(int)x y:(int)y x2:(int)x2 y2:(int)y2 {
    system([[NSString stringWithFormat:
        @"/usr/bin/autotouch inputText '%d %d swipe %d %d' 2>/dev/null", x, y, x2, y2] UTF8String]);
}

- (void)inject:(NSDictionary *)cmd {
    NSString *type = cmd[@"type"] ?: @"";
    if ([type isEqualToString:@"power"]) {
        system("/usr/bin/autotouch inputText 'power' 2>/dev/null");
    }
}

@end
