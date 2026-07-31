// daemon/MCPServer.mm — Model Context Protocol SSE server
// Exposes all automation functions as MCP tools for AI agent control
// Endpoint: /sse — Server-Sent Events stream

#import "MCPServer.h"

@interface MCPServer ()
@property (nonatomic, strong) NSMutableArray *clients;
@end

@implementation MCPServer

+ (instancetype)shared {
    static MCPServer *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[MCPServer alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _clients = [NSMutableArray array];
    }
    return self;
}

- (NSString *)description {
    return @"MCP server ready — connect to /sse";
}

// MCP protocol provides these tools to AI agents:
// Tools registry
- (NSDictionary *)mcpTools {
    return @{
        @"tools": @[
            @{@"name": @"lua_exec", @"description": @"Execute Lua/JS script on device",
              @"parameters": @{@"script": @"string", @"args": @"array?"}},
            @{@"name": @"tap", @"description": @"Tap at coordinates",
              @"parameters": @{@"x": @"number", @"y": @"number"}},
            @{@"name": @"swipe", @"description": @"Swipe gesture",
              @"parameters": @{@"x1": @"number", @"y1": @"number", @"x2": @"number", @"y2": @"number"}},
            @{@"name": @"inputText", @"description": @"Type text",
              @"parameters": @{@"text": @"string"}},
            @{@"name": @"openAcc", @"description": @"Open app with specific account data",
              @"parameters": @{@"bundleID": @"string", @"accName": @"string"}},
            @{@"name": @"backupAcc", @"description": @"Backup app data for account",
              @"parameters": @{@"bundleID": @"string", @"accName": @"string"}},
            @{@"name": @"restoreAcc", @"description": @"Restore app data for account",
              @"parameters": @{@"bundleID": @"string", @"accName": @"string"}},
            @{@"name": @"resetApp", @"description": @"Wipe all app data",
              @"parameters": @{@"bundleID": @"string"}},
            @{@"name": @"findText", @"description": @"OCR text from screen region",
              @"parameters": @{@"x": @"number", @"y": @"number", @"w": @"number", @"h": @"number"}},
            @{@"name": @"findImage", @"description": @"Find template image on screen",
              @"parameters": @{@"template": @"string", @"threshold": @"number?"}},
            @{@"name": @"captureScreen", @"description": @"Take screenshot",
              @"parameters": @{}},
            @{@"name": @"fakeLocation", @"description": @"Set fake GPS location",
              @"parameters": @{@"lat": @"number", @"lon": @"number"}},
            @{@"name": @"setProxy", @"description": @"Set HTTP/HTTPS proxy",
              @"parameters": @{@"proxy": @"string (ip:port:user:pass)"}},
            @{@"name": @"getClipboard", @"description": @"Get clipboard text",
              @"parameters": @{}},
            @{@"name": @"setClipboard", @"description": @"Set clipboard text",
              @"parameters": @{@"text": @"string"}},
            @{@"name": @"home", @"description": @"Go to home screen",
              @"parameters": @{}},
            @{@"name": @"reboot", @"description": @"Userspace reboot",
              @"parameters": @{}},
            @{@"name": @"status", @"description": @"Get device status (RAM, CPU, storage)",
              @"parameters": @{}},
        ]
    };
}

@end
