// daemon/WSDaemon.mm — WebSocket + HTTP hybrid server
// Handles: WS commands, REST API, Web IDE serving, MCP SSE
// Routes to: LuaEngine, AppFarming, DeviceControl, OCRHelper, MCPServer

#import "WSDaemon.h"
#import "LuaEngine.h"
#import "AppFarming.h"
#import "DeviceControl.h"
#import "OCRHelper.h"
#import "MCPServer.h"

#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

#define PORT 15558
#define WEBIDE_PATH "/var/mobile/Library/ZMMO/ios-auto/webide"

@interface WSDaemon () {
    int _serverSocket;
    NSMutableSet *_connections;
    BOOL _running;
}
@property (nonatomic, strong) LuaEngine *lua;
@property (nonatomic, strong) AppFarming *farming;
@property (nonatomic, strong) DeviceControl *device;
@property (nonatomic, strong) OCRHelper *ocr;
@property (nonatomic, strong) MCPServer *mcp;
@end

@implementation WSDaemon

- (instancetype)init {
    self = [super init];
    if (self) {
        _connections = [NSMutableSet set];
        _lua    = [[LuaEngine alloc] init];
        _farming = [[AppFarming alloc] init];
        _device  = [[DeviceControl alloc] init];
        _ocr     = [[OCRHelper alloc] init];
        _mcp     = [[MCPServer alloc] init];
    }
    return self;
}

- (void)start {
    _serverSocket = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(_serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(PORT);
    addr.sin_addr.s_addr = INADDR_ANY;

    bind(_serverSocket, (struct sockaddr *)&addr, sizeof(addr));
    listen(_serverSocket, 10);
    _running = YES;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        while (self->_running) {
            int client = accept(self->_serverSocket, NULL, NULL);
            if (client < 0) continue;
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                [self handleClient:client];
            });
        }
    });
}

- (void)stop {
    _running = NO;
    close(_serverSocket);
}

- (void)handleClient:(int)fd {
    char buf[65536];
    ssize_t n = recv(fd, buf, sizeof(buf) - 1, 0);
    if (n <= 0) { close(fd); return; }
    buf[n] = '\0';

    NSString *request = [NSString stringWithUTF8String:buf];
    NSArray *lines = [request componentsSeparatedByString:@"\r\n"];
    if (lines.count < 1) { close(fd); return; }

    // Detect WebSocket upgrade
    BOOL isWS = [request containsString:@"Upgrade: websocket"];
    if (isWS) {
        [self handleWebSocket:fd request:request];
        return;
    }

    // HTTP request → route
    NSString *firstLine = lines[0];
    NSArray *parts = [firstLine componentsSeparatedByString:@" "];
    if (parts.count < 2) { close(fd); return; }
    NSString *method = parts[0];
    NSString *path = parts[1];

    NSDictionary *response = [self routeHTTP:method path:path body:nil];
    [self sendHTTP:fd code:200 body:response];
    close(fd);
}

// ── HTTP Router ──

- (NSDictionary *)routeHTTP:(NSString *)method path:(NSString *)path body:(NSData *)body {
    // Web IDE
    if ([path isEqualToString:@"/"] || [path hasPrefix:@"/ide"]) {
        return @{@"html": [self serveFile:@"index.html"]};
    }
    if ([path hasPrefix:@"/webide/"]) {
        NSString *file = [path substringFromIndex:7];
        return @{@"html": [self serveFile:file]};
    }

    // API v1
    if ([path hasPrefix:@"/api/v1/"]) {
        return [self routeAPI:method path:[path substringFromIndex:8] body:body];
    }

    // MCP SSE
    if ([path hasPrefix:@"/sse"]) {
        return [[MCPServer shared] description] ?: @{};
    }

    return @{@"error": @"not found"};
}

