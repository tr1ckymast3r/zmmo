// daemon/LuaEngine.mm — Embedded Lua 5.3/5.4 scripting engine
// Uses JavaScriptCore (built-in on iOS) as JS interpreter for .lua-compatible API
// Real Lua would require liblua statically linked — JSC is zero deps

#import "LuaEngine.h"
#import <JavaScriptCore/JavaScriptCore.h>

@interface LuaEngine () {
    JSContext *_ctx;
    BOOL _shouldStop;
    NSMutableDictionary *_modules;
}
@end

@implementation LuaEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _ctx = [[JSContext alloc] init];
        _modules = [NSMutableDictionary dictionary];
        [self registerBuiltins];
    }
    return self;
}

- (void)registerBuiltins {
    __weak typeof(self) ws = self;

    // Screen / touch
    _ctx[@"tap"] = ^(double x, double y) {
        system([[NSString stringWithFormat:@"/usr/bin/autotouch inputText '%f %f tap' 2>/dev/null", x, y] UTF8String]);
    };
    _ctx[@"swipe"] = ^(double x1, double y1, double x2, double y2) {
        system([[NSString stringWithFormat:@"/usr/bin/autotouch inputText '%f %f swipe %f %f' 2>/dev/null", x1, y1, x2, y2] UTF8String]);
    };
    _ctx[@"inputText"] = ^(NSString *text) {
        system([[NSString stringWithFormat:@"/usr/bin/autotouch inputText '%@' 2>/dev/null", text] UTF8String]);
    };
    _ctx[@"home"] = ^{
        system("/usr/bin/killall -9 SpringBoard backboardd 2>/dev/null");
    };

    // File I/O (Lua-compatible)
    _ctx[@"writeFile"] = ^(NSString *path, NSString *content) {
        [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    };
    _ctx[@"readFile"] = ^NSString *(NSString *path) {
        return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
    };

    // Network
    _ctx[@"httpGet"] = ^NSString *(NSString *url) {
        NSData *d = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
        return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"";
    };
    _ctx[@"httpPost"] = ^NSString *(NSString *url, NSString *body) {
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
        req.HTTPMethod = @"POST";
        req.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
        NSData *d = [NSURLConnection sendSynchronousRequest:req returningResponse:nil error:nil];
        return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"";
    };

    // Timer / Async
    _ctx[@"sleepMs"] = ^(int ms) { usleep(ms * 1000); };
    _ctx[@"stop"] = ^{ ws->_shouldStop = YES; };

    // Log
    _ctx[@"log"] = ^(NSString *msg) { NSLog(@"[LUA] %@", msg); };

    // OCR helper bridge
    _ctx[@"findText"] = ^NSString *(int x, int y, int w, int h) {
        // Will call OCRHelper via notification
        return @"";
    };

    // Clipboard
    _ctx[@"getClipboard"] = ^NSString * {
        return [[UIPasteboard generalPasteboard] string] ?: @"";
    };
    _ctx[@"setClipboard"] = ^(NSString *text) {
        [[UIPasteboard generalPasteboard] setString:text];
    };

    // require() support
    _ctx[@"require"] = ^id(NSString *module) {
        NSString *path = [NSString stringWithFormat:@"/var/mobile/Library/ZMMO/ios-auto/modules/%@.js", module];
        NSString *code = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (!code) code = [NSString stringWithContentsOfFile:[module stringByAppendingString:@".js"] encoding:NSUTF8StringEncoding error:nil];
        if (code) return [ws->_ctx evaluateScript:code];
        return [JSValue valueWithUndefinedInContext:ws->_ctx];
    };
}

- (NSDictionary *)execute:(NSString *)script args:(NSArray *)args {
    _shouldStop = NO;
    _ctx[@"args"] = args ?: @[];

    JSValue *result = [_ctx evaluateScript:script];
    if (_ctx.exception) {
        return @{@"error": _ctx.exception.toString ?: @"unknown error",
                 @"shouldStop": @(_shouldStop)};
    }
    return @{@"result": result.toString ?: @"nil",
             @"shouldStop": @(_shouldStop)};
}

- (NSDictionary *)stop {
    _shouldStop = YES;
    return @{@"stopped": @YES};
}

- (NSDictionary *)handleAPI:(NSString *)action body:(NSData *)body {
    if ([action isEqualToString:@"exec"]) {
        NSDictionary *params = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
        return [self execute:params[@"script"] ?: @"" args:params[@"args"]];
    }
    if ([action isEqualToString:@"stop"]) return [self stop];
    if ([action isEqualToString:@"list"]) {
        NSArray *modules = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:
            @"/var/mobile/Library/ZMMO/ios-auto/modules" error:nil] ?: @[];
        return @{@"modules": modules};
    }
    return @{@"error": [NSString stringWithFormat:@"unknown action: %@", action]};
}

- (NSString *)status {
    return @"running";
}

@end
