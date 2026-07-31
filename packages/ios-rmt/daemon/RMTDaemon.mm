// daemon/RMTDaemon.mm — Screen mirroring + control server
// Port 8000: WebSocket binary frame streaming + touch events
// Port 8888: HTTP API for control + file transfer

#import "RMTDaemon.h"
#import "ScreenCapture.h"
#import "AudioStream.h"
#import "TouchInject.h"

#import <sys/socket.h>
#import <netinet/in.h>

@interface RMTDaemon () {
    int _streamServer, _ctrlServer;
    NSMutableSet *_streamClients;
    BOOL _running;
}
@property (nonatomic, strong) ScreenCapture *capture;
@property (nonatomic, strong) AudioStream *audio;
@property (nonatomic, strong) TouchInject *touch;
@property (nonatomic, strong) NSTimer *frameTimer;
@end

@implementation RMTDaemon

- (instancetype)init {
    self = [super init];
    if (self) {
        _streamClients = [NSMutableSet set];
        _capture = [[ScreenCapture alloc] init];
        _audio   = [[AudioStream alloc] init];
        _touch   = [[TouchInject alloc] init];
    }
    return self;
}

- (void)start {
    // Start screen capture
    [_capture start];

    // Start audio
    [_audio start];

    // Frame broadcast timer (30fps)
    _frameTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0
        target:self selector:@selector(broadcastFrame) userInfo:nil repeats:YES];

    // Start stream server (port 8000)
    [self startServerOnPort:8000 isStream:YES];

    // Start control server (port 8888)
    [self startServerOnPort:8888 isStream:NO];

    _running = YES;
}

- (void)stop {
    _running = NO;
    [_frameTimer invalidate];
    [_capture stop];
    [_audio stop];
    close(_streamServer);
    close(_ctrlServer);
}

- (void)startServerOnPort:(int)port isStream:(BOOL)isStream {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = INADDR_ANY;

    bind(sock, (struct sockaddr *)&addr, sizeof(addr));
    listen(sock, 20);

    if (isStream) _streamServer = sock; else _ctrlServer = sock;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        while (self->_running) {
            int client = accept(sock, NULL, NULL);
            if (client < 0) continue;
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                if (isStream) [self handleStreamClient:client];
                else [self handleControlClient:client];
            });
        }
    });
}

// ── Frame broadcast (30fps) ──

- (void)broadcastFrame {
    NSData *frame = [_capture captureFrame];
    if (!frame || _streamClients.count == 0) return;

    // Broadcast to all connected stream clients
    for (NSNumber *fdNum in [_streamClients copy]) {
        [self sendBinaryWS:[fdNum intValue] data:frame];
    }
}

// ── Stream client (WebSocket) ──

- (void)handleStreamClient:(int)fd {
    char buf[4096];
    ssize_t n = recv(fd, buf, sizeof(buf)-1, 0);
    if (n <= 0) { close(fd); return; }
    buf[n] = '\0';

    NSString *req = [NSString stringWithUTF8String:buf];

    // WebSocket upgrade
    if ([req containsString:@"Upgrade: websocket"]) {
        NSString *key = nil;
        for (NSString *line in [req componentsSeparatedByString:@"\r\n"]) {
            if ([line hasPrefix:@"Sec-WebSocket-Key: "]) {
                key = [line substringFromIndex:19];
                break;
            }
        }

        if (key) {
            NSString *accept = [self wsAcceptKey:key];
            NSString *resp = [NSString stringWithFormat:
                @"HTTP/1.1 101 Switching Protocols\r\n"
                @"Upgrade: websocket\r\nConnection: Upgrade\r\n"
                @"Sec-WebSocket-Accept: %@\r\n\r\n", accept];
            send(fd, [resp UTF8String], [resp length], 0);

            [_streamClients addObject:@(fd)];

            // Read loop for touch events
            while (_running) {
                uint8_t hdr[2];
                if (recv(fd, hdr, 2, 0) <= 0) break;
                uint8_t opcode = hdr[0] & 0x0F;
                if (opcode == 0x08) break;
                if (opcode == 0x09) { uint8_t p[]={0x8A,0x00}; send(fd,p,2,0); continue; }

                uint64_t len = hdr[1] & 0x7F;
                BOOL masked = (hdr[1] & 0x80) != 0;
                if (len == 126) { uint16_t e; recv(fd,&e,2,0); len=ntohs(e); }
                else if (len == 127) { uint64_t e; recv(fd,&e,8,0); len=ntohll(e); }

                uint8_t mask[4]={0};
                if (masked) recv(fd,mask,4,0);

                uint8_t payload[16384];
                if (len>0 && len<sizeof(payload)) {
                    recv(fd,payload,(size_t)len,0);
                    if (masked) for (uint64_t i=0;i<len;i++) payload[i]^=mask[i%4];
                    payload[len]=0;
                    NSString *msg = [NSString stringWithUTF8String:(char*)payload];
                    if (msg) [_touch handleTouchCommand:msg];
                }
            }

            [_streamClients removeObject:@(fd)];
            close(fd);
        }
    } else {
        // HTTP: serve web client
        [self serveWebClient:fd];
    }
}