- (NSDictionary *)routeAPI:(NSString *)method path:(NSString *)path body:(NSData *)body {
    NSArray *segments = [path componentsSeparatedByString:@"/"];
    if (segments.count < 2) return @{@"error": @"invalid path"};

    NSString *category = segments[0];  // lua, farm, device, ocr
    NSString *action = segments.count > 1 ? segments[1] : @"";

    if ([category isEqualToString:@"lua"]) return [self.lua handleAPI:action body:body];
    if ([category isEqualToString:@"farm"]) return [self.farming handleAPI:action body:body];
    if ([category isEqualToString:@"device"]) return [self.device handleAPI:action body:body];
    if ([category isEqualToString:@"ocr"]) return [self.ocr handleAPI:action body:body];

    if ([category isEqualToString:@"ping"]) return @{@"pong": @YES};
    if ([category isEqualToString:@"status"]) return @{
        @"lua": [self.lua status],
        @"farming": [self.farming status],
        @"uptime": @([[NSProcessInfo processInfo] systemUptime])
    };

    return @{@"error": @"unknown API"};
}

// ── WebSocket handler ──

- (void)handleWebSocket:(int)fd request:(NSString *)request {
    // Send upgrade response
    NSString *key = [self extractHeader:@"Sec-WebSocket-Key" from:request];
    if (!key) { close(fd); return; }

    NSString *acceptKey = [self wsAcceptKey:key];
    NSString *response = [NSString stringWithFormat:
        @"HTTP/1.1 101 Switching Protocols\r\n"
        @"Upgrade: websocket\r\n"
        @"Connection: Upgrade\r\n"
        @"Sec-WebSocket-Accept: %@\r\n\r\n", acceptKey];
    send(fd, [response UTF8String], [response length], 0);

    [_connections addObject:@(fd)];

    // Read loop
    while (_running) {
        uint8_t frame[2];
        ssize_t r = recv(fd, frame, 2, 0);
        if (r <= 0) break;

        uint8_t opcode = frame[0] & 0x0F;
        BOOL masked = (frame[1] & 0x80) != 0;
        uint64_t payloadLen = frame[1] & 0x7F;

        if (payloadLen == 126) {
            uint16_t ext; recv(fd, &ext, 2, 0);
            payloadLen = ntohs(ext);
        } else if (payloadLen == 127) {
            uint64_t ext; recv(fd, &ext, 8, 0);
            payloadLen = ntohll(ext);
        }

        uint8_t maskKey[4] = {0};
        if (masked) recv(fd, maskKey, 4, 0);

        uint8_t payload[65536];
        if (payloadLen > 0 && payloadLen < sizeof(payload)) {
            recv(fd, payload, (size_t)payloadLen, 0);
            if (masked) for (uint64_t i=0; i<payloadLen; i++) payload[i] ^= maskKey[i % 4];
        }

        if (opcode == 0x08) break; // Close
        if (opcode == 0x09) {       // Ping → send Pong
            uint8_t pong[] = {0x8A, 0x00};
            send(fd, pong, 2, 0);
            continue;
        }

        if (opcode == 0x01) { // Text
            NSString *msg = [[NSString alloc] initWithBytes:payload length:(NSUInteger)payloadLen encoding:NSUTF8StringEncoding];
            NSString *reply = [self handleWSMessage:msg];
            [self sendWS:fd text:reply];
        }
    }

    [_connections removeObject:@(fd)];
    close(fd);
}

