// daemon/TouchInject.mm — Touch event injection via IOKit HID
// Receives JSON commands from WebSocket and translates to touch events

#import "TouchInject.h"
#import "ZMMOTouch.h"

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
        [ZMMOTouch tap:x y:y];
    } else if ([type isEqualToString:@"swipe"]) {
        [ZMMOTouch swipe:x y:y toX:x2 toY:y2 duration:300];
    } else if ([type isEqualToString:@"swipeU"]) {
        [ZMMOTouch swipe:x y:y toX:x toY:y - 600 duration:200];
    } else if ([type isEqualToString:@"swipeD"]) {
        [ZMMOTouch swipe:x y:y toX:x toY:y + 600 duration:200];
    } else if ([type isEqualToString:@"swipeL"]) {
        [ZMMOTouch swipe:x y:y toX:x - 400 toY:y duration:200];
    } else if ([type isEqualToString:@"swipeR"]) {
        [ZMMOTouch swipe:x y:y toX:x + 400 toY:y duration:200];
    } else if ([type isEqualToString:@"home"]) {
        [ZMMOTouch home];
    } else if ([type isEqualToString:@"power"]) {
        [ZMMOTouch power];
    } else if ([type isEqualToString:@"volUp"]) {
        [ZMMOTouch volUp];
    } else if ([type isEqualToString:@"volDown"]) {
        [ZMMOTouch volDown];
    } else if ([type isEqualToString:@"clipboard"]) {
        if (cmd[@"text"]) {
            [ZMMOTouch typeText:cmd[@"text"]];
        }
    }
}

@end
