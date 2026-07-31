// ZMMOHTTPServer.mm — Minimal HTTP/1.1 server via BSD sockets
// No external dependencies. Handles concurrent connections via dispatch queues.

#import "ZMMOHTTPServer.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>

@interface ZMMOHTTPServer ()
@property (nonatomic, assign) int listenPort;
@property (nonatomic, assign) int listenSocket;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ZMMORouteHandler> *routes;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, strong) dispatch_queue_t acceptQueue;
@end

@implementation ZMMOHTTPServer

- (instancetype)initWithPort:(int)port {
    self = [super init];
    if (self) {
        _listenPort = port;
        _listenSocket = -1;
        _routes = [NSMutableDictionary dictionary];
        _running = NO;
        _acceptQueue = dispatch_queue_create("com.zmmo.http.accept", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)addRoute:(NSString *)path handler:(ZMMORouteHandler)handler {
    self.routes[path] = [handler copy];
}

- (BOOL)start {
    // Create socket
    self.listenSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (self.listenSocket < 0) {
        NSLog(@"[ZMMOHttp] socket() failed: %s", strerror(errno));
        return NO;
    }

    // Allow reuse
    int reuse = 1;
    setsockopt(self.listenSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    // Bind
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK); // 127.0.0.1 only
    addr.sin_port = htons(self.listenPort);

    if (bind(self.listenSocket, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        NSLog(@"[ZMMOHttp] bind() failed: %s", strerror(errno));
        close(self.listenSocket);
        self.listenSocket = -1;
        return NO;
    }

    // Listen
    if (listen(self.listenSocket, 10) < 0) {
        NSLog(@"[ZMMOHttp] listen() failed: %s", strerror(errno));
        close(self.listenSocket);
        self.listenSocket = -1;
        return NO;
    }

    self.running = YES;

    // Accept loop on background queue
    dispatch_async(self.acceptQueue, ^{
        while (self.running) {
            struct sockaddr_in clientAddr;
            socklen_t clientLen = sizeof(clientAddr);
            int clientSocket = accept(self.listenSocket, (struct sockaddr *)&clientAddr, &clientLen);

            if (clientSocket < 0) {
                if (self.running) {
                    NSLog(@"[ZMMOHttp] accept() failed: %s", strerror(errno));
                }
                continue;
            }

            // Handle each connection on a concurrent queue
            dispatch_async(self.acceptQueue, ^{
                [self handleConnection:clientSocket];
            });
        }
    });

    return YES;
}

- (void)stop {
    self.running = NO;
    if (self.listenSocket >= 0) {
        close(self.listenSocket);
        self.listenSocket = -1;
    }
}

- (void)handleConnection:(int)clientSocket {
    @autoreleasepool {
        // Set timeout
        struct timeval tv = {.tv_sec = 30, .tv_usec = 0};
        setsockopt(clientSocket, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(clientSocket, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

        // Read request
        char buffer[65536];
        ssize_t bytesRead = recv(clientSocket, buffer, sizeof(buffer) - 1, 0);

        if (bytesRead <= 0) {
            close(clientSocket);
            return;
        }

        buffer[bytesRead] = '\0';
        NSString *rawRequest = [[NSString alloc] initWithBytes:buffer
                                                        length:bytesRead
                                                      encoding:NSUTF8StringEncoding];
        if (!rawRequest) {
            [self sendResponse:clientSocket status:400 body:@{@"error": @"Bad encoding"}];
            close(clientSocket);
            return;
        }

        // Parse request
        NSDictionary *parsed = [self parseRequest:rawRequest];
        NSString *method = parsed[@"method"];
        NSString *path = parsed[@"path"];
        NSDictionary *params = parsed[@"params"];
        NSString *bodyStr = parsed[@"body"];

        // Route
        ZMMORouteHandler handler = self.routes[path];
        if (!handler) {
            [self sendResponse:clientSocket status:404 body:@{@"error": @"Not found", @"path": path}];
            close(clientSocket);
            return;
        }

        NSData *bodyData = bodyStr ? [bodyStr dataUsingEncoding:NSUTF8StringEncoding] : nil;

        @try {
            NSDictionary *result = handler(method, params, bodyData);
            [self sendResponse:clientSocket status:200 body:result];
        } @catch (NSException *exception) {
            NSLog(@"[ZMMOHttp] Handler error: %@", exception);
            [self sendResponse:clientSocket status:500 body:@{
                @"error": @"Internal error",
                @"detail": exception.reason ?: @"Unknown"
            }];
        }

        close(clientSocket);
    }
}

- (NSDictionary *)parseRequest:(NSString *)raw {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    NSArray *lines = [raw componentsSeparatedByString:@"\r\n"];
    if (lines.count < 1) return result;

    // Request line: GET /path?key=val HTTP/1.1
    NSString *requestLine = lines[0];
    NSArray *parts = [requestLine componentsSeparatedByString:@" "];
    if (parts.count >= 2) {
        result[@"method"] = [parts[0] uppercaseString];
        NSString *fullPath = parts[1];

        // Split path and query
        NSRange qRange = [fullPath rangeOfString:@"?"];
        if (qRange.location != NSNotFound) {
            result[@"path"] = [fullPath substringToIndex:qRange.location];
            NSString *query = [fullPath substringFromIndex:qRange.location + 1];
            result[@"params"] = [self parseQueryString:query];
        } else {
            result[@"path"] = fullPath;
            result[@"params"] = @{};
        }
    }

    // Headers and body
    BOOL inHeaders = YES;
    NSMutableString *body = [NSMutableString string];
    for (NSInteger i = 1; i < (NSInteger)lines.count; i++) {
        NSString *line = lines[i];
        if (inHeaders) {
            if (line.length == 0) {
                inHeaders = NO;
                continue;
            }
            // Skip headers for now (could extract Content-Length etc.)
        } else {
            [body appendString:line];
        }
    }

    if (body.length > 0) {
        result[@"body"] = body;
    }

    if (!result[@"path"]) result[@"path"] = @"/";
    if (!result[@"method"]) result[@"method"] = @"GET";
    if (!result[@"params"]) result[@"params"] = @{};

    return result;
}

- (NSDictionary *)parseQueryString:(NSString *)query {
    if (!query || query.length == 0) return @{};
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    NSArray *pairs = [query componentsSeparatedByString:@"&"];
    for (NSString *pair in pairs) {
        NSArray *kv = [pair componentsSeparatedByString:@"="];
        if (kv.count == 2) {
            NSString *key = [kv[0] stringByRemovingPercentEncoding];
            NSString *val = [kv[1] stringByRemovingPercentEncoding];
            if (key && val) dict[key] = val;
        }
    }
    return dict;
}

- (void)sendResponse:(int)clientSocket status:(int)status body:(NSDictionary *)body {
    @autoreleasepool {
        NSError *jsonErr = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body ?: @{}
                                                           options:NSJSONWritingPrettyPrinted
                                                             error:&jsonErr];
        if (!jsonData) {
            NSString *fallback = @"{\"error\":\"JSON serialization failed\"}";
            jsonData = [fallback dataUsingEncoding:NSUTF8StringEncoding];
        }

        NSString *statusText = (status == 200) ? @"OK" :
                               (status == 400) ? @"Bad Request" :
                               (status == 404) ? @"Not Found" :
                               (status == 500) ? @"Internal Server Error" : @"Unknown";

        NSString *header = [NSString stringWithFormat:
            @"HTTP/1.1 %d %@\r\n"
            @"Content-Type: application/json\r\n"
            @"Content-Length: %lu\r\n"
            @"Connection: close\r\n"
            @"Access-Control-Allow-Origin: *\r\n"
            @"Server: ZMMO-ios-agent/0.1.0\r\n"
            @"\r\n",
            status, statusText, (unsigned long)jsonData.length];

        send(clientSocket, [header UTF8String], [header lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 0);
        send(clientSocket, [jsonData bytes], jsonData.length, 0);
    }
}

@end