- (NSString *)handleWSMessage:(NSString *)msg {
    @try {
        NSData *data = [msg dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *cmd = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (!cmd) return [self jsonError:@"invalid JSON"];

        NSString *type = cmd[@"type"] ?: @"";
        NSDictionary *params = cmd[@"params"] ?: @{};
        NSString *idStr = cmd[@"id"] ?: @"0";

        NSDictionary *result = nil;

        if ([type isEqualToString:@"lua.exec"]) {
            result = [self.lua execute:params[@"script"] ?: @"" args:params[@"args"]];
        } else if ([type isEqualToString:@"lua.stop"]) {
            result = [self.lua stop];
        } else if ([type isEqualToString:@"farm.openAcc"]) {
            result = [self.farming openAcc:params[@"bundleID"] account:params[@"accName"]];
        } else if ([type isEqualToString:@"farm.backupAcc"]) {
            result = [self.farming backupAcc:params[@"bundleID"] account:params[@"accName"]];
        } else if ([type isEqualToString:@"farm.restoreAcc"]) {
            result = [self.farming restoreAcc:params[@"bundleID"] account:params[@"accName"]];
        } else if ([type isEqualToString:@"farm.deleteAcc"]) {
            result = [self.farming deleteAcc:params[@"bundleID"] account:params[@"accName"]];
        } else if ([type isEqualToString:@"farm.resetApp"]) {
            result = [self.farming resetApp:params[@"bundleID"]];
        } else if ([type isEqualToString:@"farm.cleanAllAcc"]) {
            result = [self.farming cleanAllAcc:params[@"bundleID"]];
        } else if ([type isEqualToString:@"device.fakeLocation"]) {
            result = [self.device fakeLocation:[params[@"lat"] doubleValue] lon:[params[@"lon"] doubleValue]];
        } else if ([type isEqualToString:@"device.setProxy"]) {
            result = [self.device setProxy:params[@"proxy"] ?: @""];
        } else if ([type isEqualToString:@"device.gesture"]) {
            result = [self.device gesture:params];
        } else if ([type isEqualToString:@"ocr.findText"]) {
            result = [self.ocr findText:params[@"region"] ?: CGRectZero];
        } else {
            result = @{@"error": [NSString stringWithFormat:@"unknown type: %@", type]};
        }

        NSDictionary *reply = @{@"id": idStr, @"result": result ?: @{}};
        NSData *replyData = [NSJSONSerialization dataWithJSONObject:reply options:0 error:nil];
        return [[NSString alloc] initWithData:replyData encoding:NSUTF8StringEncoding];
    } @catch (NSException *e) {
        return [self jsonError:e.reason];
    }
}

// ── Helpers ──

- (NSString *)jsonError:(NSString *)err {
    NSData *d = [NSJSONSerialization dataWithJSONObject:@{@"error": err ?: @"unknown"} options:0 error:nil];
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

- (void)sendWS:(int)fd text:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger len = data.length;
    NSMutableData *frame = [NSMutableData data];

    uint8_t hdr[2] = {0x81, 0};
    if (len < 126) hdr[1] = (uint8_t)len;
    else if (len < 65536) { hdr[1] = 126; uint16_t e = htons((uint16_t)len); [frame appendBytes:&e length:2]; }
    else { hdr[1] = 127; uint64_t e = htonll(len); [frame appendBytes:&e length:8]; }
    [frame appendBytes:hdr length:2];
    [frame appendData:data];
    send(fd, frame.bytes, frame.length, 0);
}

- (void)sendHTTP:(int)fd code:(int)code body:(NSDictionary *)body {
    NSString *contentType = @"application/json";
    NSData *data = nil;

    if (body[@"html"]) {
        contentType = @"text/html; charset=utf-8";
        data = [body[@"html"] dataUsingEncoding:NSUTF8StringEncoding];
    } else {
        data = [NSJSONSerialization dataWithJSONObject:body options:NSJSONWritingPrettyPrinted error:nil];
    }

    NSString *header = [NSString stringWithFormat:
        @"HTTP/1.1 %d OK\r\nContent-Type: %@\r\nContent-Length: %lu\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n",
        code, contentType, (unsigned long)data.length];
    send(fd, [header UTF8String], [header length], 0);
    send(fd, data.bytes, data.length, 0);
}

- (NSString *)extractHeader:(NSString *)name from:(NSString *)req {
    NSString *prefix = [name stringByAppendingString:@": "];
    for (NSString *line in [req componentsSeparatedByString:@"\r\n"]) {
        if ([line hasPrefix:prefix]) return [line substringFromIndex:prefix.length];
    }
    return nil;
}

- (NSString *)wsAcceptKey:(NSString *)key {
    NSString *combined = [key stringByAppendingString:@"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"];
    NSData *hashData = [combined dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(hashData.bytes, (CC_LONG)hashData.length, digest);
    return [[NSData dataWithBytes:digest length:20] base64EncodedStringWithOptions:0];
}

- (NSString *)serveFile:(NSString *)filename {
    NSString *path = [WEBIDE_PATH stringByAppendingPathComponent:filename];
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
}

@end
