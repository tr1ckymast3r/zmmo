// daemon/ScreenCapture.h

#import <Foundation/Foundation.h>

@interface ScreenCapture : NSObject
- (void)start;
- (void)stop;
- (NSData *)captureFrame;
- (NSString *)lastScreenshotPath;
@end
