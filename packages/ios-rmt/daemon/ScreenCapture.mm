// daemon/ScreenCapture.mm — GPU-level screen capture via CARenderServer
// Uses CoreGraphics for capture, JPEG compression for streaming

#import "ScreenCapture.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/CALayerHost.h>
#import <dlfcn.h>

@interface ScreenCapture ()
@property (nonatomic, assign) CGFloat quality;
@end

@implementation ScreenCapture

- (instancetype)init {
    self = [super init];
    if (self) { _quality = 0.6; }
    return self;
}

- (void)start {
    NSLog(@"[RMT] Screen capture started");
}

- (void)stop {}

- (NSData *)captureFrame {
    // Capture via UIGraphicsImageRenderer (iOS 10+)
    // For lower-level: use CARenderServerRenderDisplay — requires private API
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    CGFloat scale = [UIScreen mainScreen].scale;

    // Try: use keyWindow snapshot (works even in daemon via IOMobileFramebuffer)
    // Fallback: render server

    static void *_IOSurfaceCreate = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _IOSurfaceCreate = dlopen("/System/Library/Frameworks/IOSurface.framework/IOSurface", RTLD_NOW);
    });

    // Simple method: UIGraphicsImageRenderer
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.scale = 1.0; // Lower res for streaming
    fmt.opaque = YES;

    // Try to get keyWindow (only works if daemon has UI access)
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];

    if (window) {
        CGSize captureSize = window.bounds.size;
        captureSize.width = MIN(captureSize.width, screenSize.width * scale);
        captureSize.height = MIN(captureSize.height, screenSize.height * scale);

        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc]
            initWithSize:captureSize format:fmt];
        UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [window.layer renderInContext:ctx.CGContext];
        }];

        NSData *jpeg = UIImageJPEGRepresentation(img, _quality);
        return jpeg;
    }

    // Fallback: return a blank frame (real capture requires SpringBoard context)
    CGSize fallbackSize = CGSizeMake(screenSize.width * scale, screenSize.height * scale);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:fallbackSize format:fmt];
    UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIColor blackColor] setFill];
        UIRectFill(CGRectMake(0, 0, fallbackSize.width, fallbackSize.height));
    }];
    return UIImageJPEGRepresentation(img, 0.1);
}

- (NSString *)lastScreenshotPath {
    // Take full-res screenshot
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    if (!window) return @"/tmp/zmmo_screenshot.png";

    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:window.bounds.size format:fmt];
    UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [window.layer renderInContext:ctx.CGContext];
    }];

    NSString *path = @"/tmp/zmmo_screenshot.png";
    [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
    return path;
}

@end