// ── Control client (HTTP API) ──

- (void)handleControlClient:(int)fd {
    char buf[16384];
    ssize_t n = recv(fd, buf, sizeof(buf)-1, 0);
    if (n <= 0) { close(fd); return; }
    buf[n] = '\0';

    NSString *req = [NSString stringWithUTF8String:buf];
    NSArray *lines = [req componentsSeparatedByString:@"\r\n"];
    NSString *first = lines.count > 0 ? lines[0] : @"";
    NSArray *parts = [first componentsSeparatedByString:@" "];
    NSString *path = parts.count > 1 ? parts[1] : @"/";

    NSDictionary *result = nil;

    if ([path hasPrefix:@"/api/"]) {
        NSString *action = [path substringFromIndex:5];
        if ([action isEqualToString:@"screenshot"]) result = @{@"path": [_capture lastScreenshotPath]};
        else if ([action isEqualToString:@"mic/start"]) result = [_audio start]];
        else if ([action isEqualToString:@"mic/stop"]) result = [_audio stop]];
        else if ([action isEqualToString:@"status"]) result = @{@"streamClients": @(_streamClients.count), @"audioActive": @([_audio isActive])};
        else result = @{@"error": @"unknown"};
    } else {
        result = @{@"html": [self webClientHTML]};
    }

    NSData *body;
    NSString *ct = @"application/json";
    if (result[@"html"]) {
        body = [result[@"html"] dataUsingEncoding:NSUTF8StringEncoding];
        ct = @"text/html; charset=utf-8";
    } else {
        body = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    }

    NSString *header = [NSString stringWithFormat:
        @"HTTP/1.1 200 OK\r\nContent-Type: %@\r\nContent-Length: %lu\r\n"
        @"Access-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n",
        ct, (unsigned long)body.length];
    send(fd, [header UTF8String], [header length], 0);
    send(fd, body.bytes, body.length, 0);
    close(fd);
}

- (void)sendBinaryWS:(int)fd data:(NSData *)data {
    NSUInteger len = data.length;
    NSMutableData *frame = [NSMutableData data];
    uint8_t hdr[2] = {0x82, 0}; // Binary frame
    if (len < 126) hdr[1] = (uint8_t)len;
    else if (len < 65536) { hdr[1]=126; uint16_t e=htons((uint16_t)len); [frame appendBytes:&e length:2]; }
    else { hdr[1]=127; uint64_t e=htonll(len); [frame appendBytes:&e length:8]; }
    [frame appendBytes:hdr length:2];
    [frame appendData:data];
    send(fd, frame.bytes, frame.length, 0);
}

- (void)serveWebClient:(int)fd {
    NSString *html = [self webClientHTML];
    NSData *data = [html dataUsingEncoding:NSUTF8StringEncoding];
    NSString *header = [NSString stringWithFormat:
        @"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n"
        @"Content-Length: %lu\r\nConnection: close\r\n\r\n",
        (unsigned long)data.length];
    send(fd, [header UTF8String], [header length], 0);
    send(fd, data.bytes, data.length, 0);
    close(fd);
}

- (NSString *)wsAcceptKey:(NSString *)key {
    NSString *c = [key stringByAppendingString:@"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"];
    NSData *h = [c dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t d[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(h.bytes, (CC_LONG)h.length, d);
    return [[NSData dataWithBytes:d length:20] base64EncodedStringWithOptions:0];
}

- (NSString *)webClientHTML {
    NSString *path = @"/var/mobile/Library/ZMMO/ios-rmt/web/index.html";
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?:
    @"<html><body><h1>ZMMO Remote</h1><p>Connect via WebSocket</p></body></html>";
}

@end
