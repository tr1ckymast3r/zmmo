// daemon/WebSocket.mm

#import "WebSocket.h"

@implementation WebSocket

+ (NSData *)binaryFrame:(NSData *)payload {
    NSUInteger len = payload.length;
    NSMutableData *frame = [NSMutableData data];
    uint8_t hdr[2] = {0x82, 0};
    if (len < 126) hdr[1] = (uint8_t)len;
    else if (len < 65536) { hdr[1]=126; uint16_t e=htons((uint16_t)len); [frame appendBytes:&e length:2]; }
    else { hdr[1]=127; uint64_t e=htonll(len); [frame appendBytes:&e length:8]; }
    [frame appendBytes:hdr length:2];
    [frame appendData:payload];
    return frame;
}

+ (NSData *)textFrame:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger len = data.length;
    NSMutableData *frame = [NSMutableData data];
    uint8_t hdr[2] = {0x81, 0};
    if (len < 126) hdr[1] = (uint8_t)len;
    else if (len < 65536) { hdr[1]=126; uint16_t e=htons((uint16_t)len); [frame appendBytes:&e length:2]; }
    else { hdr[1]=127; uint64_t e=htonll(len); [frame appendBytes:&e length:8]; }
    [frame appendBytes:hdr length:2];
    [frame appendData:data];
    return frame;
}

@end
